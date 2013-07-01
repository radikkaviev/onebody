class Administration::UpdatesController < ApplicationController
  before_filter :only_admins

  def index
    @updates = toggle(Update).order('created_at desc').page(params[:page])
    @unapproved_groups = Group.unapproved
  end

  def update
    @update = Update.find(params[:id])
    if @update.update_attributes!(update_params)
      redirect_to administration_updates_path
    else
      render action: 'index'
    end
  end

  def destroy
    @update = Update.find(params[:id])
    @update.destroy
    redirect_to administration_updates_path
  end

  private

  def update_params
    params.require(:update).permit(:complete, :apply, :child)
  end

  def toggle(klass)
    if params[:complete] == 'true'
      @complete = true
      klass.complete
    else
      @complete = false
      klass.pending
    end
  end

  def only_admins
    unless @logged_in.admin?(:manage_updates)
      render text: t('only_admins'), layout: true, status: 401
      return false
    end
  end

end
