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
  require Logger

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game_with_players(game_id)
    user = socket.assigns.current_user

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

    socket =
      socket
      |> assign(:game, game)
      |> assign(:player, player)
      |> assign(:pending_players, MapSet.new())
      |> assign(:page_title, "Spiel")
      |> assign(:rounds_loading, false)

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
    # Game has started but rounds are being generated in background
    # Reload the game to get the updated state and show "preparing..." message
    game = Games.get_game_with_players(socket.assigns.game.id)
    socket = assign(socket, :game, game)
    socket = assign(socket, :rounds_loading, true)
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
    # Schedule the round advancement after showing feedback
    # Only one :all_players_picked message is sent per round, so this prevents
    # multiple advancement messages from being scheduled
    Process.send_after(self(), :show_feedback_and_advance, 3000)
    {:noreply, socket}
  end

  def handle_info(:round_started, socket) do
    # Rounds are ready, load the first/next round
    socket =
      socket
      |> assign(:rounds_loading, false)
      |> load_current_round(socket.assigns.game.id)

    {:noreply, socket}
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

    points = if is_correct, do: Games.calculate_points(socket.assigns.keywords_revealed), else: 0

    case Games.create_pick(round.id, player.id, %{
           is_correct: is_correct,
           keywords_shown: socket.assigns.keywords_revealed,
           time: socket.assigns.time_elapsed,
           word_id: word_id
         }) do
      {:ok, {_pick, all_picked}} ->
        if is_correct do
          # Reload player to get current points before adding new points
          fresh_player = Mimimi.Repo.get!(Games.Player, player.id)
          Games.add_points(fresh_player, points)
        end

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
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900 relative">
      <%!-- Player Avatar Indicator --%>
      <div class="fixed top-2 right-2 sm:top-4 sm:right-4 z-50">
        <div class="backdrop-blur-xl bg-white/95 dark:bg-gray-800/95 rounded-2xl p-3 sm:p-4 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
          <div class="flex flex-col items-center gap-1">
            <span class="text-4xl sm:text-5xl">{@player.avatar}</span>
            <%= if @game.state == "game_running" && Map.has_key?(assigns, :leaderboard) do %>
              <% current_player_data =
                Enum.find(@leaderboard, fn p -> p.id == @player.id end) || @player %>
              <span class="text-xs sm:text-sm font-bold text-purple-600 dark:text-purple-400 tabular-nums">
                {current_player_data.points}
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <div class="w-full max-w-4xl">
        <%= if @game.state == "waiting_for_players" do %>
          <%!-- Waiting for game start --%>
          <div class="text-center mb-10">
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
          <%= if Map.get(assigns, :rounds_loading, false) do %>
            <%!-- Loading state while rounds are being generated --%>
            <div class="text-center mb-10">
              <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
                Runden werden vorbereitet...
              </h1>
              <p class="text-gray-500 dark:text-gray-400 text-sm">
                Einen Moment bitte
              </p>
            </div>

            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
              <div class="flex justify-center">
                <div class="animate-spin rounded-full h-16 w-16 border-b-4 border-purple-500"></div>
              </div>
            </div>
          <% else %>
            <%= if Map.has_key?(assigns, :current_round) && @current_round do %>
              <div class="text-center mb-8">
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

              <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
                <%= if @has_picked do %>
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
                          {if @pick_result == :correct,
                            do: "Du hast richtig getippt:",
                            else: "Richtige Antwort:"}
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
                    <% end %>

                    <%= if @waiting_for_others do %>
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
                                do:
                                  "bg-green-100 dark:bg-green-900/30 border-2 border-green-500 dark:border-green-400",
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
                    <% else %>
                      <p class="text-gray-600 dark:text-gray-400 mb-6">
                        Nächste Runde beginnt...
                      </p>
                    <% end %>
                  </div>
                <% else %>
                  <%!-- Word selection grid --%>
                  <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">
                    Bilder zur Auswahl
                  </h2>
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
                          "relative w-full aspect-square rounded-2xl overflow-hidden",
                          "border-2 border-gray-200 dark:border-gray-700",
                          "disabled:opacity-50 disabled:cursor-not-allowed",
                          "bg-white dark:bg-gray-900"
                        ]}
                      >
                        <%!-- Image --%>
                        <%= if word.image_url do %>
                          <img
                            src={word.image_url}
                            alt={word.name}
                            class="w-full h-full object-cover"
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
