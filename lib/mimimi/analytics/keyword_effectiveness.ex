defmodule Mimimi.Analytics.KeywordEffectiveness do
  @moduledoc """
  Schema for tracking keyword effectiveness in helping players guess words.

  Each record represents a single keyword that was visible when a player made a pick.
  If a player saw 3 keywords before guessing, 3 records are created - one per keyword.

  This data enables analysis of:
  - Which keywords lead to fast/correct guesses
  - Which keywords are ineffective or misleading
  - Words that need better keywords
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "keyword_effectiveness" do
    # WortSchule integer IDs
    field :word_id, :integer
    field :keyword_id, :integer

    # MiMiMi UUIDs (not foreign keys since this is in a different database)
    field :pick_id, :binary_id
    field :round_id, :binary_id

    # Order & Timing
    field :keyword_position, :integer
    field :revealed_at, :utc_datetime_usec
    field :picked_at, :utc_datetime_usec

    # Outcome
    field :led_to_correct, :boolean

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [
    :word_id,
    :keyword_id,
    :pick_id,
    :round_id,
    :keyword_position,
    :revealed_at,
    :picked_at,
    :led_to_correct
  ]

  @doc false
  def changeset(keyword_effectiveness, attrs) do
    keyword_effectiveness
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:keyword_position, greater_than: 0)
  end
end
