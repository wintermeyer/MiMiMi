defmodule Mimimi.Repo.Migrations.UpdateRoundsForWortschule do
  use Ecto.Migration

  def up do
    # Clear out any existing rounds since we're changing the schema significantly
    execute("TRUNCATE TABLE rounds CASCADE")

    # Drop the foreign key constraint on word_id since we're using WortSchule word IDs
    drop constraint(:rounds, "rounds_word_id_fkey")

    # Drop the index on word_id since it's no longer a foreign key
    drop index(:rounds, [:word_id])

    # Drop and recreate word_id as integer
    execute("ALTER TABLE rounds DROP COLUMN word_id")

    alter table(:rounds) do
      add :word_id, :integer, null: false
    end

    # Drop and recreate keyword_ids as integer array
    execute("ALTER TABLE rounds DROP COLUMN keyword_ids")

    alter table(:rounds) do
      add :keyword_ids, {:array, :integer}, default: [], null: false
    end

    # Drop and recreate possible_words_ids as integer array
    execute("ALTER TABLE rounds DROP COLUMN possible_words_ids")

    alter table(:rounds) do
      add :possible_words_ids, {:array, :integer}, default: [], null: false
    end
  end

  def down do
    # Reverse: recreate with original binary_id types
    drop constraint(:rounds, "rounds_word_id_fkey")

    execute("ALTER TABLE rounds DROP COLUMN word_id")

    alter table(:rounds) do
      add :word_id, :binary_id, null: false
    end

    execute("ALTER TABLE rounds DROP COLUMN keyword_ids")

    alter table(:rounds) do
      add :keyword_ids, {:array, :binary_id}, default: [], null: false
    end

    execute("ALTER TABLE rounds DROP COLUMN possible_words_ids")

    alter table(:rounds) do
      add :possible_words_ids, {:array, :binary_id}, default: [], null: false
    end

    # Re-add the foreign key constraint
    create index(:rounds, [:word_id])
    create constraint(:rounds, "rounds_word_id_fkey", check: "word_id IS NOT NULL")
  end
end
