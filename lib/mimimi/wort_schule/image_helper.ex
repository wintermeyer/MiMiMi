defmodule Mimimi.WortSchule.ImageHelper do
  @moduledoc """
  Helper module for constructing image URLs from the wort.schule ActiveStorage system.
  """
  import Ecto.Query
  alias Mimimi.WortSchuleRepo, as: Repo

  @rails_base_url System.get_env("WORTSCHULE_RAILS_URL") || "https://wort.schule"

  @doc """
  Get image URL for a word by proxying through Rails.
  Returns nil if no image attached.

  ## Examples

      iex> ImageHelper.image_url_for_word(123)
      "https://wort.schule/rails/active_storage/blobs/redirect/abc123/word_image.png"

      iex> ImageHelper.image_url_for_word(999)
      nil
  """
  def image_url_for_word(word_id) do
    case get_image_blob(word_id) do
      nil ->
        nil

      {key, filename} ->
        "#{@rails_base_url}/rails/active_storage/blobs/redirect/#{key}/#{filename}"
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

  defp get_image_blob(word_id) do
    from(att in "active_storage_attachments",
      where:
        att.record_type == "Word" and
          att.record_id == ^word_id and
          att.name == "image",
      join: blob in "active_storage_blobs",
      on: blob.id == att.blob_id,
      select: {blob.key, blob.filename}
    )
    |> Repo.one()
  end
end
