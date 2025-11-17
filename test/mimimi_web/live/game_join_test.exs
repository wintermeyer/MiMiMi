defmodule MimimiWeb.GameJoinTest do
  use MimimiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mimimi.{Accounts, Games}

  describe "joining game via invitation" do
    test "host creates game and two players join via short code" do
      # Step 1: Create host user
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_join_test")

      # Step 2: Host creates a game
      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Get the short code for the game
      short_code = Games.get_short_code_for_game(game.id)
      assert short_code != nil
      assert String.length(short_code) == 6

      # Step 3: First player visits the invitation link
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session_join_test")

      player1_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player1_session_join_test"})

      # Player 1 goes to the avatar selection page via short code
      {:ok, player1_avatar_view, _html} = live(player1_conn, "/#{short_code}")

      # Verify player 1 is on the avatar selection page
      assert has_element?(player1_avatar_view, "h1", "Wähle dein Tier")

      # Player 1 selects an avatar
      player1_avatar_view
      |> element("button[phx-click='select_avatar'][phx-value-avatar='🐻']")
      |> render_click()

      # Player 1 should be redirected to join game (which will redirect to game play)
      # This happens via the controller action
      player1_conn_after_join =
        player1_conn
        |> get("/game/#{game.id}/join")

      assert redirected_to(player1_conn_after_join) == "/games/#{game.id}/current"

      # Now mount the game play view for player 1
      player1_play_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "session_id" => "player1_session_join_test",
          "active_game_id" => game.id
        })

      {:ok, player1_play_view, player1_html} =
        live(player1_play_conn, "/games/#{game.id}/current")

      # Player 1 should see the waiting screen
      assert player1_html =~ "Warte auf Spielstart"
      assert player1_html =~ "🐻"

      # Step 4: Second player visits the same invitation link
      {:ok, player2_user} = Accounts.get_or_create_user_by_session("player2_session_join_test")

      player2_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player2_session_join_test"})

      # Player 2 goes to the avatar selection page via short code
      {:ok, player2_avatar_view, _html} = live(player2_conn, "/#{short_code}")

      # Verify player 2 is on the avatar selection page
      assert has_element?(player2_avatar_view, "h1", "Wähle dein Tier")

      # Player 2 selects a different avatar
      player2_avatar_view
      |> element("button[phx-click='select_avatar'][phx-value-avatar='🐘']")
      |> render_click()

      # Player 2 should be redirected to join game
      player2_conn_after_join =
        player2_conn
        |> get("/game/#{game.id}/join")

      assert redirected_to(player2_conn_after_join) == "/games/#{game.id}/current"

      # Now mount the game play view for player 2
      player2_play_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "session_id" => "player2_session_join_test",
          "active_game_id" => game.id
        })

      {:ok, _player2_play_view, player2_html} =
        live(player2_play_conn, "/games/#{game.id}/current")

      # Player 2 should see the waiting screen
      assert player2_html =~ "Warte auf Spielstart"
      assert player2_html =~ "🐘"

      # Step 5: Verify both players are in the game
      game_with_players = Games.get_game_with_players(game.id)
      assert length(game_with_players.players) == 2

      player_avatars = Enum.map(game_with_players.players, & &1.avatar) |> Enum.sort()
      assert player_avatars == ["🐘", "🐻"]

      # Verify both players see each other (re-render player 1's view)
      player1_updated_html = render(player1_play_view)
      assert player1_updated_html =~ "🐻"
      assert player1_updated_html =~ "🐘"

      # Verify players are associated with correct users
      player1_record = Enum.find(game_with_players.players, &(&1.avatar == "🐻"))
      player2_record = Enum.find(game_with_players.players, &(&1.avatar == "🐘"))

      assert player1_record.user_id == player1_user.id
      assert player2_record.user_id == player2_user.id
    end

    test "player cannot join with expired short code" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_expired_test")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      short_code = Games.get_short_code_for_game(game.id)

      # Manually expire the invite
      invite = Mimimi.Repo.get_by(Games.GameInvite, short_code: short_code)

      expired_time =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(expires_at: expired_time)
      |> Mimimi.Repo.update!()

      # Try to join with expired code
      {:ok, _player_user} = Accounts.get_or_create_user_by_session("player_session_expired_test")

      player_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player_session_expired_test"})

      # Should redirect with error
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(player_conn, "/#{short_code}")

      assert flash["error"] == "Dieser Link ist abgelaufen."
    end

    test "player cannot join already started game" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_started_test")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      short_code = Games.get_short_code_for_game(game.id)

      # Start the game
      Games.update_game_state(game, "game_running")

      # Try to join
      {:ok, _player_user} = Accounts.get_or_create_user_by_session("player_session_started_test")

      player_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player_session_started_test"})

      # Should redirect with error
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               live(player_conn, "/#{short_code}")

      assert flash["error"] == "Das Spiel hat schon angefangen."
    end

    test "player cannot select already taken avatar" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_session_avatar_test")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      short_code = Games.get_short_code_for_game(game.id)

      # Player 1 joins and takes bear avatar
      {:ok, player1_user} = Accounts.get_or_create_user_by_session("player1_session_avatar_test")
      {:ok, _player1} = Games.create_player(player1_user.id, game.id, %{avatar: "🐻"})

      # Player 2 tries to join
      {:ok, _player2_user} = Accounts.get_or_create_user_by_session("player2_session_avatar_test")

      player2_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_id" => "player2_session_avatar_test"})

      {:ok, player2_avatar_view, html} = live(player2_conn, "/#{short_code}")

      # Bear should be marked as unavailable
      assert html =~ "Besetzt"

      # Verify the button is disabled
      assert has_element?(player2_avatar_view, "button[phx-value-avatar='🐻'][disabled]")
    end
  end
end
