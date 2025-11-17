defmodule Mimimi.Repo.Migrations.AddWordIdToPicks do
  use Ecto.Migration

  def change do
    alter table(:picks) do
      add :word_id, :integer
    end

    # Set default value for existing picks (set to 0 for old data)
    execute "UPDATE picks SET word_id = 0 WHERE word_id IS NULL", ""

    # Now make it non-nullable
    alter table(:picks) do
      modify :word_id, :integer, null: false
    end

    create index(:picks, [:word_id])
  end
end
