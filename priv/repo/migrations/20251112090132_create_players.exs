defmodule Mimimi.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :game_id, references(:games, on_delete: :delete_all, type: :binary_id), null: false
      add :points, :integer, default: 0, null: false
      add :avatar, :string
      add :nickname, :string

      timestamps()
    end

    create index(:players, [:user_id])
    create index(:players, [:game_id])
    create unique_index(:players, [:game_id, :avatar])
  end
end
