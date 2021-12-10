class WorkflowsController < ApplicationController
  include Seek::IndexPager
  include Seek::AssetsCommon

  before_action :workflows_enabled?
  before_action :find_assets, only: [:index]
  before_action :find_and_authorize_requested_item, except: [:index, :new, :create, :preview, :update_annotations_ajax]
  before_action :find_display_asset, only: [:show, :download, :diagram, :ro_crate, :edit_paths, :update_paths]
  before_action :login_required, only: [:create, :create_version, :new_version,
                                        :create_from_files, :create_from_ro_crate,
                                        :create_metadata, :provide_metadata, :create_from_git, :create_version_from_git]
  before_action :find_or_initialize_workflow, only: [:create_from_files, :create_from_ro_crate]

  include Seek::Publishing::PublishingCommon
  include Seek::Doi::Minting
  include Seek::IsaGraphExtensions
  include RoCrateHandling
  include Legacy::WorkflowSupport

  api_actions :index, :show, :create, :update, :destroy, :ro_crate
  user_content_actions :diagram

  rescue_from ROCrate::ReadException do |e|
    logger.error("Error whilst attempting to read RO-Crate metadata for #{@workflow&.id}.")
    respond_to do |format|
      format.html do
        flash[:error] = "Couldn't read RO-Crate metadata. Check the file is valid."
        redirect_to workflow_path(@workflow)
      end
      format.json { render json: { title: 'RO-Crate Read Error', detail: e.message }, status: :internal_server_error }
    end
  end

  def new_git_version
    @git_repository = @workflow.latest_git_version.git_repository
    if @git_repository&.remote?
      @git_repository.queue_fetch

      respond_to do |format|
        format.html
      end
    else
      @git_version = @workflow.latest_git_version.next_version(mutable: true)
      if @git_version.save
        flash[:notice] = "New development version created."
      else
        flash[:error] = "Couldn't save new version: #{@git_version.errors.full_messages.join(',')}."
      end
      respond_to do |format|
        format.html { redirect_to workflow_path(@workflow) }
      end
    end
  end

  def new_version
    if @workflow.is_git_versioned?
      redirect_to new_git_version_workflow_path(@workflow)
    else
      respond_to do |format|
        format.html
      end
    end
  end

  def create_version
    if params[:ro_crate]
      handle_ro_crate_post(true)
    else
      if handle_upload_data(true)
        comments = params[:revision_comments]
        respond_to do |format|
          if @workflow.save_as_new_version(comments)

            flash[:notice]="New version uploaded - now on version #{@workflow.version}"
          else
            flash[:error]="Unable to save new version"
          end
          format.html {redirect_to @workflow }
        end
      else
        flash[:error] = flash.now[:error]
        redirect_to @workflow
      end
    end
  end

  # PUT /Workflows/1
  def update
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)
    update_sharing_policies @workflow
    update_relationships(@workflow,params)

    respond_to do |format|
      if @workflow.update_attributes(workflow_params)
        flash[:notice] = "#{t('workflow')} metadata was successfully updated."
        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow, include: [params[:include]] }
      else
        format.html { render action: 'edit' }
        format.json { render json: json_api_errors(@workflow), status: :unprocessable_entity }
      end
    end
  end

  # Takes a single RO-Crate zip file
  def create_from_ro_crate
    @crate_extractor = WorkflowCrateExtractor.new(ro_crate_extractor_params)
    @workflow = @crate_extractor.build

    respond_to do |format|
      if @crate_extractor.valid?
        format.html { render :provide_metadata }
      else
        format.html { render action: :new, status: :unprocessable_entity }
      end
    end
  end

  # Creates an RO-Crate zip file from several files
  def create_from_files
    @crate_builder = WorkflowRepositoryBuilder.new(ro_crate_params)
    @crate_builder.workflow_class = @workflow.workflow_class
    @workflow = @crate_builder.build

    respond_to do |format|
      if @crate_builder.valid?
        format.html { render :provide_metadata }
      else
        format.html { render action: :new, status: :unprocessable_entity }
      end
    end
  end

  # Takes a remote Git repository and target ref
  def create_from_git
    wizard = GitWorkflowWizard.new(params: workflow_params)
    @workflow = wizard.run
    respond_to do |format|
      format.html { render wizard.next_step }
    end
  end

  def create_version_from_git
    wizard = GitWorkflowWizard.new(params: workflow_params, workflow: @workflow)
    @workflow = wizard.run
    respond_to do |format|
      format.html { render wizard.next_step }
    end
  end

  #
  # # Displays the form Wizard for providing the metadata for the workflow
  # def provide_metadata
  #   extract_metadata
  #   metadata = @metadata
  #   @warnings ||= metadata.delete(:warnings) || []
  #   @errors ||= metadata.delete(:errors) || []
  #   @workflow.assign_attributes(metadata)
  #
  #   respond_to do |format|
  #     format.html
  #   end
  # end

  # Receives the submitted metadata and registers the workflow
  def create_metadata
    @workflow = Workflow.new(workflow_params)
    update_sharing_policies(@workflow)
    filter_associated_projects(@workflow)

    blob = ContentBlob.where(uuid: params[:content_blob_uuid], asset_id: nil).first
    @workflow.errors.add(:content_blob, 'was not found') unless blob
    @workflow.content_blob = blob
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)
    if params[:content_blob_uuid].present?
      valid = blob && @workflow.save && blob.save
    elsif @workflow.git_version_attributes.present?
      valid = @workflow.save
    else
      valid = false
    end

    if valid
      update_relationships(@workflow, params)

      respond_to do |format|
        flash[:notice] = "#{t('workflow')} was successfully uploaded and saved." if flash.now[:notice].nil?

        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow }
      end
    else
      respond_to do |format|
        format.html do
          render :provide_metadata, status: :unprocessable_entity
        end
      end
    end
  end

  def create_version_metadata
    @workflow = Workflow.find(params[:id])
    @workflow.assign_attributes(workflow_params)
    update_sharing_policies(@workflow)
    filter_associated_projects(@workflow)
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)

    if params[:content_blob_uuid].present?
      #associate the content blob with the workflow
      blob = ContentBlob.where(uuid: params[:content_blob_uuid], asset_id: nil).first
      @workflow.errors.add(:content_blob, 'was not found') unless blob
      new_version = @workflow.version += 1
      old_content_blob = @workflow.content_blob
      blob.asset_version = new_version
      @workflow.content_blob = blob
      # asset_id on the previous content blob gets blanked out after the above command is run, so need to do:
      old_content_blob.update_column(:asset_id, @workflow.id) if old_content_blob
      valid = blob && @workflow.save_as_new_version(params[:revision_comments]) && blob.save
    elsif @workflow.git_version_attributes.present?
      valid = @workflow.save_as_new_git_version
    else
      valid = false
    end

    if valid
      update_relationships(@workflow, params)

      respond_to do |format|
        flash[:notice] = "#{t('workflow')} was successfully uploaded and saved." if flash.now[:notice].nil?

        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow }
      end
    else
      respond_to do |format|
        format.html do
          render :provide_metadata, status: :unprocessable_entity
        end
      end
    end
  end

  def diagram
    @diagram = @display_workflow.diagram
    if @diagram
      send_file(@diagram.path,
                filename: @diagram.filename,
                type: @diagram.content_type,
                disposition: 'inline')
    else
      head :not_found
    end
  end

  def download
    ro_crate
  end

  def ro_crate
    send_ro_crate(@display_workflow.ro_crate_zip,
                  "workflow-#{@workflow.id}-#{@display_workflow.version}.crate.zip")
  end

  def edit_paths

  end

  def update_paths
    respond_to do |format|
      if @workflow.update_attributes(workflow_params) && @display_workflow.reload.update_attributes(git_version_path_params)
        if params[:extract_metadata] == '1'
          extractor = @workflow.extractor
          @workflow.provide_metadata(extractor.metadata)
          flash[:notice] = "#{t('workflow')} files annotated and metadata was re-extracted. Please review the changes and confirm (or cancel to keep the existing metadata)."
          format.html { render :edit }
        else
          flash[:notice] = "#{t('workflow')} files were annotated successfully."
          format.html { redirect_to workflow_path(@workflow) }
          format.json { render json: @workflow, include: [params[:include]] }
        end
      else
        format.html { render action: 'edit' }
        format.json { render json: json_api_errors(@workflow), status: :unprocessable_entity }
      end
    end
  end

  def create
    if params[:ro_crate]
      handle_ro_crate_post
    else
      super
    end
  end

  private

  def handle_ro_crate_post(new_version = false)
    @crate_extractor = WorkflowCrateExtractor.new(ro_crate: { data: params[:ro_crate] }, params: workflow_params)
    if new_version
      if @workflow.latest_git_version.remote?
        @workflow.errors.add(:base, 'Cannot add RO-Crate to remote workflows.')
        render json: json_api_errors(@workflow), status: :unprocessable_entity
        return
      else
        @crate_extractor.workflow = @workflow
        @workflow.latest_git_version.lock if @workflow.latest_git_version.mutable?
        @crate_extractor.git_version = @workflow.latest_git_version.next_version(mutable: true).tap(&:save)
      end
    end
    @workflow = @crate_extractor.build

    if @crate_extractor.valid?
      if (!new_version || @workflow.git_version.save) && @workflow.save
        render json: @workflow, include: json_api_include_param
      else
        render json: json_api_errors(@workflow), status: :unprocessable_entity
      end
    else
      render json: json_api_errors(@crate_extractor), status: :unprocessable_entity
    end
  end

  def find_or_initialize_workflow
    if params[:workflow_id]
      @workflow = Workflow.find(params[:workflow_id])
    else
      @workflow = Workflow.new(workflow_class_id: params[:workflow_class_id])
    end
  end

  def retrieve_content(blob)
    unless blob.file_exists?
      blob.remote_content_fetch_task&.cancel
      blob.retrieve
    end
  end

  def workflow_params
    params.require(:workflow).permit(:title, :description, :workflow_class_id, # :metadata,
                                     { project_ids: [] }, :license, :other_creators,
                                     { special_auth_codes_attributes: [:code, :expiration_date, :id, :_destroy] },
                                     { creator_ids: [] }, { assay_assets_attributes: [:assay_id] }, { scales: [] },
                                     { publication_ids: [] }, { presentation_ids: [] }, { document_ids: [] },
                                     { data_file_ids: [] }, { workflow_data_files_attributes:[:id, :data_file_id, :workflow_data_file_relationship_id, :_destroy] },
                                     :internals, :maturity_level, :source_link_url,
                                     { discussion_links_attributes: [:id, :url, :label, :_destroy] },
                                     { git_version_attributes: [:name, :description, :ref, :commit, :root_path,
                                                                :git_repository_id, :main_workflow_path,
                                                                :abstract_cwl_path, :diagram_path, :remote,
                                                                { remote_sources: {} }] }, :is_git_versioned)
  end

  alias_method :asset_params, :workflow_params

  def ro_crate_params
    params.require(:ro_crate).permit({ main_workflow: [:data, :data_url, :make_local_copy] },
                                     { abstract_cwl: [:data, :data_url, :make_local_copy] },
                                     { diagram: [:data, :data_url, :make_local_copy] })
  end

  def ro_crate_extractor_params
    params.permit(ro_crate: [:data, :data_url, :make_local_copy])
  end

  def git_version_path_params
    params.require(:git_version).permit(:main_workflow_path, :abstract_cwl_path, :diagram_path)
  end
end
