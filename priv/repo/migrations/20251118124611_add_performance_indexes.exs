defmodule Mimimi.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for game state queries (used in count_active_games, count_waiting_games)
    create_if_not_exists index(:games, [:state])

    # Composite index for game invite lookups by short_code and expiration
    create_if_not_exists index(:game_invites, [:short_code, :expires_at])

    # Composite index for picks by round and correctness (used in analytics)
    create_if_not_exists index(:picks, [:round_id, :is_correct])

    # Composite index for player lookups by game and user
    create_if_not_exists index(:players, [:game_id, :user_id])

    # Index for round lookups by game
    create_if_not_exists index(:rounds, [:game_id])

    # Index for active games with updated timestamps (useful for cleanup)
    create_if_not_exists index(:games, [:state, :updated_at])
  end
end
