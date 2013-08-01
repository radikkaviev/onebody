class Family < ActiveRecord::Base

  include Authority::Abilities
  self.authorizer_name = 'FamilyAuthorizer'

  MAX_TO_BATCH_AT_A_TIME = 50

  has_many :people, order: 'sequence', dependent: :destroy
  accepts_nested_attributes_for :people
  belongs_to :site

  scope_by_site_id

  has_attached_file :photo, PAPERCLIP_PHOTO_OPTIONS

  sharable_attributes :mobile_phone, :address, :anniversary

  scope :undeleted, -> { where(deleted: false) }
  scope :deleted, -> { where(deleted: true) }
  scope :has_printable_people, -> { where('(select count(*) from people where family_id = families.id and visible_on_printed_directory = ?) > 0', true) }

  validates_uniqueness_of :barcode_id, allow_nil: true, scope: [:site_id, :deleted], unless: Proc.new { |f| f.deleted? }
  validates_uniqueness_of :alternate_barcode_id, allow_nil: true, scope: [:site_id, :deleted], unless: Proc.new { |f| f.deleted? }
  validates_length_of :barcode_id, :alternate_barcode_id, in: 10..50, allow_nil: true
  validates_format_of :barcode_id, :alternate_barcode_id, with: /^\d+$/, allow_nil: true
  validates_attachment_size :photo, less_than: PAPERCLIP_PHOTO_MAX_SIZE
  validates_attachment_content_type :photo, content_type: PAPERCLIP_PHOTO_CONTENT_TYPES

  validates_each [:barcode_id, :alternate_barcode_id] do |record, attribute, value|
    if attribute.to_s == 'barcode_id' and record.barcode_id
      if record.barcode_id == record.alternate_barcode_id
        record.errors.add(attribute, :taken)
      elsif Family.where(alternate_barcode_id: record.barcode_id).count > 0
        record.errors.add(attribute, :taken)
      end
    elsif attribute.to_s == 'alternate_barcode_id' and record.alternate_barcode_id
      if Family.where(barcode_id: record.alternate_barcode_id).count > 0
        record.errors.add(attribute, :taken)
      end
    end
  end

  def barcode_id=(b)
    write_attribute(:barcode_id, b.to_s.strip.any? ? b : nil)
    write_attribute(:barcode_assigned_at, Time.now.utc)
  end

  def alternate_barcode_id=(b)
    write_attribute(:alternate_barcode_id, b.to_s.strip.any? ? b : nil)
    write_attribute(:barcode_assigned_at, Time.now.utc)
  end

  def address
    address1.to_s + (address2.to_s.any? ? "\n#{address2}" : '')
  end

  def mapable?
    address1.to_s.any? and city.to_s.any? and state.to_s.any? and zip.to_s.any?
  end

  def mapable_address
    if mapable?
      "#{address1}, #{address2.to_s.any? ? address2+', ' : ''}#{city}, #{state} #{zip}".gsub(/'/, "\\'")
    end
  end

  # not HTML-escaped!
  def pretty_address
    a = ''
    a << address1.to_s   if address1.to_s.any?
    a << ", #{address2}" if address2.to_s.any?
    if city.to_s.any? and state.to_s.any?
      a << "\n#{city}, #{state}"
      a << "  #{zip}" if zip.to_s.any?
    end
  end

  def short_zip
    zip.to_s.split('-').first
  end

  def latitude
    return nil unless mapable?
    update_lat_lon unless read_attribute(:latitude) and read_attribute(:longitude)
    read_attribute :latitude
  end

  def longitude
    return nil unless mapable?
    update_lat_lon unless read_attribute(:latitude) and read_attribute(:longitude)
    read_attribute :longitude
  end

  def update_lat_lon
    return nil unless mapable? and Setting.get(:services, :yahoo).to_s.any?
    url = "http://api.local.yahoo.com/MapsService/V1/geocode?appid=#{Setting.get(:services, :yahoo)}&location=#{URI.escape(mapable_address)}"
    begin
      xml = URI(url).read
      result = REXML::Document.new(xml).elements['/ResultSet/Result']
      lat, lon = result.elements['Latitude'].text.to_f, result.elements['Longitude'].text.to_f
    rescue
      logger.error("Could not get latitude and longitude for address #{mapable_address} for family #{name}.")
    else
      update_attributes latitude: lat, longitude: lon
    end
  end

  self.digits_only_for_attributes = [:home_phone]

  def children_without_consent
    people.select { |p| !p.adult_or_consent? }
  end

  def visible_people
    people.find(:all).select do |person|
      !person.deleted? and (
        Person.logged_in.admin?(:view_hidden_profiles) or
        person.visible?(self)
      )
    end
  end

  def suggested_relationships
    all_people = people.all(order: 'sequence')
    relations = {
      adult: {
        male: {
          adult: {
            female: 'wife'
          },
          child: {
            male:   'son',
            female: 'daughter'
          }
        },
        female: {
          adult: {
            male: 'husband'
          },
          child: {
            male:   'son',
            female: 'daughter'
          }
        }
      },
      child: {
        male: {
          adult: {
            male:   'father',
            female: 'mother'
          }
        },
        female: {
          adult: {
            male:   'father',
            female: 'mother'
          }
        }
      }
    }
    relationships = {}
    all_people.each_with_index do |person, person_index|
      relationships[person] ||= []
      person_adult = person_index <= 1 && person.adult?
      all_people.each_with_index do |related, related_index|
        related_adult = related_index <= 1 && related.adult?
        r = relations[person_adult ? :adult : :child][person.gender.to_s.downcase.to_sym][related_adult ? :adult : :child][related.gender.to_s.downcase.to_sym] rescue nil
        relationships[person] << [related, r] if r
      end
    end
    relationships
  end

  attr_accessor :dont_mark_barcode_id_changed

  before_update :mark_barcode_id_changed
  def mark_barcode_id_changed
    return if dont_mark_barcode_id_changed
    if changed.include?('barcode_id')
      write_attribute(:barcode_id_changed, true)
    end
  end

  alias_method :destroy_for_real, :destroy
  def destroy
    people.all.each { |p| p.destroy }
    update_attribute(:deleted, true)
  end

  class << self

    # used to update a batch of records at one time, for UpdateAgent API
    def update_batch(records, options={})
      raise "Too many records to batch at once (#{records.length})" if records.length > MAX_TO_BATCH_AT_A_TIME
      records.map do |record|
        # find the family (by legacy_id, preferably)
        family = find_by_legacy_id(record['legacy_id'])
        if family.nil? and options['claim_families_by_barcode_if_no_legacy_id'] and record['barcode_id'].to_s.any?
          # if no family was found by legacy id, let's try by barcode id
          # but only if the matched family has no legacy id!
          # (because two separate families could potentially have accidentally been assigned the same barcode)
          family = find_by_legacy_id_and_barcode_id(nil, record['barcode_id'])
        end
        # last resort, create a new record
        family ||= new
        if options['delete_families_with_conflicting_barcodes_if_no_legacy_id'] and !family.new_record?
          # closely related to the other option, but this one deletes conflicting families
          # (only if they have no legacy id)
          destroy_all ["legacy_id is null and barcode_id = ? and id != ?", record['barcode_id'], family.id]
        end
        record.each do |key, value|
          value = nil if value == ''
          # avoid overwriting a newer barcode
          if key == 'barcode_id' and family.barcode_id_changed?
            if value == family.barcode_id # barcode now matches (presumably, the external db has been updated to match the OneBody db)
              family.barcode_id_changed = false # clear the flag
            else
              next # don't overwrite the newer barcode with an older one
            end
          elsif %w(barcode_id_changed remote_hash).include?(key) # skip these
            next
          end
          family.send("#{key}=", value) # be sure to call the actual method (don't use write_attribute)
        end
        family.dont_mark_barcode_id_changed = true # set flag to indicate we're the api
        if family.save
          s = {status: 'saved', legacy_id: family.legacy_id, id: family.id, name: family.name}
          if family.barcode_id_changed? # barcode_id_changed flag still set
            s[:status] = 'saved with error'
            s[:error] = "Newer barcode not overwritten: #{family.barcode_id.inspect}"
          end
          s
        else
          {status: 'not saved', legacy_id: record['legacy_id'], id: family.id, name: family.name, error: family.errors.full_messages.join('; ')}
        end
      end
    end

    def daily_barcode_assignment_counts(limit, offset, date_strftime='%Y-%m-%d', only_show_date_for=nil)
      [].tap do |data|
        counts = connection.select_all("select count(date(barcode_assigned_at)) as count, date(barcode_assigned_at) as date from families where site_id=#{Site.current.id} and barcode_assigned_at is not null group by date(barcode_assigned_at) order by barcode_assigned_at desc limit #{limit} offset #{offset};").group_by { |p| Date.parse(p['date'].strftime('%Y-%m-%d')) }
        ((Date.today-offset-limit+1)..(Date.today-offset)).each do |date|
          d = date.strftime(date_strftime)
          d = ' ' if only_show_date_for and date.strftime(only_show_date_for[0]) != only_show_date_for[1]
          count = counts[date] ? counts[date][0]['count'].to_i : 0
          data << [d, count]
        end
      end
    end

  end
end
