defmodule Mimimi.GameServer do
  @moduledoc """
  GenServer that manages the game clock for a specific game.

  Responsible for:
  - Running countdown timers for keyword reveals
  - Broadcasting keyword reveal events to all players
  - Auto-advancing rounds after timeout
  - Managing round progression
  """

  use GenServer, restart: :transient
  require Logger
  alias Mimimi.Games

  @doc """
  Starts a GameServer for a specific game.
  """
  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  defp via_tuple(game_id) do
    {:via, Registry, {Mimimi.GameRegistry, game_id}}
  end

  @doc """
  Returns a tuple for sending messages to the game server.
  """
  def game_server_ref(game_id) do
    via_tuple(game_id)
  end

  @doc """
  Starts the round timer for keyword reveals.
  Begins broadcasting keyword reveals at intervals.
  """
  def start_round_timer(game_id, round_id, clues_interval_seconds) do
    GenServer.cast(
      game_server_ref(game_id),
      {:start_round_timer, round_id, clues_interval_seconds}
    )
  end

  @doc """
  Stops the current round timer.
  """
  def stop_round_timer(game_id) do
    GenServer.cast(game_server_ref(game_id), :stop_round_timer)
  end

  @doc """
  Pauses the timer without resetting state.
  Used when all players have picked to freeze the progress bars.
  """
  def pause_timer(game_id) do
    GenServer.cast(game_server_ref(game_id), :pause_timer)
  end

  @doc """
  Gets the current state of the game server.
  """
  def get_state(game_id) do
    GenServer.call(game_server_ref(game_id), :get_state)
  rescue
    _ -> {:error, :not_running}
  end

  # GenServer Callbacks

  def init(game_id) do
    {:ok,
     %{
       game_id: game_id,
       round_id: nil,
       clues_interval: nil,
       elapsed_seconds: 0,
       timer_ref: nil,
       keywords_revealed: 0,
       keywords_total: 0,
       round_state: :idle,
       timeout_scheduled: false,
       timer_paused: false
     }}
  end

  def handle_cast({:start_round_timer, round_id, clues_interval_seconds}, state) do
    # Stop any existing timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Get the round to determine how many keywords it has
    round = Mimimi.Repo.get!(Games.Round, round_id)
    keywords_total = length(round.keyword_ids)

    # Start a new timer that ticks every second, tagged with the round_id
    timer_ref = Process.send_after(self(), {:tick, round_id}, 1000)

    Logger.info(
      "GameServer: Starting round timer for game #{state.game_id}, round #{round_id}, keywords: #{keywords_total}"
    )

    # Immediately reveal the first keyword
    Games.broadcast_to_game(state.game_id, {:keyword_revealed, 1, 0})

    {:noreply,
     %{
       state
       | round_id: round_id,
         clues_interval: clues_interval_seconds,
         elapsed_seconds: 0,
         timer_ref: timer_ref,
         keywords_revealed: 1,
         keywords_total: keywords_total,
         round_state: :playing,
         timeout_scheduled: false,
         timer_paused: false
     }}
  end

  def handle_cast(:stop_round_timer, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    Logger.info("GameServer: Stopped timer for game #{state.game_id}")

    {:noreply,
     %{
       state
       | timer_ref: nil,
         round_state: :idle,
         elapsed_seconds: 0
     }}
  end

  def handle_cast(:pause_timer, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    Logger.info("GameServer: Paused timer for game #{state.game_id} (all players picked)")

    {:noreply,
     %{
       state
       | timer_ref: nil,
         timer_paused: true
     }}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_info({:round_timeout, round_id}, state) do
    # Ignore timeouts from previous rounds
    if round_id != state.round_id do
      Logger.debug(
        "GameServer: Ignoring stale timeout from round #{round_id}, current round is #{state.round_id}"
      )

      {:noreply, state}
    else
      Logger.info("GameServer: Round timeout triggered for game #{state.game_id}")
      # Broadcast the timeout to all players - this will trigger round advancement
      # even if not all players have picked a word
      Games.broadcast_to_game(state.game_id, :round_timeout)

      {:noreply, state}
    end
  end

  def handle_info({:tick, round_id}, state) do
    cond do
      # Ignore ticks from previous rounds (prevents stale ticks from affecting new rounds)
      round_id != state.round_id ->
        Logger.debug(
          "GameServer: Ignoring stale tick from round #{round_id}, current round is #{state.round_id}"
        )

        {:noreply, state}

      # Also ignore ticks if the timer is paused (all players have picked)
      state.timer_paused ->
        Logger.debug("GameServer: Ignoring tick, timer is paused for game #{state.game_id}")
        {:noreply, state}

      # Normal tick processing
      true ->
        process_tick(state, round_id)
    end
  end

  defp process_tick(state, round_id) do
    # Increment elapsed time
    new_elapsed = state.elapsed_seconds + 1

    # Check if it's time to reveal the next keyword
    should_reveal =
      rem(new_elapsed, state.clues_interval) == 0 and
        new_elapsed > 0

    # Always broadcast the current time and keyword count (for progress bar)
    new_revealed =
      if should_reveal, do: state.keywords_revealed + 1, else: state.keywords_revealed

    Games.broadcast_to_game(state.game_id, {:keyword_revealed, new_revealed, new_elapsed})

    if should_reveal do
      Logger.debug("GameServer: Revealed keyword #{new_revealed} for game #{state.game_id}")
    end

    # Check if all keywords have finished their countdown and schedule timeout if needed
    new_state = maybe_schedule_timeout(state, round_id, new_revealed, new_elapsed)

    {:noreply,
     %{
       new_state
       | elapsed_seconds: new_elapsed,
         keywords_revealed: new_revealed,
         timer_ref: Process.send_after(self(), {:tick, round_id}, 1000)
     }}
  end

  defp maybe_schedule_timeout(state, round_id, new_revealed, new_elapsed) do
    # The last keyword finishes at time: keywords_total * clues_interval
    # We only schedule timeout once all keywords are done
    if new_revealed >= state.keywords_total and
         new_elapsed >= state.keywords_total * state.clues_interval and
         not state.timeout_scheduled do
      Logger.info(
        "GameServer: All keywords countdown complete for game #{state.game_id}, scheduling round timeout"
      )

      # Schedule the timeout immediately - all keywords are done
      Process.send_after(self(), {:round_timeout, round_id}, 0)
      %{state | timeout_scheduled: true}
    else
      state
    end
  end

  def terminate(reason, state) do
    Logger.info("GameServer terminating for game #{state.game_id}: #{inspect(reason)}")
    :ok
  end
end
