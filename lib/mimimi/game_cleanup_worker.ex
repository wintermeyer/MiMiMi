defmodule Mimimi.GameCleanupWorker do
  @moduledoc """
  A GenServer worker that periodically cleans up timed-out game lobbies.

  Runs every 5 minutes to check for lobbies in "waiting_for_players" state
  that have exceeded the 15-minute timeout threshold.
  """
  use GenServer
  require Logger
  alias Mimimi.Games

  @cleanup_interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_timed_out_lobbies()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_timed_out_lobbies do
    import Ecto.Query
    alias Mimimi.Repo
    alias Mimimi.Games.Game

    timeout_seconds = 15 * 60
    timeout_threshold = DateTime.add(DateTime.utc_now(), -timeout_seconds, :second)

    timed_out_games =
      from(g in Game,
        where: g.state == "waiting_for_players" and g.inserted_at <= ^timeout_threshold
      )
      |> Repo.all()

    Enum.each(timed_out_games, fn game ->
      Logger.info("Timing out lobby for game #{game.id}")
      Games.timeout_lobby(game)
    end)

    if length(timed_out_games) > 0 do
      Logger.info("Cleaned up #{length(timed_out_games)} timed-out lobbies")
    end
  end
end
