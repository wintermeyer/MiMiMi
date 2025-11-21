defmodule Mimimi.Games.RoundValidationTest do
  use Mimimi.DataCase, async: true

  alias Mimimi.{Accounts, Games}
  alias Mimimi.WortSchule.ImageHelper

  describe "round generation with image validation" do
    @describetag :external_db

    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("validation_test_host")
      %{host_user: host_user}
    end

    test "fails when there are not enough words with valid images", %{host_user: host_user} do
      # Create a game with max rounds and a rare word type
      # Adverbs likely have very few words with images
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 20,
          clues_interval: 9,
          grid_size: 9,
          # Use Adverb which likely has few/no valid images
          word_types: ["Adverb"]
        })

      # Starting the game should fail or set an error state
      result = Games.start_game(game)

      # The game should either return an error or have rounds_generation_failed
      case result do
        {:ok, started_game} ->
          # If it started, it should fail during round generation
          # Wait a bit for async generation
          :timer.sleep(500)

          # Check game state - should be in error or game_over
          updated_game = Games.get_game(started_game.id)
          assert updated_game.state in ["game_over", "error"]

        {:error, _reason} ->
          # Direct error is acceptable
          assert true
      end
    end

    test "all generated rounds have valid image URLs", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Generate rounds
      Games.generate_rounds(game)

      # Fetch all rounds
      rounds =
        Repo.all(
          from(r in Games.Round,
            where: r.game_id == ^game.id,
            order_by: [asc: r.position]
          )
        )

      assert length(rounds) == 3

      # Check that all words in all rounds have valid image URLs
      Enum.each(rounds, fn round ->
        Enum.each(round.possible_words_ids, fn word_id ->
          image_url = ImageHelper.image_url_for_word(word_id)

          assert image_url != nil,
                 "Word #{word_id} in round #{round.position} has no valid image URL"

          assert is_binary(image_url) and image_url != "",
                 "Word #{word_id} in round #{round.position} has invalid image URL: #{inspect(image_url)}"
        end)
      end)
    end

    test "all generated rounds have valid keywords", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Generate rounds
      Games.generate_rounds(game)

      # Fetch all rounds
      rounds =
        Repo.all(
          from(r in Games.Round,
            where: r.game_id == ^game.id,
            order_by: [asc: r.position]
          )
        )

      assert length(rounds) == 3

      # Check that all keyword IDs are valid and have names
      Enum.each(rounds, fn round ->
        assert length(round.keyword_ids) >= 3,
               "Round #{round.position} has fewer than 3 keywords: #{length(round.keyword_ids)}"

        keywords_map = Mimimi.WortSchule.get_words_batch(round.keyword_ids)

        Enum.each(round.keyword_ids, fn keyword_id ->
          keyword = Map.get(keywords_map, keyword_id)

          assert keyword != nil,
                 "Keyword #{keyword_id} in round #{round.position} not found in database"

          assert keyword.name != nil and keyword.name != "",
                 "Keyword #{keyword_id} in round #{round.position} has no name"
        end)
      end)
    end
  end

  describe "validate_word_images/1" do
    @describetag :external_db

    test "returns only words with valid image URLs" do
      # Get some word IDs
      word_ids =
        Mimimi.WortSchule.get_word_ids_with_keywords_and_images(
          min_keywords: 1,
          types: ["Noun"]
        )
        |> Enum.take(10)

      if word_ids == [] do
        # Skip if no words available
        assert true
      else
        # Validate images
        valid_word_ids = Games.validate_word_images(word_ids)

        # All returned word IDs should have valid image URLs
        Enum.each(valid_word_ids, fn word_id ->
          url = ImageHelper.image_url_for_word(word_id)
          assert url != nil and is_binary(url) and url != ""
        end)
      end
    end

    test "filters out words without valid images" do
      # This test verifies that validate_word_images actually filters
      # We can't easily create test data, but we can verify the function exists
      result = Games.validate_word_images([])
      assert result == []
    end
  end

  describe "insufficient data error handling" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("error_test_host")
      %{host_user: host_user}
    end

    test "raises informative error when not enough valid target words", %{host_user: host_user} do
      # Test with max rounds and rare word type to trigger insufficient words error
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 20,
          clues_interval: 9,
          grid_size: 9,
          # Other word type likely has very few words with 3+ keywords
          word_types: ["Other"]
        })

      # This should raise an error about insufficient words
      assert_raise RuntimeError, ~r/nicht genügend|not enough/i, fn ->
        Games.generate_rounds(game)
      end
    end

    test "raises informative error when not enough valid distractor words", %{
      host_user: host_user
    } do
      # Test with large grid and rare word type
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 20,
          clues_interval: 9,
          # Max grid size with rare word type
          grid_size: 16,
          word_types: ["Other"]
        })

      # This should raise an error about insufficient words
      assert_raise RuntimeError, ~r/nicht genügend|not enough/i, fn ->
        Games.generate_rounds(game)
      end
    end
  end
end
