defmodule Mimimi.Repo.Migrations.RemoveOldHostTokenMigrationEntry do
  use Ecto.Migration

  def up do
    # Remove the old migration entry that references the deleted pgcrypto migration
    execute "DELETE FROM schema_migrations WHERE version = '20251112130635'"
  end

  def down do
    # Add it back if we need to rollback (though the file doesn't exist anymore)
    execute "INSERT INTO schema_migrations (version, inserted_at) VALUES ('20251112130635', NOW())"
  end
end
