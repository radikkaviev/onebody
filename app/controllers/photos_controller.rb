class PhotosController < ApplicationController

  cache_sweeper :person_sweeper, :family_sweeper, :only => %w(update destroy)

  PHOTO_TYPES = %w(Family Person Recipe Picture Group) # be sure to add tests to photos_controller_test

  before_filter :get_object

  def update
    if @logged_in.can_edit?(@object)
      if params[:photo]
        @object.photo = params[:photo]
        @object.save(:validate => false)
      end
      redirect_back
    else
      render :text => t('photos.unavailable'), :status => 500
    end
  end

  def destroy
    if @logged_in.can_edit?(@object)
      @object.photo = nil
      @object.save(:validate => false)
      redirect_back
    else
      render :text => t('photos.unavailable'), :status => 500
    end
  end

  private

  def get_object
    # /families/123/photo
    # /families/123/photo/large
    if id_key = params.keys.select { |k| k =~ /_id$/ }.last \
      and PHOTO_TYPES.include?(@type = id_key.split('_').first.classify)
      @object = Kernel.const_get(@type).find(params[id_key])
    else
      render :text => t('photos.object_not_found'), :layout => true, :status => 404
      return false
    end
  end

end
