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
end
