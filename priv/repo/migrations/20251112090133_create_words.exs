defmodule Mimimi.Repo.Migrations.CreateWords do
  use Ecto.Migration

  def change do
    create table(:words, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :image_path, :string

      timestamps()
    end

    create unique_index(:words, [:name])
  end
end
