class Update < ActiveRecord::Base

  belongs_to :person
  belongs_to :site

  scope_by_site_id

  scope :pending, -> { where(complete: false) }
  scope :complete, -> { where(complete: true) }

  serialize :data, Hash
  serialize :diff, Hash

  # convert ActionController::Parameters and HWIA to a Hash
  def data=(d)
    self[:data] = data_to_hash(d)
  end

  def child=(c)
    self[:data][:person]['child'] = c
  end

  # update_attributes!(apply: true) will call apply!
  attr_accessor :apply
  after_save { apply! if apply and not complete? }

  def apply!
    return false if complete?
    transaction do
      record_diff
      person.update_attributes!(data[:person])
      family.update_attributes!(data[:family])
      update_attributes!(complete: true)
    end
  end

  def family
    person.try(:family)
  end

  def diff
    if complete?
      self[:diff].any? ? self[:diff] : data_as_diff
    else
      pending_changes
    end
  end

  # returns true if applying the update requires that the admin
  # specify if the person is a child, e.g. *removing* a birthday
  def require_child_designation?
    person.attributes = data[:person] # temporarily set attrs
    person.valid?                     # force validation check
    person.errors[:child].any?.tap do # errors on :child?
      person.reload                   # reset attrs
    end
  end

  private

  def pending_changes
    HashWithIndifferentAccess.new(
      person: Comparator.new(person, data[:person]).changes,
      family: Comparator.new(family, data[:family]).changes
    )
  end

  def record_diff
    self.diff = pending_changes
  end

  # update data in a diff format
  # to support legacy records (before we started storing the diff)
  def data_as_diff
    HashWithIndifferentAccess.new(
      person: faux_diff_attributes(data[:person]),
      family: faux_diff_attributes(data[:family])
    )
  end

  # convert top level and second level to Hash class
  # ensure top level is symbol
  def data_to_hash(d)
    self[:data] = d.each_with_object({}) do |(key, val), hash|
      hash[key.to_sym] = val.to_hash
    end
  end

  # build a fake diff with :unknown as the source
  def faux_diff_attributes(attrs)
    return {} unless attrs and attrs.any?
    attrs.each_with_object({}) do |(key, val), hash|
      hash[key] = [:unknown, val]
    end
  end

  class << self
    def daily_counts(limit, offset, date_strftime='%Y-%m-%d', only_show_date_for=nil)
      [].tap do |data|
        counts = connection.select_all("select count(date(created_at)) as count, date(created_at) as date from updates where site_id=#{Site.current.id} group by date(created_at) order by created_at desc limit #{limit.to_i} offset #{offset.to_i};").group_by { |p| Date.parse(p['date'].strftime('%Y-%m-%d')) }
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
