defmodule Mimimi.GamesTest do
  use Mimimi.DataCase, async: true

  alias Mimimi.{Accounts, Games}

  describe "short code generation" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      %{host_user: host_user}
    end

    test "creates a game with a short invitation code", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9
        })

      # Get the short code
      short_code = Games.get_short_code_for_game(game.id)

      # Short code should exist
      assert short_code != nil

      # Short code should be exactly 6 digits
      assert String.length(short_code) == 6
      assert String.match?(short_code, ~r/^\d{6}$/)
    end

    test "each game gets a unique short code", %{host_user: host_user} do
      {:ok, game1} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, game2} =
        Games.create_game(host_user.id, %{rounds_count: 5, clues_interval: 12, grid_size: 4})

      short_code1 = Games.get_short_code_for_game(game1.id)
      short_code2 = Games.get_short_code_for_game(game2.id)

      # Each game should have a different short code
      assert short_code1 != short_code2

      # Both should be 6-digit strings
      assert String.length(short_code1) == 6
      assert String.length(short_code2) == 6
    end

    test "can retrieve game by short code", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      short_code = Games.get_short_code_for_game(game.id)

      # Should be able to retrieve the game using the short code
      retrieved_game = Games.get_game_by_short_code(short_code)

      assert retrieved_game != nil
      assert retrieved_game.id == game.id
    end
  end

  describe "short code validation" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9
        })

      short_code = Games.get_short_code_for_game(game.id)

      %{host_user: host_user, game: game, short_code: short_code}
    end

    test "validates a valid short code", %{short_code: short_code, game: game} do
      assert {:ok, validated_game} = Games.validate_short_code(short_code)
      assert validated_game.id == game.id
    end

    test "returns error for non-existent short code" do
      assert {:error, :not_found} = Games.validate_short_code("999999")
    end

    test "returns error for expired short code", %{game: game} do
      # Create an expired invite
      expired_time =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      {:ok, expired_invite} =
        %Games.GameInvite{}
        |> Games.GameInvite.changeset(%{
          short_code: "111111",
          game_id: game.id,
          expires_at: expired_time
        })
        |> Repo.insert()

      assert {:error, :expired} = Games.validate_short_code(expired_invite.short_code)
    end

    test "returns error when game has already started", %{short_code: short_code, game: game} do
      # Start the game
      Games.update_game_state(game, "game_running")

      assert {:error, :already_started} = Games.validate_short_code(short_code)
    end

    test "returns error when game is over", %{short_code: short_code, game: game} do
      Games.update_game_state(game, "game_over")

      assert {:error, :game_over} = Games.validate_short_code(short_code)
    end

    test "returns error when lobby has timed out", %{short_code: short_code, game: game} do
      Games.update_game_state(game, "lobby_timeout")

      assert {:error, :lobby_timeout} = Games.validate_short_code(short_code)
    end

    test "returns error when host has disconnected", %{short_code: short_code, game: game} do
      Games.update_game_state(game, "host_disconnected")

      assert {:error, :host_disconnected} = Games.validate_short_code(short_code)
    end
  end

  describe "word types" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      %{host_user: host_user}
    end

    test "creates game with default word types", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9
        })

      assert game.word_types == ["Noun"]
    end

    test "creates game with custom word types", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun", "Verb"]
        })

      assert game.word_types == ["Noun", "Verb"]
    end

    test "rejects game with empty word types", %{host_user: host_user} do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: []
        })
      end
    end

    test "rejects game with invalid word type", %{host_user: host_user} do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["InvalidType"]
        })
      end
    end

    test "accepts multiple valid word types", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun", "Verb", "Adjective", "Adverb", "Other"]
        })

      assert length(game.word_types) == 5
    end
  end

  describe "short code expiration" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      %{host_user: host_user}
    end

    test "creates invite with default expiration time", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      # Get the game invite from the database
      invite =
        Repo.get_by(Games.GameInvite, game_id: game.id)
        |> Repo.preload(:game)

      # Check that expires_at is set to approximately 15 minutes from now
      now = DateTime.utc_now()
      expected_expiration = DateTime.add(now, 15 * 60, :second)

      # Allow 5 seconds tolerance for test execution time
      diff = DateTime.diff(invite.expires_at, expected_expiration, :second)
      assert abs(diff) < 5
    end

    test "expired invites are not returned by get_game_by_short_code", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      # Get the original short code
      short_code = Games.get_short_code_for_game(game.id)

      # Manually expire the invite
      invite = Repo.get_by(Games.GameInvite, short_code: short_code)

      expired_time =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(expires_at: expired_time)
      |> Repo.update!()

      # Should return nil for expired invite
      assert Games.get_game_by_short_code(short_code) == nil
    end

    test "expired invites are not returned by get_short_code_for_game", %{host_user: host_user} do
      {:ok, game} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      # Get the original short code
      short_code = Games.get_short_code_for_game(game.id)
      assert short_code != nil

      # Manually expire the invite
      invite = Repo.get_by(Games.GameInvite, short_code: short_code)

      expired_time =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(expires_at: expired_time)
      |> Repo.update!()

      # Should return nil for expired invite
      assert Games.get_short_code_for_game(game.id) == nil
    end
  end

  describe "round analytics" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session")
      {:ok, player3_user} = Accounts.get_or_create_user_by_session("player3_session")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 4
        })

      {:ok, player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})
      {:ok, player3} = Games.create_player(player3_user.id, game.id, %{avatar: "🦉"})

      round =
        %Games.Round{}
        |> Games.Round.changeset(%{
          game_id: game.id,
          word_id: 1,
          keyword_ids: [1, 2, 3],
          possible_words_ids: [1, 2, 3, 4],
          position: 1,
          state: "playing"
        })
        |> Repo.insert!()

      %{game: game, round: round, player1: player1, player2: player2, player3: player3}
    end

    test "returns analytics with no picks", %{round: round} do
      analytics = Games.get_round_analytics(round.id)

      assert analytics.total_players == 3
      assert analytics.picked_count == 0
      assert analytics.not_picked_count == 3
      assert analytics.correct_count == 0
      assert analytics.wrong_count == 0
      assert analytics.average_time == nil
      assert analytics.fastest_correct_time == nil
    end

    @tag :external_db
    test "returns analytics with all players picked", %{
      round: round,
      player1: player1,
      player2: player2,
      player3: player3
    } do
      {:ok, {_pick1, _all_picked1}} =
        Games.create_pick(round.id, player1.id, %{
          is_correct: true,
          keywords_shown: 1,
          time: 5,
          word_id: 1
        })

      {:ok, {_pick2, _all_picked2}} =
        Games.create_pick(round.id, player2.id, %{
          is_correct: true,
          keywords_shown: 2,
          time: 10,
          word_id: 1
        })

      {:ok, {_pick3, _all_picked3}} =
        Games.create_pick(round.id, player3.id, %{
          is_correct: false,
          keywords_shown: 3,
          time: 15,
          word_id: 2
        })

      analytics = Games.get_round_analytics(round.id)

      assert analytics.total_players == 3
      assert analytics.picked_count == 3
      assert analytics.not_picked_count == 0
      assert analytics.correct_count == 2
      assert analytics.wrong_count == 1
      assert analytics.average_time == 10
      assert analytics.fastest_correct_time == 5
    end

    @tag :external_db
    test "returns analytics with partial picks", %{
      round: round,
      player1: player1,
      player2: player2
    } do
      {:ok, {_pick1, _all_picked1}} =
        Games.create_pick(round.id, player1.id, %{
          is_correct: true,
          keywords_shown: 1,
          time: 8,
          word_id: 1
        })

      {:ok, {_pick2, _all_picked2}} =
        Games.create_pick(round.id, player2.id, %{
          is_correct: false,
          keywords_shown: 2,
          time: 12,
          word_id: 2
        })

      analytics = Games.get_round_analytics(round.id)

      assert analytics.total_players == 3
      assert analytics.picked_count == 2
      assert analytics.not_picked_count == 1
      assert analytics.correct_count == 1
      assert analytics.wrong_count == 1
      assert length(analytics.players_not_picked) == 1
    end
  end

  describe "calculate_points/1" do
    test "returns 5 points for 1 keyword" do
      assert Games.calculate_points(1) == 5
    end

    test "returns 3 points for 2 keywords" do
      assert Games.calculate_points(2) == 3
    end

    test "returns 1 point for 3 keywords" do
      assert Games.calculate_points(3) == 1
    end

    test "returns 1 point for 4 or more keywords" do
      assert Games.calculate_points(4) == 1
      assert Games.calculate_points(5) == 1
      assert Games.calculate_points(10) == 1
    end
  end

  describe "game performance stats" do
    setup do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 2,
          clues_interval: 9,
          grid_size: 4
        })

      {:ok, player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})

      round1 =
        %Games.Round{}
        |> Games.Round.changeset(%{
          game_id: game.id,
          word_id: 1,
          keyword_ids: [1, 2, 3],
          possible_words_ids: [1, 2, 3, 4],
          position: 1,
          state: "finished"
        })
        |> Repo.insert!()

      round2 =
        %Games.Round{}
        |> Games.Round.changeset(%{
          game_id: game.id,
          word_id: 2,
          keyword_ids: [4, 5, 6],
          possible_words_ids: [2, 5, 6, 7],
          position: 2,
          state: "finished"
        })
        |> Repo.insert!()

      %{game: game, round1: round1, round2: round2, player1: player1, player2: player2}
    end

    test "returns stats with no picks", %{game: game} do
      stats = Games.get_game_performance_stats(game.id)

      assert stats.game_id == game.id
      assert stats.total_rounds == 2
      assert stats.played_rounds == 0
      assert stats.average_accuracy == 0.0
      assert stats.total_correct == 0
      assert stats.total_wrong == 0
      assert stats.player_stats == []
    end

    test "calculates overall game statistics", %{
      game: game,
      round1: round1,
      round2: round2,
      player1: player1,
      player2: player2
    } do
      # Player 1: 2 correct picks
      {:ok, {_, _}} =
        Games.create_pick(round1.id, player1.id, %{
          is_correct: true,
          keywords_shown: 1,
          time: 5,
          word_id: 1
        })

      {:ok, {_, _}} =
        Games.create_pick(round2.id, player1.id, %{
          is_correct: true,
          keywords_shown: 2,
          time: 8,
          word_id: 2
        })

      # Player 2: 1 correct, 1 wrong
      {:ok, {_, _}} =
        Games.create_pick(round1.id, player2.id, %{
          is_correct: false,
          keywords_shown: 2,
          time: 10,
          word_id: 3
        })

      {:ok, {_, _}} =
        Games.create_pick(round2.id, player2.id, %{
          is_correct: true,
          keywords_shown: 3,
          time: 12,
          word_id: 2
        })

      stats = Games.get_game_performance_stats(game.id)

      assert stats.game_id == game.id
      assert stats.total_rounds == 2
      assert stats.played_rounds == 2
      assert stats.total_correct == 3
      assert stats.total_wrong == 1
      assert stats.average_accuracy == 75.0

      assert length(stats.player_stats) == 2

      # Check player1 stats (should be first due to 100% accuracy)
      player1_stats = Enum.find(stats.player_stats, &(&1.player.id == player1.id))
      assert player1_stats.picks_made == 2
      assert player1_stats.correct == 2
      assert player1_stats.wrong == 0
      assert player1_stats.accuracy == 100.0
      assert player1_stats.average_keywords_used == 1.5

      # Check player2 stats
      player2_stats = Enum.find(stats.player_stats, &(&1.player.id == player2.id))
      assert player2_stats.picks_made == 2
      assert player2_stats.correct == 1
      assert player2_stats.wrong == 1
      assert player2_stats.accuracy == 50.0
      assert player2_stats.average_keywords_used == 2.5
    end

    test "player_stats are sorted by accuracy descending", %{
      game: game,
      round1: round1,
      player1: player1,
      player2: player2
    } do
      # Player 1: lower accuracy
      {:ok, {_, _}} =
        Games.create_pick(round1.id, player1.id, %{
          is_correct: false,
          keywords_shown: 1,
          time: 5,
          word_id: 3
        })

      # Player 2: higher accuracy
      {:ok, {_, _}} =
        Games.create_pick(round1.id, player2.id, %{
          is_correct: true,
          keywords_shown: 2,
          time: 10,
          word_id: 1
        })

      stats = Games.get_game_performance_stats(game.id)

      # First player should have highest accuracy
      assert hd(stats.player_stats).accuracy >= List.last(stats.player_stats).accuracy
    end
  end
end
