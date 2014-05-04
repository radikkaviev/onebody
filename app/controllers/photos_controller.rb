class PhotosController < ApplicationController

  PHOTO_TYPES = {
    'family_id'  => Family,
    'person_id'  => Person,
    'picture_id' => Picture,
    'group_id'   => Group
  }

  before_filter :get_object

  def update
    if @logged_in.can_edit?(@object)
      if params[:photo]
        @object.photo = params[:photo]
        # annoying to users if changing their photo fails due to some other unrelated validation failure
        # this is a total hack
        if @object.valid? or @object.errors.select { |a, e| a == :photo_content_type }.empty?
          @object.save(validate: false)
        else
          flash[:warning] = @object.errors.full_messages.join('; ')
        end
      end
      redirect_back
    else
      render text: t('photos.unavailable'), status: 500
    end
  end

  def destroy
    if @logged_in.can_edit?(@object)
      @object.photo = nil
      @object.save(validate: false)
      redirect_back
    else
      render text: t('photos.unavailable'), status: 500
    end
  end

  private

  def get_object
    # /families/123/photo
    # /families/123/photo/large
    if id_key = params.keys.select { |k| k =~ /_id$/ }.last and model = PHOTO_TYPES[id_key]
      @object = model.find(params[id_key])
    else
      render text: t('photos.object_not_found'), layout: true, status: 404
      return false
    end
  end

end
