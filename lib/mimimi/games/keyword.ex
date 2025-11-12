defmodule Mimimi.Games.Keyword do
  @moduledoc """
  Schema for keywords/clues associated with words. These are shown to help players guess.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "keywords" do
    field :name, :string

    belongs_to :word, Mimimi.Games.Word

    timestamps()
  end

  @doc false
  def changeset(keyword, attrs) do
    keyword
    |> cast(attrs, [:name, :word_id])
    |> validate_required([:name, :word_id])
    |> foreign_key_constraint(:word_id)
  end
end
