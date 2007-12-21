# == Schema Information
# Schema version: 86
#
# Table name: prayer_signups
#
#  id         :integer(11)   not null, primary key
#  person_id  :integer(11)   
#  start      :datetime      
#  created_at :datetime      
#  reminded   :boolean(1)    
#  other      :string(100)   
#

# == Schema Information
# Schema version: 78
#
# Table name: prayer_signups
#
#  id         :integer(11)   not null, primary key
#  person_id  :integer(11)   
#  start      :datetime      
#  created_at :datetime      
#  reminded   :boolean(1)    
#  other      :string(100)   
#

class PrayerSignup < ActiveRecord::Base
  belongs_to :person
  acts_as_logger LogItem

  class << self
    def deliver_reminders
      signups = find :all, :conditions => "start >= now()"
      signups = signups.group_by &:person
      signups.each do |person, times|
        if person.email.to_s.any?
          puts person.name
          Notifier.deliver_prayer_reminder(person, times)
        end
      end
      nil
    end
  end
end
