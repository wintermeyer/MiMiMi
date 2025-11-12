defmodule Mimimi.Repo.Migrations.CreatePicks do
  use Ecto.Migration

  def change do
    create table(:picks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :round_id, references(:rounds, on_delete: :delete_all, type: :binary_id), null: false
      add :player_id, references(:players, on_delete: :delete_all, type: :binary_id), null: false
      add :time, :integer, null: false
      add :keywords_shown, :integer, null: false
      add :is_correct, :boolean, default: false, null: false

      timestamps()
    end

    create index(:picks, [:round_id])
    create index(:picks, [:player_id])
    create unique_index(:picks, [:round_id, :player_id])
  end
end
