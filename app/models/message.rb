require 'uri'
require 'digest/md5'

class Message < ActiveRecord::Base

  include Authority::Abilities
  self.authorizer_name = 'MessageAuthorizer'

  MESSAGE_ID_RE = /<(\d+)_([0-9abcdef]{6})_/
  MESSAGE_ID_RE_IN_BODY = /id:\s*(\d+)_([0-9abcdef]{6})/i

  belongs_to :group
  belongs_to :person
  belongs_to :to, class_name: 'Person', foreign_key: 'to_person_id'
  belongs_to :parent, class_name: 'Message', foreign_key: 'parent_id'
  has_many :children, -> { where('to_person_id is null') }, class_name: 'Message', foreign_key: 'parent_id', dependent: :destroy
  has_many :attachments, dependent: :destroy
  has_many :log_items, -> { where(loggable_type: 'Message') }, foreign_key: 'loggable_id'
  belongs_to :site

  scope_by_site_id

  scope :same_as, -> m { where('id != ?', m.id || 0).where(person_id: m.person_id, subject: m.subject, body: m.body, to_person_id: m.to_person_id, group_id: m.group_id).where('created_at >= ?', 1.day.ago) }

  validates_presence_of :person_id
  validates_presence_of :subject
  validates_length_of :subject, minimum: 2

  validates_each :to_person_id, allow_nil: true do |record, attribute, value|
    if attribute.to_s == 'to_person_id' and value and record.to and record.to.email.nil?
      record.errors.add attribute, :invalid
    end
  end

  validates_each :body do |record, attribute, value|
    if attribute.to_s == 'body' and value.to_s.blank? and record.html_body.to_s.blank?
      record.errors.add attribute, :blank
    end
  end

  def name
    if self.to
      "Private Message to #{to.name rescue '[deleted]'}"
    elsif parent
      "Reply to \"#{parent.subject}\" in Group #{top.group.name rescue '[deleted]'}"
    else
      "Message \"#{subject}\" in Group #{group.name rescue '[deleted]'}"
    end
  end

  def top
    top = self
    while top.parent
      top = top.parent
    end
    return top
  end

  before_save :remove_unsubscribe_link

  def remove_unsubscribe_link
    if body
      body.gsub!(/http:\/\/.*?person_id=\d+&code=\d+/i, '--removed--')
    end
    if html_body
      html_body.gsub!(/http:\/\/.*?person_id=\d+&code=\d+/i, '--removed--')
    end
  end

  before_save :remove_message_id_in_body

  def remove_message_id_in_body
    if body
      body.gsub! MESSAGE_ID_RE_IN_BODY, ''
    end
    if html_body
      html_body.gsub! MESSAGE_ID_RE_IN_BODY, ''
    end
  end

  validate on: :create do |record|
    if Message.same_as(self).any?
      record.errors.add :base, 'already saved' # Notifier relies on this message (don't change it)
      record.errors.add :base, :taken
    end
    if record.subject =~ /Out of Office/i
      record.errors.add :base, 'autoreply' # don't change!
    end
  end

  attr_accessor :dont_send

  after_create :send_message

  def send_message
    return if dont_send
    if group
      send_to_group
    elsif to
      send_to_person(to)
    end
  end

  def send_to_person(person)
    if person.email.to_s.any?
      email = Notifier.full_message(person, self, id_and_code)
      email.add_message_id
      email.message_id = "<#{id_and_code}_#{email.message_id.gsub(/^</, '')}"
      email.deliver_now
    end
  end

  def send_to_group(sent_to=[])
    return unless group
    group.people.each do |person|
      if should_send_group_email_to_person?(person, sent_to)
        send_to_person(person)
        sent_to << person.email
      end
    end
  end

  def should_send_group_email_to_person?(person, sent_to)
    person.email.present? and
    person.email =~ VALID_EMAIL_ADDRESS and
    group.get_options_for(person).get_email? and
    not sent_to.include?(person.email)
  end

  def id_and_code
    "#{self.id.to_s}_#{Digest::MD5.hexdigest(code.to_s)[0..5]}"
  end

  # TODO remove
  def introduction(to_person)
    ''
  end

  def reply_url
    if group
      "#{Setting.get(:url, :site)}messages/view/#{self.id.to_s}"
    else
      reply_subject = self.subject
      reply_subject = "RE: #{subject}" unless reply_subject =~ /^re:/i
      "#{Setting.get(:url, :site)}messages/send_email/#{self.person.id}?subject=#{URI.escape(reply_subject)}"
    end
  end

  def reply_instructions(to_person)
    msg = ''
    if to
      msg << "Hit \"Reply\" to send a message to #{self.person.name rescue 'the sender'} only.\n"
    elsif group
      msg << "Hit \"Reply\" to send a message to #{self.person.name rescue 'the sender'} only.\n"
      if group.can_post? to_person
        if group.address.to_s.any?
          msg << "Hit \"Reply to All\" to send a message to the group, or send to: #{group.address + '@' + Site.current.email_host}\n"
          msg << "Group page: #{Setting.get(:url, :site)}groups/#{group.id}\n"
        else
          msg << "To reply: #{reply_url}\n"
        end
      end
    end
    msg
  end

  def disable_email_instructions(to_person)
    msg = ''
    if group
      msg << "To stop email from this group: "
      if new_record?
        msg << '-link to turn off email-'
      else
        msg << disable_group_email_link(to_person)
      end
    else
      msg << "To stop these emails, go to your privacy page:\n#{Setting.get(:url, :site)}privacy"
    end
    msg + "\n"
  end

  def disable_group_email_link(to_person)
    "#{Setting.get(:url, :site)}groups/#{group.id}/memberships/#{to_person.id}?code=#{to_person.feed_code}&email=off"
  end

  def email_from(to_person)
    if group
      from_address("#{person.name} [#{group.name}]")
    else
      from_address(person.name)
    end
  end

  def email_reply_to(to_person)
    if not to_person.messages_enabled?
      "\"DO NOT REPLY\" <#{Site.current.noreply_email}>"
    else
      from_address(person.name, :real)
    end
  end

  def from_address(name, real=false)
    if person.email.present?
      %("#{name.gsub(/"/, '')}" <#{real ? person.email : Site.current.noreply_email}>)
    else
      "\"DO NOT REPLY\" <#{Site.current.noreply_email}>"
    end
  end

  before_create :generate_security_code

  def generate_security_code
    begin
      code = rand(999999)
      write_attribute :code, code
    end until code > 0
  end

  def code_hash
    Digest::MD5.hexdigest(code.to_s)[0..5]
  end

  def streamable?
    person_id and not to_person_id and group
  end

  after_create :create_as_stream_item

  def create_as_stream_item
    return unless streamable?
    StreamItem.create!(
      title:           subject,
      body:            html_body.to_s.any? ? html_body : body,
      text:            !html_body.to_s.any?,
      person_id:       person_id,
      group_id:        group_id,
      streamable_type: 'Message',
      streamable_id:   id,
      created_at:      created_at,
      shared:          !!group
    )
  end

  after_update :update_stream_items

  def update_stream_items
    return unless streamable?
    StreamItem.where(streamable_type: "Message", streamable_id: id).each do |stream_item|
      stream_item.title = subject
      if html_body.to_s.any?
        stream_item.body = html_body
        stream_item.text = false
      else
        stream_item.body = body
        stream_item.text = true
      end
      stream_item.save
    end
  end

  after_destroy :delete_stream_items

  def delete_stream_items
    StreamItem.destroy_all(streamable_type: 'Message', streamable_id: id)
  end

  def self.preview(attributes)
    msg = Message.new(attributes)
    Notifier.full_message(Person.new(email: 'test@example.com'), msg)
  end

  def self.create_with_attachments(attributes, files)
    message = Message.create(attributes.update(dont_send: true))
    unless message.errors.any?
      files.select { |f| f && f.size > 0 }.each do |file|
        attachment = message.attachments.create(
          name:         File.split(file.original_filename).last,
          content_type: file.content_type,
          file:         file
        )
        if attachment.errors.any?
          attachment.errors.each_full { |e| message.errors.add(:base, e) }
          return message
        end
      end
      message.dont_send = false
      message.send_message
    end
    message
  end

  def self.daily_counts(limit, offset, date_strftime='%Y-%m-%d', only_show_date_for=nil)
    [].tap do |data|
      private_counts = connection.select_all("select count(date(created_at)) as count, date(created_at) as date from messages where to_person_id is not null and site_id=#{Site.current.id} group by date(created_at) order by created_at desc limit #{limit.to_i} offset #{offset.to_i};").group_by { |p| Date.parse(p['date'].strftime('%Y-%m-%d')) }
      group_counts   = connection.select_all("select count(date(created_at)) as count, date(created_at) as date from messages where group_id     is not null and site_id=#{Site.current.id} group by date(created_at) order by created_at desc limit #{limit.to_i} offset #{offset.to_i};").group_by { |p| Date.parse(p['date'].strftime('%Y-%m-%d')) }
      ((Date.today-offset-limit+1)..(Date.today-offset)).each do |date|
        d = date.strftime(date_strftime)
        d = ' ' if only_show_date_for and date.strftime(only_show_date_for[0]) != only_show_date_for[1]
        private_count = private_counts[date] ? private_counts[date][0]['count'].to_i : 0
        group_count   = group_counts[date]   ? group_counts[date][0]['count'].to_i   : 0
        data << [d, private_count, group_count]
      end
    end
  end
end
