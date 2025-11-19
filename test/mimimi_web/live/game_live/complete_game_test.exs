defmodule MimimiWeb.GameLive.CompleteGameTest do
  @moduledoc """
  Integration test that simulates a complete game flow from start to finish.
  Tests the entire game lifecycle with two players going through multiple rounds.
  """
  use MimimiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Mimimi.{Accounts, Games, Repo}

  describe "Complete game flow with 2 players" do
    @describetag :external_db
    test "two players complete a full game with 2 rounds" do
      # ========================================
      # SETUP: Create host and two players
      # ========================================
      {:ok, host} = Accounts.get_or_create_user_by_session("host_session")
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session")
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session")

      # ========================================
      # STEP 1: Host creates a game
      # ========================================
      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 2,
          clues_interval: 6,
          grid_size: 9,
          word_types: ["Noun"]
        })

      assert game.state == "waiting_for_players"
      assert game.rounds_count == 2

      # ========================================
      # STEP 2: Player 1 joins the game
      # ========================================
      {:ok, player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})
      assert player1.points == 0

      # ========================================
      # STEP 3: Player 2 joins the game
      # ========================================
      {:ok, player2} = Games.create_player(player2_user.id, game.id, %{avatar: "🐘"})
      assert player2.points == 0

      # Verify both players are in the game
      game = Games.get_game_with_players(game.id)
      assert length(game.players) == 2

      # ========================================
      # STEP 4: Host starts the game
      # ========================================
      {:ok, game} = Games.start_game(game)
      assert game.state == "game_running"

      # Wait for rounds to be generated
      :timer.sleep(500)

      # Verify rounds were created
      rounds =
        Repo.all(
          from r in Mimimi.Games.Round,
            where: r.game_id == ^game.id,
            order_by: [asc: r.position]
        )

      assert length(rounds) == 2

      # ========================================
      # STEP 5: Both players mount their game views
      # ========================================
      player1_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player1_session"})

      player2_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player2_session"})

      {:ok, p1_view, _html} = live(player1_conn, "/games/#{game.id}/current")
      {:ok, p2_view, _html} = live(player2_conn, "/games/#{game.id}/current")

      # ========================================
      # ROUND 1
      # ========================================

      # Get the current round (should be round 1)
      round1 = Games.get_current_round(game.id)
      assert round1 != nil
      assert round1.position == 1
      assert round1.state == "playing"

      # Verify both players can see the round
      p1_html = render(p1_view)
      p2_html = render(p2_view)

      assert p1_html =~ "Runde 1 von 2"
      assert p2_html =~ "Runde 1 von 2"

      # Simulate keyword reveal (GameServer broadcasts this)
      send(p1_view.pid, {:keyword_revealed, 1, 6})
      send(p2_view.pid, {:keyword_revealed, 1, 6})

      # Wait for LiveView to process the message
      :timer.sleep(50)

      # Verify players can see keywords
      p1_html = render(p1_view)
      assert p1_html =~ "Bilder zur Auswahl"

      # ========================================
      # STEP 6: Player 1 picks the CORRECT word (after 1 keyword = 5 points)
      # ========================================
      correct_word_id = round1.word_id

      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      # Wait for pick to be saved
      :timer.sleep(100)

      # Verify player 1 sees success feedback
      p1_html = render(p1_view)
      assert p1_html =~ "Richtig!"
      assert p1_html =~ "+5 Punkte!"
      assert p1_html =~ "Warte auf andere Spieler..."

      # ========================================
      # STEP 7: Player 2 picks a WRONG word (gets 0 points)
      # ========================================
      wrong_word_id = Enum.find(round1.possible_words_ids, &(&1 != correct_word_id))

      p2_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{wrong_word_id}']")
      |> render_click()

      # Wait for all_players_picked event and show_feedback_and_advance (3s delay)
      :timer.sleep(100)

      # Verify player 2 sees wrong feedback
      p2_html = render(p2_view)
      assert p2_html =~ "Leider falsch"
      assert p2_html =~ "Richtige Antwort"

      # Verify both players should see the correct word
      correct_word = Mimimi.WortSchule.get_word(correct_word_id)
      assert p1_html =~ correct_word.name
      assert p2_html =~ correct_word.name

      # ========================================
      # STEP 8: Wait for round advancement (3 second feedback delay)
      # ========================================
      :timer.sleep(3500)

      # Verify round 1 is finished
      round1_updated = Repo.get!(Mimimi.Games.Round, round1.id)
      assert round1_updated.state == "finished"

      # Verify points were awarded correctly
      player1_updated = Repo.get!(Games.Player, player1.id)
      player2_updated = Repo.get!(Games.Player, player2.id)

      assert player1_updated.points == 5, "Player 1 should have 5 points (1 keyword revealed)"
      assert player2_updated.points == 0, "Player 2 should have 0 points (wrong answer)"

      # ========================================
      # ROUND 2
      # ========================================

      # Get the new current round (should be round 2)
      round2 = Games.get_current_round(game.id)
      assert round2 != nil
      assert round2.position == 2
      assert round2.state == "playing"

      # Verify both players advanced to round 2
      :timer.sleep(100)
      p1_html = render(p1_view)
      p2_html = render(p2_view)

      assert p1_html =~ "Runde 2 von 2"
      assert p2_html =~ "Runde 2 von 2"

      # Simulate keyword reveal for round 2 (2 keywords = 3 points)
      send(p1_view.pid, {:keyword_revealed, 2, 12})
      send(p2_view.pid, {:keyword_revealed, 2, 12})

      :timer.sleep(50)

      # ========================================
      # STEP 9: Both players pick CORRECT word in round 2
      # ========================================
      correct_word_id_r2 = round2.word_id

      # Player 1 picks first
      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id_r2}']")
      |> render_click()

      :timer.sleep(100)

      # Player 2 picks second
      p2_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id_r2}']")
      |> render_click()

      :timer.sleep(100)

      # Verify both see success
      p1_html = render(p1_view)
      p2_html = render(p2_view)

      assert p1_html =~ "Richtig!"
      assert p1_html =~ "+3 Punkte!"
      assert p2_html =~ "Richtig!"
      assert p2_html =~ "+3 Punkte!"

      # ========================================
      # STEP 10: Wait for game to finish (no more rounds)
      # ========================================
      :timer.sleep(3500)

      # Verify round 2 is finished
      round2_updated = Repo.get!(Mimimi.Games.Round, round2.id)
      assert round2_updated.state == "finished"

      # Verify game is over
      game_updated = Repo.get!(Games.Game, game.id)
      assert game_updated.state == "game_over"

      # ========================================
      # STEP 11: Verify final points
      # ========================================
      player1_final = Repo.get!(Games.Player, player1.id)
      player2_final = Repo.get!(Games.Player, player2.id)

      assert player1_final.points == 8, "Player 1: 5 (round 1) + 3 (round 2) = 8 points"
      assert player2_final.points == 3, "Player 2: 0 (round 1) + 3 (round 2) = 3 points"

      # ========================================
      # STEP 12: Verify leaderboard
      # ========================================
      leaderboard = Games.get_leaderboard(game.id)
      assert length(leaderboard) == 2

      # Player 1 should be first (more points)
      assert hd(leaderboard).id == player1.id
      assert hd(leaderboard).points == 8

      # Player 2 should be second
      assert Enum.at(leaderboard, 1).id == player2.id
      assert Enum.at(leaderboard, 1).points == 3

      # ========================================
      # STEP 13: Verify players are redirected to dashboard
      # ========================================
      assert_redirect(p1_view, "/dashboard/#{game.id}")
      assert_redirect(p2_view, "/dashboard/#{game.id}")

      # ========================================
      # STEP 14: Verify dashboard shows final results
      # ========================================
      {:ok, _dashboard_view, dashboard_html} =
        live(player1_conn, "/dashboard/#{game.id}")

      assert dashboard_html =~ "Spiel fertig!"
      # Should show winner (Player 1 with 8 points)
      assert dashboard_html =~ player1.avatar
      assert dashboard_html =~ "8"
    end

    test "three players complete game with different pick speeds" do
      # ========================================
      # SETUP
      # ========================================
      {:ok, host} = Accounts.get_or_create_user_by_session("host_3player")
      {:ok, p1_user} = Accounts.get_or_create_user_by_session("p1_3player")
      {:ok, p2_user} = Accounts.get_or_create_user_by_session("p2_3player")
      {:ok, p3_user} = Accounts.get_or_create_user_by_session("p3_3player")

      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 1,
          clues_interval: 6,
          grid_size: 9,
          word_types: ["Noun"]
        })

      {:ok, player1} = Games.create_player(p1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(p2_user.id, game.id, %{avatar: "🐘"})
      {:ok, player3} = Games.create_player(p3_user.id, game.id, %{avatar: "🦉"})

      # Start game
      {:ok, game} = Games.start_game(game)
      :timer.sleep(500)

      # Mount views
      p1_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p1_3player"})
      p2_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p2_3player"})
      p3_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p3_3player"})

      {:ok, p1_view, _} = live(p1_conn, "/games/#{game.id}/current")
      {:ok, p2_view, _} = live(p2_conn, "/games/#{game.id}/current")
      {:ok, p3_view, _} = live(p3_conn, "/games/#{game.id}/current")

      round = Games.get_current_round(game.id)
      correct_word_id = round.word_id

      # Simulate keywords revealed
      send(p1_view.pid, {:keyword_revealed, 1, 6})
      send(p2_view.pid, {:keyword_revealed, 1, 6})
      send(p3_view.pid, {:keyword_revealed, 1, 6})
      :timer.sleep(50)

      # ========================================
      # Player 1 picks immediately (1 keyword = 5 points)
      # ========================================
      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Player 1 should see "waiting for others"
      p1_html = render(p1_view)
      assert p1_html =~ "Warte auf andere Spieler"

      # ========================================
      # Player 2 picks second (1 keyword = 5 points)
      # ========================================
      p2_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Both should still be waiting
      p2_html = render(p2_view)
      assert p2_html =~ "Warte auf andere Spieler"

      # ========================================
      # Player 3 picks last (1 keyword = 5 points)
      # ========================================
      p3_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Now all have picked - should see "next round begins"
      p3_html = render(p3_view)
      assert p3_html =~ "Richtig!" or p3_html =~ "Nächste Runde beginnt"

      # Wait for game to end
      :timer.sleep(3500)

      # Verify all players got the same points (all picked at 1 keyword)
      player1_final = Repo.get!(Games.Player, player1.id)
      player2_final = Repo.get!(Games.Player, player2.id)
      player3_final = Repo.get!(Games.Player, player3.id)

      assert player1_final.points == 5
      assert player2_final.points == 5
      assert player3_final.points == 5

      # Game should be over
      game_updated = Repo.get!(Games.Game, game.id)
      assert game_updated.state == "game_over"
    end

    test "game handles one player picking wrong and one correct" do
      {:ok, host} = Accounts.get_or_create_user_by_session("host_mixed")
      {:ok, p1_user} = Accounts.get_or_create_user_by_session("p1_mixed")
      {:ok, p2_user} = Accounts.get_or_create_user_by_session("p2_mixed")

      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 1,
          clues_interval: 6,
          grid_size: 9,
          word_types: ["Noun"]
        })

      {:ok, player1} = Games.create_player(p1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(p2_user.id, game.id, %{avatar: "🐘"})

      {:ok, game} = Games.start_game(game)
      :timer.sleep(500)

      p1_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p1_mixed"})
      p2_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p2_mixed"})

      {:ok, p1_view, _} = live(p1_conn, "/games/#{game.id}/current")
      {:ok, p2_view, _} = live(p2_conn, "/games/#{game.id}/current")

      round = Games.get_current_round(game.id)
      correct_word_id = round.word_id
      wrong_word_id = Enum.find(round.possible_words_ids, &(&1 != correct_word_id))

      # Reveal first keyword
      send(p1_view.pid, {:keyword_revealed, 1, 6})
      send(p2_view.pid, {:keyword_revealed, 1, 6})
      :timer.sleep(50)

      # Player 1 picks WRONG
      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{wrong_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Player 2 picks CORRECT
      p2_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Verify feedback
      p1_html = render(p1_view)
      p2_html = render(p2_view)

      assert p1_html =~ "Leider falsch"
      assert p2_html =~ "Richtig!"
      assert p2_html =~ "+5 Punkte!"

      # Both should see the correct word
      correct_word = Mimimi.WortSchule.get_word(correct_word_id)
      assert p1_html =~ correct_word.name
      assert p2_html =~ correct_word.name

      # Wait for game end
      :timer.sleep(3500)

      # Verify final scores
      player1_final = Repo.get!(Games.Player, player1.id)
      player2_final = Repo.get!(Games.Player, player2.id)

      assert player1_final.points == 0, "Player 1 picked wrong, should have 0 points"

      assert player2_final.points == 5,
             "Player 2 picked correct with 1 keyword, should have 5 points"

      # Verify leaderboard order
      leaderboard = Games.get_leaderboard(game.id)
      assert hd(leaderboard).id == player2.id
      assert hd(leaderboard).points == 5
    end

    test "2-player game advances to next round when one player doesn't pick before timeout" do
      # ========================================
      # SETUP
      # ========================================
      {:ok, host} = Accounts.get_or_create_user_by_session("host_no_pick")
      {:ok, p1_user} = Accounts.get_or_create_user_by_session("p1_no_pick")
      {:ok, p2_user} = Accounts.get_or_create_user_by_session("p2_no_pick")

      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 2,
          clues_interval: 6,
          grid_size: 9,
          word_types: ["Noun"]
        })

      {:ok, player1} = Games.create_player(p1_user.id, game.id, %{avatar: "🐻"})
      {:ok, player2} = Games.create_player(p2_user.id, game.id, %{avatar: "🐘"})

      {:ok, game} = Games.start_game(game)
      :timer.sleep(500)

      p1_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p1_no_pick"})
      p2_conn = build_conn() |> Plug.Test.init_test_session(%{"session_id" => "p2_no_pick"})

      {:ok, p1_view, _} = live(p1_conn, "/games/#{game.id}/current")
      {:ok, p2_view, _} = live(p2_conn, "/games/#{game.id}/current")

      # ========================================
      # ROUND 1: Player 1 picks, Player 2 doesn't
      # ========================================
      round1 = Games.get_current_round(game.id)
      assert round1.position == 1

      correct_word_id = round1.word_id

      # Reveal first keyword
      send(p1_view.pid, {:keyword_revealed, 1, 6})
      send(p2_view.pid, {:keyword_revealed, 1, 6})
      :timer.sleep(50)

      # Player 1 picks CORRECT
      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id}']")
      |> render_click()

      :timer.sleep(100)

      # Player 1 should see "waiting for others" since player 2 hasn't picked
      p1_html = render(p1_view)
      assert p1_html =~ "Warte auf andere Spieler"

      # Player 2 does NOT pick - simulate round timeout
      # Send round_timeout to both players (this would come from GameServer)
      send(p1_view.pid, :round_timeout)
      send(p2_view.pid, :round_timeout)

      # Wait for advancement delay
      :timer.sleep(150)

      # Verify round 1 is finished
      round1_updated = Repo.get!(Mimimi.Games.Round, round1.id)
      assert round1_updated.state == "finished"

      # Verify player 1 got points, player 2 got 0
      player1_updated = Repo.get!(Games.Player, player1.id)
      player2_updated = Repo.get!(Games.Player, player2.id)

      assert player1_updated.points == 5, "Player 1 should have 5 points"
      assert player2_updated.points == 0, "Player 2 should have 0 points (didn't pick)"

      # ========================================
      # Verify we advanced to ROUND 2, NOT repeated ROUND 1
      # ========================================
      :timer.sleep(500)

      round2 = Games.get_current_round(game.id)
      assert round2 != nil, "Round 2 should exist"
      assert round2.position == 2, "Should be round 2, not repeated round 1"
      assert round2.state == "playing"
      assert round2.id != round1.id, "Should be a different round"

      # Verify both players are now on round 2
      p1_html = render(p1_view)
      p2_html = render(p2_view)

      assert p1_html =~ "Runde 2 von 2"
      assert p2_html =~ "Runde 2 von 2"

      # ========================================
      # ROUND 2: Complete normally to verify game continues
      # ========================================
      correct_word_id_r2 = round2.word_id

      # Reveal second keyword (at 12 seconds total = 2 keywords shown = 3 points)
      send(p1_view.pid, {:keyword_revealed, 2, 12})
      send(p2_view.pid, {:keyword_revealed, 2, 12})
      :timer.sleep(50)

      # Both players pick correctly
      p1_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id_r2}']")
      |> render_click()

      :timer.sleep(100)

      p2_view
      |> element("button[phx-click='guess_word'][phx-value-word_id='#{correct_word_id_r2}']")
      |> render_click()

      :timer.sleep(3500)

      # Verify game is over
      game_updated = Repo.get!(Games.Game, game.id)
      assert game_updated.state == "game_over"

      # Verify final scores
      player1_final = Repo.get!(Games.Player, player1.id)
      player2_final = Repo.get!(Games.Player, player2.id)

      assert player1_final.points == 8, "Player 1: 5 (round 1) + 3 (round 2) = 8 points"
      assert player2_final.points == 3, "Player 2: 0 (round 1) + 3 (round 2) = 3 points"
    end
  end
end
