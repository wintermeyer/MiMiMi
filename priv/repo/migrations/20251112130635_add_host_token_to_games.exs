defmodule Mimimi.Repo.Migrations.AddHostTokenToGames do
  use Ecto.Migration

  def up do
    # Enable pgcrypto extension for gen_random_bytes
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    # First add the column as nullable
    alter table(:games) do
      add :host_token, :string, null: true
    end

    # Generate host tokens for existing games using PostgreSQL's gen_random_bytes
    execute """
    UPDATE games
    SET host_token = replace(encode(gen_random_bytes(32), 'base64'), '/', '_')
    WHERE host_token IS NULL;
    """

    # Now make it NOT NULL
    alter table(:games) do
      modify :host_token, :string, null: false
    end

    create unique_index(:games, [:host_token])
  end

  def down do
    drop index(:games, [:host_token])

    alter table(:games) do
      remove :host_token
    end
  end
end
