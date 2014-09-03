require_relative '../spec_helper'

GLOBAL_SUPER_ADMIN_EMAIL = 'support@example.com' unless defined?(GLOBAL_SUPER_ADMIN_EMAIL) and GLOBAL_SUPER_ADMIN_EMAIL == 'support@example.com'

describe PeopleController do
  render_views

  before do
    @person, @other_person = FactoryGirl.create_list(:person, 2)
    @limited_person = FactoryGirl.create(:person, full_access: false)
  end

  it "should redirect the index action to the currently logged in person" do
    get :index, nil, {logged_in_id: @person.id}
    expect(response).to redirect_to(action: 'show', id: @person.id)
  end

  it "should show a person" do
    get :show, {id: @person.id}, {logged_in_id: @person.id} # myself
    expect(response).to be_success
    expect(response).to render_template('show')
    get :show, {id: @person.id}, {logged_in_id: @other_person.id} # someone else
    expect(response).to be_success
    expect(response).to render_template('show')
  end

  it "should show a limited view of a person" do
    get :show, {id: @person.id}, {logged_in_id: @limited_person.id}
    expect(response).to be_success
    expect(response).to render_template('show_limited')
  end

  it "should not show a person if they are invisible to the logged in user" do
    @person.update_attribute :visible, false
    get :show, {id: @person.id}, {logged_in_id: @other_person.id}
    expect(response).to be_missing
  end

  it "should create a person update" do
    Setting.set(Site.current.id, 'Features', 'Updates Must Be Approved', true)
    get :edit, {id: @person.id}, {logged_in_id: @person.id}
    expect(response).to be_success
    post :update,
      {
        id: @person.id,
        person: {
          first_name: 'Bob',
          last_name: 'Smith'
        },
        family: {
          name: 'Bob Smith',
          last_name: 'Smith'
        }
      },
      {logged_in_id: @person.id}
    expect(response).to redirect_to(person_path(@person))
    expect(@person.reload.first_name).to eq("John") # should not change person
    expect(@person.updates.count).to eq(1)
  end

  it "should edit favorites and other non-basic person information" do
    post :update,
      {
        id: @person.id,
        person: {
          first_name: @person.first_name, # no change
          testimony: 'testimony',
          interests: 'interests'
        }
      },
      {logged_in_id: @person.id}
    expect(response).to redirect_to(person_path(@person))
    expect(@person.reload.testimony).to eq("testimony")
    expect(@person.interests).to eq("interests")
    expect(@person.updates.count).to eq(0)
  end

  it "should edit a person basics when user is admin" do
    @other_person.admin = Admin.create!(edit_profiles: true)
    @other_person.save!
    post :update,
      {
        id: @person.id,
        person: {
          first_name: 'Bob',
          last_name: 'Smith'
        },
        family: {
          name: 'Bob Smith',
          last_name: 'Smith'
        }
      },
      {logged_in_id: @other_person.id}
    expect(response).to redirect_to(person_path(@person))
    expect(@person.reload.first_name).to eq("Bob")
    expect(@person.updates.count).to eq(0)
  end

  it "should delete a person" do
    @other_person.admin = Admin.create!(edit_profiles: true)
    @other_person.save!
    post :destroy, {id: @person.id}, {logged_in_id: @other_person.id}
    expect(@person.reload).to be_deleted
  end

  it "should not delete self" do
    @person.admin = Admin.create!(edit_profiles: true)
    @person.save!
    post :destroy, {id: @person.id}, {logged_in_id: @person.id}
    expect(response).to be_unauthorized
    expect(@person.reload).to_not be_deleted
  end

  it "should not delete a person unless admin" do
    post :destroy, {id: @person.id}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
    post :destroy, {id: @person.id}, {logged_in_id: @other_person.id}
    expect(response).to be_unauthorized
  end

  it "should not show xml unless user can export data" do
    expect {
      get :show, {id: @person.id, format: 'xml'}, {logged_in_id: @person.id}
    }.to raise_error(ActionController::UnknownFormat)
  end

  it "should show xml for admin who can export data" do
    @other_person.admin = Admin.create!(export_data: true)
    @other_person.save!
    get :show, {id: @person.id, format: 'xml'}, {logged_in_id: @other_person.id}
    expect(response).to be_success
  end

  it "should not allow deletion of a global super admin" do
     @super_admin = FactoryGirl.create(:person, admin: Admin.create(super_admin: true))
     @global_super_admin = FactoryGirl.create(:person, email: 'support@example.com')
     post :destroy, {id: @global_super_admin.id}, {logged_in_id: @super_admin.id}
     expect(response).to be_unauthorized
  end

  it "should not error when viewing a person not in a family" do
    @admin = FactoryGirl.create(:person, admin: Admin.create(view_hidden_profiles: true))
    @person = Person.create!(first_name: 'Deanna', last_name: 'Troi', child: false, visible_to_everyone: true)
    # normal person should not see
    expect { get :show, {id: @person.id}, {logged_in_id: @other_person.id} }.to_not raise_error

    expect(response).to be_missing
    # admin should see a message
    expect { get :show, {id: @person.id}, {logged_in_id: @admin.id} }.to_not raise_error
    expect(response).to be_success
    expect(response.body).to include(I18n.t('people.no_family_for_this_person'))
  end

  describe '#show' do
    context '?business=true' do
      context 'person has a business' do
        before do
          @person.business_name = 'Tim Morgan Enterprises'
          @person.save!
          get :show, { id: @person.id, business: true }, { logged_in_id: @person.id }
        end

        it 'shows the business template' do
          expect(response).to render_template('business')
        end
      end

      context 'person does not have a business' do
        before do
          get :show, { id: @person.id, business: true }, { logged_in_id: @person.id }
        end

        it 'renders the profile' do
          expect(response).to render_template('show')
        end
      end
    end
  end

  describe '#new' do
    let(:admin) { FactoryGirl.create(:person, :admin_edit_profiles) }

    context 'given a family id' do
      let(:family) { @person.family }

      before do
        get :new, { family_id: family.id }, { logged_in_id: admin.id }
      end

      it 'renders the new template' do
        expect(response).to render_template('new')
      end
    end

    context 'given no family' do
      before do
        get :new, {}, { logged_in_id: admin.id }
      end

      it 'renders the new template' do
        expect(response).to render_template('new')
      end
    end
  end

  describe '#create' do
    let!(:admin) { FactoryGirl.create(:person, :admin_edit_profiles) }

    context 'with existing family' do
      let(:family) { @person.family }

      before do
        post :create,
          {
            person: {
              first_name: 'Todd',
              last_name: 'Jones',
              family_id: family.id,
              child: '0'
            }
          },
          { logged_in_id: admin.id }
      end

      it 'creates the new person in the existing family and redirects' do
        expect(family.people.to_a.map(&:name)).to include('Todd Jones')
        expect(response).to redirect_to(family_path(family))
      end
    end

    context 'with no family' do
      def do_post
        post :create,
          {
            person: {
              first_name: 'Todd',
              last_name: 'Jones',
              family_id: '',
              child: '0',
            },
            family: {
              home_phone: '123-456-7890'
            }
          },
          { logged_in_id: admin.id }
      end

      it 'creates the new person in a new family and redirects' do
        expect { do_post }.to change { Family.count }.by(1)
        family = Family.last
        expect(family.name).to eq('Todd Jones')
        expect(family.last_name).to eq('Jones')
        expect(family.home_phone).to eq('1234567890')
        expect(family.people.to_a.map(&:name)).to eq(['Todd Jones'])
        expect(response).to redirect_to(family_path(family))
      end
    end

    context 'with no family, invalid family attributes' do
      def do_post
        post :create,
          {
            person: {
              first_name: '',
              last_name: '',
            },
          },
          { logged_in_id: admin.id }
      end

      render_views

      it 'renders the new template again with errors' do
        expect { do_post }.to_not change { Family.count }
        expect(response).to render_template('new')
      end
    end
  end

  describe '#update' do
    context 'given a id and a family_id and the param move_person' do
      before do
        @admin = FactoryGirl.create(:person, :admin_edit_profiles)
        @old_family = @person.family
        @other_family = FactoryGirl.create(:family)
        post :update,
          {
            id: @person.id,
            family_id: @other_family.id,
            move_person: true
          },
          {
            logged_in_id: @admin.id
          }
      end

      it 'moves the person to the family' do
        expect(@other_family.people.reload).to include(@person)
        expect(@old_family.people.reload).to_not include(@person)
      end

      it 'redirects to the new family' do
        expect(response).to redirect_to(@other_family)
      end

      it 'sets a flash message' do
        expect(flash[:info]).to eq(I18n.t('people.move.success_message', person: @person.name, family: @other_family.name))
      end
    end
  end

  describe '#import' do
    context 'user is not admin with import permission' do
      before do
        get :import, {}, { logged_in_id: @person.id }
      end

      it 'returns unauthorized' do
        expect(response).to be_unauthorized
      end
    end

    context 'user is admin with import permission' do
      before do
        @person.update_attribute(:admin, Admin.create(import_data: true))
        get :import, {}, { logged_in_id: @person.id }
      end

      it 'renders the import template' do
        expect(response).to render_template(:import)
      end
    end

    context 'user is admin with import permission' do
      before do
        @person.update_attribute(:admin, Admin.create(import_data: true))
        @file = ActionDispatch::Http::UploadedFile.new(tempfile: File.new("#{Rails.root}/spec/fixtures/files/people.csv"), filename: "person.csv")
        @attributes = {can_sign_in: "true",
                       full_access: "true",
                       visible_to_everyone: "true",
                       visible_on_printed_directory: "true"}
        post :import, { file: @file, match_by_name: 'true', attributes: @attributes }, { logged_in_id: @person.id }
      end
      it 'uploads a file' do
        expect(response).to render_template(:import_queue)
      end
    end
  end
end
