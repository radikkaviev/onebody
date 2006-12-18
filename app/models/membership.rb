class Membership < ActiveRecord::Base
  belongs_to :group
  belongs_to :person
  
  def family; person.family; end
  
  inherited_attribute :share_address, :person
  inherited_attribute :share_mobile_phone, :person
  inherited_attribute :share_work_phone, :person
  inherited_attribute :share_fax, :person
  inherited_attribute :share_email, :person
  inherited_attribute :share_birthday, :person
  inherited_attribute :share_anniversary, :person
  
  # generates security code
  def before_create
    begin
      code = rand(999999)
      write_attribute :code, code
    end until code > 0
  end
end
