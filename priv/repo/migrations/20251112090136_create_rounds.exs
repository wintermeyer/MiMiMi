defmodule Mimimi.Repo.Migrations.CreateRounds do
  use Ecto.Migration

  def change do
    create table(:rounds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, on_delete: :delete_all, type: :binary_id), null: false
      add :word_id, references(:words, on_delete: :restrict, type: :binary_id), null: false
      add :keyword_ids, {:array, :binary_id}, default: [], null: false
      add :possible_words_ids, {:array, :binary_id}, default: [], null: false
      add :position, :integer, null: false
      add :state, :string, default: "on_hold", null: false

      timestamps()
    end

    create index(:rounds, [:game_id])
    create index(:rounds, [:word_id])
    create unique_index(:rounds, [:game_id, :position])
  end
end
