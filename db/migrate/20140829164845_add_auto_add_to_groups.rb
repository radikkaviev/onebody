class AddAutoAddToGroups < ActiveRecord::Migration
  def up
    change_table :groups do |t|
      t.string :membership_mode, limit: 10, default: 'manual'
    end

    Group.reset_column_information

    print 'Updating groups'
    Site.each do
      Group.all.each do |group|
        if group.linked?
          group.membership_mode = 'link_code'
        elsif group.parents_of.present?
          group.membership_mode = 'parents_of'
        else
          group.membership_mode = 'manual'
        end
        group.dont_update_memberships
        group.save(validate: false)
        print '.'
      end
    end
    puts
  end

  def down
    change_table :groups do |t|
      t.remove :membership_mode
    end
  end
end
