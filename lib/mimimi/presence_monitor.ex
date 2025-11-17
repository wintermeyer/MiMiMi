defmodule Mimimi.PresenceMonitor do
  @moduledoc """
  Monitors host and player presence via Phoenix.Presence.

  When a host disconnects (their browser closes), this monitor
  automatically cleans up the game to prevent zombie games.
  """
  use GenServer
  require Logger
  alias Mimimi.Games

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Subscribes to presence updates for a game's host.
  Call this when a game is created to start monitoring the host.
  """
  def monitor_game_host(game_id) do
    GenServer.cast(__MODULE__, {:monitor_game_host, game_id})
  end

  def init(state) do
    # Start with an empty set of monitored games
    {:ok, Map.put(state, :monitored_games, MapSet.new())}
  end

  def handle_cast({:monitor_game_host, game_id}, state) do
    # Subscribe to host presence changes for this game
    topic = "game:#{game_id}:host"
    Phoenix.PubSub.subscribe(Mimimi.PubSub, topic)

    monitored_games = MapSet.put(state.monitored_games, game_id)
    {:noreply, %{state | monitored_games: monitored_games}}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          topic: "game:" <> rest,
          payload: %{leaves: leaves}
        },
        state
      ) do
    # Extract game_id from topic (format: "game:GAME_ID:host")
    case String.split(rest, ":") do
      [game_id, "host"] when map_size(leaves) > 0 ->
        # Wait a moment to see if the host reconnects (e.g., during LiveView updates)
        # Only cleanup if host is still gone after 2 seconds
        Process.send_after(self(), {:check_host_disconnect, game_id}, 2000)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:check_host_disconnect, game_id}, state) do
    # Check if host presence still exists
    presence = Mimimi.Presence.list("game:#{game_id}:host")

    if map_size(presence) == 0 do
      # Host is truly gone, cleanup the game
      # But only if the game is still in a state where host presence matters
      game = Games.get_game(game_id)

      if game && game.state in ["waiting_for_players", "game_running"] do
        Logger.info("Host disconnected from game #{game_id}, cleaning up...")
        Games.cleanup_game_on_host_disconnect(game_id)

        # Unsubscribe from this game's presence
        Phoenix.PubSub.unsubscribe(Mimimi.PubSub, "game:#{game_id}:host")

        # Remove from monitored games
        monitored_games = MapSet.delete(state.monitored_games, game_id)
        {:noreply, %{state | monitored_games: monitored_games}}
      else
        {:noreply, state}
      end
    else
      # Host is back, no cleanup needed
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
