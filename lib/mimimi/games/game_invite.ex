defmodule Mimimi.Games.GameInvite do
  @moduledoc """
  Schema for game invitations with short codes that expire.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id
  schema "game_invites" do
    field :short_code, :string
    field :expires_at, :utc_datetime

    belongs_to :game, Mimimi.Games.Game

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_invite, attrs) do
    game_invite
    |> cast(attrs, [:short_code, :game_id, :expires_at])
    |> validate_required([:short_code, :game_id, :expires_at])
    |> unique_constraint(:short_code)
    |> foreign_key_constraint(:game_id)
  end
end
