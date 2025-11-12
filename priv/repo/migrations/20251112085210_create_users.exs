defmodule Mimimi.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:session_id])
  end
end
