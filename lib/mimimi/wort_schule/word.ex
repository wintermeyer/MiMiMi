defmodule Mimimi.WortSchule.Word do
  @moduledoc """
  Schema for accessing words from the wort.schule database.
  This is a read-only schema for an external database.
  """
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [inserted_at: :created_at, updated_at: :updated_at]
  schema "words" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :meaning, :string
    field :meaning_long, :string
    field :syllables, :string
    field :example_sentences, {:array, :string}
    field :hit_counter, :integer
    field :prototype, :boolean
    field :foreign, :boolean
    field :compound, :boolean
    field :with_tts, :boolean

    timestamps()

    # Many-to-many self-referential association for keywords
    many_to_many :keywords, __MODULE__,
      join_through: "keywords",
      join_keys: [word_id: :id, keyword_id: :id]
  end
end
