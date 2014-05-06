require_relative '../spec_helper'

describe Search do

  before do
    @user = FactoryGirl.create(:person)
    Person.logged_in = @user
    @nobody = FactoryGirl.create(:person, first_name: 'Jack', last_name: 'Jones', family: FactoryGirl.create(:family, name: 'Jack Jones', last_name: 'Jones'))
  end

  it 'should not return deleted people' do
    @deleted = FactoryGirl.create(:person, deleted: true)
    expect(Search.new.results).to_not include(@deleted)
  end

  it 'should not return people from deleted families' do
    @deleted_family = FactoryGirl.create(:family, deleted: true)
    @person = FactoryGirl.create(:person, family: @deleted_family)
    expect(Search.new.results).to_not include(@person)
  end

  it 'should return people in alphabetical order by last, first' do
    @a = FactoryGirl.create(:person, first_name: 'a', last_name: 'a')
    @z = FactoryGirl.create(:person, first_name: 'z', last_name: 'z')
    expect(Search.new.results.first).to eq(@a)
    expect(Search.new.results.last).to eq(@z)
  end

  context 'search by name' do
    before do
      @search = Search.new
      @user.first_name = 'John'
      @user.last_name = 'Smith'
      @user.save!
      @user.family.name = 'Johnny Smith'
      @user.family.save!
    end

    it 'should return person matching the first name' do
      @search.name = 'John'
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the last name' do
      @search.name = 'Smith'
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the full name' do
      @search.name = 'John Smith'
      expect(@search.results).to eq([@user])
    end

    it 'should return none if no name matches' do
      @search.name = 'John Smithey'
      expect(@search.results).to eq([])
    end

    it 'should return person matching first part of each name' do
      @search.name = 'Jo Smi'
      expect(@search.results).to eq([@user])
    end

    it 'should return person based on family name' do
      @search.name = 'Johnny Smith'
      expect(@search.results).to eq([@user])
    end
  end

  context 'search by birthday' do
    before do
      @search = Search.new
      @user.birthday = Date.new(1980, 1, 1)
      @user.save!
    end

    it 'should return person matching the birthday day' do
      @search.birthday = {day: '1'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the birthday month' do
      @search.birthday = {month: '1'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the birthday month and day' do
      @search.birthday = {month: '1', day: '1'}
      expect(@search.results).to eq([@user])
    end

    it 'should not return person if birthday is not matched' do
      @search.birthday = {month: '1', day: '2'}
      expect(@search.results).to eq([])
    end
  end

  context 'search by anniversary' do
    before do
      @search = Search.new
      @user.anniversary = Date.new(1990, 2, 2)
      @user.save!
    end

    it 'should return person matching the anniversary day' do
      @search.anniversary = {day: '2'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the anniversary month' do
      @search.anniversary = {month: '2'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the anniversary month and day' do
      @search.anniversary = {month: '2', day: '2'}
      expect(@search.results).to eq([@user])
    end

    it 'should not return person if anniversary is not matched' do
      @search.anniversary = {month: '2', day: '3'}
      expect(@search.results).to eq([])
    end
  end

  context 'search by address' do
    before do
      @search = Search.new
      @user.family.address1 = '123 S. Street'
      @user.family.city = 'Tulsa'
      @user.family.state = 'OK'
      @user.family.zip = '74010'
      @user.family.save!
    end

    it 'should return person matching the address city' do
      @search.address = {city: 'Tulsa'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the address state' do
      @search.address = {state: 'OK'}
      expect(@search.results).to eq([@user])
    end

    it 'should return person matching the address zip' do
      @search.address = {zip: '74010'}
      expect(@search.results).to eq([@user])
    end

    it 'should not return person if address does not match' do
      @search.address = {city: 'Tulsa', state: 'AR', zip: '74011'}
      expect(@search.results).to eq([])
    end
  end

  context 'search by type' do
    before do
      @search = Search.new
    end

    it 'should return members' do
      @search.type = 'member'
      expect(@search.results).to eq([])
      @user.member = true
      @user.save!
      expect(@search.results.reload).to eq([@user])
    end

    it 'should return staff' do
      @search.type = 'staff'
      expect(@search.results).to eq([])
      @user.staff = true
      @user.save!
      expect(@search.results.reload).to eq([@user])
    end

    it 'should return elder' do
      @search.type = 'elder'
      expect(@search.results).to eq([])
      @user.elder = true
      @user.save!
      expect(@search.results.reload).to eq([@user])
    end
  end

  context 'search by gender' do
    before do
      @search = Search.new
      @user.gender = 'Female'
      @user.save!
    end

    it 'should return males' do
      @search.gender = 'Male'
      expect(@search.results).to eq([@nobody])
    end

    it 'should return females' do
      @search.gender = 'Female'
      expect(@search.results).to eq([@user])
    end
  end

  context 'given a child' do
    before do
      @search = Search.new
      @child = FactoryGirl.create(:person, first_name: 'Mac', child: true)
    end

    context 'child does not have parental consent' do
      it 'should not return child' do
        @search.name = 'mac'
        expect(@search.results).to eq([])
      end

      context 'user is admin and show_hidden is true' do
        before do
          @user.admin = Admin.create(view_hidden_profiles: true)
        end

        it 'should return child' do
          @search.name = 'mac'
          @search.show_hidden = true
          expect(@search.results).to eq([@child])
        end
      end
    end

    context 'child has parental consent' do
      before do
        @child.parental_consent = 'John Smith 1/1/2014'
        @child.save!
      end

      it 'should return child' do
        @search.name = 'mac'
        expect(@search.results).to eq([@child])
      end
    end
  end

  context 'search for families' do
    before do
      @search = Search.new(source: :family)
    end

    it 'should return matching families by name' do
      @search.family_name = 'Smith'
      expect(@search.results).to eq([@user.family])
    end

    it 'should return matching families by barcode id' do
      @user.family.barcode_id = '1234567890'
      @user.family.save!
      @search.family_barcode_id = '1234567890'
      expect(@search.results).to eq([@user.family])
    end
  end

  context 'search for businesses' do
    before do
      @search = Search.new(business: true)
      @business = FactoryGirl.create(:person, :with_business)
    end

    it 'should return only businesses' do
      expect(@search.results).to eq([@business])
    end
  end
end
