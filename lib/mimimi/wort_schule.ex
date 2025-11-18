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
  Get complete word data for multiple words in a single batch query.
  Much faster than calling get_complete_word/1 in a loop.

  ## Examples

      iex> WortSchule.get_complete_words_batch([123, 456])
      %{
        123 => %{id: 123, name: "Affe", keywords: [...], image_url: "..."},
        456 => %{id: 456, name: "Baum", keywords: [...], image_url: "..."}
      }

      iex> WortSchule.get_complete_words_batch([])
      %{}
  """
  def get_complete_words_batch([]), do: %{}

  def get_complete_words_batch(word_ids) when is_list(word_ids) do
    from(w in Word,
      where: w.id in ^word_ids,
      preload: [keywords: ^from(k in Word, order_by: k.name)]
    )
    |> Repo.all()
    |> Enum.map(fn word -> {word.id, format_word(word)} end)
    |> Enum.into(%{})
  end

  @doc """
  Get word by ID.
  """
  def get_word(id) do
    Repo.get(Word, id)
  end

  @doc """
  Get multiple words by IDs in a single batch query.
  Returns a map of word_id => word struct.

  ## Examples

      iex> WortSchule.get_words_batch([123, 456])
      %{123 => %Word{id: 123, name: "Affe"}, 456 => %Word{id: 456, name: "Baum"}}
  """
  def get_words_batch([]), do: %{}

  def get_words_batch(word_ids) when is_list(word_ids) do
    from(w in Word, where: w.id in ^word_ids)
    |> Repo.all()
    |> Enum.map(fn word -> {word.id, word} end)
    |> Enum.into(%{})
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
  Get all words that have at least one keyword and an image.
  Returns formatted word data with keywords and image URL.
  """
  def get_words_with_keywords_and_images do
    from(w in Word,
      join: att in "active_storage_attachments",
      on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
      join: k in "keywords",
      on: k.word_id == w.id,
      distinct: true,
      order_by: w.name,
      preload: [keywords: ^from(kw in Word, order_by: kw.name)]
    )
    |> Repo.all()
    |> Enum.map(&format_word/1)
  end

  @doc """
  Get IDs of all words that have at least one keyword and an image.
  This is a lightweight query that only fetches IDs for async processing.

  ## Options

    * `:min_keywords` - Minimum number of keywords required (default: 1)
    * `:types` - List of word types to filter by (e.g., ["Noun", "Verb"]) (default: all types)

  ## Examples

      iex> WortSchule.get_word_ids_with_keywords_and_images()
      [123, 456, 789]

      iex> WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 2)
      [123, 789]

      iex> WortSchule.get_word_ids_with_keywords_and_images(types: ["Noun"])
      [123, 456]
  """
  def get_word_ids_with_keywords_and_images(opts \\ []) do
    try do
      min_keywords = Keyword.get(opts, :min_keywords, 1)
      types = Keyword.get(opts, :types)

      query =
        from(w in Word,
          join: att in "active_storage_attachments",
          on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
          join: k in "keywords",
          on: k.word_id == w.id,
          join: kw in Word,
          on: kw.id == k.keyword_id,
          group_by: [w.id, w.name],
          having: count(k.keyword_id, :distinct) >= ^min_keywords,
          order_by: w.name,
          select: {w.id, w.name}
        )

      query =
        if types && types != [] do
          from(w in query, where: w.type in ^types)
        else
          query
        end

      query
      |> Repo.all()
      |> Enum.map(fn {id, _name} -> id end)
    rescue
      _error -> []
    end
  end

  @doc """
  Get the maximum number of keywords for any word that has an image.
  Returns 0 if no words with images exist.

  ## Examples

      iex> WortSchule.get_max_keywords_count()
      15
  """
  def get_max_keywords_count do
    try do
      result =
        from(w in Word,
          join: att in "active_storage_attachments",
          on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
          join: k in "keywords",
          on: k.word_id == w.id,
          join: kw in Word,
          on: kw.id == k.keyword_id,
          group_by: w.id,
          select: count(k.keyword_id, :distinct)
        )
        |> Repo.all()

      case result do
        [] -> 0
        counts -> Enum.max(counts)
      end
    rescue
      _error -> 1
    end
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
