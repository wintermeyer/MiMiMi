defmodule Mimimi.Repo.Migrations.CreateGameInvites do
  use Ecto.Migration

  def change do
    create table(:game_invites) do
      add :short_code, :string, null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_invites, [:short_code])
    create index(:game_invites, [:game_id])
    create index(:game_invites, [:expires_at])
  end
end
