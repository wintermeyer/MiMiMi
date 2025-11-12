defmodule Mimimi.Games.Word do
  @moduledoc """
  Schema for words that players need to guess in the game.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "words" do
    field :name, :string
    field :image_path, :string

    has_many :keywords, Mimimi.Games.Keyword
    has_many :rounds, Mimimi.Games.Round

    timestamps()
  end

  @doc false
  def changeset(word, attrs) do
    word
    |> cast(attrs, [:name, :image_path])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
