class MembershipRequest < ActiveRecord::Base
  belongs_to :person
  belongs_to :group
  belongs_to :site

  validates_uniqueness_of :group_id, scope: [:site_id, :person_id]

  scope_by_site_id

  after_create :deliver

  def deliver
    Notifier.membership_request(group, person).deliver
  end

  validate :validate_duplicate_membership

  def validate_duplicate_membership
    if Membership.find_by_group_id_and_person_id(group_id, person_id)
      errors.add(:base, 'Already a member of this group.')
    end
  end
end
