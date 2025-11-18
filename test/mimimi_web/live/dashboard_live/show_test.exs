defmodule MimimiWeb.DashboardLive.ShowTest do
  use MimimiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mimimi.{Accounts, Games}

  describe "waiting room host authentication" do
    setup do
      # Create host user and game
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9
        })

      %{host_user: host_user, game: game}
    end

    test "host can access waiting room with valid host token", %{conn: conn, game: game} do
      # Simulate host session with host token
      host_token_key = "host_token_#{game.id}"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "host_session_id",
          host_token_key => game.host_token
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Host should see the waiting room controls
      assert html =~ "Einladungscode"
      assert html =~ "Jetzt spielen!"
    end

    test "host cannot access waiting room without host token cookie", %{conn: conn, game: game} do
      # Simulate host session but WITHOUT host token in session
      conn =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "host_session_id"})

      # Try to access waiting room - should be redirected
      result = live(conn, ~p"/dashboard/#{game.id}")

      # Should get a redirect with error flash
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => error_message}}}} = result
      assert error_message =~ "Unberechtigter Zugriff"
    end

    test "different user cannot hijack waiting room even with same URL", %{conn: conn, game: game} do
      # Create a different user (attacker)
      {:ok, _attacker_user} = Accounts.get_or_create_user_by_session("attacker_session_id")

      # Attacker tries to access the waiting room URL
      conn =
        conn
        |> Plug.Test.init_test_session(%{"session_id" => "attacker_session_id"})

      # Attacker tries with host's game URL but no host token
      # Should be completely denied access
      result = live(conn, ~p"/dashboard/#{game.id}")

      # Should get a redirect with error flash
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => error_message}}}} = result
      assert error_message =~ "Unberechtigter Zugriff"
    end

    test "different user cannot hijack even if they steal the URL and add fake cookie", %{
      conn: conn,
      game: game
    } do
      # Create a different user (attacker)
      {:ok, _attacker_user} = Accounts.get_or_create_user_by_session("attacker_session_id")

      # Attacker tries to access with their session and a fake token
      host_token_key = "host_token_#{game.id}"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "attacker_session_id",
          host_token_key => "fake_token_123"
        })

      # Should be redirected because token doesn't match
      result = live(conn, ~p"/dashboard/#{game.id}")

      # Should get a redirect with error flash
      assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => error_message}}}} = result
      assert error_message =~ "Unberechtigter Zugriff"
    end
  end

  describe "host token generation" do
    test "each game gets a unique host token" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")

      {:ok, game1} =
        Games.create_game(host_user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, game2} =
        Games.create_game(host_user.id, %{rounds_count: 5, clues_interval: 12, grid_size: 4})

      # Each game should have a different host token
      assert game1.host_token != game2.host_token

      # Tokens should be non-empty strings
      assert is_binary(game1.host_token)
      assert is_binary(game2.host_token)
      assert String.length(game1.host_token) > 20
      assert String.length(game2.host_token) > 20
    end
  end

  describe "game over view with correct picks" do
    @describetag :external_db

    setup do
      # Create host user and players
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_id")
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session_id")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session_id")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 4,
          word_types: ["Noun"]
        })

      # Add players to the game
      {:ok, player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🦁"})
      {:ok, player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})

      %{
        host_user: host_user,
        player1: player1,
        player2: player2,
        game: game
      }
    end

    test "displays correct picks with word images for each player", %{
      conn: conn,
      player1: player1,
      player2: player2,
      game: game
    } do
      # Start the game and generate rounds
      {:ok, game} = Games.start_game(game)
      round = Games.get_current_round(game.id)

      # Simulate picks - player1 picks correctly, player2 picks incorrectly
      {:ok, {_pick1, _}} =
        Games.create_pick(round.id, player1.id, %{
          word_id: round.word_id,
          time: 5,
          keywords_shown: 2,
          is_correct: true
        })

      # Get a distractor word for player2's incorrect pick
      distractor_id = Enum.find(round.possible_words_ids, &(&1 != round.word_id))

      {:ok, {_pick2, _}} =
        Games.create_pick(round.id, player2.id, %{
          word_id: distractor_id,
          time: 8,
          keywords_shown: 3,
          is_correct: false
        })

      # Award points to player1
      {:ok, _updated_player1} = Games.add_points(player1, 3)

      # End the game
      {:ok, _game} = Games.update_game_state(game, "game_over")

      # Host views the game over page
      host_token_key = "host_token_#{game.id}"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "host_session_id",
          host_token_key => game.host_token
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Should show "Spiel fertig!" heading
      assert html =~ "Spiel fertig!"

      # Should show both players in the leaderboard
      assert html =~ "🦁"
      assert html =~ "🐘"

      # Should show player1 with 3 points and player2 with 0 points
      assert html =~ "3 Punkte"
      assert html =~ "0 Punkte"

      # Should show correct picks section for players
      # We can't test for specific word images without knowing the word_id,
      # but we can verify the structure exists
      assert html =~ ~r/class="[^"]*correct-picks/
    end

    test "host sees new game button on game over screen", %{
      conn: conn,
      player1: player1,
      game: game
    } do
      # Start the game and generate rounds
      {:ok, game} = Games.start_game(game)
      round = Games.get_current_round(game.id)

      # Simulate a pick
      {:ok, {_pick1, _}} =
        Games.create_pick(round.id, player1.id, %{
          word_id: round.word_id,
          time: 5,
          keywords_shown: 2,
          is_correct: true
        })

      # End the game
      {:ok, _game} = Games.update_game_state(game, "game_over")

      # Host views the game over page
      host_token_key = "host_token_#{game.id}"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "host_session_id",
          host_token_key => game.host_token
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Host should see the new game button
      assert html =~ "Neues Spiel mit denselben Spielern"
      assert html =~ "phx-click=\"start_new_game\""
    end

    test "player does not see new game button on game over screen", %{
      conn: conn,
      player1: player1,
      game: game
    } do
      # Start the game and generate rounds
      {:ok, game} = Games.start_game(game)
      round = Games.get_current_round(game.id)

      # Simulate a pick
      {:ok, {_pick1, _}} =
        Games.create_pick(round.id, player1.id, %{
          word_id: round.word_id,
          time: 5,
          keywords_shown: 2,
          is_correct: true
        })

      # End the game
      {:ok, _game} = Games.update_game_state(game, "game_over")

      # Player views the game over page (not host)
      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "player1_session_id"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Player should NOT see the new game button
      refute html =~ "Neues Spiel mit denselben Spielern"
      refute html =~ "phx-click=\"start_new_game\""
    end

    test "restart button creates new game and automatically starts it in round 1", %{
      conn: conn,
      player1: player1,
      player2: player2,
      game: game
    } do
      {:ok, game} = Games.start_game(game)
      round = Games.get_current_round(game.id)

      {:ok, {_pick1, _}} =
        Games.create_pick(round.id, player1.id, %{
          word_id: round.word_id,
          time: 5,
          keywords_shown: 2,
          is_correct: true
        })

      {:ok, {_pick2, _}} =
        Games.create_pick(round.id, player2.id, %{
          word_id: round.word_id,
          time: 6,
          keywords_shown: 3,
          is_correct: true
        })

      {:ok, _game} = Games.update_game_state(game, "game_over")

      host_token_key = "host_token_#{game.id}"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "session_id" => "host_session_id",
          host_token_key => game.host_token
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/#{game.id}")

      Mimimi.Presence.track(
        self(),
        "game:#{game.id}:players",
        "player_#{player1.user_id}",
        %{
          user_id: player1.user_id,
          game_id: game.id,
          joined_at: System.system_time(:second)
        }
      )

      Mimimi.Presence.track(
        self(),
        "game:#{game.id}:players",
        "player_#{player2.user_id}",
        %{
          user_id: player2.user_id,
          game_id: game.id,
          joined_at: System.system_time(:second)
        }
      )

      :timer.sleep(100)

      view
      |> element("button", "Neues Spiel mit denselben Spielern")
      |> render_click()

      all_games = Mimimi.Repo.all(Mimimi.Games.Game)
      new_game = Enum.find(all_games, fn g -> g.id != game.id end)

      assert new_game
      assert new_game.rounds_count == game.rounds_count
      assert new_game.clues_interval == game.clues_interval
      assert new_game.grid_size == game.grid_size
      assert new_game.word_types == game.word_types

      new_players = Games.list_players_for_game(new_game.id)
      assert length(new_players) == 2
      assert Enum.any?(new_players, &(&1.avatar == "🦁"))
      assert Enum.any?(new_players, &(&1.avatar == "🐘"))

      assert new_game.state == "game_running"

      new_round = Games.get_current_round(new_game.id)
      assert new_round
      assert new_round.state == "playing"
      assert new_round.position == 1

      assert_redirect(view, ~p"/game/#{new_game.id}/set-host-token")
    end
  end
end
