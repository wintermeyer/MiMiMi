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
    <div class="min-h-screen flex items-center justify-center px-4 py-8">
      <div class="w-full max-w-2xl">
        <%= if @game.state == "waiting_for_players" do %>
          <div class="text-center">
            <h1 class="text-3xl font-bold mb-8 dark:text-white">
              Warte auf Spielstart...
            </h1>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8">
              <div class="animate-pulse mb-6">
                <div class="text-6xl mb-4">{@player.avatar}</div>
                <p class="text-lg font-medium dark:text-white">Du bist dabei!</p>
              </div>

              <h2 class="text-xl font-bold mb-4 dark:text-white">
                Wer spielt mit?
                <%= if MapSet.size(@pending_players) > 0 do %>
                  <span class="text-sm font-normal text-purple-600 dark:text-purple-400">
                    (+ {MapSet.size(@pending_players)} wählt Avatar...)
                  </span>
                <% end %>
              </h2>
              <div class="grid grid-cols-3 sm:grid-cols-4 gap-3">
                <%= for player <- @game.players do %>
                  <div class="flex flex-col items-center p-2">
                    <span class="text-7xl sm:text-8xl">{player.avatar}</span>
                  </div>
                <% end %>
                <%= for _user_id <- @pending_players do %>
                  <div class="flex flex-col items-center p-2 border-2 border-dashed border-purple-400 dark:border-purple-500 rounded-lg bg-purple-50 dark:bg-purple-900/20 animate-pulse">
                    <span class="text-7xl sm:text-8xl">❓</span>
                    <span class="text-xs text-center text-purple-600 dark:text-purple-400 font-medium">
                      Wählt Avatar...
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center">
            <h1 class="text-3xl font-bold mb-8 dark:text-white">
              Welches Wort ist richtig?
            </h1>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8">
              <p class="text-lg dark:text-white">
                Das Spiel läuft...
              </p>
              <p class="text-sm text-gray-600 dark:text-gray-400 mt-2">
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
