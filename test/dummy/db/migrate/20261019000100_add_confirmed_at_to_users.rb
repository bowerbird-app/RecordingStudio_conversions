# frozen_string_literal: true

# Mirrors RecordingStudioUser::Generators::MigrationsGenerator template
# add_devise_confirmable_to_users.rb.tt.
class AddConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |table|
      table.string :confirmation_token
      table.datetime :confirmed_at
      table.datetime :confirmation_sent_at
      table.string :unconfirmed_email
    end

    add_index :users, :confirmation_token, unique: true

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE users SET confirmed_at = CURRENT_TIMESTAMP WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
