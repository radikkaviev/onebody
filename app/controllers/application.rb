# Filters added to this controller will be run for all controllers in the application.
# Likewise, all the methods added will be available for all controllers.
class ApplicationController < ActionController::Base
  include ExceptionNotifiable

  layout 'default'
  
  before_filter :authenticate_user, :except => ['sign_in', 'family_email', 'verify_email', 'verify_mobile', 'verify_birthday', 'verify_code', 'select_person', 'news_feed']
    
  private
    def authenticate_user
      return true if params[:controller] == 'help' # ignore entire help_controller
      if id = session[:logged_in_id]
        person = Person.find(id)
        unless person.can_sign_in?
          session[:logged_in_id] = nil
          redirect_to :controller => 'account', :action => 'bad_status'
          return false
        end
        Person.logged_in = @logged_in = person
        # some minimal session hijacking protection
        if session[:ip_address] and session[:ip_address].split('.')[0..1].join('.') != request.remote_ip.split('.')[0..1].join('.')
          session[:logged_in_id] = nil
          session[:ip_address] = nil
          logger.warn "There was an error loading the session. (Expected IP address #{session[:ip_address]} but got #{request.remote_ip})" rescue nil
          redirect_to :controller => 'people', :action => 'index'
          return false
        end
        unless @logged_in.email
          redirect_to :controller => 'account', :action => 'change_email_and_password'
          return false
        end
      elsif session[:family_id] and :action == 'change_email_and_password'
        @family = Family.find session[:family_id]
      elsif params[:action] == 'toggle_email'
        # don't do anything
      else
        redirect_to :controller => 'account', :action => 'sign_in', :from => request.request_uri
        return false
      end
    end
    
    def render_message(message)
      respond_to do |wants|
        wants.js { render(:update) { |p| p.alert message } }
        wants.html { render :text => message, :layout => true }
      end
    end
    
    def decimal_in_words(number)
      if number % 1 == 0.0
        "exactly #{number}"
      elsif number % 1 < 0.5
        "more than #{number.to_i}"
      elsif number % 1 >= 0.5
        "less than #{number.to_i + 1}"
      end
    end
    
    # stolen from ActionView::Helpers::NumberHelper
    def number_to_phone(number, options = {})
      options   = options.stringify_keys
      area_code = options.delete("area_code") { false }
      delimiter = options.delete("delimiter") { "-" }
      extension = options.delete("extension") { "" }
      begin
        str = area_code == true ? number.to_s.gsub(/([0-9]{3})([0-9]{3})([0-9]{4})/,"(\\1) \\2#{delimiter}\\3") : number.to_s.gsub(/([0-9]{3})([0-9]{3})([0-9]{4})/,"\\1#{delimiter}\\2#{delimiter}\\3")
        extension.to_s.strip.empty? ? str : "#{str} x #{extension.to_s.strip}"
      rescue
        number
      end
    end
    
    def only_admins
      unless @logged_in.admin?
        render :text => 'You must be an administrator to use this section.', :layout => true
        return false
      end
    end
end
