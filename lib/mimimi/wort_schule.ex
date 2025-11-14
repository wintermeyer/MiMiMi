defmodule Mimimi.WortSchule do
  @moduledoc """
  Context module for accessing wort.schule data.
  Provides a clean interface for querying words, keywords, and images.
  """
  import Ecto.Query
  alias Mimimi.WortSchuleRepo, as: Repo
  alias Mimimi.WortSchule.{Word, ImageHelper}

  @doc """
  Get complete word data: id, name, keywords, and image URL.

  ## Examples

      iex> WortSchule.get_complete_word(123)
      {:ok, %{
        id: 123,
        name: "Affe",
        keywords: [%{id: 456, name: "Tier"}],
        image_url: "https://wort.schule/rails/active_storage/blobs/redirect/..."
      }}

      iex> WortSchule.get_complete_word(99999)
      {:error, :not_found}
  """
  def get_complete_word(word_id) do
    case get_word_with_keywords(word_id) do
      nil -> {:error, :not_found}
      word -> {:ok, format_word(word)}
    end
  end

  @doc """
  Get word by ID.
  """
  def get_word(id) do
    Repo.get(Word, id)
  end

  @doc """
  Get word by slug.
  """
  def get_word_by_slug(slug) do
    Repo.get_by(Word, slug: slug)
  end

  @doc """
  Get word with keywords preloaded.
  """
  def get_word_with_keywords(id) do
    from(w in Word,
      where: w.id == ^id,
      preload: [keywords: ^from(k in Word, order_by: k.name)]
    )
    |> Repo.one()
  end

  @doc """
  Search words by name.

  ## Examples

      iex> WortSchule.search_words("Affe")
      [%Word{name: "Affe", ...}]
  """
  def search_words(search_term) do
    pattern = "%#{search_term}%"

    from(w in Word,
      where: ilike(w.name, ^pattern),
      order_by: w.name,
      limit: 20
    )
    |> Repo.all()
  end

  @doc """
  Get all words with images.
  """
  def get_words_with_images do
    from(w in Word,
      join: att in "active_storage_attachments",
      on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
      distinct: true,
      order_by: w.name
    )
    |> Repo.all()
  end

  @doc """
  Check if a word has an image.
  """
  def word_has_image?(word_id) do
    ImageHelper.has_image?(word_id)
  end

  @doc """
  Get image URL for a word.
  """
  def get_image_url(word_id) do
    ImageHelper.image_url_for_word(word_id)
  end

  @doc """
  List all words with optional filters.

  ## Options

    * `:type` - Filter by word type (e.g., "Noun", "Verb")
    * `:limit` - Limit results (default: 100)
    * `:offset` - Offset for pagination (default: 0)

  ## Examples

      iex> WortSchule.list_words(type: "Noun", limit: 10)
      [%Word{}, ...]
  """
  def list_words(opts \\ []) do
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query = from(w in Word, order_by: w.name)

    query =
      if type do
        from(w in query, where: w.type == ^type)
      else
        query
      end

    query
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp format_word(word) do
    %{
      id: word.id,
      name: word.name,
      keywords: Enum.map(word.keywords, &%{id: &1.id, name: &1.name}),
      image_url: ImageHelper.image_url_for_word(word.id)
    }
  end
end
