defmodule Mimimi.Repo.Migrations.CreateKeywords do
  use Ecto.Migration

  def change do
    create table(:keywords, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :word_id, references(:words, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:keywords, [:word_id])
  end
end
