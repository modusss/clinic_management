class RemoveForeignKeyFromServices < ActiveRecord::Migration[7.0]
  def change
    remove_column :clinic_management_services, :time_slot_id
  end
end
