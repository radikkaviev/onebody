class Person < ActiveRecord::Base
  include Authority::UserAbilities
  include Authority::Abilities
  self.authorizer_name = 'PersonAuthorizer'

  MAX_TO_BATCH_AT_A_TIME = 50

  cattr_accessor :logged_in # set in addition to @logged_in (for use by Notifier and other models)

  belongs_to :family
  belongs_to :admin
  has_many :memberships, dependent: :destroy
  has_many :membership_requests, dependent: :destroy
  has_many :groups, through: :memberships
  has_many :albums, as: :owner
  has_many :pictures, -> { order(created_at: :desc) }
  has_many :messages
  has_many :notes, -> { order(created_at: :desc) }
  has_many :updates, -> { order(:created_at) }
  has_many :prayer_signups
  has_and_belongs_to_many :verses
  has_many :log_items
  has_many :stream_items
  has_many :friendships
  has_many :friends, -> { order('people.last_name', 'people.first_name') }, class_name: 'Person', through: :friendships
  has_many :friendship_requests
  has_many :pending_friendship_requests, -> { where(rejected: false) }, class_name: 'FriendshipRequest'
  has_many :relationships, dependent: :delete_all
  has_many :related_people, class_name: 'Person', through: :relationships, source: :related
  has_many :inward_relationships, class_name: 'Relationship', foreign_key: 'related_id', dependent: :delete_all
  has_many :inward_related_people, class_name: 'Person', through: :inward_relationships, source: :person
  has_many :prayer_requests, -> { order(created_at: :desc) }
  has_many :attendance_records
  has_many :stream_items
  has_many :generated_files
  has_one :stream_item, as: :streamable
  belongs_to :site

  scope_by_site_id

  scope :undeleted, -> { where(deleted: false) }
  scope :deleted, -> { where(deleted: true) }
  scope :adults, -> { where(child: false) }
  scope :adults_or_have_consent, -> { where("child = 0 or coalesce(parental_consent, '') != ''") }
  scope :children, -> { where(child: true) }
  scope :can_sign_in, -> { undeleted.where(can_sign_in: true) }
  scope :administrators, -> { undeleted.where('admin_id is not null') }
  scope :email_changed, -> { undeleted.where(email_changed: true) }
  scope :minimal, -> { select('people.id, people.first_name, people.last_name, people.suffix, people.child, people.gender, people.birthday, people.gender, people.photo_file_name, people.photo_content_type, people.photo_fingerprint, people.photo_updated_at, people.deleted') }
  scope :with_birthday_month, -> m { where('birthday is not null and month(birthday) = ?', m) }

  has_attached_file :photo, PAPERCLIP_PHOTO_OPTIONS

  validates_presence_of :first_name, :last_name
  validates_length_of :password, minimum: 5, allow_nil: true, if: Proc.new { Person.logged_in }
  validates_length_of :description, maximum: 25
  validates_confirmation_of :password, if: Proc.new { Person.logged_in }
  validates_uniqueness_of :alternate_email, allow_nil: true, scope: [:site_id, :deleted], unless: Proc.new { |p| p.deleted? }
  validates_uniqueness_of :feed_code, allow_nil: true, scope: :site_id
  validates_format_of :website, allow_nil: true, allow_blank: true, with: /\Ahttps?\:\/\/.+/
  validates_format_of :business_website, allow_nil: true, allow_blank: true, with: /\Ahttps?\:\/\/.+/
  validates_format_of :business_email, allow_nil: true, allow_blank: true, with: VALID_EMAIL_ADDRESS
  validates_format_of :email, allow_nil: true, allow_blank: true, with: VALID_EMAIL_ADDRESS
  validates_format_of :alternate_email, allow_nil: true, allow_blank: true, with: VALID_EMAIL_ADDRESS
  validates_exclusion_of :business_category, in: ['!']
  validates_inclusion_of :gender, in: %w(Male Female), allow_nil: true
  validates_date_of :birthday, :anniversary, allow_nil: true
  validates_attachment_size :photo, less_than: PAPERCLIP_PHOTO_MAX_SIZE
  validates_attachment_content_type :photo, content_type: PAPERCLIP_PHOTO_CONTENT_TYPES
  validate :validate_email_unique

  def validate_email_unique
    return unless email.present? and not deleted?
    if Person.where("email = ? and family_id != ? and id != ? and deleted = ?", email, family_id || 0, id || 0, false).any?
      errors.add :email, :taken
    end
  end

  lowercase_attribute :email, :alternate_email

  after_initialize :guess_last_name, if: -> p { p.last_name.nil? }

  def guess_last_name
    return unless family
    self.last_name = family.last_name
  end

  after_create :create_as_stream_item

  def create_as_stream_item
    StreamItem.create!(
      title: name,
      person_id: id,
      streamable_type: 'Person',
      streamable_id: id,
      created_at: created_at,
      shared: visible? && email.present?
    )
  end

  after_update :update_stream_item

  def update_stream_item
    return unless stream_item
    stream_item.title = name
    stream_item.shared = visible? && email.present?
    stream_item.save!
  end

  def name
    @name ||= begin
      if deleted?
        "(removed person)"
      elsif suffix
        "#{first_name} #{last_name}, #{suffix}" rescue '???'
      else
        "#{first_name} #{last_name}" rescue '???'
      end
    end
  end

  # FIXME this assumes English - how to fix?
  def name_possessive
    name =~ /s$/ ? "#{name}'" : "#{name}'s"
  end

  def inspect
    "<#{name}>"
  end

  # FIXME deprecated
  def self.can_create?
    true
  end

  def birthday_soon?
    today = Date.today
    birthday and ((birthday.yday()+365 - today.yday()).modulo(365) < BIRTHDAY_SOON_DAYS)
  end

  fall_through_attributes :home_phone, :address, :address1, :address2, :city, :state, :zip, :short_zip, :mapable?, to: :family
  sharable_attributes     :home_phone, :mobile_phone, :work_phone, :fax, :email, :birthday, :address, :anniversary, :activity

  self.skip_time_zone_conversion_for_attributes = [:birthday, :anniversary]
  self.digits_only_for_attributes = [:mobile_phone, :work_phone, :fax, :business_phone]

  def groups_sharing(attribute)
    memberships.where(["share_#{attribute.to_s} = ?", true]).map(&:group)
  end

  def can_sign_in?
    read_attribute(:can_sign_in) and adult_or_consent?
  end

  def messages_enabled?
    read_attribute(:messages_enabled) and email.present?
  end

  # deprecated
  alias_method :can_see?, :can_read?
  alias_method :can_edit?, :can_update?

  def member_of?(group)
    memberships.where(group_id: group.id).any?
  end

  def birthday=(d)
    if d.is_a?(String) and d.length > 0 and date = Date.parse_in_locale(d).try(:rfc3339)
      self[:birthday] = date
    else
      self[:birthday] = d
    end
  end

  def anniversary=(d)
    if d.is_a?(String) and d.length > 0 and date = Date.parse_in_locale(d).try(:rfc3339)
      self[:anniversary] = date
    else
      self[:anniversary] = d
    end
  end

  def parental_consent?; parental_consent.present?; end
  def adult_or_consent?; adult? or parental_consent?; end

  def visible?(fam=nil)
    fam ||= self.family
    fam and fam.visible? and read_attribute(:visible) and adult_or_consent? and visible_to_everyone?
  end

  def admin?(perm=nil)
    if super_admin?
      true
    elsif perm
      admin and admin.flags[perm.to_s]
    else
      admin ? true : false
    end
  end

  def super_admin?
    (admin and admin.super_admin?) or global_super_admin?
  end

  def global_super_admin?
    defined?(GLOBAL_SUPER_ADMIN_EMAIL) and GLOBAL_SUPER_ADMIN_EMAIL.present? and email == GLOBAL_SUPER_ADMIN_EMAIL
  end

  def valid_email?
    email.to_s.strip =~ VALID_EMAIL_ADDRESS
  end

  def gender=(g)
    if g.to_s.strip.blank?
      g = nil
    else
      g = g.capitalize
    end
    write_attribute(:gender, g)
  end

  # get the parents/guardians by grabbing people in family sequence 1 and 2 and adult?
  def parents
    if family
      family.people.select { |p| !p.deleted? and p.adult? and [1, 2].include?(p.sequence) }
    end
  end

  def active?
    log_items.count(["created_at >= ?", 1.day.ago]) > 0
  end

  def has_favs?
    %w(activities interests music tv_shows movies books quotes).detect do |fav|
      self.send(fav).present?
    end ? true : false
  end

  def access_attributes
    self.attributes.keys.grep(/_access$/).reject { |a| a == 'full_access' }
  end

  # generates security code for grabbing feed(s) without logging in
  before_create :update_feed_code
  def update_feed_code
    begin # ensure unique
      code = SecureRandom.hex(50)[0...50]
      write_attribute :feed_code, code
    end while Person.where(feed_code: code).count > 0
  end

  def generate_api_key
    write_attribute :api_key, SecureRandom.hex(50)[0...50]
  end

  attr_writer :no_auto_sequence

  before_save :update_sequence
  def update_sequence
    return if @no_auto_sequence
    if family and sequence.nil?
      scope = family.people.undeleted
      scope = scope.where('id != ?', id) unless new_record?
      self.sequence = scope.maximum(:sequence).to_i + 1
    end
  end

  def can_edit_profile?
    admin?(:edit_profiles) or not Setting.get(:features, :updates_must_be_approved)
  end

  def suffix=(s)
    s = nil if s.blank?
    write_attribute(:suffix, s)
  end

  def email_changed?
    self[:email_changed]
  end

  attr_accessor :dont_mark_email_changed

  before_update :mark_email_changed
  def mark_email_changed
    return if dont_mark_email_changed
    if changed.include?('email')
      write_attribute(:email_changed, true)
      Notifier.email_update(self).deliver
    end
  end

  def show_attribute_to?(attribute, who)
    send(attribute).to_s.strip.any? and
    (not respond_to?("share_#{attribute}_with?") or
    send("share_#{attribute}_with?", who))
  end

  def age_group
    the_classes = self.classes.to_s.split(',')
    if the_class = the_classes.detect { |c| c =~ /^AG:/ }
      the_class.match(/^AG:(.+)$/)[1]
    end
  end

  def attendance_today
    attendance_records.on_date(Date.today).includes(:group).order(:attended_at)
  end

  def update_relationships_hash
    rels = relationships.includes(:related).to_a.select do |relationship|
      !Setting.get(:system, :online_only_relationships).include?(relationship.name_or_other)
    end.map do |relationship|
      "#{relationship.related.legacy_id}[#{relationship.name_or_other}]"
    end.sort
    self.relationships_hash = Digest::SHA1.hexdigest(rels.join(','))
  end

  def update_relationships_hash!
    update_relationships_hash
    save(validate: false)
  end

  alias_method :destroy_for_real, :destroy
  def destroy
    self.update_attribute(:deleted, true)
    self.updates.destroy_all
    self.memberships.destroy_all
    self.friendships.destroy_all
    self.membership_requests.destroy_all
    self.friendship_requests.destroy_all
    self.stream_item.try(:destroy)
  end

  def set_default_visibility
    self.can_sign_in = true
    self.visible_to_everyone = true
    self.visible_on_printed_directory = true
    self.full_access = true
  end

  class << self

    def new_with_default_sharing(attrs)
      attrs.symbolize_keys! if attrs.respond_to?(:symbolize_keys!)
      attrs.merge!(
        share_address:      Setting.get(:privacy, :share_address_by_default     ),
        share_home_phone:   Setting.get(:privacy, :share_home_phone_by_default  ),
        share_mobile_phone: Setting.get(:privacy, :share_mobile_phone_by_default),
        share_work_phone:   Setting.get(:privacy, :share_work_phone_by_default  ),
        share_fax:          Setting.get(:privacy, :share_fax_by_default         ),
        share_email:        Setting.get(:privacy, :share_email_by_default       ),
        share_birthday:     Setting.get(:privacy, :share_birthday_by_default    ),
        share_anniversary:  Setting.get(:privacy, :share_anniversary_by_default )
      )
      new(attrs)
    end

    # used to update a batch of records at one time, for UpdateAgent API
    def update_batch(records, options={})
      raise "Too many records to batch at once (#{records.length})" if records.length > MAX_TO_BATCH_AT_A_TIME
      records.map do |record|
        person = where(legacy_id: record["legacy_id"]).first
        # find the family (by legacy_id, preferably)
        family_id = Family.connection.select_value("select id from families where legacy_id = #{record['legacy_family_id'].to_i} and site_id = #{Site.current.id}")
        if person.nil? and options['claim_families_by_barcode_if_no_legacy_id'] and family_id
          # family should have already been claimed by barcode -- we're just going to try to match up people by name
          if person = where(family_id: family_id, legacy_id: nil, first_name: record['first_name'], last_name: record['last_name']).first
            person.deleted = false
          end
        end
        # last resort, create a new record
        person ||= new
        person.family_id = family_id
        record.each do |key, value|
          value = nil if value == ''
          # avoid overwriting a newer email address
          if key == 'email' and person.email_changed?
            if value == person.email # email now matches (presumably, the external db has been updated to match the OneBody db)
              person.email_changed = false # clear the flag
            else
              next # don't overwrite the newer email address with an older one
            end
          elsif %w(family email_changed remote_hash relationships relationships_hash).include?(key) # skip these
            next
          end
          person.send("#{key}=", value) # be sure to call the actual method (don't use write_attribute)
        end
        person.dont_mark_email_changed = true # set flag to indicate we're the api
        if person.save
          if record['relationships_hash'] != person.relationships_hash
            person.relationships.to_a.select do |relationship|
              !Setting.get(:system, :online_only_relationships).include?(relationship.name_or_other)
            end.each { |r| r.delete }
            record['relationships'].to_s.split(',').each do |relationship|
              if relationship =~ /(\d+)\[([^\]]+)\]/ and related = Person.where(legacy_id: $1).first
                person.relationships.create(
                  related:    related,
                  name:       'other',
                  other_name: $2
                )
              end
            end
            person.update_relationships_hash!
          end
          s = {status: 'saved', legacy_id: person.legacy_id, id: person.id, name: person.name}
          if person.email_changed? # email_changed flag still set
            s[:status] = 'saved with error'
            s[:error] = "Newer email not overwritten: #{person.email.inspect}"
          end
          s
        else
          {status: 'not saved', legacy_id: record['legacy_id'], id: person.id, name: person.name, error: person.errors.full_messages.join('; ')}
        end
      end
    end

    def business_categories
      connection.select("select distinct business_category as name from people where business_category is not null and business_category != '' and site_id = #{Site.current.id} order by business_category").map { |c| c['name'] }
    end

    def custom_types
      connection.select("select distinct custom_type as name from people where custom_type is not null and custom_type != '' and site_id = #{Site.current.id} order by custom_type").map { |t| t['name'] }
    end

  end

  # FIXME why does these have to be at the bottom?
  include Concerns::Person::Child
  include Concerns::Person::Password
  include Concerns::Person::Friend
  include Concerns::Person::Sharing
  include Concerns::Person::Import
  include Concerns::Person::Export
  include Concerns::Person::PdfGen
end
