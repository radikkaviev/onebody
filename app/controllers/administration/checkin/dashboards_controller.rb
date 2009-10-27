class Administration::Checkin::DashboardsController < ApplicationController

  before_filter :only_admins
  
  def show
  end
  
  private
  
    def only_admins
      unless @logged_in.admin?(:manage_checkin) or @logged_in.admin?(:assign_checkin_cards)
        render :text => 'You must be an administrator to use this section.', :layout => true, :status => 401
        return false
      end
    end
  
    def feature_enabled?
      unless Setting.get(:features, :checkin_modules)
        render :text => 'This feature is unavailable.', :layout => true
        false
      end
    end
  
end
