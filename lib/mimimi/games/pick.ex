defmodule Mimimi.Games.Pick do
  @moduledoc """
  Schema for player picks/guesses in a round. Tracks timing and correctness.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "picks" do
    field :time, :integer
    field :keywords_shown, :integer
    field :is_correct, :boolean, default: false
    field :word_id, :integer

    belongs_to :round, Mimimi.Games.Round
    belongs_to :player, Mimimi.Games.Player

    timestamps()
  end

  @doc false
  def changeset(pick, attrs) do
    pick
    |> cast(attrs, [:time, :keywords_shown, :is_correct, :word_id, :round_id, :player_id])
    |> validate_required([:time, :keywords_shown, :word_id, :round_id, :player_id])
    |> foreign_key_constraint(:round_id)
    |> foreign_key_constraint(:player_id)
    |> unique_constraint([:round_id, :player_id])
  end
end
