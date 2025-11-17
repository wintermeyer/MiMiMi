defmodule Mimimi.PresenceMonitorTest do
  use Mimimi.DataCase, async: false

  alias Mimimi.{Accounts, Games, Presence, PresenceMonitor}

  describe "game cleanup on host disconnect" do
    setup do
      {:ok, user} =
        Accounts.get_or_create_user_by_session("test_session_#{System.unique_integer()}")

      {:ok, game} =
        Games.create_game(user.id, %{rounds_count: 1, clues_interval: 3, grid_size: 2})

      %{user: user, game: game}
    end

    test "game can be marked as host_disconnected", %{game: game} do
      # Verify game is in waiting state
      assert game.state == "waiting_for_players"

      # Simulate host disconnect cleanup
      Games.cleanup_game_on_host_disconnect(game.id)

      # Verify game was cleaned up
      game = Games.get_game(game.id)
      assert game.state == "host_disconnected"
    end

    @tag :external_db
    test "running game is stopped when host disconnects", %{user: user, game: game} do
      # Add a player
      {:ok, _player} = Games.create_player(user.id, game.id, %{avatar: "🐻"})

      # Start the game
      {:ok, game} = Games.start_game(game)
      assert game.state == "game_running"

      # Simulate host disconnect
      Games.cleanup_game_on_host_disconnect(game.id)

      # Verify game was cleaned up
      game = Games.get_game(game.id)
      assert game.state == "host_disconnected"
    end

    test "players are notified when host disconnects", %{user: user, game: game} do
      # Add a player
      {:ok, _player} = Games.create_player(user.id, game.id, %{avatar: "🐻"})

      # Subscribe to game updates (simulating a player listening)
      Games.subscribe_to_game(game.id)

      # Simulate host disconnect
      Games.cleanup_game_on_host_disconnect(game.id)

      # Verify broadcast was sent - it's just the atom message
      assert_receive :host_disconnected
    end
  end

  describe "delayed host disconnect detection" do
    test "does not cleanup game when host reconnects within 2 seconds" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_reconnect_test")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Start monitoring
      PresenceMonitor.monitor_game_host(game.id)

      # Track host presence
      Presence.track(
        self(),
        "game:#{game.id}:host",
        "host",
        %{
          user_id: host_user.id,
          game_id: game.id,
          joined_at: System.system_time(:second)
        }
      )

      Process.sleep(100)

      # Verify game is active
      game = Games.get_game(game.id)
      assert game.state == "waiting_for_players"

      # Untrack (simulating temporary disconnect)
      Presence.untrack(self(), "game:#{game.id}:host", "host")

      # Wait a bit, then reconnect BEFORE the 2 second delay expires
      Process.sleep(500)

      Presence.track(
        self(),
        "game:#{game.id}:host",
        "host",
        %{
          user_id: host_user.id,
          game_id: game.id,
          joined_at: System.system_time(:second)
        }
      )

      # Wait for the full delay period plus buffer
      Process.sleep(2500)

      # Game should still be active
      game = Games.get_game(game.id)
      assert game.state == "waiting_for_players"
    end

    test "cleans up game when host stays disconnected for 2+ seconds" do
      {:ok, host_user} = Accounts.get_or_create_user_by_session("host_permanent_disconnect")

      {:ok, game} =
        Games.create_game(host_user.id, %{
          rounds_count: 1,
          clues_interval: 9,
          grid_size: 9,
          word_types: ["Noun"]
        })

      # Start monitoring
      PresenceMonitor.monitor_game_host(game.id)

      # Track host presence
      Presence.track(
        self(),
        "game:#{game.id}:host",
        "host",
        %{
          user_id: host_user.id,
          game_id: game.id,
          joined_at: System.system_time(:second)
        }
      )

      Process.sleep(100)

      # Untrack (simulating permanent disconnect)
      Presence.untrack(self(), "game:#{game.id}:host", "host")

      # Wait for the full delay period plus buffer
      Process.sleep(2500)

      # Game should be marked as disconnected
      game = Games.get_game(game.id)
      assert game.state == "host_disconnected"
    end
  end

  describe "player presence tracking" do
    setup do
      {:ok, user} =
        Accounts.get_or_create_user_by_session("host_session_#{System.unique_integer()}")

      {:ok, game} =
        Games.create_game(user.id, %{rounds_count: 1, clues_interval: 3, grid_size: 2})

      {:ok, player_user} =
        Accounts.get_or_create_user_by_session("player_session_#{System.unique_integer()}")

      {:ok, player} = Games.create_player(player_user.id, game.id, %{avatar: "🐻"})

      %{game: game, player: player, player_user: player_user}
    end

    test "player presence can be tracked", %{game: game, player_user: player_user} do
      # Track player presence
      {:ok, _} =
        Presence.track(
          self(),
          "game:#{game.id}:players",
          "player_#{player_user.id}",
          %{
            user_id: player_user.id,
            game_id: game.id,
            joined_at: System.system_time(:second)
          }
        )

      # Give presence time to sync
      Process.sleep(50)

      # List presence
      presences = Presence.list("game:#{game.id}:players")
      assert Map.has_key?(presences, "player_#{player_user.id}")
    end

    test "player presence is removed on disconnect", %{game: game, player_user: player_user} do
      # Track player presence
      {:ok, _} =
        Presence.track(
          self(),
          "game:#{game.id}:players",
          "player_#{player_user.id}",
          %{
            user_id: player_user.id,
            game_id: game.id,
            joined_at: System.system_time(:second)
          }
        )

      # Verify presence
      Process.sleep(50)
      presences = Presence.list("game:#{game.id}:players")
      assert Map.has_key?(presences, "player_#{player_user.id}")

      # Untrack
      Presence.untrack(self(), "game:#{game.id}:players", "player_#{player_user.id}")

      # Verify presence removed
      Process.sleep(50)
      presences = Presence.list("game:#{game.id}:players")
      refute Map.has_key?(presences, "player_#{player_user.id}")
    end
  end
end
