class Administration::ImportsController < ApplicationController
  before_filter :only_admins

  def index
    @imports = Import.order(created_at: :desc).page(params[:page])
  end

  def show
    @import = Import.find(params[:id])
    respond_to do |format|
      format.html do
        @rows = @import.rows.includes(:import_attributes).paginate(page: params[:page], per_page: 100)
        redirect_to(action: :edit) if @import.parsed?
        render :errored if @import.errored?
      end
      format.json do
        render json: @import
      end
    end
  end

  def new
  end

  def create
    return redirect_to(action: 'new') unless params[:file]
    @import = Import.create(
      person:                   @logged_in,
      filename:                 params[:file].original_filename,
      importable_type:          'Person',
      status:                   'pending',
      mappings:                 previous_import.try(:mappings) || {},
      match_strategy:           previous_import.try(:match_strategy),
      create_as_active:         previous_import.try(:create_as_active?),
      overwrite_changed_emails: previous_import.try(:overwrite_changed_emails?)
    )
    @import.parse_async(
      file:          params[:file],
      strategy_name: 'csv'
    )
    redirect_to administration_import_path(@import)
  end

  def edit
    @import = Import.find(params[:id])
    @import.update_attributes(status: 'parsed')
    @example = build_example
  end

  def update
    @import = Import.find(params[:id])
    @import.attributes = import_params
    @import.mappings = params[:import][:mappings]
    @import.status = 'matched' if params[:status] == 'matched'
    if @import.save
      @import.execute_async if @import.dont_preview
      redirect_to administration_import_path(@import)
    else
      @example = build_example
      render action :edit
    end
  end

  def destroy
    @import = Import.find(params[:id])
    @import.destroy if @import.destroyable?
    redirect_to administration_imports_path
  end

  def execute
    @import = Import.find(params[:id])
    @import.execute_async
    redirect_to administration_import_path(@import)
  end

  private

  def import_params
    params[:import].delete(:dont_preview) if params.fetch(:import, {})[:dont_preview] == '0'
    params.require(:import).permit(:match_strategy, :create_as_active, :overwrite_changed_emails, :dont_preview)
  end

  def build_example
    @import.rows.first.try(:import_attributes_as_hash, keep_invalid: true) || {}
  end

  def only_admins
    return if @logged_in.admin?(:import_data)
    render text: t('only_admins'), layout: true, status: 401
    false
  end

  def previous_import
    Import.order(:created_at).last
  end
end
