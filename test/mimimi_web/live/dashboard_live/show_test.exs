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
      assert html =~ "Warteraum"
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
end
