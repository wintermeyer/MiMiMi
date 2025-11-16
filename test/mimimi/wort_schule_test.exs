defmodule Mimimi.WortSchuleTest do
  use ExUnit.Case, async: true

  @moduletag :external_db

  alias Mimimi.WortSchuleRepo
  alias Mimimi.WortSchule

  describe "database connection" do
    test "can query the wort_schule database" do
      # This test verifies the connection works
      # It will only pass if the wortschule_development database exists
      result = WortSchuleRepo.query("SELECT 1 AS test")
      assert {:ok, %Postgrex.Result{}} = result
    end
  end

  describe "list_words/1" do
    test "returns a list of words" do
      # This will return an empty list if no words exist, or a list of words
      words = WortSchule.list_words(limit: 5)
      assert is_list(words)
    end

    test "can filter by type" do
      words = WortSchule.list_words(type: "Noun", limit: 5)
      assert is_list(words)
      # All returned words should be nouns
      Enum.each(words, fn word ->
        assert word.type == "Noun"
      end)
    end
  end

  describe "search_words/1" do
    test "returns a list of matching words" do
      words = WortSchule.search_words("test")
      assert is_list(words)
    end
  end

  describe "get_word/1" do
    test "returns nil for non-existent word" do
      # Use a very high ID that likely doesn't exist
      assert WortSchule.get_word(999_999_999) == nil
    end
  end

  describe "get_complete_word/1" do
    test "returns error tuple for non-existent word" do
      assert {:error, :not_found} = WortSchule.get_complete_word(999_999_999)
    end

    test "returns direct image URLs from wort.schule" do
      # Get a word that should have an image
      word_ids = WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1)

      if length(word_ids) > 0 do
        word_id = Enum.at(word_ids, 0)
        {:ok, word} = WortSchule.get_complete_word(word_id)

        # If the word has an image, verify it's a direct URL from wort.schule
        if word.image_url do
          assert String.starts_with?(word.image_url, "https://wort.schule/"),
                 "Image URL should be a direct URL from wort.schule, got: #{word.image_url}"
        end
      end
    end
  end

  describe "get_word_ids_with_keywords_and_images/1" do
    test "filters words by minimum number of keywords" do
      # Get all words with at least 1 keyword
      all_word_ids = WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1)

      # Get words with at least 3 keywords
      filtered_word_ids = WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 3)

      # The filtered list should be a subset of all words
      assert is_list(all_word_ids)
      assert is_list(filtered_word_ids)
      assert length(filtered_word_ids) <= length(all_word_ids)

      # Verify each word in the filtered list actually has at least 3 keywords
      Enum.each(filtered_word_ids, fn word_id ->
        {:ok, word} = WortSchule.get_complete_word(word_id)
        keyword_count = length(word.keywords)

        assert keyword_count >= 3,
               "Word '#{word.name}' (ID: #{word_id}) has only #{keyword_count} keywords, but should have at least 3"
      end)
    end
  end

  describe "get_max_keywords_count/0" do
    test "returns the maximum number of keywords for any word with an image" do
      max_count = WortSchule.get_max_keywords_count()

      # Should return a non-negative integer
      assert is_integer(max_count)
      assert max_count >= 0

      # If we have words with images, max should be at least 1
      word_ids = WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1)

      if length(word_ids) > 0 do
        assert max_count >= 1
      end
    end

    test "max count is accurate by verifying against actual word data" do
      max_count = WortSchule.get_max_keywords_count()

      # Get a sample of words with images
      word_ids = WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1)

      if length(word_ids) > 0 do
        # Check that no word has more keywords than the max
        Enum.each(Enum.take(word_ids, 10), fn word_id ->
          {:ok, word} = WortSchule.get_complete_word(word_id)
          keyword_count = length(word.keywords)

          assert keyword_count <= max_count,
                 "Word '#{word.name}' has #{keyword_count} keywords, but max is #{max_count}"
        end)
      end
    end
  end
end
