defmodule MimimiWeb.GameLive.PlayTest do
  use MimimiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Mimimi.{Accounts, Games}

  setup %{conn: conn} do
    # Create host user
    {:ok, host} = Accounts.get_or_create_user_by_session("host_session")

    # Create player user
    {:ok, player} = Accounts.get_or_create_user_by_session("player_session")

    # Create a game
    {:ok, game} =
      Games.create_game(host.id, %{
        rounds_count: 1,
        clues_interval: 9,
        grid_size: 9,
        word_types: ["Noun"]
      })

    # Add player to the game
    {:ok, player_record} = Games.create_player(player.id, game.id, %{avatar: "👤"})

    # Set up player connection with session
    player_conn =
      conn
      |> Plug.Test.init_test_session(%{"session_id" => "player_session"})

    %{
      conn: conn,
      host: host,
      player: player,
      player_conn: player_conn,
      game: game,
      player_record: player_record
    }
  end

  describe "Game play page - invalid game states" do
    test "redirects player when game is in host_disconnected state", %{
      player_conn: player_conn,
      game: game
    } do
      # Update game state to host_disconnected
      Games.update_game_state(game, "host_disconnected")

      # Try to mount the play view - should redirect
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(player_conn, "/games/#{game.id}/current")

      assert flash["error"] == "Das Spiel ist nicht mehr aktiv."
    end

    test "redirects player when game is in game_over state", %{
      player_conn: player_conn,
      game: game
    } do
      # Update game state to game_over
      Games.update_game_state(game, "game_over")

      # Try to mount the play view - should redirect
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(player_conn, "/games/#{game.id}/current")

      assert flash["error"] == "Das Spiel ist nicht mehr aktiv."
    end
  end

  describe "Game play page - first round keyword display" do
    @tag :skip
    test "displays first keyword after round timer starts", %{
      player_conn: player_conn,
      game: game
    } do
      # Start the game to transition to game_running state
      Games.start_game(game)

      # Mount the play view as a player
      {:ok, view, _html} = live(player_conn, "/games/#{game.id}/current")

      # Simulate the countdown and round start
      # This is what happens when the host starts the game
      send(view.pid, {:round_countdown, 3})
      send(view.pid, {:round_countdown, 2})
      send(view.pid, {:round_countdown, 1})
      send(view.pid, :start_round_timer)

      # Give the view a moment to process
      :timer.sleep(100)

      # Simulate the first keyword being revealed (this is what GameServer does)
      send(view.pid, {:keyword_revealed, 1, 0})

      # Give the view a moment to process
      :timer.sleep(100)

      # Re-render to ensure we have the latest state
      html = render(view)

      # Verify that at least one keyword should be revealed
      # Look for revealed keyword badges (purple gradient background)
      assert html =~ "bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-lg"
    end

    @tag :skip
    test "countdown works and displays numbers 3, 2, 1", %{
      player_conn: player_conn,
      game: game
    } do
      # Start the game
      Games.start_game(game)

      {:ok, view, _html} = live(player_conn, "/games/#{game.id}/current")

      # Simulate countdown messages (this is what the host's dashboard broadcasts)
      send(view.pid, {:round_countdown, 3})
      :timer.sleep(50)
      html_3 = render(view)
      assert html_3 =~ "Runde 1 startet in"
      assert html_3 =~ "3"

      send(view.pid, {:round_countdown, 2})
      :timer.sleep(50)
      html_2 = render(view)
      assert html_2 =~ "Runde 1 startet in"
      assert html_2 =~ "2"

      send(view.pid, {:round_countdown, 1})
      :timer.sleep(50)
      html_1 = render(view)
      assert html_1 =~ "Runde 1 startet in"
      assert html_1 =~ "1"

      # After countdown, the timer should start
      send(view.pid, :start_round_timer)
      :timer.sleep(50)
      html_start = render(view)

      # Countdown should be gone
      refute html_start =~ "startet in"
    end
  end

  describe "Game play page - multi-round progression" do
    @tag :external_db
    test "3-round game plays all 3 rounds with multiple players", %{
      host: host
    } do
      # Create a new game with 3 rounds
      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 3,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Create two players
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session")

      {:ok, _player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})
      {:ok, _player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})

      # Start the game to generate rounds
      {:ok, game} = Games.start_game(game)

      # Verify 3 rounds were created
      rounds =
        Mimimi.Repo.all(
          from r in Mimimi.Games.Round,
            where: r.game_id == ^game.id,
            order_by: [asc: r.position]
        )

      assert length(rounds) == 3
      assert Enum.map(rounds, & &1.position) == [1, 2, 3]

      # Mount play views for both players
      player1_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player1_session"})

      player2_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player2_session"})

      {:ok, view1, _html} = live(player1_conn, "/games/#{game.id}/current")
      {:ok, view2, _html} = live(player2_conn, "/games/#{game.id}/current")

      # Get the current round
      round1 = Games.get_current_round(game.id)
      assert round1.position == 1

      # Simulate both players making picks in round 1
      # Send keyword_revealed first so they can pick
      send(view1.pid, {:keyword_revealed, 1, 5})
      send(view2.pid, {:keyword_revealed, 1, 5})

      # Both players pick a word
      possible_word_id = hd(round1.possible_words_ids)

      view1
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{possible_word_id}']")
      |> render_click()

      view2
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{possible_word_id}']")
      |> render_click()

      # Wait for the show_feedback_and_advance messages to be processed (3 seconds + buffer)
      :timer.sleep(3500)

      # Check what round we're on now - should be round 2
      round2 = Games.get_current_round(game.id)
      assert round2.position == 2, "Expected to be on round 2, but got round #{round2.position}"

      # Verify round 1 is finished
      round1_updated = Mimimi.Repo.get!(Mimimi.Games.Round, round1.id)
      assert round1_updated.state == "finished"

      # Continue with round 2
      send(view1.pid, {:keyword_revealed, 1, 5})
      send(view2.pid, {:keyword_revealed, 1, 5})

      possible_word_id2 = hd(round2.possible_words_ids)

      view1
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{possible_word_id2}']")
      |> render_click()

      view2
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{possible_word_id2}']")
      |> render_click()

      # Wait for the show_feedback_and_advance messages
      :timer.sleep(3500)

      # Check what round we're on now - should be round 3
      round3 = Games.get_current_round(game.id)
      assert round3.position == 3, "Expected to be on round 3, but got round #{round3.position}"

      # Verify round 2 is finished
      round2_updated = Mimimi.Repo.get!(Mimimi.Games.Round, round2.id)
      assert round2_updated.state == "finished"
    end

    @tag :external_db
    test "points accumulate correctly across multiple rounds", %{host: host} do
      # Create a game with 2 rounds
      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 2,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Create two players
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_points_test")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_points_test")

      {:ok, player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})

      # Verify initial points are 0
      assert player1.points == 0
      assert player2.points == 0

      # Start the game
      {:ok, game} = Games.start_game(game)

      # Get round 1
      round1 = Games.get_current_round(game.id)
      assert round1.position == 1

      # Player 1 guesses correctly with 1 keyword (5 points)
      # Player 2 guesses correctly with 2 keywords (3 points)
      {:ok, {_pick1, _}} =
        Games.create_pick(round1.id, player1.id, %{
          is_correct: true,
          keywords_shown: 1,
          time: 5,
          word_id: round1.word_id
        })

      Games.add_points(player1, 5)

      {:ok, {_pick2, _}} =
        Games.create_pick(round1.id, player2.id, %{
          is_correct: true,
          keywords_shown: 2,
          time: 10,
          word_id: round1.word_id
        })

      Games.add_points(player2, 3)

      # Verify points after round 1
      player1 = Mimimi.Repo.get!(Games.Player, player1.id)
      player2 = Mimimi.Repo.get!(Games.Player, player2.id)

      assert player1.points == 5
      assert player2.points == 3

      # Finish round 1 and advance to round 2
      Games.finish_round(round1)
      {:ok, round2} = Games.advance_to_next_round(game.id)
      assert round2.position == 2

      # Player 1 guesses correctly with 3 keywords (1 point)
      # Player 2 guesses correctly with 1 keyword (5 points)
      {:ok, {_pick3, _}} =
        Games.create_pick(round2.id, player1.id, %{
          is_correct: true,
          keywords_shown: 3,
          time: 15,
          word_id: round2.word_id
        })

      Games.add_points(player1, 1)

      {:ok, {_pick4, _}} =
        Games.create_pick(round2.id, player2.id, %{
          is_correct: true,
          keywords_shown: 1,
          time: 8,
          word_id: round2.word_id
        })

      Games.add_points(player2, 5)

      # Verify points accumulate correctly
      player1 = Mimimi.Repo.get!(Games.Player, player1.id)
      player2 = Mimimi.Repo.get!(Games.Player, player2.id)

      assert player1.points == 6, "Player 1 should have 5 + 1 = 6 points"
      assert player2.points == 8, "Player 2 should have 3 + 5 = 8 points"

      # Verify leaderboard shows correct order
      leaderboard = Games.get_leaderboard(game.id)
      assert length(leaderboard) == 2
      assert hd(leaderboard).id == player2.id
      assert hd(leaderboard).points == 8
      assert Enum.at(leaderboard, 1).id == player1.id
      assert Enum.at(leaderboard, 1).points == 6
    end
  end
end
