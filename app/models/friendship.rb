class Friendship < ActiveRecord::Base
  belongs_to :person
  belongs_to :friend, class_name: 'Person', foreign_key: 'friend_id'
  belongs_to :site

  scope_by_site_id

  validates_presence_of :person_id
  validates_presence_of :friend_id
  validates_uniqueness_of :friend_id, scope: [:site_id, :person_id]

  attr_accessor :skip_mirror

  before_create :mirror_friendship
  def mirror_friendship
    unless skip_mirror
      mirror = Friendship.new(person_id: friend_id)
      mirror.friend_id = person_id
      mirror.skip_mirror = true
      mirror.save!
    end
  end

  def destroy
    Friendship.delete_all ['(friend_id = ? and person_id = ?) or (friend_id = ? and person_id = ?)', person.id, friend.id, friend.id, person.id]
  end
end
