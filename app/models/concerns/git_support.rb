module GitSupport
  DEFAULT_LOCAL_REF = 'refs/heads/master'

  extend ActiveSupport::Concern

  def git_base
    git_repository.git_base
  end

  def file_contents(path, &block)
    blob = object(path)
    return unless blob&.is_a?(Rugged::Blob)

    if block_given?
      block.call(StringIO.new(blob.content)) # Rugged does not support streaming blobs :(
    else
      blob.content
    end
  end

  def object(path)
    return nil unless commit
    git_base.lookup(tree.path(path)[:oid])
  rescue Rugged::TreeError
    nil
  end

  def tree
    git_base.lookup(commit).tree if commit
  end

  def trees
    t = []
    return t unless commit

    tree.each_tree { |tree| t << tree }
    t
  end

  def blobs
    b = []
    return b unless commit

    tree.each_blob { |blob| b << blob }
    b
  end

  def file_exists?(path)
    !object(path).nil?
  end

  def total_size
    total = 0

    tree.walk_blobs do |_, entry|
      blob = git_base.lookup(entry[:oid])
      total += blob.size
    end

    total
  end

  # Checkout the commit into the given directory.
  def in_dir(dir)
    base = git_base.base
    wd = base.workdir
    base.workdir = dir
    base.checkout_tree(tree.oid, strategy: [:dont_update_index, :force, :no_refresh])
  ensure
    if base && wd
      base.workdir = wd
    end
  end

  def in_temp_dir
    Dir.mktmpdir do |dir|
      in_dir(dir)
      yield dir
    end
  end

  def add_file(path, io, message: nil)
    message ||= (file_exists?(path) ? 'Updated' : 'Added')
    perform_commit("#{message} #{path}") do |index|
      oid = git_base.write(io.read, :blob) # Write the file into the object DB
      index.add(path: path, oid: oid, mode: 0100644) # Add it to the index
    end
  end

  def add_files(path_io_pairs, message: nil)
    message ||= "Added/updated #{path_io_pairs.count} files"
    perform_commit(message) do |index|
      path_io_pairs.each do |path, io|
        oid = git_base.write(io.read, :blob) # Write the file into the object DB
        index.add(path: path, oid: oid, mode: 0100644) # Add it to the index
      end
    end
  end

  def remove_file(path)
    raise Seek::Git::PathNotFoundException.new(path: path) unless file_exists?(path)

    perform_commit("Deleted #{path}") do |index|
      index.remove(path)
    end
  end

  def move_file(oldpath, newpath)
    raise Seek::Git::PathNotFoundException.new(path: oldpath) unless file_exists?(oldpath)

    perform_commit("Moved #{oldpath} -> #{newpath}") do |index|
      existing = index[oldpath]
      index.add(path: newpath, oid: existing[:oid], mode: 0100644)
      index.remove(oldpath)
    end
  end

  private

  def perform_commit(message, &block)
    raise Seek::Git::ImmutableVersionException unless mutable?

    index = git_base.index

    is_initial = git_base.head_unborn?

    index.read_tree(git_base.head.target.tree) unless is_initial

    yield index

    options = {}
    options[:tree] = index.write_tree(git_base.base) # Write a new tree with the changes in `index`, and get back the oid
    options[:author] = git_author
    options[:committer] = git_author
    options[:message] ||= message
    options[:parents] =  git_base.empty? ? [] : [git_base.head.target].compact
    options[:update_ref] = ref unless is_initial

    self.commit = Rugged::Commit.create(git_base.base, options)

    if is_initial
      r = ref.blank? ? DEFAULT_LOCAL_REF : ref
      git_base.references.create(r, self.commit)
      git_base.head = r if git_base.head.blank?
    end

    self.commit
  end
end
