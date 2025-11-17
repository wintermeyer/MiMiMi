defmodule MimimiWeb.DashboardLiveTest do
  use MimimiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Mimimi.{Games, Accounts}

  describe "Dashboard - Player Join Updates" do
    setup do
      # Create host user
      {:ok, host} = Accounts.get_or_create_user_by_session("host_session")

      # Create a game with minimal rounds to avoid test database constraints
      {:ok, game} =
        Games.create_game(host.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9
        })

      %{host: host, game: game}
    end

    test "dashboard updates when player joins", %{conn: conn, game: game} do
      # Set up host session with proper token
      conn =
        conn
        |> init_test_session(%{"user_session_id" => "host_session"})
        |> put_session("host_token_#{game.id}", game.host_token)

      # Mount the dashboard as the host
      {:ok, view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Initially, no players should be shown
      assert html =~ "Mitspieler (0)"
      assert html =~ "Warte auf Spieler..."

      # Button should be disabled
      assert html =~ "disabled"

      # Now simulate a player joining by creating a player in another process
      # This mimics what happens when a player selects an avatar
      {:ok, player_user} = Accounts.get_or_create_user_by_session("player_session")

      {:ok, _player} =
        Games.create_player(player_user.id, game.id, %{avatar: "🐻", nickname: "🐻"})

      # Broadcast the player_joined event (this is what avatar selection does)
      Games.broadcast_to_game(game.id, :player_joined)

      # Give LiveView a moment to process the broadcast
      :timer.sleep(100)

      # Re-render the view to get updated HTML
      html = render(view)

      # Now the dashboard should show 1 player
      assert html =~ "Mitspieler (1)"
      refute html =~ "Warte auf Spieler..."
      assert html =~ "🐻"

      # Button should no longer be disabled
      refute html =~ ~r/disabled.*Jetzt spielen!/
    end

    test "dashboard shows pending players choosing avatars", %{conn: conn, game: game} do
      # Set up host session
      conn =
        conn
        |> init_test_session(%{"user_session_id" => "host_session"})
        |> put_session("host_token_#{game.id}", game.host_token)

      # Mount the dashboard
      {:ok, view, html} = live(conn, ~p"/dashboard/#{game.id}")

      # Initially no pending players
      assert html =~ "Mitspieler (0)"

      # Simulate someone arriving at avatar selection
      {:ok, player_user} = Accounts.get_or_create_user_by_session("player_session")
      Games.broadcast_to_game(game.id, {:pending_player_arrived, player_user.id})

      :timer.sleep(100)
      html = render(view)

      # Should show pending player
      assert html =~ "wählt Avatar..."
      assert html =~ "❓"

      # Now they select an avatar
      {:ok, _player} =
        Games.create_player(player_user.id, game.id, %{avatar: "🐻", nickname: "🐻"})

      Games.broadcast_to_game(game.id, {:pending_player_left, player_user.id})
      Games.broadcast_to_game(game.id, :player_joined)

      :timer.sleep(100)
      html = render(view)

      # Pending indicator should be gone, real player should show
      refute html =~ "wählt Avatar..."
      assert html =~ "🐻"
      assert html =~ "Mitspieler (1)"
    end

    test "players receive game_started event and see the round", %{game: game} do
      # Create a player user and add them to the game
      {:ok, player_user} = Accounts.get_or_create_user_by_session("player_session")

      {:ok, _player} =
        Games.create_player(player_user.id, game.id, %{avatar: "🐻", nickname: "🐻"})

      # Set up player session with the correct session_id
      player_conn =
        build_conn()
        |> init_test_session(%{"session_id" => "player_session"})

      # Mount the game as the player (should show waiting screen)
      {:ok, player_view, html} = live(player_conn, ~p"/games/#{game.id}/current")

      # Should show waiting for game start
      assert html =~ "Warte auf Spielstart..."
      assert html =~ "Du bist dabei!"

      # Now start the game (this is what the host does)
      {:ok, _game} = Games.start_game(game)
      Games.broadcast_to_game(game.id, :game_started)

      # Give LiveView a moment to process the broadcast
      :timer.sleep(100)

      # Re-render the player view
      html = render(player_view)

      # Player should now see the round has started
      refute html =~ "Warte auf Spielstart..."
      assert html =~ "Runde 1 von"
      assert html =~ "Welches Wort ist richtig?"
    end
  end
end
