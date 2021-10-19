require 'ro_crate'
require 'seek/download_handling/http_streamer'

# A kind of "form object" to instantiate a workflow from a given git repository, target ref, and several paths in that
# repository that indicate where to find the main workflow, diagram etc..
# Alternatively, these paths can be inferred from RO-Crate metadata, if present.
#
class GitWorkflowWizard
  include ActiveModel::Model

  attr_reader :next_step, :workflow_class, :git_repository

  attr_accessor :params, :workflow

  def run
    @next_step = :new

    if new_version?
      workflow_class = workflow.workflow_class
      current_version = workflow.git_version
      git_version = workflow.git_versions.build(params.delete(:git_version_attributes))
      # Assign existing paths if they still exist in the new version
      [:main_workflow_path, :abstract_cwl_path, :diagram_path].each do |path_attr|
        path = current_version.send(path_attr)
        git_version.send("#{path_attr}=", path) if git_version.send(path_attr).blank? && path && git_version.file_exists?(path)
      end
    else
      self.workflow = Workflow.new
    end

    workflow.assign_attributes(params)
    git_version ||= workflow.git_version

    if git_version.git_repository.blank?
      if git_version.remote.blank?
        workflow.errors.add(:base, 'Git URL was blank.')
        return workflow
      else
        git_version.set_default_git_repository
        git_version.git_repository.queue_fetch
      end
    end

    if git_version.ref.blank?
      @next_step = :select_ref
      return workflow
    end

    git_version.set_default_metadata

    if git_version.ro_crate?
      git_version.in_temp_dir do |dir|
        crate = ROCrate::WorkflowCrateReader.read(dir)
        git_version.main_workflow_path ||= crate.main_workflow&.id if crate.main_workflow&.id
        git_version.abstract_cwl_path ||= crate.main_workflow&.cwl_description&.id if crate.main_workflow&.cwl_description&.id
        git_version.diagram_path ||= crate.main_workflow&.diagram&.id if crate.main_workflow&.diagram&.id

        workflow_class ||= WorkflowClass.match_from_metadata(crate&.main_workflow&.programming_language&.properties || {})
      end
    end

    if git_version.main_workflow_path.blank?
      @next_step = :select_paths
      return workflow
    end

    extractor = workflow.extractor
    workflow.provide_metadata(extractor.metadata)

    @next_step = :provide_metadata

    workflow
  end

  private

  def new_version?
    workflow.present? && workflow.persisted?
  end
end
