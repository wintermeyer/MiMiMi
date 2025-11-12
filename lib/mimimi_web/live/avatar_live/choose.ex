defmodule MimimiWeb.AvatarLive.Choose do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(%{"invitation_id" => invitation_id}, _session, socket) do
    case Games.validate_invitation(invitation_id) do
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
          {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/current")}

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
    <div class="min-h-screen flex items-center justify-center px-4 py-8">
      <div class="w-full max-w-2xl">
        <h1 class="text-3xl font-bold text-center mb-8 dark:text-white">
          Wähle dein Tier
        </h1>

        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
          <%= for {avatar, available} <- @avatars do %>
            <button
              type="button"
              phx-click={if available, do: "select_avatar", else: nil}
              phx-value-avatar={avatar}
              disabled={!available}
              class={[
                "relative aspect-square flex flex-col items-center justify-center rounded-lg border-2 transition-all text-4xl sm:text-5xl md:text-6xl",
                if(available,
                  do:
                    "border-gray-300 dark:border-gray-600 hover:border-purple-500 hover:bg-purple-50 dark:hover:bg-purple-900 cursor-pointer",
                  else:
                    "border-gray-200 dark:border-gray-700 bg-gray-100 dark:bg-gray-800 cursor-not-allowed opacity-50"
                )
              ]}
            >
              <span>{avatar}</span>
              <%= if available do %>
                <span class="text-sm font-medium text-green-600 dark:text-green-400 mt-2">Frei</span>
              <% else %>
                <span class="text-sm font-medium text-red-600 dark:text-red-400 mt-2">Besetzt</span>
                <div class="absolute inset-0 flex items-center justify-center">
                  <.icon name="hero-x-mark" class="w-16 h-16 text-red-500" />
                </div>
              <% end %>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
