defmodule MimimiWeb.DashboardLive.Show do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game_with_players(game_id)

    if connected?(socket) do
      Games.subscribe_to_game(game_id)
      Games.subscribe_to_active_games()
    end

    invitation_url = "#{MimimiWeb.Endpoint.url()}/choose-avatar/#{game.invitation_id}"
    qr_code_svg = generate_qr_code(invitation_url)

    socket =
      socket
      |> assign(:game, game)
      |> assign(:players, game.players)
      |> assign(:mode, determine_mode(game, socket.assigns.current_user))
      |> assign(:lobby_time_remaining, nil)
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
    {:noreply, push_navigate(socket, to: ~p"/dashboard/#{socket.assigns.game.id}")}
  end

  def handle_info(:lobby_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
     |> push_navigate(to: ~p"/")}
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
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen px-4 py-8">
      <%= case @mode do %>
        <% :waiting_for_players -> %>
          {render_lobby(assigns)}
        <% :host_dashboard -> %>
          {render_host_dashboard(assigns)}
        <% :game_over -> %>
          {render_game_over(assigns)}
      <% end %>
    </div>
    """
  end

  defp render_lobby(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto flex flex-col min-h-screen py-4">
      <h1 class="text-3xl font-bold text-center mb-6 text-gray-900 dark:text-white">
        Warteraum
      </h1>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-4 sm:p-6 mb-4">
        <h2 class="text-lg font-bold mb-3 text-gray-900 dark:text-white">Einladungslink zeigen</h2>

        <div class="flex flex-col gap-2 mb-4">
          <input
            type="text"
            readonly
            value={@invitation_url}
            class="w-full px-3 py-2 text-sm border rounded bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white border-gray-300 dark:border-gray-600"
            id="invitation-link"
          />
          <button
            type="button"
            phx-click={
              JS.dispatch("phx:copy", to: "#invitation-link")
              |> JS.transition("opacity-0", to: "#copy-text")
              |> JS.transition("opacity-100", to: "#copied-text", time: 0)
              |> JS.transition("opacity-100", to: "#copy-text", time: 2000)
              |> JS.transition("opacity-0", to: "#copied-text", time: 2000)
            }
            class="w-full px-4 py-2 bg-purple-600 hover:bg-purple-700 active:scale-95 active:bg-purple-800 text-white rounded font-medium transition-all duration-150 ease-in-out"
          >
            <span id="copy-text">Link kopieren</span>
            <span id="copied-text" class="hidden opacity-0">Kopiert! ✓</span>
          </button>
        </div>

        <div class="flex justify-center p-3 bg-white dark:bg-gray-900 rounded">
          <div class="w-48 h-48 flex items-center justify-center">
            {Phoenix.HTML.raw(@qr_code_svg)}
          </div>
        </div>
      </div>

      <div class="mb-4">
        <button
          type="button"
          phx-click="start_game"
          disabled={length(@players) == 0}
          class={[
            "w-full text-xl font-bold py-4 rounded-lg transition-colors",
            if(length(@players) > 0,
              do: "bg-green-600 hover:bg-green-700 text-white",
              else: "bg-gray-300 dark:bg-gray-600 text-gray-500 dark:text-gray-400 cursor-not-allowed"
            )
          ]}
        >
          Jetzt spielen!
        </button>
      </div>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-4 sm:p-6">
        <h2 class="text-lg font-bold mb-3 text-gray-900 dark:text-white">
          Mitspieler ({length(@players)})
          <%= if MapSet.size(@pending_players) > 0 do %>
            <span class="text-sm font-normal text-purple-600 dark:text-purple-400">
              + {MapSet.size(@pending_players)} wählt Avatar...
            </span>
          <% end %>
        </h2>

        <%= if @players == [] && MapSet.size(@pending_players) == 0 do %>
          <p class="text-gray-600 dark:text-gray-400">Warte auf Spieler...</p>
        <% else %>
          <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-2">
            <%= for player <- @players do %>
              <div class="flex flex-col items-center justify-center p-2 border-2 border-gray-200 dark:border-gray-600 rounded-lg aspect-square">
                <span class="text-7xl sm:text-8xl">{player.avatar}</span>
              </div>
            <% end %>
            <%= for _user_id <- @pending_players do %>
              <div class="flex flex-col items-center justify-center p-2 border-2 border-dashed border-purple-400 dark:border-purple-500 rounded-lg bg-purple-50 dark:bg-purple-900/20 animate-pulse aspect-square">
                <span class="text-7xl sm:text-8xl mb-1">❓</span>
                <span class="text-xs text-center text-purple-600 dark:text-purple-400 font-medium leading-tight">
                  Wählt...
                </span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_host_dashboard(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <h1 class="text-3xl font-bold text-center mb-8 dark:text-white">
        Spielleiter Dashboard
      </h1>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <p class="text-center text-lg dark:text-white">
          Das Spiel läuft...
        </p>
        <p class="text-center text-sm text-gray-600 dark:text-gray-400 mt-2">
          (Volle Spielfunktionalität wird noch implementiert)
        </p>
      </div>
    </div>
    """
  end

  defp render_game_over(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <h1 class="text-3xl font-bold text-center mb-8 dark:text-white">
        Spiel fertig!
      </h1>

      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <h2 class="text-2xl font-bold mb-6 text-center dark:text-white">Wer hat gewonnen?</h2>

        <div class="space-y-3">
          <%= for {player, index} <- Enum.with_index(Enum.sort_by(@players, & &1.points, :desc)) do %>
            <div class={[
              "flex items-center justify-between p-4 rounded-lg",
              case index do
                0 -> "bg-yellow-100 dark:bg-yellow-900 border-2 border-yellow-400"
                1 -> "bg-gray-100 dark:bg-gray-700 border-2 border-gray-400"
                2 -> "bg-orange-100 dark:bg-orange-900 border-2 border-orange-400"
                _ -> "bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600"
              end
            ]}>
              <div class="flex items-center gap-4">
                <span class="text-2xl font-bold dark:text-white">{index + 1}.</span>
                <span class="text-3xl">{player.avatar}</span>
              </div>
              <span class="text-xl font-bold dark:text-white">{player.points} Punkte</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
