require_relative '../spec_helper'

describe PrayerRequestsController do

  before do
    @person, @other_person = FactoryGirl.create_list(:person, 2)
    @group = FactoryGirl.create(:group)
    @group.memberships.create(person_id: @person.id)
    @prayer_request = FactoryGirl.create(:prayer_request, group: @group, person: @person)
  end

  it "should list all prayer requests" do
    get :index, {group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    expect(assigns(:reqs).length).to eq(1)
  end

  it "should list all answered prayer requests" do
    @unanswered = FactoryGirl.create(:prayer_request, group: @group, answer: nil, person: @person)
    get :index, {answered: true, group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    expect(assigns(:reqs).length).to eq(1)
  end

  it "should show a prayer request" do
    get :show, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
  end

  it "should not show a prayer request if the user is not a member of the group" do
    get :show, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @other_person.id}
    expect(response).to be_missing
  end

  it "should create a prayer request" do
    get :new, {group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    post :create, {group_id: @group.id, prayer_request: {request: 'test req', answer: 'test answer', answered_at: '1/1/2010'}}, {logged_in_id: @person.id}
    expect(response).to be_redirect
    new_req = PrayerRequest.last
    expect(new_req.request).to eq("test req")
    expect(new_req.answer).to eq("test answer")
    expect(new_req.answered_at.strftime("%m/%d/%Y")).to eq("01/01/2010")
  end

  it "should not create a prayer request if the user is not a member of the group" do
    get :new, {group_id: @group.id}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
    post :create, {group_id: @group.id, prayer_request: {request: 'test req', answer: 'test answer', answered_at: '1/1/2010'}}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
  end

  it "should edit a prayer request" do
    get :edit, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    post :update, {id: @prayer_request.id, group_id: @group.id, prayer_request: {request: 'test req', answer: 'test answer', answered_at: '1/1/2010'}}, {logged_in_id: @person.id}
    expect(response).to be_redirect
    expect(@prayer_request.reload.request).to eq("test req")
    expect(@prayer_request.answer).to eq("test answer")
    expect(@prayer_request.answered_at.strftime("%m/%d/%Y")).to eq("01/01/2010")
  end

  it "should not edit a prayer request if the user is not a member of the group" do
    get :edit, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
    post :update, {id: @prayer_request.id, group_id: @group.id, prayer_request: {request: 'test req', answer: 'test answer', answered_at: '1/1/2010'}}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
  end

  it "should delete a prayer request" do
    post :destroy, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @person.id}
    expect(response).to be_redirect
    assert_raise(ActiveRecord::RecordNotFound) do
      @prayer_request.reload
    end
  end

  it "should not delete a prayer request if the user is not a member of the group" do
    post :destroy, {id: @prayer_request.id, group_id: @group.id}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
  end

end
