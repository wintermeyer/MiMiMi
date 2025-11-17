defmodule MimimiWeb.GameLive.Play do
  use MimimiWeb, :live_view
  alias Mimimi.Games
  alias Mimimi.WortSchule
  require Logger

  @doc """
  The main gameplay LiveView for players.
  Handles keyword reveals, word guessing, and round progression.
  """

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game_with_players(game_id)
    user = socket.assigns.current_user

    # Check if player exists for this game
    player = Games.get_player_by_game_and_user(game_id, user.id)

    socket =
      if player do
        socket = maybe_subscribe_to_game(socket, game_id, game.state, user.id)

        socket =
          socket
          |> assign(:game, game)
          |> assign(:player, player)
          |> assign(:pending_players, MapSet.new())
          |> assign(:page_title, "Spiel")

        # Load current round if game is running
        if game.state == "game_running" do
          load_current_round(socket, game_id)
        else
          socket
        end
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

      if game_state == "waiting_for_players" do
        Phoenix.PubSub.subscribe(Mimimi.PubSub, "player_presence:#{game_id}:#{user_id}")
      end
    end

    socket
  end

  defp load_current_round(socket, game_id) do
    case Games.get_current_round(game_id) do
      nil ->
        # No current round - should not happen during game_running
        socket
        |> put_flash(:error, "Keine aktuelle Runde gefunden.")
        |> push_navigate(to: ~p"/")

      round ->
        # Load possible words with images from WortSchule
        possible_word_ids = round.possible_words_ids
        possible_words = fetch_words_with_images(possible_word_ids)

        # Load keywords for this round
        keyword_ids = round.keyword_ids
        keywords = fetch_keywords(keyword_ids)

        # Start the game server timer if not already running
        if socket.assigns.game.state == "game_running" && round.state == "playing" do
          Games.start_game_server(game_id, round.id, socket.assigns.game.clues_interval)
        end

        socket
        |> assign(:current_round, round)
        |> assign(:possible_words, possible_words)
        |> assign(:keywords, keywords)
        |> assign(:keywords_revealed, 1)
        |> assign(:time_elapsed, 0)
        |> assign(:has_picked, false)
        |> assign(:pick_result, nil)
        |> assign(:waiting_for_others, false)
        |> assign(:players_picked, MapSet.new())
    end
  end

  defp fetch_words_with_images(word_ids) do
    Enum.map(word_ids, fn word_id ->
      case WortSchule.get_complete_word(word_id) do
        {:ok, word_data} ->
          %{
            id: word_data.id,
            name: word_data.name,
            image_url: word_data.image_url
          }

        {:error, :not_found} ->
          %{
            id: word_id,
            name: "?",
            image_url: nil
          }
      end
    end)
  end

  defp fetch_keywords(keyword_ids) do
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
  def terminate(_reason, socket) do
    # Stop the game server when leaving gameplay
    if socket.assigns[:game] && socket.assigns.game.state == "game_running" do
      Games.stop_game_server(socket.assigns.game.id)
    end

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
    # Reload the game to get the updated state
    game = Games.get_game_with_players(socket.assigns.game.id)
    socket = assign(socket, :game, game)
    {:noreply, load_current_round(socket, game.id)}
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

  def handle_info({:keyword_revealed, revealed_count, time_elapsed}, socket) do
    keywords_shown = min(revealed_count, length(socket.assigns.keywords))
    revealed_keywords = Enum.take(socket.assigns.keywords, keywords_shown)

    {:noreply,
     socket
     |> assign(:keywords_revealed, keywords_shown)
     |> assign(:time_elapsed, time_elapsed)
     |> assign(:revealed_keywords, revealed_keywords)}
  end

  def handle_info(:show_feedback_and_advance, socket) do
    game = socket.assigns.game
    round = socket.assigns.current_round

    Games.finish_round(round)

    case Games.advance_to_next_round(game.id) do
      {:ok, _next_round} ->
        Games.broadcast_to_game(game.id, :round_started)
        {:noreply, load_current_round(socket, game.id)}

      {:error, :no_more_rounds} ->
        Games.update_game_state(game, "game_over")
        Games.broadcast_to_game(game.id, :game_finished)
        Games.stop_game_server(game.id)
        {:noreply, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}
    end
  end

  def handle_info({:player_picked, _player_id, _is_correct}, socket) do
    all_picked = Games.all_players_picked?(socket.assigns.current_round.id)
    {:noreply, assign(socket, :waiting_for_others, not all_picked)}
  end

  def handle_info(:round_started, socket) do
    {:noreply, load_current_round(socket, socket.assigns.game.id)}
  end

  @impl true
  def handle_event("guess_word", %{"word_id" => word_id_str}, socket) do
    word_id = String.to_integer(word_id_str)
    round = socket.assigns.current_round
    player = socket.assigns.player
    game = socket.assigns.game

    is_correct = word_id == round.word_id

    points = if is_correct, do: Games.calculate_points(socket.assigns.keywords_revealed), else: 0

    case Games.create_pick(round.id, player.id, %{
           is_correct: is_correct,
           keywords_shown: socket.assigns.keywords_revealed,
           time: socket.assigns.time_elapsed
         }) do
      {:ok, _pick} ->
        if is_correct do
          Games.add_points(player, points)
        end

        Games.broadcast_to_game(game.id, {:player_picked, player.id, is_correct})

        all_picked = Games.all_players_picked?(round.id)

        socket =
          socket
          |> assign(:has_picked, true)
          |> assign(:pick_result, if(is_correct, do: :correct, else: :wrong))
          |> assign(:points_earned, points)

        socket =
          if all_picked do
            assign(socket, :waiting_for_others, false)
          else
            assign(socket, :waiting_for_others, true)
          end

        Process.send_after(self(), :show_feedback_and_advance, 3000)

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
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-4xl">
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
          <%= if @current_round do %>
            <div class="text-center mb-8">
              <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-orange-500 to-red-500 mb-4 shadow-lg">
                <span class="text-4xl">🎯</span>
              </div>
              <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
                Runde {@current_round.position} von {@game.rounds_count}
              </h1>
              <p class="text-lg text-gray-600 dark:text-gray-400">
                Welches Wort ist richtig?
              </p>
            </div>

            <%!-- Keywords revealed --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-8">
              <div class="flex flex-wrap justify-center gap-3">
                <%= for {keyword, index} <- Enum.with_index(@keywords, 1) do %>
                  <% is_revealed = index <= @keywords_revealed
                  # The current keyword is the next one to be revealed (not yet revealed)
                  is_current = index == @keywords_revealed + 1
                  # Calculate progress for the current keyword
                  progress_percent =
                    if is_current && @time_elapsed > 0 do
                      # Time since the last keyword was revealed
                      time_in_interval = rem(@time_elapsed, @game.clues_interval)
                      # If time_in_interval is 0, we just revealed this keyword, so it's 100%
                      if time_in_interval == 0 do
                        100
                      else
                        (time_in_interval / @game.clues_interval * 100) |> round()
                      end
                    else
                      0
                    end %>
                  <div class={[
                    "relative overflow-hidden px-4 py-2 rounded-2xl font-semibold transition-all duration-300 transform",
                    cond do
                      is_revealed ->
                        "bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-lg scale-100"

                      is_current ->
                        "bg-gray-300 dark:bg-gray-700 text-gray-900 dark:text-gray-100 scale-100"

                      true ->
                        "bg-gray-300 dark:bg-gray-700 text-gray-400 dark:text-gray-500 scale-95 opacity-60"
                    end
                  ]}>
                    <%= if is_current && progress_percent > 0 do %>
                      <%!-- Progress bar for current keyword --%>
                      <div
                        class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 opacity-30"
                        style={"width: #{progress_percent}%; transition: width 0.5s linear;"}
                      >
                      </div>
                    <% end %>
                    <span class="relative z-10">
                      {if is_revealed, do: keyword.name, else: "???"}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Word grid --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
              <%= if @has_picked do %>
                <%!-- Feedback overlay --%>
                <div class="text-center py-12">
                  <div class={[
                    "inline-flex items-center justify-center w-24 h-24 rounded-full mb-6 shadow-lg",
                    if(@pick_result == :correct,
                      do: "bg-gradient-to-br from-green-500 to-emerald-500",
                      else: "bg-gradient-to-br from-red-500 to-orange-500"
                    )
                  ]}>
                    <span class="text-6xl">
                      {if @pick_result == :correct, do: "✅", else: "❌"}
                    </span>
                  </div>

                  <h2 class="text-3xl font-bold mb-2">
                    {if @pick_result == :correct, do: "Richtig!", else: "Leider falsch"}
                  </h2>

                  <%= if @pick_result == :correct do %>
                    <p class="text-xl text-green-600 dark:text-green-400 font-semibold mb-4">
                      +{@points_earned} Punkte!
                    </p>
                  <% end %>

                  <p class="text-gray-600 dark:text-gray-400 mb-6">
                    {if @waiting_for_others,
                      do: "Warte auf andere Spieler...",
                      else: "Nächste Runde beginnt..."}
                  </p>

                  <%= if @waiting_for_others do %>
                    <div class="flex justify-center">
                      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-purple-600 dark:border-purple-400">
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <%!-- Word selection grid --%>
                <div class={[
                  "grid gap-4",
                  grid_class(@game.grid_size)
                ]}>
                  <%= for word <- @possible_words do %>
                    <button
                      phx-click="guess_word"
                      phx-value-word_id={word.id}
                      disabled={@has_picked}
                      class={[
                        "relative w-full aspect-square rounded-2xl overflow-hidden group transition-all duration-300",
                        "border-2 border-gray-200 dark:border-gray-700",
                        "hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-lg",
                        "disabled:opacity-50 disabled:cursor-not-allowed",
                        "bg-white dark:bg-gray-900"
                      ]}
                    >
                      <%!-- Gradient overlay on hover --%>
                      <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                      </div>

                      <%!-- Image --%>
                      <%= if word.image_url do %>
                        <img
                          src={word.image_url}
                          alt={word.name}
                          class="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                        />
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
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-12">
              <div class="text-6xl mb-4">⚠️</div>
              <p class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
                Keine Runde verfügbar
              </p>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp grid_class(2), do: "grid-cols-2"
  defp grid_class(4), do: "grid-cols-2"
  defp grid_class(9), do: "grid-cols-3"
  defp grid_class(16), do: "grid-cols-4"
  defp grid_class(_), do: "grid-cols-3"
end
