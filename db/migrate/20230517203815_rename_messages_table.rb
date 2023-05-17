class RenameMessagesTable < ActiveRecord::Migration[7.0]
  def change
    rename_table :clinic_management_messages, :clinic_management_lead_messages
  end
end
