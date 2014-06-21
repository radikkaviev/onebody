require_relative '../spec_helper'

describe PictureUploader do

  let(:user) { FactoryGirl.create(:person) }

  let(:params) do
    { pictures: [
      Rack::Test::UploadedFile.new(
        Rails.root.join('spec/fixtures/files/image.jpg'),
        'image/jpeg',
        true
      )
    ] }
  end

  describe '#save' do
    context 'given no album' do
      subject do
        PictureUploader.new(nil, params, user)
      end

      it 'returns false' do
        expect(subject.save).to eq(false)
      end

      it 'has an error on album' do
        subject.save
        expect(subject.errors[:album]).to eq(['You must select an album.'])
      end
    end

    context 'given an album' do
      it 'creates a picture'
    end
  end

end
