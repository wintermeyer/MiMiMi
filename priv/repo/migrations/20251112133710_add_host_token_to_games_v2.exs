defmodule Mimimi.Repo.Migrations.AddHostTokenToGamesV2 do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Check if the column exists before adding it
    # This handles the case where the previous migration already ran
    if !column_exists?(:games, :host_token) do
      # Add the column as nullable
      alter table(:games) do
        add :host_token, :string, null: true
      end
    end

    # Generate host tokens for existing games using Elixir
    flush()

    # Use Elixir to generate tokens for existing records that don't have one
    Mimimi.Repo.all(from(g in "games", where: is_nil(g.host_token), select: g.id))
    |> Enum.each(fn game_id ->
      host_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      Mimimi.Repo.query!(
        "UPDATE games SET host_token = $1 WHERE id = $2",
        [host_token, game_id]
      )
    end)

    # Now make it NOT NULL if it's not already
    alter table(:games) do
      modify :host_token, :string, null: false
    end

    # Create unique index if it doesn't exist
    create_if_not_exists unique_index(:games, [:host_token])
  end

  defp column_exists?(table, column) do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_name = '#{table}'
      AND column_name = '#{column}'
    )
    """

    case Mimimi.Repo.query(query) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  def down do
    drop index(:games, [:host_token])

    alter table(:games) do
      remove :host_token
    end
  end
end
