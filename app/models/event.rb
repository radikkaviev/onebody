class Event < ActiveRecord::Base
  has_many :pictures, :order => 'created_at', :dependent => :destroy
  has_many :recipes, :order => 'title', :dependent => :nullify
  has_many :comments
  has_and_belongs_to_many :verses, :order => 'reference'
  belongs_to :person
  serialize :admins
  
  acts_as_logger LogItem
  
  validates_presence_of :name
  validates_presence_of :when
    
  def cover_picture
    if pictures.count > 0
      pictures.find_all_by_cover(true).first || pictures.last
    end
  end
  
  def admin?(person)
    person == self.person or person.admin?
  end
end
