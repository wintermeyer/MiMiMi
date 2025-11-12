defmodule Mimimi.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :host_user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :rounds_count, :integer, default: 3, null: false
      add :clues_interval, :integer, default: 10, null: false
      add :grid_size, :integer, default: 9, null: false
      add :invitation_id, :binary_id, null: false
      add :state, :string, default: "waiting_for_players", null: false
      add :started_at, :utc_datetime

      timestamps()
    end

    create unique_index(:games, [:invitation_id])
    create index(:games, [:host_user_id])
    create index(:games, [:state])
  end
end
