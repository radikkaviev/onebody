class Administration::MembershipRequestsController < ApplicationController
  before_filter :only_admins

  def index
    @reqs_by_group = MembershipRequest.all.to_a.group_by(&:group)
  end

  private

    def only_admins
      unless @logged_in.admin?(:manage_groups)
        render text: t('only_admins'), layout: true, status: 401
        return false
      end
    end

end
