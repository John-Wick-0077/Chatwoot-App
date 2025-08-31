class ChangeFeatureFlagsToJsonInAccounts < ActiveRecord::Migration[7.1]
  def change
    # Step 1: Add a new column
    add_column :accounts, :feature_flags_json, :jsonb, default: {}, null: false

    # Step 2: Remove the old column
    remove_column :accounts, :feature_flags

    # Step 3: Rename new column to old name
    rename_column :accounts, :feature_flags_json, :feature_flags
  end
end
