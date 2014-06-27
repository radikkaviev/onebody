class SetupsController < ApplicationController

  skip_before_filter :authenticate_user
  before_filter :check_setup_requirements

  layout 'signed_out'

  def show
    redirect_to new_setup_path
  end

  def new
    @person = Person.new
  end

  def create
    @setup = Setup.new(params.permit!)
    if @setup.execute!
      flash[:notice] = t('setup.complete_html', url: admin_path).html_safe
      session[:logged_in_id] = @setup.person.id
      redirect_to root_path
    else
      @person = @setup.person
      render action: 'new'
    end
  end

  private

    def check_setup_requirements
      if Person.count > 0
        render text: t('not_authorized'), layout: true
        return false
      end
    end

end
