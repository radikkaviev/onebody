require_relative '../spec_helper'

describe MessagesController do
  render_views

  before do
    @person, @other_person = FactoryGirl.create_list(:person, 2)
    @group = Group.create! name: 'Some Group', category: 'test'
    @group.memberships.create! person: @person
  end

  it "should delete a group message" do
    @message = @group.messages.create! subject: 'Just a Test', body: 'body', person: @person
    post :destroy, {id: @message.id}, {logged_in_id: @person.id}
    expect(response).to be_redirect
  end

  it "should create new private messages" do
    ActionMailer::Base.deliveries = []
    get :new, {to_person_id: @person.id}, {logged_in_id: @other_person.id}
    expect(response).to be_success
    post :create, {message: {to_person_id: @person.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @other_person.id}
    expect(response).to be_success
    assert_select 'body', /message.+sent/
    expect(ActionMailer::Base.deliveries).to be_any
  end

  it "should render preview of private message" do
    ActionMailer::Base.deliveries = []
    post :create, {format: 'js', preview: true, message: {to_person_id: @person.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @other_person.id}
    expect(response).to be_success
    expect(response).to render_template('create')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "should create new group messages" do
    ActionMailer::Base.deliveries = []
    get :new, {group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    post :create, {message: {group_id: @group.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @person.id}
    expect(response).to be_redirect
    expect(response).to redirect_to(group_path(@group))
    expect(flash[:notice]).to match(/has been sent/)
    expect(ActionMailer::Base.deliveries).to be_any
  end

  it "should render preview of group message" do
    ActionMailer::Base.deliveries = []
    post :create, {format: 'js', preview: true, message: {group_id: @group.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @person.id}
    expect(response).to be_success
    expect(response).to render_template('create')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "should not allow someone to post to a group they don't belong to unless they're an admin" do
    get :new, {group_id: @group.id}, {logged_in_id: @other_person.id}
    expect(response).to be_error
    post :create, {message: {group_id: @group.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @other_person.id}
    expect(response).to be_error
  end

  it "should create new group messages with an attachment" do
    ActionMailer::Base.deliveries = []
    get :new, {group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    post :create, {files: [Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/attachment.pdf'), 'application/pdf', true)], message: {group_id: @group.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @person.id}
    expect(response).to be_redirect
    expect(response).to redirect_to(group_path(@group))
    expect(flash[:notice]).to match(/has been sent/)
    expect(ActionMailer::Base.deliveries).to be_any
    expect(Message.last.attachments.count).to eq(1)
  end

  it "should create new private messages with an attachment" do
    ActionMailer::Base.deliveries = []
    get :new, {to_person_id: @person.id}, {logged_in_id: @other_person.id}
    expect(response).to be_success
    post :create, {files: [Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/attachment.pdf'), 'application/pdf', true)], message: {to_person_id: @person.id, subject: 'Hello There', body: 'body'}}, {logged_in_id: @person.id}
    expect(response).to be_success
    assert_select 'body', /message.+sent/
    expect(ActionMailer::Base.deliveries).to be_any
    expect(Message.last.attachments.count).to eq(1)
  end

  it "should not allow parent_id on message user cannot see" do
    @message = FactoryGirl.create(:message, to: @other_person)
    get :new, {parent_id: @message.id}, {logged_in_id: @person.id}
    expect(response.status).to eq(500)
    post :create, {message: {to_person_id: @other_person.id, subject: 'Hello There', body: 'body', parent_id: @message.id}}, {logged_in_id: @person.id}
    expect(response).to be_unauthorized
  end

  it "should show a message" do
    @message = @group.messages.create!(person: @person, subject: 'test subject', body: 'test body')
    get :show, {id: @message.id}, {logged_in_id: @person.id}
    expect(response).to be_success
  end

  it "should show a message with an attachment" do
    @message = Message.create_with_attachments(
      {group: @group, person: @person, subject: 'test subject', body: 'test body'},
      [Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/attachment.pdf'), 'application/pdf', true)]
    )
    @attachment = @message.attachments.first
    get :show, {id: @message.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    assert_select 'body', /attachment\.pdf/
  end

end
