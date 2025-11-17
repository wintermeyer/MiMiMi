defmodule MimimiWeb.DashboardLive.Show do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"id" => game_id}, session, socket) do
    game = Games.get_game_with_players(game_id)

    # Only allow access if the user has the valid host token
    # This prevents hijacking even if someone copies the URL to another device
    host_token_key = "host_token_#{game_id}"
    stored_token = Map.get(session, host_token_key)

    # Verify the token matches - REQUIRED for waiting room access
    if stored_token == game.host_token do
      # Valid host token - proceed with mounting
      mount_dashboard(game_id, game, socket, :host)
    else
      # No valid token - deny access completely
      {:ok,
       socket
       |> put_flash(
         :error,
         "Unberechtigter Zugriff. Nur der Spielleiter kann den Warteraum öffnen."
       )
       |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_dashboard(game_id, game, socket, _role) do
    if connected?(socket) do
      Games.subscribe_to_game(game_id)
      Games.subscribe_to_active_games()
    end

    # Get the short code for the invitation URL
    short_code = Games.get_short_code_for_game(game_id)
    invitation_url = "#{MimimiWeb.Endpoint.url()}/#{short_code}"
    qr_code_svg = generate_qr_code(invitation_url)

    socket =
      socket
      |> assign(:game, game)
      |> assign(:players, game.players)
      |> assign(:mode, determine_mode(game, socket.assigns.current_user))
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

    {:ok, socket}
  end

  defp determine_mode(game, user) do
    cond do
      game.state == "waiting_for_players" && game.host_user_id == user.id ->
        :waiting_for_players

      game.state == "game_running" && game.host_user_id == user.id ->
        :host_dashboard

      game.state == "game_over" ->
        :game_over

      true ->
        :waiting_for_players
    end
  end

  defp schedule_lobby_tick(socket) do
    Process.send_after(self(), :lobby_tick, 1000)
    time_remaining = Games.calculate_lobby_time_remaining(socket.assigns.game)
    assign(socket, :lobby_time_remaining, time_remaining)
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
    # Reload current round for display on host dashboard
    game = Games.get_game_with_players(socket.assigns.game.id)
    socket = assign(socket, :game, game)
    socket = assign(socket, :mode, determine_mode(game, socket.assigns.current_user))

    # Load current round if available
    socket =
      case Games.get_current_round(game.id) do
        nil ->
          socket

        round ->
          socket
          |> assign(:current_round, round)
          |> assign(:keywords_revealed, 0)
          |> assign(:players_picked, MapSet.new())
      end

    {:noreply, socket}
  end

  def handle_info(:lobby_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:keyword_revealed, revealed_count, _time_elapsed}, socket) do
    {:noreply, assign(socket, :keywords_revealed, revealed_count)}
  end

  def handle_info({:player_picked, _player_id, _is_correct}, socket) do
    # Reload players to show updated picks
    game = Games.get_game_with_players(socket.assigns.game.id)
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info(:round_started, socket) do
    # Reload current round
    case Games.get_current_round(socket.assigns.game.id) do
      nil ->
        {:noreply, socket}

      round ->
        {:noreply,
         socket
         |> assign(:current_round, round)
         |> assign(:keywords_revealed, 0)
         |> assign(:players_picked, MapSet.new())}
    end
  end

  def handle_info(:game_finished, socket) do
    # Game is over, reload for game_over view
    game = Games.get_game_with_players(socket.assigns.game.id)
    socket = assign(socket, :game, game)
    socket = assign(socket, :mode, determine_mode(game, socket.assigns.current_user))
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game = socket.assigns.game

    if length(socket.assigns.players) > 0 do
      case Games.start_game(game) do
        {:ok, _game} ->
          Games.broadcast_to_game(game.id, :game_started)
          {:noreply, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}

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

  defp generate_qr_code(url) do
    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: 192)
    |> String.replace(~r/<svg ([^>]*) width="[^"]*"/, "<svg \\1")
    |> String.replace(~r/<svg ([^>]*) height="[^"]*"/, "<svg \\1")
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
                <div class="relative flex flex-col items-center justify-center p-3 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl aspect-square transition-all duration-300 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md overflow-hidden group">
                  <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative text-6xl sm:text-7xl">{player.avatar}</span>
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
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-4xl">
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
              Spielleiter Dashboard
            </p>
          </div>

          <%!-- Game status cards --%>
          <div class="grid grid-cols-2 gap-4 mb-8">
            <%!-- Players who picked --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-5 shadow-xl border border-gray-200/50 dark:border-gray-700/50">
              <p class="text-sm text-gray-600 dark:text-gray-400 mb-2 font-medium">
                Gewählt:
              </p>
              <p class="text-3xl font-bold text-purple-600 dark:text-purple-400">
                <span>Wird berechnet...</span>
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

          <%!-- Players with their avatars --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-8">
            <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
              Spieler ({length(@game.players)})
            </h2>

            <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-3">
              <%= for player <- @game.players do %>
                <div class="relative flex flex-col items-center justify-center p-3 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl aspect-square transition-all duration-300 overflow-hidden group hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md">
                  <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative text-5xl sm:text-6xl">{player.avatar}</span>
                  <%!-- Badge showing if picked --%>
                  <div class="absolute -top-2 -right-2 w-6 h-6 rounded-full bg-green-500 shadow-lg animate-pulse hidden">
                  </div>
                </div>
              <% end %>
            </div>

            <p class="text-sm text-gray-600 dark:text-gray-400 text-center mt-6">
              👆 Spieler-Avatar zeigt Status an
            </p>
          </div>

          <%!-- Live leaderboard --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <h2 class="text-lg font-semibold mb-6 text-gray-900 dark:text-white">
              Aktuelle Punkte
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

        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
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
      </div>
    </div>
    """
  end
end
