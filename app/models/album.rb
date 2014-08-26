class Album < ActiveRecord::Base

  include Authority::Abilities
  include Concerns::Ability
  self.authorizer_name = 'AlbumAuthorizer'

  belongs_to :owner, polymorphic: true
  belongs_to :site
  has_many :pictures, dependent: :destroy

  scope_by_site_id

  validates :name, presence: true, uniqueness: { scope: [:site_id, :owner_type, :owner_id] }
  validates :owner, presence: true

  def cover
    pictures.order('cover desc, id').first
  end

  def cover=(picture)
    pictures.update_all(cover: false)
    pictures.find(picture.id).update_attributes!(cover: true)
  end

  after_destroy :delete_stream_items

  def delete_stream_items
    StreamItem.destroy_all(streamable_type: 'Album', streamable_id: id)
  end

  def group
    Group === owner ? owner : nil
  end

  def person
    Person === owner ? owner : nil
  end
end
