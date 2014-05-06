require_relative '../spec_helper'

describe NewsController do

  before do
    @person = FactoryGirl.create(:person)
    @news_item = FactoryGirl.create(:news_item)
  end

  it "should list all items by js" do
    get :index, nil, {logged_in_id: @person.id}
    expect(response).to be_success
    expect(assigns(:news_items).length).to eq(1)
  end

end
