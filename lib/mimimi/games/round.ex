defmodule Mimimi.Games.Round do
  @moduledoc """
  Schema for game rounds. Each round has a word to guess and associated keywords.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rounds" do
    # WortSchule word ID (not a foreign key)
    field :word_id, :integer
    # WortSchule keyword IDs
    field :keyword_ids, {:array, :integer}, default: []
    # WortSchule word IDs
    field :possible_words_ids, {:array, :integer}, default: []
    field :position, :integer
    field :state, :string, default: "on_hold"

    belongs_to :game, Mimimi.Games.Game
    has_many :picks, Mimimi.Games.Pick

    timestamps()
  end

  @doc false
  def changeset(round, attrs) do
    round
    |> cast(attrs, [:keyword_ids, :possible_words_ids, :position, :state, :game_id, :word_id])
    |> validate_required([:position, :game_id, :word_id])
    |> validate_inclusion(:state, ["on_hold", "playing", "finished"])
    |> foreign_key_constraint(:game_id)
    |> unique_constraint([:game_id, :position])
  end
end
