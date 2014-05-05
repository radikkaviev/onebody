require_relative '../test_helper'

class MessageTest < ActiveSupport::TestCase
  include MessagesHelper

  def setup
    @person, @second_person, @third_person = FactoryGirl.create_list(:person, 3)
    @admin_person = FactoryGirl.create(:person, admin: Admin.create(manage_groups: true))
    @group = Group.create! name: 'Some Group', category: 'test'
    @group.memberships.create! person: @person
  end

  should "create a new message with attachments" do
    files = [Rack::Test::UploadedFile.new(Rails.root.join('test/fixtures/files/attachment.pdf'), 'application/pdf', true)]
    @message = Message.create_with_attachments({to: @person, person: @second_person, subject: 'subject', body: 'body'}, files)
    assert_equal 1, @message.attachments.count
  end

  should "preview a message" do
    @preview = Message.preview(to: @person, person: @second_person, subject: 'subject', body: 'body')
    assert_equal 'subject', @preview.subject
    @body = get_email_body(@preview)
    assert @body.to_s.index('body')
    assert_match(/Hit "Reply" to send a message/, @body.to_s)
    assert_match(/http:\/\/.+\/privacy/, @body.to_s)
  end

  should "know who can see the message" do
    # group message
    @message = Message.create(group: @group, person: @person, subject: 'subject', body: 'body')
    assert @person.can_see?(@message)
    assert !@second_person.can_see?(@message)
    assert @admin_person.can_see?(@message)
    # group message in private group
    @group.update_attributes! private: true
    assert !@third_person.can_see?(@message)
    # private message
    @message = Message.create(to: @second_person, person: @person, subject: 'subject', body: 'body')
    assert @person.can_see?(@message)
    assert @second_person.can_see?(@message)
    assert !@third_person.can_see?(@message)
  end

  should 'allow a message without body if it has an html body' do
    @message = Message.create(subject: 'foo', html_body: 'bar', person: @person, group: @group)
    assert @message.valid?
  end

  should 'be invalid if no body or html body' do
    @message = Message.create(subject: 'foo', person: @person, group: @group)
    assert !@message.valid?
    assert @message.errors[:body].any?
  end

  should 'not allow two identical messages to be saved' do
    details = {subject: 'foo', body: 'foo', person: @person, group: @group}
    @message = Message.create!(details)
    @message2 = Message.new(details)
    assert !@message2.valid?
  end
end
