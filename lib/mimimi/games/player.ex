defmodule Mimimi.Games.Player do
  @moduledoc """
  Schema for game players. Links users to games with their avatar and score.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "players" do
    field :points, :integer, default: 0
    field :avatar, :string
    field :nickname, :string

    belongs_to :user, Mimimi.Accounts.User
    belongs_to :game, Mimimi.Games.Game
    has_many :picks, Mimimi.Games.Pick

    timestamps()
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [:points, :avatar, :nickname, :user_id, :game_id])
    |> validate_required([:user_id, :game_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:game_id)
    |> unique_constraint([:game_id, :avatar])
  end
end
