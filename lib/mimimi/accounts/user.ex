defmodule Mimimi.Accounts.User do
  @moduledoc """
  Schema for users. Users are identified by session and can host or join games.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :session_id, :string

    has_many :games, Mimimi.Games.Game, foreign_key: :host_user_id
    has_many :players, Mimimi.Games.Player

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:session_id])
    |> validate_required([:session_id])
    |> unique_constraint(:session_id)
  end
end
