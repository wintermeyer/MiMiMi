defmodule MimimiWeb.DashboardLive.Show do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"id" => game_id}, session, socket) do
    game = Games.get_game_with_players(game_id)
    user = socket.assigns.current_user

    host_token_key = "host_token_#{game_id}"
    stored_token = Map.get(session, host_token_key)
    is_host = stored_token == game.host_token

    # Check if user is a player in this game
    player = Games.get_player_by_game_and_user(game_id, user.id)
    is_player = !is_nil(player)

    # Allow access if:
    # 1. User is the host, OR
    # 2. User is a player AND the game is over (to see the leaderboard)
    cond do
      is_host ->
        mount_dashboard(game_id, game, socket, :host)

      is_player && game.state == "game_over" ->
        mount_dashboard(game_id, game, socket, :player)

      true ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Unberechtigter Zugriff."
         )
         |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_dashboard(game_id, game, socket, role) do
    socket =
      if connected?(socket) do
        Games.subscribe_to_game(game_id)
        Games.subscribe_to_active_games()

        # Only track host presence if this is the host
        if role == :host do
          # Track host presence - when this LiveView process dies, presence will be removed
          # and we can cleanup the game
          Mimimi.Presence.track(
            self(),
            "game:#{game_id}:host",
            "host",
            %{
              user_id: socket.assigns.current_user.id,
              game_id: game_id,
              joined_at: System.system_time(:second)
            }
          )

          # Tell the PresenceMonitor to start monitoring this game's host
          Mimimi.PresenceMonitor.monitor_game_host(game_id)
        end

        # Subscribe to player presence changes to show disconnections in real-time
        Phoenix.PubSub.subscribe(Mimimi.PubSub, "game:#{game_id}:players")

        # Get initial presence list
        initial_presence = Mimimi.Presence.list("game:#{game_id}:players")

        assign(socket, :online_player_ids, extract_online_player_ids(initial_presence))
      else
        assign(socket, :online_player_ids, MapSet.new())
      end

    # Get the short code for the invitation URL
    short_code = Games.get_short_code_for_game(game_id)
    invitation_url = "#{MimimiWeb.Endpoint.url()}/#{short_code}"
    qr_code_svg = generate_qr_code(invitation_url)

    socket =
      socket
      |> assign(:game, game)
      |> assign(:players, game.players)
      |> assign(:mode, determine_mode(game, socket.assigns.current_user, role))
      |> assign(:lobby_time_remaining, nil)
      |> assign(:short_code, short_code)
      |> assign(:invitation_url, invitation_url)
      |> assign(:qr_code_svg, qr_code_svg)
      |> assign(:pending_players, MapSet.new())

    socket =
      if socket.assigns.mode == :waiting_for_players do
        schedule_lobby_tick(socket)
      else
        socket
      end

    socket =
      if socket.assigns.mode == :host_dashboard do
        load_host_dashboard_data(socket, game)
      else
        socket
      end

    socket =
      if socket.assigns.mode == :game_over do
        load_game_over_data(socket, game)
      else
        socket
      end

    {:ok, socket}
  end

  defp load_host_dashboard_data(socket, game) do
    case Games.get_current_round(game.id) do
      nil ->
        socket

      round ->
        analytics = Games.get_round_analytics(round.id)
        keywords = fetch_keywords(round.keyword_ids)
        game_stats = Games.get_game_performance_stats(game.id)

        if connected?(socket) && round.state == "playing" do
          Games.start_game_server(game.id, round.id, game.clues_interval)
        end

        socket
        |> assign(:current_round, round)
        |> assign(:keywords_revealed, 0)
        |> assign(:time_elapsed, 0)
        |> assign(:round_analytics, analytics)
        |> assign(:keywords, keywords)
        |> assign(:game_stats, game_stats)
    end
  end

  defp determine_mode(game, user, role) do
    cond do
      game.state == "waiting_for_players" && game.host_user_id == user.id ->
        :waiting_for_players

      game.state == "game_running" && game.host_user_id == user.id ->
        :host_dashboard

      game.state == "game_over" ->
        :game_over

      true ->
        # Players should not see the waiting room or dashboard unless they're the host
        # This handles the edge case where a player tries to access during waiting_for_players
        if role == :host do
          :waiting_for_players
        else
          :game_over
        end
    end
  end

  defp load_game_over_data(socket, game) do
    correct_picks_by_player = Games.get_correct_picks_by_player(game.id)
    assign(socket, :correct_picks_by_player, correct_picks_by_player)
  end

  defp schedule_lobby_tick(socket) do
    Process.send_after(self(), :lobby_tick, 1000)
    time_remaining = Games.calculate_lobby_time_remaining(socket.assigns.game)
    assign(socket, :lobby_time_remaining, time_remaining)
  end

  defp fetch_keywords(keyword_ids) do
    alias Mimimi.WortSchule

    Enum.map(keyword_ids, fn kw_id ->
      case WortSchule.get_word(kw_id) do
        %{id: id, name: name} ->
          %{id: id, name: name}

        nil ->
          %{id: kw_id, name: "?"}
      end
    end)
  end

  @impl true
  def handle_info(:lobby_tick, socket) do
    game = socket.assigns.game
    time_remaining = Games.calculate_lobby_time_remaining(game)

    socket =
      if time_remaining <= 0 do
        Games.timeout_lobby(game)
        Games.broadcast_to_game(game.id, :lobby_timeout)

        socket
        |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
        |> push_navigate(to: ~p"/")
      else
        Process.send_after(self(), :lobby_tick, 1000)
        assign(socket, :lobby_time_remaining, time_remaining)
      end

    {:noreply, socket}
  end

  def handle_info(:game_count_changed, socket) do
    {:noreply, assign(socket, :active_games, Games.count_active_games())}
  end

  def handle_info(:player_joined, socket) do
    game = Games.get_game_with_players(socket.assigns.game.id)
    {:noreply, assign(socket, game: game, players: game.players)}
  end

  def handle_info(:player_left, socket) do
    game = Games.get_game_with_players(socket.assigns.game.id)
    {:noreply, assign(socket, game: game, players: game.players)}
  end

  def handle_info({:pending_player_arrived, user_id}, socket) do
    pending_players = MapSet.put(socket.assigns.pending_players, user_id)
    {:noreply, assign(socket, :pending_players, pending_players)}
  end

  def handle_info({:pending_player_left, user_id}, socket) do
    pending_players = MapSet.delete(socket.assigns.pending_players, user_id)
    {:noreply, assign(socket, :pending_players, pending_players)}
  end

  def handle_info(:game_started, socket) do
    game = Games.get_game_with_players(socket.assigns.game.id)

    # Determine role based on whether user is host
    role = if game.host_user_id == socket.assigns.current_user.id, do: :host, else: :player

    socket = assign(socket, :game, game)
    socket = assign(socket, :mode, determine_mode(game, socket.assigns.current_user, role))

    socket =
      case Games.get_current_round(game.id) do
        nil ->
          socket

        round ->
          analytics = Games.get_round_analytics(round.id)
          keywords = fetch_keywords(round.keyword_ids)
          game_stats = Games.get_game_performance_stats(game.id)

          Games.start_game_server(game.id, round.id, game.clues_interval)

          socket
          |> assign(:current_round, round)
          |> assign(:keywords_revealed, 0)
          |> assign(:time_elapsed, 0)
          |> assign(:round_analytics, analytics)
          |> assign(:keywords, keywords)
          |> assign(:game_stats, game_stats)
      end

    {:noreply, socket}
  end

  def handle_info(:lobby_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:keyword_revealed, revealed_count, time_elapsed}, socket) do
    {:noreply,
     socket
     |> assign(:keywords_revealed, revealed_count)
     |> assign(:time_elapsed, time_elapsed)}
  end

  def handle_info({:player_picked, _player_id, _is_correct}, socket) do
    # Reload players and round analytics
    game = Games.get_game_with_players(socket.assigns.game.id)

    socket =
      if socket.assigns[:current_round] do
        analytics = Games.get_round_analytics(socket.assigns.current_round.id)
        assign(socket, :round_analytics, analytics)
      else
        socket
      end

    socket
    |> assign(:game, game)
    |> assign(:players, game.players)
    |> then(&{:noreply, &1})
  end

  def handle_info(:round_started, socket) do
    case Games.get_current_round(socket.assigns.game.id) do
      nil ->
        {:noreply, socket}

      round ->
        analytics = Games.get_round_analytics(round.id)
        keywords = fetch_keywords(round.keyword_ids)
        game_stats = Games.get_game_performance_stats(socket.assigns.game.id)

        {:noreply,
         socket
         |> assign(:current_round, round)
         |> assign(:keywords_revealed, 0)
         |> assign(:time_elapsed, 0)
         |> assign(:round_analytics, analytics)
         |> assign(:keywords, keywords)
         |> assign(:game_stats, game_stats)}
    end
  end

  def handle_info(:game_finished, socket) do
    # Game is over, reload for game_over view
    game = Games.get_game_with_players(socket.assigns.game.id)

    # Determine role based on whether user is host
    role = if game.host_user_id == socket.assigns.current_user.id, do: :host, else: :player

    socket =
      socket
      |> assign(:game, game)
      |> assign(:players, game.players)
      |> assign(:mode, determine_mode(game, socket.assigns.current_user, role))

    socket =
      if socket.assigns.mode == :game_over do
        load_game_over_data(socket, game)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:game_stopped_by_host, socket) do
    # Game was manually stopped by host, reload for game_over view
    game = Games.get_game_with_players(socket.assigns.game.id)

    # Determine role based on whether user is host
    role = if game.host_user_id == socket.assigns.current_user.id, do: :host, else: :player

    socket =
      socket
      |> assign(:game, game)
      |> assign(:players, game.players)
      |> assign(:mode, determine_mode(game, socket.assigns.current_user, role))

    socket =
      if socket.assigns.mode == :game_over do
        load_game_over_data(socket, game)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: %{joins: joins, leaves: leaves}
        },
        socket
      ) do
    online_player_ids =
      socket.assigns.online_player_ids
      |> MapSet.union(extract_online_player_ids(joins))
      |> MapSet.difference(extract_online_player_ids(leaves))

    {:noreply, assign(socket, :online_player_ids, online_player_ids)}
  end

  @impl true
  def terminate(_reason, _socket) do
    :ok
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game = socket.assigns.game

    if length(socket.assigns.players) > 0 do
      case Games.start_game(game) do
        {:ok, _game} ->
          Games.broadcast_to_game(game.id, :game_started)
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Fehler beim Starten des Spiels")}
      end
    else
      {:noreply, put_flash(socket, :error, "Du brauchst mehr Spieler.")}
    end
  end

  def handle_event("copy_link", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("stop_game", _params, socket) do
    game = socket.assigns.game

    case Games.stop_game_manually(game.id) do
      {:ok, _game} ->
        # The game_stopped_by_host broadcast will be handled by handle_info
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Fehler beim Stoppen des Spiels")}
    end
  end

  def handle_event("stop_modal_propagation", _params, socket) do
    # Prevent modal from closing when clicking inside it
    {:noreply, socket}
  end

  defp generate_qr_code(url) do
    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: 192)
    |> String.replace(~r/<svg ([^>]*) width="[^"]*"/, "<svg \\1")
    |> String.replace(~r/<svg ([^>]*) height="[^"]*"/, "<svg \\1")
  end

  defp extract_online_player_ids(presence_map) do
    presence_map
    |> Map.keys()
    |> Enum.map(fn "player_" <> user_id -> user_id end)
    |> MapSet.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= case @mode do %>
      <% :waiting_for_players -> %>
        {render_lobby(assigns)}
      <% :host_dashboard -> %>
        {render_host_dashboard(assigns)}
      <% :game_over -> %>
        {render_game_over(assigns)}
    <% end %>
    """
  end

  defp render_lobby(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-4xl">
        <%!-- Invitation Card --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-6 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6">
          <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white text-center">
            Einladungscode
          </h2>

          <%!-- Large prominent code display --%>
          <div class="relative mb-6 overflow-hidden rounded-3xl">
            <div class="absolute inset-0 bg-gradient-to-br from-purple-500 via-pink-500 to-purple-600 opacity-10">
            </div>
            <div class="relative backdrop-blur-xl bg-white/90 dark:bg-gray-900/90 border-4 border-purple-500/30 dark:border-purple-400/30 rounded-3xl p-8 text-center">
              <div class="text-6xl sm:text-8xl md:text-9xl font-black text-transparent bg-clip-text bg-gradient-to-br from-purple-600 via-pink-500 to-purple-600 dark:from-purple-400 dark:via-pink-400 dark:to-purple-400 tracking-wider mb-2 select-all">
                {@short_code}
              </div>
              <p class="text-sm text-gray-600 dark:text-gray-400 font-medium">
                Gib diesen Code ein auf
                <span class="font-bold text-purple-600 dark:text-purple-400">
                  {URI.parse(@invitation_url).host}
                </span>
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-center">
            <div class="flex flex-col gap-3 lg:col-span-2">
              <div class="relative group">
                <div class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                </div>
                <input
                  type="text"
                  readonly
                  value={@invitation_url}
                  class="relative w-full px-4 py-3 text-sm bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white outline-none"
                  id="invitation-link"
                />
              </div>
              <button
                type="button"
                phx-click={
                  JS.dispatch("phx:copy", to: "#invitation-link")
                  |> JS.transition("opacity-0", to: "#copy-text")
                  |> JS.transition("opacity-100", to: "#copied-text", time: 0)
                  |> JS.transition("opacity-100", to: "#copy-text", time: 2000)
                  |> JS.transition("opacity-0", to: "#copied-text", time: 2000)
                }
                class="relative w-full py-3 bg-gradient-to-r from-purple-600 via-purple-500 to-pink-500 hover:from-purple-700 hover:via-purple-600 hover:to-pink-600 text-white rounded-2xl shadow-lg shadow-purple-500/30 hover:shadow-xl hover:shadow-purple-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 font-semibold overflow-hidden group"
              >
                <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
                </div>
                <span id="copy-text" class="relative">Link kopieren</span>
                <span id="copied-text" class="relative hidden opacity-0">Kopiert! ✓</span>
              </button>
            </div>

            <div class="flex items-center justify-center p-6 bg-white dark:bg-gray-900 rounded-2xl border-2 border-gray-200 dark:border-gray-700 shadow-lg">
              <div class="w-48 h-48 flex items-center justify-center">
                {Phoenix.HTML.raw(@qr_code_svg)}
              </div>
            </div>
          </div>
        </div>

        <%!-- Start Game Button --%>
        <div class="mb-6">
          <button
            type="button"
            phx-click="start_game"
            disabled={length(@players) == 0}
            class={[
              "relative w-full text-xl font-semibold py-5 rounded-2xl shadow-xl transition-all duration-200 overflow-hidden group",
              if(length(@players) > 0,
                do:
                  "bg-gradient-to-r from-green-500 to-emerald-500 hover:from-green-600 hover:to-emerald-600 text-white shadow-green-500/30 hover:shadow-2xl hover:shadow-green-500/40 hover:scale-[1.02] active:scale-[0.98]",
                else:
                  "bg-gray-300 dark:bg-gray-600 text-gray-500 dark:text-gray-400 cursor-not-allowed"
              )
            ]}
          >
            <%= if length(@players) > 0 do %>
              <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
              </div>
            <% end %>
            <span class="relative">Jetzt spielen!</span>
          </button>
        </div>

        <%!-- Players Card --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-6 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
          <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
            Mitspieler ({length(@players)})
            <%= if MapSet.size(@pending_players) > 0 do %>
              <span class="text-sm font-normal text-purple-600 dark:text-purple-400">
                + {MapSet.size(@pending_players)} wählt Avatar...
              </span>
            <% end %>
          </h2>

          <%= if @players == [] && MapSet.size(@pending_players) == 0 do %>
            <div class="text-center py-8">
              <div class="text-6xl mb-4 opacity-50">👥</div>
              <p class="text-gray-600 dark:text-gray-400">Warte auf Spieler...</p>
            </div>
          <% else %>
            <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-3">
              <%= for player <- @players do %>
                <% is_online = MapSet.member?(@online_player_ids, player.user_id) %>
                <div class={[
                  "relative flex flex-col items-center justify-center p-3 rounded-2xl aspect-square transition-all duration-300 overflow-hidden group",
                  if(is_online,
                    do:
                      "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md",
                    else:
                      "bg-gray-100 dark:bg-gray-800 border-2 border-dashed border-gray-300 dark:border-gray-600 opacity-50"
                  )
                ]}>
                  <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class={[
                    "relative text-6xl sm:text-7xl",
                    if(!is_online, do: "grayscale")
                  ]}>
                    {player.avatar}
                  </span>
                  <%= if !is_online do %>
                    <div class="absolute -bottom-1 -right-1 w-5 h-5 rounded-full bg-gray-400 border-2 border-white dark:border-gray-800 flex items-center justify-center">
                      <span class="text-white text-xs">⚠</span>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <%= for _user_id <- @pending_players do %>
                <div class="relative flex flex-col items-center justify-center p-3 border-2 border-dashed border-purple-400 dark:border-purple-500 rounded-2xl bg-purple-50/50 dark:bg-purple-900/20 backdrop-blur-sm animate-pulse aspect-square">
                  <span class="text-6xl sm:text-7xl mb-1">❓</span>
                  <span class="text-xs text-center text-purple-600 dark:text-purple-400 font-medium leading-tight">
                    Wählt...
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_host_dashboard(assigns) do
    ~H"""
    <div class="min-h-screen px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-6xl mx-auto">
        <%= if assigns[:current_round] do %>
          <%!-- Round information --%>
          <div class="text-center mb-8">
            <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 mb-4 shadow-lg">
              <span class="text-4xl">🎯</span>
            </div>
            <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
              Runde {@current_round.position} von {@game.rounds_count}
            </h1>
            <p class="text-lg text-gray-600 dark:text-gray-400">
              Lehrkraft Dashboard
            </p>
          </div>

          <%!-- Game status cards --%>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            <%!-- Players who picked --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-5 shadow-xl border border-gray-200/50 dark:border-gray-700/50">
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-2 font-medium">
                Gewählt:
              </p>
              <p class="text-3xl font-bold text-purple-600 dark:text-purple-400">
                {@round_analytics.picked_count} / {@round_analytics.total_players}
              </p>
            </div>

            <%!-- Correct answers --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-5 shadow-xl border border-gray-200/50 dark:border-gray-700/50">
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-2 font-medium">
                Richtig:
              </p>
              <p class="text-3xl font-bold text-green-600 dark:text-green-400">
                {@round_analytics.correct_count}
              </p>
            </div>

            <%!-- Wrong answers --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-5 shadow-xl border border-gray-200/50 dark:border-gray-700/50">
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-2 font-medium">
                Falsch:
              </p>
              <p class="text-3xl font-bold text-red-600 dark:text-red-400">
                {@round_analytics.wrong_count}
              </p>
            </div>

            <%!-- Keywords revealed --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-5 shadow-xl border border-gray-200/50 dark:border-gray-700/50">
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-2 font-medium">
                Hinweise:
              </p>
              <p class="text-3xl font-bold text-blue-600 dark:text-blue-400">
                {min(assigns[:keywords_revealed] || 0, 3)} / 3
              </p>
            </div>
          </div>

          <%!-- Keywords display --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-8">
            <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
              Aktuelle Schlüsselwörter
            </h2>
            <div class="flex flex-wrap gap-3">
              <%= for {keyword, index} <- Enum.with_index(@keywords, 1) do %>
                <% # A keyword is fully revealed if we've moved past it
                is_revealed = index < @keywords_revealed
                # The current keyword is the one being revealed right now
                is_current = index == @keywords_revealed
                # Not yet reached
                is_upcoming = index > @keywords_revealed

                # Calculate progress for the current keyword
                progress_percent =
                  if is_current && @keywords_revealed > 0 do
                    # Time since this keyword was revealed
                    # For keyword N, it was revealed at time (N-1) * interval
                    # So the time it's been showing is: elapsed - (N-1) * interval
                    keyword_revealed_at = (@keywords_revealed - 1) * @game.clues_interval
                    time_showing = @time_elapsed - keyword_revealed_at

                    # Progress is how much of the interval has passed
                    min(time_showing / @game.clues_interval * 100, 100) |> round()
                  else
                    0
                  end %>
                <div class={
                  [
                    "relative overflow-hidden px-4 py-2 rounded-2xl font-semibold transition-all duration-300 transform",
                    cond do
                      is_revealed ->
                        # Fully revealed keywords show with purple gradient
                        "bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-lg scale-100"

                      is_current ->
                        # Current keyword shows gray background with progress bar
                        "bg-gray-300 dark:bg-gray-700 text-gray-900 dark:text-gray-100 scale-100"

                      is_upcoming ->
                        # Upcoming keywords are dimmed
                        "bg-gray-300 dark:bg-gray-700 text-gray-400 dark:text-gray-500 scale-95 opacity-60"
                    end
                  ]
                }>
                  <%= if is_current && progress_percent > 0 do %>
                    <%!-- Progress bar for current keyword --%>
                    <div
                      class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 opacity-30"
                      style={"width: #{progress_percent}%; transition: width 0.5s linear;"}
                    >
                    </div>
                  <% end %>
                  <span class="relative z-10">
                    {if is_revealed || is_current, do: keyword.name, else: "???"}
                  </span>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Players with their pick status and chosen word --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-8">
            <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
              Spieler Auswahl
            </h2>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%= for player_pick <- @round_analytics.players_picked do %>
                <div class={[
                  "relative rounded-2xl p-4 transition-all duration-300 border-2",
                  if(player_pick.is_correct,
                    do: "bg-green-50 dark:bg-green-900/20 border-green-500 dark:border-green-400",
                    else: "bg-red-50 dark:bg-red-900/20 border-red-500 dark:border-red-400"
                  )
                ]}>
                  <div class="flex items-start gap-4">
                    <%!-- Player avatar --%>
                    <div class="flex-shrink-0">
                      <div class="relative">
                        <span class="text-5xl">{player_pick.player.avatar}</span>
                        <div class={[
                          "absolute -top-1 -right-1 w-6 h-6 rounded-full shadow-lg flex items-center justify-center",
                          if(player_pick.is_correct,
                            do: "bg-green-500",
                            else: "bg-red-500"
                          )
                        ]}>
                          <span class="text-white text-sm font-bold">
                            {if player_pick.is_correct, do: "✓", else: "✗"}
                          </span>
                        </div>
                      </div>
                    </div>
                    <%!-- Picked word with image --%>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-3 mb-2">
                        <%= if player_pick.picked_word.image_url do %>
                          <img
                            src={player_pick.picked_word.image_url}
                            alt={player_pick.picked_word.name}
                            class="w-16 h-16 object-cover rounded-lg border-2 border-gray-300 dark:border-gray-600"
                          />
                        <% else %>
                          <div class="w-16 h-16 bg-gray-200 dark:bg-gray-700 rounded-lg flex items-center justify-center">
                            <span class="text-2xl">🖼️</span>
                          </div>
                        <% end %>
                        <div class="flex-1">
                          <p class="font-semibold text-gray-900 dark:text-white">
                            {player_pick.picked_word.name}
                          </p>
                          <p class="text-xs text-gray-600 dark:text-gray-400">
                            {player_pick.keywords_shown} Hinweise • {player_pick.time}s
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              <%= for player <- @round_analytics.players_not_picked do %>
                <div class="relative rounded-2xl p-4 bg-gray-100 dark:bg-gray-800 border-2 border-dashed border-gray-300 dark:border-gray-600 animate-pulse">
                  <div class="flex items-center gap-4">
                    <span class="text-5xl opacity-50">{player.avatar}</span>
                    <div class="flex-1">
                      <p class="text-gray-500 dark:text-gray-400 font-medium">
                        Wartet auf Antwort...
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Game performance statistics --%>
          <%= if @game_stats.played_rounds > 0 do %>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-8">
              <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
                Bisherige Leistung
              </h2>

              <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div class="bg-gradient-to-br from-blue-50 to-blue-100 dark:from-blue-900/30 dark:to-blue-800/30 rounded-xl p-4">
                  <p class="text-sm text-blue-600 dark:text-blue-400 mb-1 font-medium">
                    Gespielte Runden
                  </p>
                  <p class="text-2xl font-bold text-blue-900 dark:text-blue-100">
                    {@game_stats.played_rounds} / {@game_stats.total_rounds}
                  </p>
                </div>

                <div class="bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/30 dark:to-green-800/30 rounded-xl p-4">
                  <p class="text-sm text-green-600 dark:text-green-400 mb-1 font-medium">
                    Gesamt Genauigkeit
                  </p>
                  <p class="text-2xl font-bold text-green-900 dark:text-green-100">
                    {@game_stats.average_accuracy}%
                  </p>
                </div>

                <div class="bg-gradient-to-br from-purple-50 to-purple-100 dark:from-purple-900/30 dark:to-purple-800/30 rounded-xl p-4">
                  <p class="text-sm text-purple-600 dark:text-purple-400 mb-1 font-medium">
                    Richtig / Falsch
                  </p>
                  <p class="text-2xl font-bold text-purple-900 dark:text-purple-100">
                    {@game_stats.total_correct} / {@game_stats.total_wrong}
                  </p>
                </div>
              </div>

              <%!-- Per-player statistics --%>
              <h3 class="text-md font-semibold mb-4 text-gray-900 dark:text-white">
                Spieler Statistiken
              </h3>
              <div class="space-y-2">
                <%= for stat <- @game_stats.player_stats do %>
                  <div class="bg-white dark:bg-gray-900 rounded-xl p-4 border border-gray-200 dark:border-gray-700">
                    <div class="flex items-center justify-between mb-2">
                      <div class="flex items-center gap-3">
                        <span class="text-3xl">{stat.player.avatar}</span>
                        <div>
                          <p class="font-semibold text-gray-900 dark:text-white">
                            Genauigkeit: {stat.accuracy}%
                          </p>
                          <p class="text-sm text-gray-600 dark:text-gray-400">
                            {stat.correct} richtig, {stat.wrong} falsch
                          </p>
                        </div>
                      </div>
                      <div class="text-right">
                        <p class="text-lg font-bold text-purple-600 dark:text-purple-400">
                          {stat.points} Punkte
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400">
                          ⌀ {stat.average_keywords_used} Hinweise
                        </p>
                      </div>
                    </div>
                    <%!-- Progress bar for accuracy --%>
                    <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                      <div
                        class="bg-gradient-to-r from-purple-500 to-pink-500 h-2 rounded-full transition-all duration-300"
                        style={"width: #{stat.accuracy}%"}
                      >
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Current leaderboard --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
              Aktuelle Rangliste
            </h2>

            <div class="space-y-2">
              <%= for {player, index} <- Enum.with_index(Enum.sort_by(@game.players, & &1.points, :desc)) do %>
                <div class={[
                  "relative flex items-center justify-between p-4 rounded-xl transition-all duration-300 overflow-hidden",
                  if(index == 0,
                    do:
                      "bg-gradient-to-r from-yellow-400 to-orange-400 text-white shadow-lg shadow-yellow-500/30",
                    else: "bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700"
                  )
                ]}>
                  <div class="relative flex items-center gap-4">
                    <span class="text-2xl font-bold">{index + 1}.</span>
                    <span class="text-4xl">{player.avatar}</span>
                    <span class={[
                      "font-semibold",
                      if(index == 0,
                        do: "text-white",
                        else: "text-gray-900 dark:text-white"
                      )
                    ]}>
                      {player.points} Punkte
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Stop Game Button --%>
          <div class="mt-6">
            <button
              type="button"
              phx-click={JS.show(to: "#stop-game-modal")}
              class="relative w-full py-4 bg-gradient-to-r from-red-600 via-red-500 to-orange-500 hover:from-red-700 hover:via-red-600 hover:to-orange-600 text-white rounded-2xl shadow-xl shadow-red-500/30 hover:shadow-2xl hover:shadow-red-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 font-semibold overflow-hidden group"
            >
              <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
              </div>
              <span class="relative">⏹️ Spiel jetzt beenden</span>
            </button>
          </div>

          <%!-- Stop Game Confirmation Modal --%>
          <div
            id="stop-game-modal"
            class="hidden fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
            phx-click={JS.hide(to: "#stop-game-modal")}
          >
            <div
              class="relative w-full max-w-md backdrop-blur-xl bg-white/90 dark:bg-gray-800/90 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50"
              phx-click="stop_modal_propagation"
            >
              <div class="text-center mb-6">
                <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-gradient-to-br from-red-500 to-orange-500 mb-4 shadow-lg">
                  <span class="text-3xl">⚠️</span>
                </div>
                <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                  Spiel wirklich beenden?
                </h2>
                <p class="text-gray-600 dark:text-gray-400">
                  Das Spiel wird sofort beendet und alle Spieler sehen die finale Rangliste.
                </p>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <button
                  type="button"
                  phx-click={JS.hide(to: "#stop-game-modal")}
                  class="relative py-3 bg-gray-200 dark:bg-gray-700 hover:bg-gray-300 dark:hover:bg-gray-600 text-gray-900 dark:text-white rounded-xl font-semibold transition-all duration-200 hover:scale-[1.02] active:scale-[0.98]"
                >
                  Abbrechen
                </button>
                <button
                  type="button"
                  phx-click={JS.push("stop_game") |> JS.hide(to: "#stop-game-modal")}
                  class="relative py-3 bg-gradient-to-r from-red-600 to-orange-500 hover:from-red-700 hover:to-orange-600 text-white rounded-xl shadow-lg shadow-red-500/30 hover:shadow-xl hover:shadow-red-500/40 font-semibold transition-all duration-200 hover:scale-[1.02] active:scale-[0.98] overflow-hidden group"
                >
                  <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
                  </div>
                  <span class="relative">Ja, beenden</span>
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center mb-10">
            <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 mb-4 shadow-lg animate-pulse">
              <span class="text-4xl">⏳</span>
            </div>
            <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
              Spielleiter Dashboard
            </h1>
            <p class="text-lg text-gray-600 dark:text-gray-400">
              Spiel wird vorbereitet...
            </p>
          </div>

          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <div class="text-center py-8">
              <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-purple-600 dark:border-purple-400 mx-auto mb-4">
              </div>
              <p class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
                Runden werden generiert...
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                Bitte warten Sie einen Moment
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_game_over(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-4xl">
        <div class="text-center mb-10">
          <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-yellow-400 to-orange-500 mb-4 shadow-lg">
            <span class="text-4xl">🏆</span>
          </div>
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            Spiel fertig!
          </h1>
          <p class="text-gray-500 dark:text-gray-400">
            Wer hat gewonnen?
          </p>
        </div>

        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6">
          <div class="space-y-3">
            <%= for {player, index} <- Enum.with_index(Enum.sort_by(@players, & &1.points, :desc)) do %>
              <div class={[
                "relative flex items-center justify-between p-5 rounded-2xl transition-all duration-300 overflow-hidden group",
                case index do
                  0 ->
                    "bg-gradient-to-r from-yellow-400 to-orange-400 text-white shadow-lg shadow-yellow-500/50"

                  1 ->
                    "bg-gradient-to-r from-gray-300 to-gray-400 dark:from-gray-600 dark:to-gray-700 text-white shadow-lg shadow-gray-500/50"

                  2 ->
                    "bg-gradient-to-r from-orange-400 to-red-400 text-white shadow-lg shadow-orange-500/50"

                  _ ->
                    "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-900 dark:text-white"
                end
              ]}>
                <div class="relative flex items-center gap-4">
                  <span class="text-2xl font-bold">{index + 1}.</span>
                  <span class="text-4xl">{player.avatar}</span>
                </div>
                <span class="relative text-xl font-bold">{player.points} Punkte</span>
                <%= if index < 3 do %>
                  <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Correct picks section --%>
        <%= if @correct_picks_by_player && map_size(@correct_picks_by_player) > 0 do %>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6 correct-picks">
            <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-6 text-center">
              Richtig geraten! 🎉
            </h2>

            <div class="space-y-8">
              <%= for player <- Enum.sort_by(@players, & &1.points, :desc) do %>
                <% correct_words = Map.get(@correct_picks_by_player, player.id, []) %>
                <%= if correct_words != [] do %>
                  <div class="relative overflow-hidden rounded-2xl bg-gradient-to-br from-purple-50 to-pink-50 dark:from-purple-900/20 dark:to-pink-900/20 p-6 border-2 border-purple-200 dark:border-purple-700">
                    <%!-- Player header --%>
                    <div class="flex items-center gap-4 mb-4">
                      <span class="text-5xl">{player.avatar}</span>
                      <div>
                        <p class="font-bold text-lg text-gray-900 dark:text-white">
                          {length(correct_words)} {if length(correct_words) == 1,
                            do: "Wort",
                            else: "Wörter"} richtig
                        </p>
                        <p class="text-sm text-gray-600 dark:text-gray-400">
                          {player.points} {if player.points == 1, do: "Punkt", else: "Punkte"} gesammelt
                        </p>
                      </div>
                    </div>

                    <%!-- Word images grid --%>
                    <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
                      <%= for word <- correct_words do %>
                        <div class="relative group">
                          <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 rounded-xl opacity-0 group-hover:opacity-20 transition-opacity duration-300">
                          </div>
                          <div class="relative aspect-square rounded-xl overflow-hidden bg-white dark:bg-gray-800 border-2 border-gray-200 dark:border-gray-700 group-hover:border-purple-400 dark:group-hover:border-purple-500 transition-all duration-300 group-hover:scale-105 group-hover:shadow-xl">
                            <%= if word.image_url do %>
                              <img
                                src={word.image_url}
                                alt={word.name}
                                class="w-full h-full object-cover"
                              />
                              <div class="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/80 to-transparent p-2">
                                <p class="text-white text-xs font-semibold text-center truncate">
                                  {word.name}
                                </p>
                              </div>
                            <% else %>
                              <div class="w-full h-full flex flex-col items-center justify-center">
                                <span class="text-4xl mb-2">🖼️</span>
                                <p class="text-xs text-gray-600 dark:text-gray-400 font-semibold text-center px-2">
                                  {word.name}
                                </p>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <a
          href="/game/leave"
          class="block w-full text-center text-lg font-semibold py-4 bg-gradient-to-r from-purple-600 via-purple-500 to-pink-500 hover:from-purple-700 hover:via-purple-600 hover:to-pink-600 text-white rounded-2xl shadow-xl shadow-purple-500/30 hover:shadow-2xl hover:shadow-purple-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
        >
          Zurück zur Startseite
        </a>
      </div>
    </div>
    """
  end
end
