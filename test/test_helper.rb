ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/application', __FILE__)
require 'rails/test_help'
#require 'notifier'
require 'rake'
require File.expand_path('../../lib/rake_abandon', __FILE__)
OneBody::Application.load_tasks

# flatten settings hash and write to fixture file
Rake::Task['onebody:build_settings_fixture_file'].invoke

require File.dirname(__FILE__) + '/forgeries'

class ActiveSupport::TestCase

  self.use_transactional_fixtures = true
  self.use_instantiated_fixtures  = false

  def sign_in_as(person, password='secret')
    sign_in_and_assert_name(person.email, person.name, password)
  end

  def sign_in_and_assert_name(email, name, password='secret')
    post_sign_in_form(email, password)
    assert_response :redirect
    follow_redirect!
    assert_template 'streams/show'
    assert_select 'h1', Regexp.new(name)
  end

  def post_sign_in_form(email, password='secret')
    Setting.set_global('Features', 'SSL', true)
    post '/session', :email => email, :password => password
  end

  def view_profile(person)
    get "/people/#{person.id}"
    assert_response :success
    assert_template 'people/show'
    assert_select 'h1', Regexp.new(person.name)
  end

  def site!(site)
    host! site
    get '/'
  end

  def assert_deliveries(count)
    assert_equal count, ActionMailer::Base.deliveries.length
  end

  def assert_emails_delivered(email, people)
    people.each do |person|
      matches = ActionMailer::Base.deliveries.select do |delivered|
        delivered.subject == email.subject and \
        delivered.body.to_s.index(email.body.to_s) and \
        delivered.to == [person.email]
      end
      assert_equal 1, matches.length
    end
  end

  fixtures :all
end
