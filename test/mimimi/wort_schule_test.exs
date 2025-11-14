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
  end
end
