class AddPositionToCustomFields < ActiveRecord::Migration
  def up
    remove_column :custom_fields, :ordering
    add_column :custom_fields, :position, :integer

    CustomField.reset_column_information
    Site.each do
      CustomField.order(:id).each_with_index do |field, index|
        field.position = index + 1
        field.save!
      end
    end
  end

  def down
    remove_column :custom_fields, :position, :integer
    add_column :custom_fields, :ordering, :integer
  end
end
