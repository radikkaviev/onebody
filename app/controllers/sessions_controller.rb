class SessionsController < ApplicationController
  skip_before_filter :authenticate_user
  before_filter :check_ssl, except: %w(destroy)
  before_filter :check_too_many_signin_failures, only: %w(create)

  def show
    redirect_to new_session_path
  end

  # sign in form
  def new
    if not Person.any?
      if Setting.get(:features, :multisite)
        @show_help = request.local?
        render action: 'no_users'
      else
        redirect_to new_setup_path
      end
    end
  end

  # sign in
  def create
    if person = Person.authenticate(params[:email], params[:password])
      unless person.can_sign_in?
        redirect_to page_for_public_path('system/unauthorized')
        return
      end
      session[:logged_in_id] = person.id
      session[:logged_in_name] = person.first_name + ' ' + person.last_name
      session[:ip_address] = request.remote_ip
      if params[:from].to_s.any?
        redirect_to 'http://' + request.host + ([80, 443].include?(request.port) ? '' : ":#{request.port}") + params[:from]
      elsif person.full_access?
        redirect_to stream_path
      else
        redirect_to person
      end
    elsif person == nil
      if family = Family.find_by_email(params[:email])
        flash[:warning] = t('session.email_found')
        redirect_to new_account_path(email: params[:email])
      else
        flash[:warning] = t('session.email_not_found_try_another')
        render action: 'new'
        flash.clear
      end
    else
      if p = Person.find_by_email(params[:email]) and p.encrypted_password.nil?
        flash[:warning] = t('session.account_not_activated_html')
      else
        flash[:warning] = t('session.password_doesnt_match')
        SigninFailure.create(email: params[:email].downcase, ip: request.remote_ip)
      end
      render action: 'new'
      flash.clear
    end
  end

  # sign out
  def destroy
    reset_session
    redirect_to new_session_path
  end

  private
    def check_ssl
      unless request.ssl? or !Rails.env.production? or !Setting.get(:features, :ssl)
        redirect_to protocol: 'https://', from: params[:from]
        return false
      end
    end

    def check_too_many_signin_failures
      if SigninFailure.matching(request).count > Setting.get(:privacy, :max_sign_in_attempts).to_i
        render text: t('session.max_sign_in_attempts'), layout: true
        return false
      end
    end

end
