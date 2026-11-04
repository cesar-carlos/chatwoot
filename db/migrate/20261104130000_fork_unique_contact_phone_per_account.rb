# frozen_string_literal: true

# FORK: stop address-book imports from creating two contacts with the same phone.
class ForkUniqueContactPhonePerAccount < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    add_index :contacts, %i[account_id phone_number],
              unique: true,
              where: "phone_number IS NOT NULL AND phone_number <> ''",
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'uniq_phone_per_account_contact'
  end

  def down
    remove_index :contacts, name: 'uniq_phone_per_account_contact',
                            algorithm: :concurrently,
                            if_exists: true
  end
end
