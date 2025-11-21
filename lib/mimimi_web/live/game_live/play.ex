defmodule MimimiWeb.GameLive.Play do
  @moduledoc """
  The main gameplay LiveView for players.

  Handles:
  - Progressive keyword reveals
  - Word selection and guess submission
  - Real-time feedback on correct/incorrect guesses
  - Round progression and game state updates
  - Points calculation based on keywords shown
  """
  use MimimiWeb, :live_view
  alias Mimimi.Games
  alias Mimimi.Analytics
  import MimimiWeb.GameComponents
  require Logger

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game_with_players(game_id)
    user = socket.assigns.current_user

    # Get player by user ID
    player = Games.get_player_by_game_and_user(game_id, user.id)

    socket =
      cond do
        is_nil(player) ->
          socket
          |> put_flash(:error, "Du bist nicht in diesem Spiel.")
          |> push_navigate(to: ~p"/")

        game.state in ["host_disconnected", "game_over"] ->
          socket
          |> put_flash(:error, "Das Spiel ist nicht mehr aktiv.")
          |> push_navigate(to: ~p"/")

        true ->
          mount_player_game(socket, game, player, game_id, user.id)
      end

    {:ok, socket, temporary_assigns: []}
  end

  defp mount_player_game(socket, game, player, game_id, user_id) do
    socket = maybe_subscribe_to_game(socket, game_id, game.state, user_id)

    # Get initial online status
    online_players = Games.get_players_online_status(game_id)

    socket =
      socket
      |> assign(:game, game)
      |> assign(:player, player)
      |> assign(:pending_players, MapSet.new())
      |> assign(:online_players, online_players)
      |> assign(:page_title, "Spiel")
      |> assign(:rounds_loading, false)
      |> assign(:debug_waiting_since, nil)

    if game.state == "game_running" do
      load_current_round(socket, game_id)
    else
      socket
    end
  end

  defp maybe_subscribe_to_game(socket, game_id, game_state, user_id) do
    if connected?(socket) do
      Games.subscribe_to_game(game_id)
      Games.subscribe_to_active_games()

      if game_state == "waiting_for_players" do
        Phoenix.PubSub.subscribe(Mimimi.PubSub, "player_presence:#{game_id}:#{user_id}")
      end

      # Subscribe to player presence changes to update online status
      Phoenix.PubSub.subscribe(Mimimi.PubSub, "game:#{game_id}:players")

      # Track player presence so host can see when players disconnect
      Mimimi.Presence.track(
        self(),
        "game:#{game_id}:players",
        "player_#{user_id}",
        %{
          user_id: user_id,
          game_id: game_id,
          joined_at: System.system_time(:second)
        }
      )
    end

    socket
  end

  defp load_current_round(socket, game_id) do
    case Games.get_current_round(game_id) do
      nil ->
        # Game is running but rounds haven't been generated yet (async task)
        # Show loading state instead of redirecting
        socket
        |> assign(:current_round, nil)
        |> assign(:rounds_loading, true)

      round ->
        load_round_data(socket, game_id, round)
    end
  end

  # Optimized version that only loads the new round data, not game/player data
  defp load_round_data(socket, game_id, round) do
    possible_word_ids = round.possible_words_ids
    possible_words = fetch_words_with_images(possible_word_ids)

    keyword_ids = round.keyword_ids
    keywords = fetch_keywords(keyword_ids)

    # Ensure GameServer is running if round is playing
    if connected?(socket) && round.state == "playing" do
      game = socket.assigns.game
      Games.start_game_server(game_id, round.id, game.clues_interval)
    end

    # Sync with GameServer if round is already playing
    {initial_keywords_revealed, initial_time_elapsed} =
      get_initial_round_state(game_id, round.state)

    # Calculate which keywords should be shown based on server state
    keywords_shown = min(initial_keywords_revealed, length(keywords))
    revealed_keywords = Enum.take(keywords, keywords_shown)

    # Load leaderboard for current standings
    leaderboard = Games.get_leaderboard(game_id)

    # Initialize keyword reveal timestamps for analytics
    # For keywords already revealed, we estimate timestamps based on clues_interval
    now = DateTime.utc_now()

    keyword_reveal_timestamps =
      if keywords_shown > 0 do
        keyword_ids = round.keyword_ids

        Enum.reduce(1..keywords_shown, [], fn position, acc ->
          keyword_id = Enum.at(keyword_ids, position - 1)
          # Estimate: first keyword at t=0, then every clues_interval seconds
          seconds_ago = initial_time_elapsed - (position - 1) * socket.assigns.game.clues_interval
          revealed_at = DateTime.add(now, -seconds_ago, :second)
          [{keyword_id, position, revealed_at} | acc]
        end)
        |> Enum.reverse()
      else
        []
      end

    socket
    |> assign(:current_round, round)
    |> assign(:possible_words, possible_words)
    |> assign(:keywords, keywords)
    |> assign(:keywords_revealed, keywords_shown)
    |> assign(:revealed_keywords, revealed_keywords)
    |> assign(:time_elapsed, initial_time_elapsed)
    |> assign(:has_picked, false)
    |> assign(:pick_result, nil)
    |> assign(:waiting_for_others, false)
    |> assign(:players_picked, MapSet.new())
    |> assign(:correct_word_info, nil)
    |> assign(:leaderboard, leaderboard)
    |> assign(:all_players_picked, false)
    |> assign(:keyword_reveal_timestamps, keyword_reveal_timestamps)
  end

  defp get_initial_round_state(game_id, round_state) when round_state == "playing" do
    try do
      case Games.get_game_server_state(game_id) do
        {:ok, server_state} ->
          {server_state.keywords_revealed, server_state.elapsed_seconds}

        _ ->
          {0, 0}
      end
    catch
      # GameServer might not be running yet, default to initial state
      :exit, _ -> {0, 0}
    end
  end

  defp get_initial_round_state(_game_id, _round_state), do: {0, 0}

  defp fetch_words_with_images(word_ids) do
    Games.fetch_words_for_display(word_ids)
  end

  defp fetch_keywords(keyword_ids) do
    Games.fetch_keywords_for_display(keyword_ids)
  end

  @impl true
  def terminate(_reason, socket) do
    # Only remove player if game is still in waiting state
    # During gameplay, the player's avatar will automatically show as offline
    # via Presence tracking - the game continues for other players
    if socket.assigns[:game] && socket.assigns.game.state == "waiting_for_players" do
      game_id = socket.assigns.game.id
      user_id = socket.assigns.current_user.id
      Games.remove_player_on_disconnect(game_id, user_id)
    end

    :ok
  end

  @impl true
  def handle_info(:game_count_changed, socket) do
    {:noreply, assign(socket, :active_games, Games.count_active_games())}
  end

  def handle_info(:game_started, socket) do
    # Game has started but rounds are being generated in background
    # Reload the game to get the updated state and show "preparing..." message
    Logger.info(
      "Player #{socket.assigns.player.id}: Received :game_started, setting rounds_loading=true"
    )

    game = Games.get_game_with_players(socket.assigns.game.id)

    # Set a timeout to check if rounds are ready after 10 seconds
    # This is a fallback in case the :round_started broadcast is missed
    Process.send_after(self(), :check_rounds_ready, 10_000)

    socket = assign(socket, :game, game)
    socket = assign(socket, :rounds_loading, true)
    socket = assign(socket, :debug_waiting_since, DateTime.utc_now())
    {:noreply, socket}
  end

  def handle_info(:round_generation_failed, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Fehler beim Vorbereiten der Runden. Bitte versuche es erneut.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(:lobby_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(:game_finished, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboard/#{socket.assigns.game.id}")}
  end

  def handle_info({:pending_player_arrived, user_id}, socket) do
    pending_players = MapSet.put(socket.assigns.pending_players, user_id)
    {:noreply, assign(socket, :pending_players, pending_players)}
  end

  def handle_info({:pending_player_left, user_id}, socket) do
    pending_players = MapSet.delete(socket.assigns.pending_players, user_id)
    {:noreply, assign(socket, :pending_players, pending_players)}
  end

  def handle_info(:player_joined, socket) do
    game = Games.get_game_with_players(socket.assigns.game.id)
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info(:player_left, socket) do
    game = Games.get_game_with_players(socket.assigns.game.id)
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Update online players status when presence changes (someone joins or leaves)
    game_id = socket.assigns.game.id
    online_players = Games.get_players_online_status(game_id)
    {:noreply, assign(socket, :online_players, online_players)}
  end

  def handle_info({:keyword_revealed, revealed_count, time_elapsed}, socket) do
    keywords_shown = min(revealed_count, length(socket.assigns.keywords))
    revealed_keywords = Enum.take(socket.assigns.keywords, keywords_shown)

    # Track timestamp for newly revealed keywords (for analytics)
    current_timestamps = socket.assigns[:keyword_reveal_timestamps] || []
    current_count = length(current_timestamps)

    keyword_reveal_timestamps =
      if keywords_shown > current_count do
        # New keywords were revealed, record their timestamps
        round = socket.assigns.current_round
        now = DateTime.utc_now()

        new_timestamps =
          Enum.map((current_count + 1)..keywords_shown, fn position ->
            keyword_id = Enum.at(round.keyword_ids, position - 1)
            {keyword_id, position, now}
          end)

        current_timestamps ++ new_timestamps
      else
        current_timestamps
      end

    {:noreply,
     socket
     |> assign(:keywords_revealed, keywords_shown)
     |> assign(:time_elapsed, time_elapsed)
     |> assign(:revealed_keywords, revealed_keywords)
     |> assign(:keyword_reveal_timestamps, keyword_reveal_timestamps)}
  end

  def handle_info(:show_feedback_and_advance, socket) do
    game = socket.assigns.game
    round = socket.assigns.current_round

    # Check if this round is still in the "playing" state
    # This prevents double-advancing if multiple messages somehow get through
    current_round_state = Mimimi.Repo.get!(Mimimi.Games.Round, round.id)

    if current_round_state.state == "playing" do
      Games.finish_round(round)

      case Games.advance_to_next_round(game.id) do
        {:ok, next_round} ->
          Games.broadcast_to_game(game.id, :round_started)
          Games.start_game_server(game.id, next_round.id, game.clues_interval)
          {:noreply, load_current_round(socket, game.id)}

        {:error, :no_more_rounds} ->
          Games.update_game_state(game, "game_over")
          Games.broadcast_to_game(game.id, :game_finished)
          Games.stop_game_server(game.id)
          {:noreply, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}
      end
    else
      # Round already finished, just ignore this message
      {:noreply, socket}
    end
  end

  def handle_info({:player_picked, player_id, _is_correct}, socket) do
    players_picked = MapSet.put(socket.assigns.players_picked, player_id)
    all_picked = Games.all_players_picked?(socket.assigns.current_round.id)

    # Reload leaderboard to show updated points
    leaderboard = Games.get_leaderboard(socket.assigns.game.id)

    {:noreply,
     socket
     |> assign(:waiting_for_others, not all_picked)
     |> assign(:players_picked, players_picked)
     |> assign(:leaderboard, leaderboard)}
  end

  def handle_info(:all_players_picked, socket) do
    # Pause the GameServer timer to freeze progress bars
    Mimimi.GameServer.pause_timer(socket.assigns.game.id)

    # Schedule the round advancement after showing feedback
    # Only one :all_players_picked message is sent per round, so this prevents
    # multiple advancement messages from being scheduled
    Process.send_after(self(), :show_feedback_and_advance, 3000)

    {:noreply, assign(socket, :all_players_picked, true)}
  end

  def handle_info(:round_timeout, socket) do
    # Round timeout triggered - all keywords have finished their countdown
    # Advance to next round even if not all players picked
    # This handles the case where one or more players didn't choose a word
    Logger.info("GameLive.Play: Round timeout received for game #{socket.assigns.game.id}")

    # Advance to next round after a brief delay to allow system to settle
    # The show_feedback_and_advance handler checks if round is still playing,
    # so multiple calls (from timeout + all_players_picked) are safe
    Process.send_after(self(), :show_feedback_and_advance, 100)
    {:noreply, socket}
  end

  def handle_info(:round_started, socket) do
    # Rounds are ready, load the first/next round
    Logger.info("Player #{socket.assigns.player.id}: Received :round_started, loading round")

    socket =
      socket
      |> assign(:rounds_loading, false)
      |> assign(:debug_waiting_since, nil)
      |> load_current_round(socket.assigns.game.id)

    {:noreply, socket}
  end

  def handle_info(:check_rounds_ready, socket) do
    # Fallback timeout check - in case :round_started broadcast was missed
    # This checks if rounds are actually ready by querying the database
    if socket.assigns.rounds_loading do
      Logger.info(
        "Player #{socket.assigns.player.id}: Timeout checking if rounds are ready for game #{socket.assigns.game.id}"
      )

      case Games.get_current_round(socket.assigns.game.id) do
        nil ->
          # Still no round available after 10 seconds - something went wrong
          Logger.error(
            "Player #{socket.assigns.player.id}: No rounds available after 10 second timeout for game #{socket.assigns.game.id}"
          )

          {:noreply,
           socket
           |> put_flash(
             :error,
             "Fehler beim Laden der Runden. Bitte lade die Seite neu oder kontaktiere den Support."
           )
           |> assign(:rounds_loading, false)}

        _round ->
          # Round is ready! The broadcast was probably missed
          Logger.warning(
            "Player #{socket.assigns.player.id}: Round was ready but :round_started broadcast was missed for game #{socket.assigns.game.id}"
          )

          socket =
            socket
            |> assign(:rounds_loading, false)
            |> assign(:debug_waiting_since, nil)
            |> load_current_round(socket.assigns.game.id)

          {:noreply, socket}
      end
    else
      # rounds_loading is false, so we already received :round_started - ignore this timeout
      {:noreply, socket}
    end
  end

  def handle_info(:host_disconnected, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Der Spielleiter hat die Verbindung getrennt. Das Spiel wurde beendet.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(:game_stopped_by_host, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Das Spiel wurde vom Spielleiter beendet.")
     |> push_navigate(to: ~p"/dashboard/#{socket.assigns.game.id}")}
  end

  def handle_info({:new_game_started, new_game_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Ein neues Spiel wurde gestartet!")
     |> push_navigate(to: ~p"/games/#{new_game_id}/current")}
  end

  @impl true
  def handle_event("guess_word", %{"word_id" => word_id_str}, socket) do
    word_id = String.to_integer(word_id_str)
    round = socket.assigns.current_round
    player = socket.assigns.player
    game = socket.assigns.game

    is_correct = word_id == round.word_id

    points =
      if is_correct,
        do: Games.calculate_points(socket.assigns.keywords_revealed, length(round.keyword_ids)),
        else: 0

    case Games.create_pick(round.id, player.id, %{
           is_correct: is_correct,
           keywords_shown: socket.assigns.keywords_revealed,
           time: socket.assigns.time_elapsed,
           word_id: word_id
         }) do
      {:ok, {pick, all_picked}} ->
        if is_correct do
          # Reload player to get current points before adding new points
          fresh_player = Mimimi.Repo.get!(Games.Player, player.id)
          Games.add_points(fresh_player, points)
        end

        # Record keyword effectiveness analytics asynchronously
        record_keyword_effectiveness(socket, round, pick.id, is_correct)

        # Broadcast to all players that someone picked
        Games.broadcast_to_game(game.id, {:player_picked, player.id, is_correct})

        # Only broadcast :all_players_picked if this was the LAST pick
        # The all_picked flag is set atomically in the transaction, so only
        # one player will ever see all_picked=true per round
        if all_picked do
          Games.broadcast_to_game(game.id, :all_players_picked)
        end

        # Get the correct word info to show to all players
        correct_word_info = Enum.find(socket.assigns.possible_words, &(&1.id == round.word_id))

        socket =
          socket
          |> assign(:has_picked, true)
          |> assign(:pick_result, if(is_correct, do: :correct, else: :wrong))
          |> assign(:points_earned, points)
          |> assign(:waiting_for_others, not all_picked)
          |> assign(:correct_word_info, correct_word_info)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Fehler beim Speichern der Antwort.")}
    end
  end

  def handle_event("guess_word", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container class="relative">
      <.render_player_avatar_indicator
        player={@player}
        game={@game}
        leaderboard={Map.get(assigns, :leaderboard)}
      />

      <div class="w-full max-w-4xl">
        <%= cond do %>
          <% @game.state == "waiting_for_players" -> %>
            <.render_waiting_for_players
              game={@game}
              player={@player}
              pending_players={@pending_players}
              online_players={@online_players}
            />
          <% Map.get(assigns, :rounds_loading, false) -> %>
            <.render_loading_rounds
              game={@game}
              player={@player}
              debug_waiting_since={Map.get(assigns, :debug_waiting_since)}
            />
          <% Map.has_key?(assigns, :current_round) && @current_round -> %>
            <.render_active_gameplay
              current_round={@current_round}
              game={@game}
              keywords={@keywords}
              keywords_revealed={@keywords_revealed}
              time_elapsed={@time_elapsed}
              has_picked={@has_picked}
              possible_words={@possible_words}
              pick_result={@pick_result}
              waiting_for_others={@waiting_for_others}
              correct_word_info={@correct_word_info}
              players_picked={@players_picked}
              points_earned={Map.get(assigns, :points_earned, 0)}
              all_players_picked={Map.get(assigns, :all_players_picked, false)}
            />
          <% true -> %>
            <.render_no_round_available />
        <% end %>
      </div>
    </.page_container>
    """
  end

  # Renders the fixed player avatar indicator in the top right
  defp render_player_avatar_indicator(assigns) do
    ~H"""
    <div class="fixed top-2 right-2 sm:top-4 sm:right-4 z-50">
      <.glass_card class="p-3 sm:p-4">
        <div class="flex flex-col items-center gap-1">
          <span class="text-4xl sm:text-5xl">{@player.avatar}</span>
          <%= if @game.state == "game_running" && @leaderboard do %>
            <% current_player_data =
              Enum.find(@leaderboard, fn p -> p.id == @player.id end) || @player %>
            <span class="text-xs sm:text-sm font-bold text-purple-600 dark:text-purple-400 tabular-nums">
              {current_player_data.points}
            </span>
          <% end %>
        </div>
      </.glass_card>
    </div>
    """
  end

  # Renders the waiting for players screen
  defp render_waiting_for_players(assigns) do
    ~H"""
    <div class="text-center mb-10">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
        Warte auf Spielstart...
      </h1>
    </div>

    <.glass_card class="p-8">
      <%!-- Player badge --%>
      <div class="text-center mb-8 pb-8 border-b border-gray-200 dark:border-gray-700">
        <.gradient_icon_badge icon={@player.avatar} size="lg" class="w-24 h-24 mb-4 animate-pulse" />
        <p class="text-xl font-semibold text-gray-900 dark:text-white">
          Du bist dabei!
        </p>
      </div>

      <%!-- Other players --%>
      <div>
        <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white text-center">
          Wer spielt mit?
          <%= if MapSet.size(@pending_players) > 0 do %>
            <span class="text-sm font-normal text-purple-600 dark:text-purple-400">
              (+ {MapSet.size(@pending_players)} wählt Avatar...)
            </span>
          <% end %>
        </h2>
        <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-3">
          <%= for player <- @game.players do %>
            <.render_player_grid_item player={player} online_players={@online_players} />
          <% end %>
          <%= for _user_id <- @pending_players do %>
            <.render_pending_player_item />
          <% end %>
        </div>
      </div>
    </.glass_card>
    """
  end

  # Renders a single player in the waiting screen grid
  defp render_player_grid_item(assigns) do
    ~H"""
    <% is_online = MapSet.member?(@online_players, @player.user_id) %>
    <div class={[
      "relative flex flex-col items-center justify-center p-3 border-2 rounded-2xl aspect-square transition-all duration-300 overflow-hidden group",
      if(is_online,
        do:
          "bg-white dark:bg-gray-900 border-gray-200 dark:border-gray-700 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md",
        else: "bg-gray-100 dark:bg-gray-800 border-gray-300 dark:border-gray-600 opacity-60"
      )
    ]}>
      <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
      </div>
      <span class="relative text-6xl">{@player.avatar}</span>
      <%= if !is_online do %>
        <div class="absolute top-1 right-1 bg-red-500 text-white rounded-full w-5 h-5 flex items-center justify-center text-xs font-bold">
          ✕
        </div>
        <span class="absolute bottom-0 left-0 right-0 bg-black/60 text-white text-xs py-1 text-center font-semibold">
          Offline
        </span>
      <% end %>
    </div>
    """
  end

  # Renders a pending player placeholder
  defp render_pending_player_item(assigns) do
    ~H"""
    <div class="relative flex flex-col items-center justify-center p-3 border-2 border-dashed border-purple-400 dark:border-purple-500 rounded-2xl bg-purple-50/50 dark:bg-purple-900/20 backdrop-blur-sm animate-pulse aspect-square">
      <span class="text-6xl mb-1">❓</span>
      <span class="text-xs text-center text-purple-600 dark:text-purple-400 font-medium leading-tight">
        Wählt...
      </span>
    </div>
    """
  end

  # Renders the loading state while rounds are being generated
  defp render_loading_rounds(assigns) do
    ~H"""
    <div class="text-center mb-10">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
        Runden werden vorbereitet...
      </h1>
      <p class="text-gray-500 dark:text-gray-400 text-sm">
        Einen Moment bitte
      </p>
    </div>

    <.glass_card class="p-8">
      <div class="flex flex-col items-center gap-6">
        <.spinner class="h-16 w-16" />

        <%!-- Debug information --%>
        <div class="text-left text-sm text-gray-600 dark:text-gray-400 font-mono bg-gray-100 dark:bg-gray-900 p-4 rounded-xl w-full max-w-md">
          <p class="mb-2"><strong>Debug Info:</strong></p>
          <p>Game ID: {@game.id}</p>
          <p>Game State: {@game.state}</p>
          <p>Player ID: {@player.id}</p>
          <%= if @debug_waiting_since do %>
            <p>
              Waiting since: {Calendar.strftime(@debug_waiting_since, "%H:%M:%S")}
            </p>
          <% end %>
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-500">
            Wenn dieser Bildschirm länger als 10 Sekunden angezeigt wird,
            bitte die Seite neu laden oder den Entwickler kontaktieren.
          </p>
        </div>
      </div>
    </.glass_card>
    """
  end

  # Renders the active gameplay (keywords + word selection or feedback)
  defp render_active_gameplay(assigns) do
    ~H"""
    <div class="text-center mb-8">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
        Runde {@current_round.position} von {@game.rounds_count}
      </h1>
      <p class="text-lg text-gray-600 dark:text-gray-400">
        Welches Wort ist richtig?
      </p>
    </div>

    <%!-- Keywords revealed --%>
    <.render_keywords_section
      keywords={@keywords}
      keywords_revealed={@keywords_revealed}
      time_elapsed={@time_elapsed}
      clues_interval={@game.clues_interval}
      all_players_picked={@all_players_picked}
    />

    <.glass_card class="p-8">
      <%= if @has_picked do %>
        <.render_feedback_state
          pick_result={@pick_result}
          correct_word_info={@correct_word_info}
          points_earned={@points_earned}
          waiting_for_others={@waiting_for_others}
          game={@game}
          players_picked={@players_picked}
        />
      <% else %>
        <.render_word_selection_grid
          possible_words={@possible_words}
          grid_size={@game.grid_size}
          has_picked={@has_picked}
        />
      <% end %>
    </.glass_card>
    """
  end

  # Renders the keywords section with progress indicators
  defp render_keywords_section(assigns) do
    ~H"""
    <.glass_card class="p-8 mb-8">
      <div class="flex flex-wrap justify-center gap-3">
        <%= for {keyword, index} <- Enum.with_index(@keywords, 1) do %>
          <.keyword_badge
            keyword={keyword}
            index={index}
            keywords_revealed={@keywords_revealed}
            time_elapsed={@time_elapsed}
            clues_interval={@clues_interval}
            all_picked?={@all_players_picked}
          />
        <% end %>
      </div>
    </.glass_card>
    """
  end

  # Renders the word selection grid before player has picked
  defp render_word_selection_grid(assigns) do
    ~H"""
    <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
      Bilder zur Auswahl
    </h2>
    <div class={[
      "grid gap-4",
      grid_class(@grid_size)
    ]}>
      <%= for word <- @possible_words do %>
        <button
          phx-click="guess_word"
          phx-value-word_id={word.id}
          disabled={@has_picked}
          class={[
            "relative w-full aspect-square rounded-2xl overflow-hidden",
            "border-2 border-gray-200 dark:border-gray-700",
            "disabled:opacity-50 disabled:cursor-not-allowed",
            "bg-white dark:bg-gray-900"
          ]}
        >
          <%!-- Image --%>
          <%= if word.image_url do %>
            <img src={word.image_url} alt={word.name} class="w-full h-full object-cover" />
          <% else %>
            <div class="w-full h-full flex items-center justify-center bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-800 dark:to-gray-700">
              <span class="text-4xl">🖼️</span>
            </div>
          <% end %>

          <%!-- Label --%>
          <div class="absolute inset-0 flex items-end justify-center pb-2 bg-gradient-to-t from-black/60 to-transparent">
            <p class="text-white font-semibold text-center px-2">
              {word.name}
            </p>
          </div>
        </button>
      <% end %>
    </div>
    """
  end

  # Renders the feedback state after player has picked
  defp render_feedback_state(assigns) do
    ~H"""
    <div class={[
      "py-6 md:py-4",
      if(@correct_word_info,
        do: "md:flex md:items-start md:gap-8 md:justify-center",
        else: "text-center py-12"
      )
    ]}>
      <%!-- Feedback Section --%>
      <div class={[
        "text-center",
        if(@correct_word_info, do: "md:flex-shrink-0", else: "")
      ]}>
        <.gradient_icon_badge
          icon={if @pick_result == :correct, do: "✅", else: "❌"}
          size="lg"
          gradient={
            if @pick_result == :correct,
              do: "from-green-500 to-emerald-500",
              else: "from-red-500 to-orange-500"
          }
          class="w-24 h-24 mb-6"
        />

        <h2 class="text-3xl font-bold mb-2 text-gray-900 dark:text-white">
          {if @pick_result == :correct, do: "Richtig!", else: "Leider falsch"}
        </h2>

        <%= if @pick_result == :correct do %>
          <p class="text-xl text-green-600 dark:text-green-400 font-semibold mb-4">
            +{@points_earned} Punkte!
          </p>
        <% end %>
      </div>

      <%!-- Show correct word to all players --%>
      <%= if @correct_word_info do %>
        <.render_correct_word_display
          correct_word_info={@correct_word_info}
          pick_result={@pick_result}
        />
      <% end %>

      <%= if @waiting_for_others do %>
        <.render_waiting_for_others_section game={@game} players_picked={@players_picked} />
      <% else %>
        <p class="text-gray-600 dark:text-gray-400 mb-6">
          Nächste Runde beginnt...
        </p>
      <% end %>
    </div>
    """
  end

  # Renders the correct word display after picking
  defp render_correct_word_display(assigns) do
    ~H"""
    <div class={[
      "mt-6 md:mt-0 max-w-sm mx-auto md:mx-0",
      "md:max-w-xs"
    ]}>
      <p class={[
        "text-sm mb-3 font-semibold text-center md:text-left",
        if(@pick_result == :correct,
          do: "text-green-600 dark:text-green-400",
          else: "text-gray-600 dark:text-gray-400"
        )
      ]}>
        {if @pick_result == :correct, do: "Du hast richtig getippt:", else: "Richtige Antwort:"}
      </p>
      <div class="relative overflow-hidden rounded-2xl border-2 border-green-500 dark:border-green-400 shadow-lg">
        <%!-- Image --%>
        <%= if @correct_word_info.image_url do %>
          <img
            src={@correct_word_info.image_url}
            alt={@correct_word_info.name}
            class="w-full aspect-square object-cover"
          />
        <% else %>
          <div class="w-full aspect-square flex items-center justify-center bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-800 dark:to-gray-700">
            <span class="text-6xl">🖼️</span>
          </div>
        <% end %>
        <%!-- Label with green gradient --%>
        <div class="absolute inset-0 flex items-end justify-center pb-3 bg-gradient-to-t from-green-900/80 to-transparent">
          <p class="text-white font-bold text-xl px-3 text-center">
            {@correct_word_info.name}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Renders the "waiting for others" section with player avatars
  defp render_waiting_for_others_section(assigns) do
    ~H"""
    <p class="text-gray-600 dark:text-gray-400 mb-6">
      Warte auf andere Spieler...
    </p>

    <div class="max-w-md mx-auto mb-6">
      <div class="grid grid-cols-4 sm:grid-cols-5 gap-3">
        <%= for player <- @game.players do %>
          <% has_picked = MapSet.member?(@players_picked, player.id) %>
          <div class={[
            "relative flex flex-col items-center justify-center p-3 rounded-2xl aspect-square transition-all duration-300",
            if(has_picked,
              do: "bg-green-100 dark:bg-green-900/30 border-2 border-green-500 dark:border-green-400",
              else:
                "bg-gray-100 dark:bg-gray-800 border-2 border-dashed border-gray-300 dark:border-gray-600 animate-pulse"
            )
          ]}>
            <span class={[
              "text-4xl",
              if(has_picked, do: "", else: "opacity-50")
            ]}>
              {player.avatar}
            </span>
            <%= if has_picked do %>
              <div class="absolute -top-1 -right-1 w-6 h-6 rounded-full bg-green-500 shadow-lg flex items-center justify-center">
                <span class="text-white text-xs font-bold">✓</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Renders the fallback "no round available" state
  defp render_no_round_available(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="text-6xl mb-4">⚠️</div>
      <p class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
        Keine Runde verfügbar
      </p>
    </div>
    """
  end

  # Helper to determine grid class based on grid size
  defp grid_class(2), do: "grid-cols-2"
  defp grid_class(4), do: "grid-cols-2"
  defp grid_class(9), do: "grid-cols-3"
  defp grid_class(16), do: "grid-cols-4"
  defp grid_class(_), do: "grid-cols-3"

  # Records keyword effectiveness analytics in a background task
  defp record_keyword_effectiveness(socket, round, pick_id, is_correct) do
    keyword_timestamps = socket.assigns[:keyword_reveal_timestamps] || []

    if length(keyword_timestamps) > 0 do
      picked_at = DateTime.utc_now()

      Task.start(fn ->
        Analytics.record_pick_effectiveness(
          round.id,
          pick_id,
          round.word_id,
          keyword_timestamps,
          picked_at,
          is_correct
        )
      end)
    end
  end
end
