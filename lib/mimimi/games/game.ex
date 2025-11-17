defmodule Mimimi.Games.Game do
  @moduledoc """
  Schema for games. Manages game state, settings, and relationships to players and rounds.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "games" do
    field :rounds_count, :integer, default: 3
    field :clues_interval, :integer, default: 10
    field :grid_size, :integer, default: 9
    field :word_types, {:array, :string}, default: ["Noun"]
    field :invitation_id, :binary_id
    field :host_token, :string
    field :state, :string, default: "waiting_for_players"
    field :started_at, :utc_datetime

    belongs_to :host_user, Mimimi.Accounts.User, foreign_key: :host_user_id
    has_many :players, Mimimi.Games.Player
    has_many :rounds, Mimimi.Games.Round

    timestamps()
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :rounds_count,
      :clues_interval,
      :grid_size,
      :word_types,
      :invitation_id,
      :host_token,
      :state,
      :started_at,
      :host_user_id
    ])
    |> validate_required([
      :rounds_count,
      :clues_interval,
      :grid_size,
      :word_types,
      :host_user_id,
      :host_token
    ])
    |> validate_inclusion(:rounds_count, 1..20)
    |> validate_inclusion(:clues_interval, [3, 6, 9, 12, 15, 20, 30, 45, 60])
    |> validate_inclusion(:grid_size, [2, 4, 9, 16])
    |> validate_word_types()
    |> validate_inclusion(:state, [
      "waiting_for_players",
      "game_running",
      "game_over",
      "lobby_timeout",
      "host_disconnected"
    ])
    |> unique_constraint(:invitation_id)
    |> unique_constraint(:host_token)
    |> foreign_key_constraint(:host_user_id)
  end

  defp validate_word_types(changeset) do
    changeset
    |> validate_length(:word_types, min: 1, message: "must include at least one word type")
    |> validate_change(:word_types, fn :word_types, types ->
      valid_types = ["Noun", "Verb", "Adjective", "Adverb", "Other"]
      invalid_types = Enum.reject(types, &(&1 in valid_types))

      if invalid_types == [] do
        []
      else
        [word_types: "contains invalid types: #{Enum.join(invalid_types, ", ")}"]
      end
    end)
  end
end
