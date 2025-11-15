defmodule Mimimi.WortSchule.ImageHelper do
  @moduledoc """
  Helper module for fetching image URLs from the wort.schule JSON API.
  Uses an in-memory ETS cache with 24-hour expiration to minimize API calls.
  """
  import Ecto.Query
  alias Mimimi.WortSchuleRepo, as: Repo
  alias Mimimi.WortSchule.{Word, ImageUrlCache}

  @rails_base_url System.get_env("WORTSCHULE_RAILS_URL") || "https://wort.schule"

  @doc """
  Get image URL for a word by fetching from the wort.schule JSON API.
  Results are cached for 24 hours to minimize API calls.
  Returns a proxied URL to avoid CORS issues, or nil if no image attached or if the API request fails.

  ## Examples

      iex> ImageHelper.image_url_for_word(123)
      "/proxy/image/rails/active_storage/blobs/redirect/..."

      iex> ImageHelper.image_url_for_word(999)
      nil
  """
  def image_url_for_word(word_id) do
    case ImageUrlCache.get(word_id) do
      {:ok, url} ->
        url

      :miss ->
        case ImageUrlCache.try_fetch_lock(word_id) do
          :ok ->
            url = fetch_and_cache_url(word_id)
            ImageUrlCache.release_fetch_lock(word_id)
            url

          :already_fetching ->
            wait_for_fetch(word_id, 0)
        end
    end
  end

  defp wait_for_fetch(word_id, retry_count) when retry_count < 30 do
    Process.sleep(100)

    case ImageUrlCache.get(word_id) do
      {:ok, url} ->
        url

      :miss ->
        wait_for_fetch(word_id, retry_count + 1)
    end
  end

  defp wait_for_fetch(_word_id, _retry_count) do
    nil
  end

  defp fetch_and_cache_url(word_id) do
    url =
      case get_word_slug(word_id) do
        nil ->
          nil

        slug ->
          case fetch_word_data(slug) do
            {:ok, %{"image_url" => image_url}} when is_binary(image_url) and image_url != "" ->
              # Return proxied URL instead of direct URL to avoid CORS issues
              "/proxy/image#{image_url}"

            _ ->
              nil
          end
      end

    # Cache the result (even if nil) to avoid repeated failed lookups
    ImageUrlCache.put(word_id, url)
    url
  end

  defp get_word_slug(word_id) do
    from(w in Word, where: w.id == ^word_id, select: w.slug)
    |> Repo.one()
  end

  defp fetch_word_data(slug) do
    url = "#{@rails_base_url}/#{slug}.json"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        # Word not found in Rails app - this is expected for some words
        {:error, :not_found}

      {:ok, %{status: status}} ->
        require Logger
        Logger.warning("[ImageHelper] API returned status #{status} for #{url}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        require Logger
        Logger.warning("[ImageHelper] Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Check if a word has an image.

  ## Examples

      iex> ImageHelper.has_image?(123)
      true

      iex> ImageHelper.has_image?(999)
      false
  """
  def has_image?(word_id) do
    from(att in "active_storage_attachments",
      where:
        att.record_type == "Word" and
          att.record_id == ^word_id and
          att.name == "image"
    )
    |> Repo.exists?()
  end
end
