defmodule MimimiWeb.AvatarLive.Choose do
  @moduledoc """
  Avatar selection LiveView for players joining a game.

  Players use this view to choose their avatar and name before joining a game lobby.
  Validates the invitation code and handles error states gracefully.
  """
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"short_code" => short_code}, session, socket) do
    active_game_id = Map.get(session, "active_game_id")

    if active_game_id do
      case Games.get_game(active_game_id) do
        %{state: state} when state in ["waiting_for_players", "game_running"] ->
          {:ok,
           socket
           |> put_flash(:error, "Du bist bereits in einem aktiven Spiel.")
           |> push_navigate(to: ~p"/")}

        _ ->
          mount_avatar_selection(short_code, socket)
      end
    else
      mount_avatar_selection(short_code, socket)
    end
  end

  defp mount_avatar_selection(short_code, socket) do
    case Games.validate_short_code(short_code) do
      {:ok, game} ->
        if connected?(socket) do
          Games.subscribe_to_game(game.id)
          Games.subscribe_to_active_games()
          # Notify the host that someone is choosing an avatar
          Games.broadcast_to_game(
            game.id,
            {:pending_player_arrived, socket.assigns.current_user.id}
          )
        end

        avatars = Games.list_available_avatars(game.id)

        {:ok,
         socket
         |> assign(:game, game)
         |> assign(:avatars, avatars)
         |> assign(:page_title, "Wähle dein Tier")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Dieser Link geht nicht.")
         |> push_navigate(to: ~p"/")}

      {:error, :expired} ->
        {:ok,
         socket
         |> put_flash(:error, "Dieser Link ist abgelaufen.")
         |> push_navigate(to: ~p"/")}

      {:error, :already_started} ->
        {:ok,
         socket
         |> put_flash(:error, "Das Spiel hat schon angefangen.")
         |> push_navigate(to: ~p"/")}

      {:error, :game_over} ->
        {:ok,
         socket
         |> put_flash(:error, "Das Spiel ist schon fertig.")
         |> push_navigate(to: ~p"/")}

      {:error, :lobby_timeout} ->
        {:ok,
         socket
         |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
         |> push_navigate(to: ~p"/")}

      {:error, :host_disconnected} ->
        {:ok,
         socket
         |> put_flash(:error, "Der Gastgeber hat die Verbindung verloren.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("select_avatar", %{"avatar" => avatar}, socket) do
    game = socket.assigns.game
    user = socket.assigns.current_user

    # Check if avatar is still available
    avatars = Games.list_available_avatars(game.id)

    if Enum.any?(avatars, fn {a, available} -> a == avatar && available end) do
      case Games.create_player(user.id, game.id, %{avatar: avatar, nickname: avatar}) do
        {:ok, _player} ->
          # Notify that pending player is no longer pending (they joined)
          Games.broadcast_to_game(game.id, {:pending_player_left, user.id})
          Games.broadcast_to_game(game.id, :player_joined)
          {:noreply, redirect(socket, to: ~p"/game/#{game.id}/join")}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Dieses Tier ist schon besetzt.")
           |> assign(:avatars, Games.list_available_avatars(game.id))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Dieses Tier ist schon besetzt.")
       |> assign(:avatars, Games.list_available_avatars(game.id))}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Notify that the pending player left the page
    if Map.has_key?(socket.assigns, :game) do
      Games.broadcast_to_game(
        socket.assigns.game.id,
        {:pending_player_left, socket.assigns.current_user.id}
      )
    end

    :ok
  end

  @impl true
  def handle_info(:game_count_changed, socket) do
    {:noreply, assign(socket, :active_games, Games.count_active_games())}
  end

  def handle_info(:player_joined, socket) do
    {:noreply, assign(socket, :avatars, Games.list_available_avatars(socket.assigns.game.id))}
  end

  def handle_info(:lobby_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Das Spiel ist zu Ende. Es hat zu lange gedauert.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(:host_disconnected, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Der Gastgeber hat die Verbindung verloren.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:pending_player_arrived, _user_id}, socket) do
    # No action needed - this is handled in the lobby
    {:noreply, socket}
  end

  def handle_info({:pending_player_left, _user_id}, socket) do
    # No action needed - this is handled in the lobby
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <div class="w-full max-w-3xl">
        <div class="text-center mb-10">
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            Wähle dein Tier
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            Klicke auf ein verfügbares Tier
          </p>
        </div>

        <.glass_card class="p-8">
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4">
            <%= for {avatar, available} <- @avatars do %>
              <button
                type="button"
                phx-click={if available, do: "select_avatar", else: nil}
                phx-value-avatar={avatar}
                disabled={!available}
                class={[
                  "relative aspect-square flex flex-col items-center justify-center rounded-2xl transition-all duration-300 text-5xl sm:text-6xl overflow-hidden group",
                  if(available,
                    do:
                      "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 hover:border-green-400 dark:hover:border-green-500 hover:shadow-lg hover:scale-105 cursor-pointer",
                    else:
                      "bg-gray-100 dark:bg-gray-800 border-2 border-gray-200 dark:border-gray-700 cursor-not-allowed opacity-50"
                  )
                ]}
              >
                <%= if available do %>
                  <div class="absolute inset-0 bg-gradient-to-br from-green-400 to-emerald-400 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                <% end %>
                <span class="relative">{avatar}</span>
                <%= if available do %>
                  <span class="relative text-xs font-semibold text-green-600 dark:text-green-400 mt-2">
                    Frei
                  </span>
                <% else %>
                  <span class="relative text-xs font-semibold text-red-600 dark:text-red-400 mt-2">
                    Besetzt
                  </span>
                  <div class="absolute inset-0 flex items-center justify-center bg-black/20 backdrop-blur-sm">
                    <.icon name="hero-x-mark" class="w-12 h-12 text-red-500" />
                  </div>
                <% end %>
              </button>
            <% end %>
          </div>
        </.glass_card>
      </div>
    </.page_container>
    """
  end
end
