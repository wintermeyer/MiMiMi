defmodule Mimimi.Repo.Migrations.AddWordTypesToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :word_types, {:array, :string}, default: ["Noun"], null: false
    end
  end
end
