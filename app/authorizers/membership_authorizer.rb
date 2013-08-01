class MembershipAuthorizer < ApplicationAuthorizer

  def readable_by?(user)
    false # TODO
  end

  def updatable_by?(user)
    # my membership
    if resource.person == user
      true
    # someone in my family and I'm an adult
    elsif resource.person.try(:family) == user.family and user.adult?
      true
    # group admin
    elsif resource.group.try(:admin?, user)
      true
    # admin with edit_profiles privilege
    elsif user.admin?(:edit_profiles)
      true
    end
  end

  alias_method :deletable_by?, :updatable_by?

end
