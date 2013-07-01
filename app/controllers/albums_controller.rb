class AlbumsController < ApplicationController

  cache_sweeper :person_sweeper, :family_sweeper, only: %w(create update destroy)

  def index
    if params[:person_id]
      @person = Person.find(params[:person_id])
      if @logged_in.can_see?(@person)
        @albums = @person.albums.all
      else
        render text: t('not_authorized'), layout: true, status: 401
      end
    elsif params[:group_id]
      @group = Group.find(params[:group_id])
      if @logged_in.can_see?(@group)
        @albums = @group.albums.all
      else
        render text: t('not_authorized'), layout: true, status: 401
      end
    else
      @albums = (
        Album.find_all_by_group_id_and_is_public(nil, true, order: 'created_at desc') +
        Album.where("person_id in (?)", [@logged_in.id] + @logged_in.all_friend_and_groupy_ids).all
      ).uniq.sort_by(&:name)
    end
    respond_to do |format|
      format.html
      format.js { render text: @albums.to_json }
    end
  end

  def show
    @album = Album.find(params[:id])
    redirect_to album_pictures_path(@album)
  end

  def new
    if @group = Group.find_by_id(params[:group_id]) and can_add_pictures_to_group?(@group)
      @album = @group.albums.build
    else
      @album = Album.new(is_public: true)
    end
  end

  def can_add_pictures_to_group?(group)
    group.pictures? and (@logged_in.member_of?(group) or group.admin?(@logged_in))
  end

  def create
    @album = Album.new(album_params)
    if @album.group and !can_add_pictures_to_group?(@album.group)
      @album.errors.add(:base, t('albums.cannot_add_pictures_to_group'))
    end
    if params['remove_owner'] and @logged_in.admin?(:manage_pictures)
      @album.person = nil
      @album.is_public = true
    else
      @album.person = @logged_in
    end
    if @album.save
      flash[:notice] = t('albums.saved')
      redirect_to @album
    else
      render action: 'new'
    end
  end

  def edit
    @album = Album.find(params[:id])
    unless @logged_in.can_edit?(@album)
      render text: t('not_authorized'), layout: true, status: 401
    end
  end

  def update
    @album = Album.find(params[:id])
    if @logged_in.can_edit?(@album)
      if @album.update_attributes(album_params)
        flash[:notice] = t('Changes_saved')
        redirect_to @album
      else
        render action: 'edit'
      end
    else
      render text: t('not_authorized'), layout: true, status: 401
    end
  end

  def destroy
    @album = Album.find(params[:id])
    if @logged_in.can_edit?(@album)
      @album.destroy
      redirect_to albums_path
    else
      render text: t('not_authorized'), layout: true, status: 401
    end
  end

  private

  def album_params
    params.require(:album).permit(:name, :description, :group_id, :is_public)
  end

end
