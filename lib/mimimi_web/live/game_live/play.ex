defmodule MimimiWeb.GameLive.Play do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game_with_players(game_id)
    user = socket.assigns.current_user

    # Check if player exists for this game
    player = Games.get_player_by_game_and_user(game_id, user.id)

    socket =
      if player do
        socket = maybe_subscribe_to_game(socket, game_id, game.state, user.id)

        socket
        |> assign(:game, game)
        |> assign(:player, player)
        |> assign(:pending_players, MapSet.new())
        |> assign(:page_title, "Spiel")
      else
        socket
        |> put_flash(:error, "Du bist nicht in diesem Spiel.")
        |> push_navigate(to: ~p"/")
      end

    {:ok, socket, temporary_assigns: []}
  end

  defp maybe_subscribe_to_game(socket, game_id, game_state, user_id) do
    if connected?(socket) do
      Games.subscribe_to_game(game_id)
      Games.subscribe_to_active_games()

      # Monitor the LiveView process for disconnection
      # Only track presence if game is still in waiting state
      if game_state == "waiting_for_players" do
        Phoenix.PubSub.subscribe(Mimimi.PubSub, "player_presence:#{game_id}:#{user_id}")
      end
    end

    socket
  end

  @impl true
  def terminate(_reason, socket) do
    # Only remove player if game is still in waiting state
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
    {:noreply, push_navigate(socket, to: ~p"/games/#{socket.assigns.game.id}/current")}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-3xl">
        <%= if @game.state == "waiting_for_players" do %>
          <%!-- Waiting for game start --%>
          <div class="text-center mb-10">
            <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 mb-4 shadow-lg animate-pulse">
              <span class="text-4xl">⏳</span>
            </div>
            <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
              Warte auf Spielstart...
            </h1>
          </div>

          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <%!-- Player badge --%>
            <div class="text-center mb-8 pb-8 border-b border-gray-200 dark:border-gray-700">
              <div class="inline-flex items-center justify-center w-24 h-24 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 mb-4 shadow-lg animate-pulse">
                <span class="text-7xl">{@player.avatar}</span>
              </div>
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
                  <div class="relative flex flex-col items-center justify-center p-3 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl aspect-square transition-all duration-300 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md overflow-hidden group">
                    <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                    </div>
                    <span class="relative text-6xl">{player.avatar}</span>
                  </div>
                <% end %>
                <%= for _user_id <- @pending_players do %>
                  <div class="relative flex flex-col items-center justify-center p-3 border-2 border-dashed border-purple-400 dark:border-purple-500 rounded-2xl bg-purple-50/50 dark:bg-purple-900/20 backdrop-blur-sm animate-pulse aspect-square">
                    <span class="text-6xl mb-1">❓</span>
                    <span class="text-xs text-center text-purple-600 dark:text-purple-400 font-medium leading-tight">
                      Wählt...
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <%!-- Game running --%>
          <div class="text-center mb-10">
            <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-orange-500 to-red-500 mb-4 shadow-lg">
              <span class="text-4xl">🎯</span>
            </div>
            <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
              Welches Wort ist richtig?
            </h1>
          </div>

          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <div class="text-center py-8">
              <div class="text-6xl mb-4">🎮</div>
              <p class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
                Das Spiel läuft...
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400">
                (Volle Spielfunktionalität wird noch implementiert)
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
