class Group < ActiveRecord::Base
  has_many :memberships, :dependent => :destroy
  has_many :membership_requests, :dependent => :destroy
  has_many :people, :through => :memberships do
    def thumbnails
      # TODO figure out why select is changed to include people.*
      self.all(:select => 'people.id, people.first_name, people.last_name, people.suffix, people.gender, people.photo_file_name, people.photo_content_type, people.photo_fingerprint', :order => 'people.last_name, people.first_name')
    end
  end
  has_many :admins, :through => :memberships, :source => :person, :order => 'last_name, first_name', :conditions => ['memberships.admin = ?', true]
  has_many :messages, :conditions => 'parent_id is null', :order => 'updated_at desc', :dependent => :destroy
  has_many :notes, :order => 'created_at desc'
  has_many :prayer_requests, :order => 'created_at desc'
  has_many :attendance_records
  has_many :albums
  has_many :stream_items, :dependent => :destroy
  has_many :attachments, :dependent => :delete_all
  belongs_to :creator, :class_name => 'Person', :foreign_key => 'creator_id'
  belongs_to :leader, :class_name => 'Person', :foreign_key => 'leader_id'
  belongs_to :parents_of_group, :class_name => 'Group', :foreign_key => 'parents_of'
  belongs_to :site

  scope :active, :conditions => {:hidden => false}

  scope_by_site_id

  attr_accessible :name, :description, :meets, :location, :directions, :other_notes, :address, :members_send, :private, :category, :leader_id, :blog, :email, :prayer, :attendance, :gcal_private_link, :approval_required_to_join, :pictures, :cm_api_list_id
  attr_accessible :approved, :link_code, :parents_of, :hidden, :if => Proc.new { Person.logged_in && Person.logged_in.admin?(:manage_groups) }

  validates_presence_of :name
  validates_presence_of :category
  validates_uniqueness_of :name, :scope => :site_id
  validates_format_of :address, :with => /^[a-zA-Z0-9]+$/, :allow_nil => true
  validates_uniqueness_of :address, :allow_nil => true, :scope => :site_id
  validates_length_of :address, :in => 2..30, :allow_nil => true
  validates_uniqueness_of :cm_api_list_id, :allow_nil => true, :allow_blank => true, :scope => :site_id
  validates_attachment_size :photo, :less_than => PAPERCLIP_PHOTO_MAX_SIZE
  validates_attachment_content_type :photo, :content_type => PAPERCLIP_PHOTO_CONTENT_TYPES

  serialize :cached_parents

  validate :validate_self_referencing_parents_of

  def validate_self_referencing_parents_of
    begin
      errors.add('parents_of', :points_to_self) if not new_record? and parents_of == id
    rescue
      puts 'error checking for self-referencing parents_of (OK if you are migrating)'
    end
  end

  has_attached_file :photo, PAPERCLIP_PHOTO_OPTIONS
  acts_as_logger LogItem

  scope :checkin_destinations, :include => :group_times, :conditions => ['group_times.checkin_time_id is not null'], :order => 'group_times.ordering'

  def name_group # returns something like "Morgan group"
    "#{name}#{name =~ /group$/i ? '' : ' group'}"
  end

  def inspect
    "<#{name}>"
  end

  def self.can_create?
    Site.current.max_groups.nil? or Group.active.count < Site.current.max_groups
  end

  def admin?(person, exclude_global_admins=false)
    if person
      if exclude_global_admins
        admins.include? person
      else
        person.admin?(:manage_groups) or admins.include? person
      end
    end
  end

  def last_admin?(person)
    person and admin?(person, :exclude_global_admins) and admins.length == 1
  end

  def linked?
    link_code and link_code.any?
  end

  def mapable?
    # must look like "OK 74137"
    # TODO: this needs some work to be usable in other countries
    location.to_s.any? && location =~ /\s[A-Z]{2}\s+\d{5}/ ? true : false
  end

  def address=(a)
    write_attribute(:address, a == '' ? nil : a)
  end

  def get_options_for(person)
    memberships.find_by_person_id(person.id)
  end

  def set_options_for(person, options)
    memberships.find_by_person_id(person.id).update_attributes!(options)
  end

  after_save :update_memberships

  def update_memberships
    if parents_of
      parents = Group.find(parents_of).people.map { |p| p.parents }.flatten.uniq
      update_membership_associations(parents)
    elsif linked?
      conditions = []
      link_code.downcase.split.each do |code|
        conditions.add_condition ["#{sql_lcase('classes')} = ? or #{sql_lcase('classes')} like ? or #{sql_lcase('classes')} like ? or #{sql_lcase('classes')} like ? or #{sql_lcase('classes')} like ? or #{sql_lcase('classes')} like ?", code, "#{code},%", "%,#{code}", "%,#{code},%", "#{code}[%", "%,#{code}[%"], 'or'
      end
      update_membership_associations(Person.find(:all, :conditions => conditions))
    elsif Membership.column_names.include?('auto')
      memberships.find_all_by_auto(true).each { |m| m.destroy }
    end
    if respond_to?(:cm_api_list_id) and cm_api_list_id.to_s.any? and Setting.get(:services, :campaign_monitor_api_key).to_s.any?
      sync_with_campaign_monitor
    end
    # have to expire the group fragments here since this is run in background nightly
    ActionController::Base.cache_store.delete_matched(%r{groups/#{id}})
  end

  def update_membership_associations(new_people)
    new_people.reject! { |p| p.deleted? }
    self.people.reload
    (new_people - self.people).each { |p| memberships.create!(:person => p, :auto => true) }
    ids_to_delete = (self.people - new_people).each { |p| p.id }
    Membership.delete_all(["group_id = ? and person_id in (?) and auto = ?", id, ids_to_delete, true])
  end

  def can_send?(person)
    (members_send and person.member_of?(self) and person.messages_enabled?) or admin?(person)
  end
  alias_method 'can_post?', 'can_send?'

  def can_share?(person)
    person.member_of?(self) and \
      (
        (email? and can_post?(person)) or \
        blog? or \
        pictures? or \
        prayer?
      )
  end

  def full_address
    address.to_s.any? ? (address + '@' + Site.current.host) : nil
  end

  def get_people_attendance_records_for_date(date)
    records = {}
    people.each { |p| records[p.id] = [p, false] }
    date = Date.parse(date) if(date.is_a?(String))
    attendance_records.all(:conditions => ['attended_at >= ? and attended_at <= ?', date.strftime('%Y-%m-%d 0:00'), date.strftime('%Y-%m-%d 23:59:59')]).each do |record|
      records[record.person.id] = [record.person, record]
    end
    records.values.sort_by { |r| [r[0].last_name, r[0].first_name] }
  end

  def attendance_dates
    attendance_records.find_by_sql("select distinct attended_at from attendance_records where group_id = #{id} and site_id = #{Site.current.id} order by attended_at desc").map { |r| r.attended_at }
  end

  def gcal_url
    if gcal_private_link.to_s.any?
      if token = gcal_token
        "https://www.google.com/calendar/embed?pvttk=#{token}&amp;showTitle=0&amp;showCalendars=0&amp;showTz=1&amp;height=600&amp;wkst=1&amp;bgcolor=%23FFFFFF&amp;src=#{gcal_account}&amp;color=%23A32929&amp;ctz=#{Time.zone.tzinfo.name}"
      end
    end
  end

  def gcal_account
    gcal_private_link.to_s.match(/[a-z0-9\._]+(@|%40)[a-z\.]+/).to_s.sub(/@/, '%40')
  end

  def gcal_token
    gcal_private_link.to_s.match(/private\-([a-z0-9]+)/)[1] rescue ''
  end

  def shared_stream_items(count)
    items = stream_items.all(
      :order => 'stream_items.created_at desc',
      :limit => count,
      :include => :person
    )
    # do our own eager loading here...
    comment_people_ids = items.map { |s| s.context['comments'].to_a.map { |c| c['person_id'] } }.flatten
    comment_people = Person.all(
      :conditions => ["id in (?)", comment_people_ids],
      :select => 'first_name, last_name, suffix, gender, id, family_id, updated_at, photo_file_name, photo_fingerprint' # only what's needed
    ).inject({}) { |h, p| h[p.id] = p; h } # as a hash with id as the key
    items.each do |stream_item|
      stream_item.context['comments'].to_a.each do |comment|
        comment['person'] = comment_people[comment['person_id']]
      end
      stream_item.readonly!
    end
    items
  end

  before_destroy :remove_parent_of_links

  def remove_parent_of_links
    Group.find_all_by_parents_of(id).each { |g| g.update_attribute(:parents_of, nil) }
  end

  def sync_with_campaign_monitor
    return unless (api_key = Setting.get(:services, :campaign_monitor_api_key)).to_s.any?
    return unless cm_api_list_id.to_s.any?
    cm = CampaignMonitorParty.new(api_key)
    in_group = self.people.all(:conditions => ['memberships.get_email = ?', true]).select { |p| p.email.to_s.any? }
    unsubscribed = cm.Subscribers.GetUnsubscribed('ListID' => cm_api_list_id, 'Date' => '2000-01-01 00:00:00')['anyType']['Subscriber'].to_a.map { |s| [s['Name'], s['EmailAddress']] }
    # ensure we don't resubscribe someone who has already unsubscribed
    # (and also set their get_email attribute to false in the group)
    upload_to_cm = []
    in_group.each do |person|
      if unsubscribed.map { |p| p[1].downcase }.include?(person.email.downcase)
        person.memberships.find_by_group_id(self.id).update_attribute(:get_email, false)
      else
        upload_to_cm << [person.name, person.email]
      end
    end
    # unsubscribe addresses in the subscriber list but not found in the group
    subscribed = cm.Subscribers.GetActive('ListID' => cm_api_list_id, 'Date' => '2000-01-01 00:00:00')['anyType']['Subscriber'].to_a.map { |s| [s['Name'], s['EmailAddress']] }
    subscribed.each do |name, email|
      if not upload_to_cm.any? { |n, e| e.downcase == email.downcase }
        cm.Subscriber.Unsubscribe('ListID' => cm_api_list_id, 'Email' => email)
      end
    end
    # subscribe addresses in the group but not in the subscriber list
    upload_to_cm.each do |name, email|
      if not subscribed.any? { |n, e| e.downcase == email.downcase }
        cm.Subscriber.Add('ListID' => cm_api_list_id, 'Email' => email, 'Name' => name)
      end
    end
  end

  class << self
    def update_memberships
      all(:order => 'parents_of').each { |group| group.update_memberships }
    end

    def categories
      {}.tap do |cats|
        if Person.logged_in.admin?(:manage_groups)
          results = Group.find_by_sql("select category, count(*) as group_count from groups where category is not null and category != '' and category != 'Subscription' and site_id = #{Site.current.id} group by category").map { |g| [g.category, g.group_count] }
        else
          results = Group.find_by_sql(["select category, count(*) as group_count from groups where category is not null and category != '' and category != 'Subscription' and hidden = ? and approved = ? and site_id = #{Site.current.id} group by category", false, true]).map { |g| [g.category, g.group_count] }
        end
        results.each do |cat, count|
          cats[cat] = count.to_i
        end
      end
    end

    def category_names
      categories.keys.sort
    end

    def count_by_type
      {
        :public             => Group.count('id', :conditions => {:private => false, :hidden => false}),
        :private            => Group.count('id', :conditions => {:private => true,  :hidden => false}),
      }.reject { |k, v| v == 0 }
    end

    def count_by_linked
      {
        :standard           => Group.count('id', :conditions => "parents_of is null and (link_code is null or link_code = '')"),
        :linked             => Group.count('id', :conditions => "link_code is not null and link_code != ''"),
        :parents_of         => Group.count('id', :conditions => "parents_of is not null")
      }.reject { |k, v| v == 0 }
    end

    EXPORT_COLS = {
      :group => %w(
        name
        description
        meets
        location
        directions
        other_notes
        creator_id
        address
        members_send
        private
        category
        leader_id
        updated_at
        hidden
        approved
        link_code
        parents_of
        blog
        email
        prayer
        attendance
        legacy_id
        gcal_private_link
        approval_required_to_join
        pictures
        cm_api_list_id
      ),
      :member => %w(
        first_name
        last_name
        id
        legacy_id
      )
    }

    def to_csv
      FasterCSV.generate do |csv|
        csv << EXPORT_COLS[:group]
        (1..(Group.count/50)).each do |page|
          Group.paginate(:include => :people, :per_page => 50, :page => page).each do |group|
            csv << EXPORT_COLS[:group].map { |c| group.send(c) }
          end
        end
      end
    end

    def create_to_csv_job
      Job.add("GeneratedFile.create!(:job_id => JOB_ID, :person_id => #{Person.logged_in.id}, :file => FakeFile.new(Group.to_csv, 'groups.csv'))")
    end

    def to_xml
      builder = Builder::XmlMarkup.new
      builder.groups do |groups|
        (1..(Group.count/50)).each do |page|
          Group.paginate(:include => :people, :per_page => 100, :page => page).each do |group|
            groups.group do |g|
              EXPORT_COLS[:group].each do |col|
                g.tag!(col, group.send(col))
              end
              g.people do |people|
                group.people.each do |person|
                  people.person do |p|
                    EXPORT_COLS[:member].each do |col|
                      p.tag!(col, person.send(col))
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    def create_to_xml_job
      Job.add("GeneratedFile.create!(:job_id => JOB_ID, :person_id => #{Person.logged_in.id}, :file => FakeFile.new(Group.to_xml, 'groups.xml'))")
    end
  end
end
