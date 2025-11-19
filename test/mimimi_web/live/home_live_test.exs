defmodule MimimiWeb.HomeLiveTest do
  use MimimiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mimimi.{Accounts, Games}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_session("test_session_id")

    conn =
      conn
      |> Plug.Test.init_test_session(%{"session_id" => "test_session_id"})

    %{conn: conn, user: user}
  end

  describe "Home page" do
    test "displays only create game section when no games are waiting", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Join game section should not be visible when no games are waiting
      refute has_element?(view, "h2", "Spiel beitreten")
      refute has_element?(view, "#join-game-form")

      # Check for create game section
      assert has_element?(view, "h2", "Neues Spiel")
      assert has_element?(view, "#game-setup-form")
    end

    test "displays both join and create game sections when games are waiting for players", %{
      conn: conn,
      user: user
    } do
      # Create a game in waiting_for_players state
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      # Check for join game section (should now be visible)
      assert has_element?(view, "h2", "Spiel beitreten")
      assert has_element?(view, "#join-game-form")

      # Check for create game section
      assert has_element?(view, "h2", "Neues Spiel")
      assert has_element?(view, "#game-setup-form")
    end

    test "allows entering invitation code", %{conn: conn, user: user} do
      # Create a game so join form is visible
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      # Enter a code
      view
      |> form("#join-game-form", invite: %{code: "123456"})
      |> render_change()

      # Check that the code is in the input
      assert has_element?(view, "input[name='invite[code]'][value='123456']")
    end

    test "cleans up non-numeric characters from invitation code", %{conn: conn, user: user} do
      # Create a game so join form is visible
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      # Enter a code with non-numeric characters
      view
      |> form("#join-game-form", invite: %{code: "12-34 56"})
      |> render_change()

      # Check that only digits remain
      assert has_element?(view, "input[name='invite[code]'][value='123456']")
    end

    test "shows error when submitting empty code", %{conn: conn, user: user} do
      # Create a game so join form is visible
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("#join-game-form", invite: %{code: ""})
      |> render_submit()

      # Check for error message
      assert render(view) =~ "Bitte gib einen Einladungscode ein"
    end

    test "shows error when submitting code with wrong length", %{conn: conn, user: user} do
      # Create a game so join form is visible
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("#join-game-form", invite: %{code: "12345"})
      |> render_submit()

      # Check for error message
      assert render(view) =~ "Der Code muss 6 Ziffern haben"
    end

    test "shows error for non-existent invitation code", %{conn: conn, user: user} do
      # Create a game so join form is visible
      {:ok, _game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("#join-game-form", invite: %{code: "999999"})
      |> render_submit()

      # Check for error message
      assert render(view) =~ "Dieser Code existiert nicht."
    end

    test "redirects to avatar selection with valid code", %{conn: conn, user: user} do
      # Create a game with a valid invitation code
      {:ok, game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      short_code = Games.get_short_code_for_game(game.id)

      {:ok, view, _html} = live(conn, "/")

      # Submit the valid code
      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#join-game-form", invite: %{code: short_code})
        |> render_submit()

      # Should redirect to the short code route
      assert path == "/#{short_code}"
    end

    test "shows error for expired invitation code", %{conn: conn, user: user} do
      # Create a game
      {:ok, game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      # Get the invite and manually expire it
      invite = Mimimi.Repo.get_by(Games.GameInvite, game_id: game.id)

      expired_time =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(expires_at: expired_time)
      |> Mimimi.Repo.update!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("#join-game-form", invite: %{code: invite.short_code})
      |> render_submit()

      # Check for error message
      assert render(view) =~ "Dieser Code ist abgelaufen"
    end

    test "shows error when game has already started", %{conn: conn, user: user} do
      # Create a game
      {:ok, game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      short_code = Games.get_short_code_for_game(game.id)

      # Start the game - this changes state to game_running
      Games.update_game_state(game, "game_running")

      # Create another game that is still waiting - so the join form is visible
      {:ok, _waiting_game} =
        Games.create_game(user.id, %{rounds_count: 3, clues_interval: 9, grid_size: 9})

      {:ok, view, _html} = live(conn, "/")

      # Try to join the started game with its code
      view
      |> form("#join-game-form", invite: %{code: short_code})
      |> render_submit()

      # Check for error message
      assert render(view) =~ "Dieses Spiel hat bereits begonnen."
    end

    test "can still create a new game", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Submit the create game form
      {:error, {:redirect, %{to: path}}} =
        view
        |> form("#game-setup-form",
          game: %{rounds_count: "3", clues_interval: "9", grid_size: "9"}
        )
        |> render_submit()

      # Should redirect to set-host-token route
      assert path =~ "/game/"
      assert path =~ "/set-host-token"
    end

    test "displays word type selection checkboxes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Check that all word type options are displayed
      assert has_element?(view, "#word-type-noun")
      assert has_element?(view, "#word-type-verb")
      assert has_element?(view, "#word-type-adjective")
      assert has_element?(view, "#word-type-adverb")
      assert has_element?(view, "#word-type-other")

      # Check that Noun is checked by default
      html = render(view)
      assert html =~ "Nomen"
      assert html =~ "Verb"
      assert html =~ "Adjektiv"
      assert html =~ "Adverb"
      assert html =~ "Andere"
    end

    test "creates game with custom word types", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Submit the create game form with multiple word types
      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#game-setup-form",
          game: %{
            rounds_count: "3",
            clues_interval: "9",
            grid_size: "9",
            word_types: ["Noun", "Verb", "Adjective"]
          }
        )
        |> render_submit()

      # Verify the game was created with the selected word types
      game =
        Games.get_game_by_short_code(
          Games.get_short_code_for_game(List.first(Mimimi.Repo.all(Games.Game)).id)
        )

      assert length(game.word_types) == 3
      assert "Noun" in game.word_types
      assert "Verb" in game.word_types
      assert "Adjective" in game.word_types
    end
  end
end
