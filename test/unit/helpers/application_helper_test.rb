require_relative '../../test_helper'

class ApplicationHelperTest < ActionView::TestCase
  setup do
    @user = FactoryGirl.create(:person, birthday: Date.new(1981, 4, 28), mobile_phone: '9181234567')
  end

  context 'sanitize_html' do
    should 'remove style tags and their content' do
      assert_equal('before after', sanitize_html('before <style type="text/css">body { font-size: 12pt; }</style>after'))
    end

    should 'remove script tags and their content' do
      assert_equal('before after', sanitize_html('before <script type="text/javascript">alert("hi")</script>after'))
    end

    should 'remove other illegal tags' do
      assert_equal('before and after', sanitize_html('before <bad>and</bad> after'))
    end

    should 'allow safe tags' do
      assert_equal('<p>before <strong>bold</strong> and <em>italic</em> after</p>', sanitize_html('<p>before <strong>bold</strong> and <em>italic</em> after</p>'))
    end

    should 'be html_safe' do
      assert sanitize_html('<strong>safe</strong>').html_safe?
    end
  end

  context 'error_messages_for' do
    setup do
      @form = Struct.new(:object)
    end

    should 'return nothing if no errors' do
      form = @form.new(@user)
      assert error_messages_for(form).nil?
    end

    should 'be html_safe' do
      form = @form.new(Album.create) # album doesn't have a name
      assert error_messages_for(form).html_safe?
    end
  end

  context 'render_page_content' do
    setup do
      Page.find('system/sign_in_header').update_attributes!(body: 'safe<script>notsafe</script>')
    end

    should 'return sanitized content' do
      content = render_page_content('system/sign_in_header')
      assert_equal 'safe', content
    end

    should 'be html_safe' do
      assert render_page_content('system/sign_in_header').html_safe?
    end

    should 'return nil if no page found' do
      assert_nil render_page_content('system/nonexistent_page')
    end
  end

  context 'sortable_column_heading' do
    attr_accessor :params

    should 'generate a link to the correct url' do
      @params = {controller: 'administration/syncs', action: 'show', id: 1}
      assert_match %r{/admin/syncs/1},
                   sortable_column_heading('type', 'sync_items.syncable_type')
      @params = {controller: 'administration/deleted_people', action: 'index'}
      assert_match %r{/admin/deleted_people},
                   sortable_column_heading('id', 'people.id')
      @params = {controller: 'administration/attendance', action: 'index'}
      assert_match %r{/admin/attendance},
                   sortable_column_heading('group', 'groups.name')
    end

    should 'prepend sort arg and trail existing ones off' do
      @params = {controller: 'administration/attendance', action: 'index'}
      assert_match %r{/admin/attendance\?sort=groups\.name},
                   sortable_column_heading('group', 'groups.name')
      @params = {controller: 'administration/attendance', action: 'index', sort: 'groups.name'}
      assert_match %r{/admin/attendance\?sort=attendance_records\.attended_at%2Cgroups\.name},
                   sortable_column_heading('class time', 'attendance_records.attended_at')
      @params = {controller: 'administration/attendance', action: 'index', sort: 'attendance_records.attended_at,groups.name'}
      assert_match %r{/admin/attendance\?sort=groups\.name%2Cattendance_records\.attended_at},
                   sortable_column_heading('group', 'groups.name')
    end

    should 'preserve other args' do
      @params = {controller: 'administration/attendance', action: 'index', page: 1}
      assert_match %r{/admin/attendance\?page=1&amp;sort=groups\.name},
                   sortable_column_heading('group', 'groups.name', [:page])
    end
  end

  context 'date_field and date_field_tag' do
    should 'output a text field' do
      Setting.set(:formats, :date, '%m/%d/%Y')
      OneBody.set_local_formats
      assert_equal '<input id="birthday" name="birthday" size="12" type="text" value="04/28/1981" />',
                   date_field_tag(:birthday, Date.new(1981, 4, 28))
      form_for(@user) do |form|
        assert_equal '<input id="person_birthday" name="person[birthday]" size="12" type="text" value="04/28/1981" />',
                     form.date_field(:birthday)
      end
    end

    should 'handle nil and empty string' do
      @user.birthday = nil
      assert_equal '<input id="birthday" name="birthday" size="12" type="text" value="" />',
                   date_field_tag(:birthday, '')
      form_for(@user) do |form|
        assert_equal '<input id="person_birthday" name="person[birthday]" size="12" type="text" value="" />',
                     form.date_field(:birthday)
      end
    end
  end

  context 'phone_field' do
    should 'output a text field' do
      form_for(@user) do |form|
        assert_equal '<input id="person_mobile_phone" name="person[mobile_phone]" size="15" type="text" value="(918) 123-4567" />',
                     form.phone_field(:mobile_phone)
      end
    end
  end

end
