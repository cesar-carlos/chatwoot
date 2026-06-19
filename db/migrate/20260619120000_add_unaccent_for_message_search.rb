class AddUnaccentForMessageSearch < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension 'unaccent' unless extension_enabled?('unaccent')

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION unaccent_immutable(text)
      RETURNS text AS $$
        SELECT public.unaccent('public.unaccent', $1)
      $$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;
    SQL

    add_index :messages,
              'unaccent_immutable(content) gin_trgm_ops',
              name: 'index_messages_on_unaccent_content_trgm',
              using: :gin,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :messages,
                 name: 'index_messages_on_unaccent_content_trgm',
                 algorithm: :concurrently,
                 if_exists: true
    execute 'DROP FUNCTION IF EXISTS unaccent_immutable(text)'
  end
end
