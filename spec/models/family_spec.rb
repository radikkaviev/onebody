require_relative '../spec_helper'

describe Family do

  describe 'Barcodes' do
    it 'should not allow the same barcode id to be assigned to two families' do
      @family = FactoryGirl.create(:family, barcode_id: '1234567890')
      @family2 = FactoryGirl.build(:family)
      @family2.barcode_id = '1234567890'
      @family2.save
      expect(@family2.errors[:barcode_id]).to be
    end

    it 'should not allow the same alternate barcode id to be assigned to two families' do
      @family = FactoryGirl.create(:family, alternate_barcode_id: '1234567890')
      @family2 = FactoryGirl.build(:family)
      @family2.alternate_barcode_id = '1234567890'
      @family2.save
      expect(@family2.errors[:alternate_barcode_id]).to be
    end

    it 'should not allow the same id to be assigned to a barcode_id and an alternate_barcode_id on different families' do
      # alternate was there first
      @family = FactoryGirl.create(:family, alternate_barcode_id: '1234567890')
      @family2 = FactoryGirl.build(:family)
      @family2.barcode_id = '1234567890'
      @family2.save
      expect(@family2.errors[:barcode_id]).to be
      # main id was there first
      @family3 = FactoryGirl.create(:family, barcode_id: '9876543210')
      @family4 = FactoryGirl.build(:family)
      @family4.alternate_barcode_id = '9876543210'
      @family4.save
      expect(@family4.errors[:alternate_barcode_id]).to be
    end

    it 'should not allow a barcode_id and alternate_barcode_id to be the same' do
      # on existing record
      @family = FactoryGirl.build(:family)
      @family.barcode_id = '1234567890'
      @family.save
      expect(@family).to be_valid
      @family.alternate_barcode_id = '1234567890'
      @family.save
      expect(@family.errors[:barcode_id]).to be_any
      # on new record
      @family2 = FactoryGirl.build(:family)
      @family2.barcode_id = '1231231231'
      @family2.alternate_barcode_id = '1231231231'
      @family2.save
      expect(@family2.errors[:barcode_id]).to be_any
    end

    it 'should allow both barcode_id and alternate_barcode_id to be nil' do
      @family = FactoryGirl.build(:family)
      @family.barcode_id = ''
      @family.alternate_barcode_id = nil
      @family.save
      expect(@family.errors[:barcode_id]).to eq([])
      expect(@family.barcode_id).to eq(nil)
      expect(@family.alternate_barcode_id).to eq(nil)
    end
  end

  describe '#suggested_name' do
    subject { FactoryGirl.create(:family) }

    context 'given a new family' do
      it 'returns nil' do
        expect(subject.suggested_name).to be_nil
      end
    end

    context 'given a family with one adult' do
      let!(:adult) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Tim", last_name: "Morgan") }

      it 'returns name of first adult' do
        expect(subject.suggested_name).to eq("Tim Morgan")
      end
    end

    context 'given a family with two adults' do
      let!(:adult1) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Tim", last_name: "Morgan") }
      let!(:adult2) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Jennie", last_name: "Morgan") }

      it 'returns first names of both adults and common last name' do
        expect(subject.suggested_name).to eq("Tim & Jennie Morgan")
      end

      context 'given the adults have different last names' do
        before { adult2.last_name = 'Smith'; adult2.save! }

        it 'returns full name of both adults' do
          expect(subject.suggested_name).to eq("Tim Morgan & Jennie Smith")
        end
      end

      context 'given one of the adults is deleted' do
        before { adult2.destroy }

        it 'returns full name only first adult' do
          expect(subject.suggested_name).to eq("Tim Morgan")
        end
      end
    end

    context 'given a family with three adults' do
      let!(:adult1) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Tim", last_name: "Morgan") }
      let!(:adult2) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Jennie", last_name: "Morgan") }
      let!(:adult3) { FactoryGirl.create(:person, family: subject, child: false, first_name: "Ruth", last_name: "Morgan") }

      it 'returns first names of first two adults and common last name' do
        expect(subject.suggested_name).to eq("Tim & Jennie Morgan")
      end
    end
  end

  describe '#name' do
    before do
      @family = FactoryGirl.create(:family)
    end

    context 'family name is empty' do
      before do
        @family.name = nil
      end

      it 'should be invalid' do
        expect(@family).to be_invalid
      end
    end
  end

  describe '#last_name' do
    before do
      @family = FactoryGirl.create(:family)
    end

    context 'family last name is empty' do
      before do
        @family.last_name = nil
      end

      it 'should be invalid' do
        expect(@family).to be_invalid
      end
    end
  end

  describe 'country' do
    context 'default country is New Zealand' do
      before do
        Setting.set(:system, :default_country, 'NZ')
      end

      it 'sets the country on a new family' do
        expect(Family.new.country).to eq('NZ')
      end
    end
  end

  describe '#anniversary_sharable_with' do
    let(:husband) { FactoryGirl.create(:person) }
    let(:wife) { FactoryGirl.create(:person, family: husband.family) }

    context 'two adults in family with same wedding anniversary' do
      before do
        husband.update_attribute(:anniversary, Date.new(2001, 11, 22))
        wife.update_attribute(:anniversary, Date.new(2001, 11, 22))
      end

      it 'shows their shared anniversary' do
        anniversary = husband.family.anniversary_sharable_with(husband)
        expect(anniversary).to eq(Date.new(2001, 11, 22))
      end
    end

    context 'two adults in family with different wedding anniversaries' do
      before do
        husband.update_attribute(:anniversary, Date.new(2001, 11, 22))
        wife.update_attribute(:anniversary, Date.new(2001, 10, 20))
      end

      it 'does not show their anniversary' do
        anniversary = husband.family.anniversary_sharable_with(husband)
        expect(anniversary).to be_nil
      end
    end

    context 'one adult in family with a wedding anniversary' do
      before do
        husband.update_attribute(:anniversary, Date.new(2001, 11, 22))
        wife.destroy
      end

      it 'shows the anniversary' do
        anniversary = husband.family.anniversary_sharable_with(husband)
        expect(anniversary).to eq(Date.new(2001, 11, 22))
      end
    end
  end
end
