defmodule MimimiWeb.HomeLive.Index do
  @moduledoc """
  Home page LiveView for creating new games and joining existing ones.

  This LiveView provides:
  - Game creation form with customizable settings (grid size, rounds, word types)
  - Short code input for joining existing games
  - Real-time display of active games count
  - Validation of game settings against available words
  """
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Games.subscribe_to_active_games()
    end

    active_game_id = Map.get(session, "active_game_id")
    handle_active_game(socket, active_game_id, session)
  end

  defp handle_active_game(socket, nil, session), do: mount_home_page(socket, session)

  defp handle_active_game(socket, active_game_id, session) do
    case Games.get_game(active_game_id) do
      %{state: state} = game when state in ["waiting_for_players", "game_running"] ->
        redirect_to_active_game(socket, game, session)

      _ ->
        mount_home_page(socket, session)
    end
  end

  defp redirect_to_active_game(socket, game, session) do
    user_id = socket.assigns.current_user.id
    player = Games.get_player_by_game_and_user(game.id, user_id)
    is_host = game.host_user_id == user_id

    cond do
      is_host -> {:ok, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}
      player -> {:ok, push_navigate(socket, to: ~p"/games/#{game.id}/current")}
      true -> mount_home_page(socket, session)
    end
  end

  defp mount_home_page(socket, _session) do
    has_waiting_games = has_waiting_games?()

    initial_params = %{
      "rounds_count" => "3",
      "clues_interval" => "9",
      "grid_size" => "9",
      "word_types" => ["Noun", "Verb", "Adjective", "Adverb", "Other"]
    }

    {:ok,
     socket
     |> assign(:form, to_form(initial_params, as: :game))
     |> assign(:invite_form, to_form(%{"code" => ""}, as: :invite))
     |> assign(:invite_error, nil)
     |> assign(:has_waiting_games, has_waiting_games)
     |> assign(:page_title, "MiMiMi")
     |> validate_words_availability(initial_params)}
  end

  @impl true
  def handle_info(:game_count_changed, socket) do
    has_waiting_games = has_waiting_games?()
    {:noreply, assign(socket, :has_waiting_games, has_waiting_games)}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(game_params, as: :game))
     |> validate_words_availability(game_params)}
  end

  @impl true
  def handle_event("validate_invite", %{"invite" => invite_params}, socket) do
    # Clean up the code - remove spaces and keep only digits
    code = String.replace(invite_params["code"] || "", ~r/[^\d]/, "")
    cleaned_params = %{"code" => code}

    {:noreply,
     socket
     |> assign(:invite_form, to_form(cleaned_params, as: :invite))
     |> assign(:invite_error, nil)}
  end

  @impl true
  def handle_event("join_game", %{"invite" => %{"code" => code}}, socket) do
    cleaned_code = String.replace(code, ~r/[^\d]/, "")

    with :ok <- validate_code_presence(cleaned_code),
         :ok <- validate_code_length(cleaned_code),
         {:ok, _game} <- Games.validate_short_code(cleaned_code) do
      {:noreply, push_navigate(socket, to: ~p"/#{cleaned_code}")}
    else
      {:error, error_message} ->
        {:noreply, assign_invite_error(socket, cleaned_code, error_message)}
    end
  end

  @impl true
  def handle_event("stop_modal_propagation", _params, socket) do
    # Prevent event from bubbling up to details/summary toggle
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"game" => game_params}, socket) do
    rounds_count = String.to_integer(game_params["rounds_count"] || "3")
    clues_interval = String.to_integer(game_params["clues_interval"] || "9")
    grid_size = String.to_integer(game_params["grid_size"] || "9")
    word_types = Map.get(game_params, "word_types", ["Noun"])

    case Games.create_game(socket.assigns.current_user.id, %{
           rounds_count: rounds_count,
           clues_interval: clues_interval,
           grid_size: grid_size,
           word_types: word_types
         }) do
      {:ok, game} ->
        # Redirect to controller route that sets the host token cookie
        {:noreply, redirect(socket, to: ~p"/game/#{game.id}/set-host-token")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Fehler beim Erstellen des Spiels")
         |> assign(:form, to_form(game_params, as: :game))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container>
      <div class="w-full max-w-md space-y-6">
        <div class="text-center">
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            MiMiMi
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            Wörter-Ratespiel
          </p>
        </div>

        <%= if @has_waiting_games do %>
          <.render_join_game_section form={@invite_form} error={@invite_error} />
          <.divider_with_text text="oder" />
        <% end %>

        <.render_create_game_section
          form={@form}
          words_error={@words_error}
          can_create_game={@can_create_game}
        />
      </div>
    </.page_container>
    """
  end

  defp render_join_game_section(assigns) do
    ~H"""
    <.glass_card class="p-8">
      <div class="text-center mb-6">
        <.gradient_icon_badge icon="🎯" gradient="from-green-500 to-emerald-500" />
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-1">
          Spiel beitreten
        </h2>
        <p class="text-gray-600 dark:text-gray-400 text-sm">
          Gib deinen Einladungscode ein
        </p>
      </div>

      <.form
        for={@form}
        id="join-game-form"
        phx-change="validate_invite"
        phx-submit="join_game"
        class="space-y-4"
      >
        <div class="space-y-2">
          <.glass_input
            name="invite[code]"
            value={@form[:code].value || ""}
            placeholder="123456"
            gradient="from-green-500 to-emerald-500"
            maxlength="6"
            inputmode="numeric"
            pattern="[0-9]*"
            autocomplete="off"
            class="text-center text-2xl font-bold tracking-widest py-4 focus:border-green-500 dark:focus:border-green-400 focus:ring-green-100 dark:focus:ring-green-900/30"
          />

          <.error_banner :if={@error} message={@error} />
        </div>

        <.gradient_button
          type="submit"
          gradient="from-green-600 via-green-500 to-emerald-500"
          hover_gradient="from-green-700 via-green-600 to-emerald-600"
          shadow_color="shadow-green-500/30"
          hover_shadow_color="shadow-green-500/40"
          class="text-lg"
        >
          Spiel beitreten
        </.gradient_button>
      </.form>
    </.glass_card>
    """
  end

  defp render_create_game_section(assigns) do
    ~H"""
    <.glass_card class="p-8">
      <div class="text-center mb-6">
        <.gradient_icon_badge icon="✨" />
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-1">
          Neues Spiel
        </h2>
        <p class="text-gray-600 dark:text-gray-400 text-sm">
          Erstelle ein neues Spiel
        </p>
      </div>

      <.form
        for={@form}
        id="game-setup-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-7"
      >
        <.render_rounds_and_time_inputs form={@form} />
        <.render_word_types_selector form={@form} />
        <.render_grid_size_selector form={@form} />

        <.error_banner :if={@words_error} message={@words_error} class="items-start" />

        <.gradient_button
          type="submit"
          disabled={!@can_create_game}
          class={[
            "text-lg",
            !@can_create_game &&
              "!bg-gray-300 dark:!bg-gray-700 !text-gray-500 !cursor-not-allowed !opacity-60 !shadow-none hover:!scale-100"
          ]}
        >
          Einladungslink generieren
        </.gradient_button>
      </.form>
    </.glass_card>
    """
  end

  defp render_rounds_and_time_inputs(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-3">
      <div class="space-y-2">
        <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
          Wie viele Runden?
        </label>
        <.glass_input
          type="number"
          name="game[rounds_count]"
          value={@form[:rounds_count].value || 3}
          min="1"
          max="20"
          class="text-lg"
        />
      </div>

      <div class="space-y-2">
        <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
          Zeit für Hinweise
        </label>
        <div class="relative group">
          <div class="absolute inset-0 bg-gradient-to-r from-blue-500 to-cyan-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300">
          </div>
          <select
            name="game[clues_interval]"
            class="relative w-full text-lg px-4 py-3.5 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl focus:border-purple-500 dark:focus:border-purple-400 focus:ring-4 focus:ring-purple-100 dark:focus:ring-purple-900/30 transition-all duration-200 dark:text-white outline-none cursor-pointer appearance-none"
          >
            <option value="3" selected={@form[:clues_interval].value == "3"}>3 Sek.</option>
            <option value="6" selected={@form[:clues_interval].value == "6"}>6 Sek.</option>
            <option
              value="9"
              selected={@form[:clues_interval].value == "9" || !@form[:clues_interval].value}
            >
              9 Sek.
            </option>
            <option value="10" selected={@form[:clues_interval].value == "10"}>10 Sek.</option>
            <option value="12" selected={@form[:clues_interval].value == "12"}>12 Sek.</option>
            <option value="15" selected={@form[:clues_interval].value == "15"}>15 Sek.</option>
            <option value="20" selected={@form[:clues_interval].value == "20"}>20 Sek.</option>
            <option value="30" selected={@form[:clues_interval].value == "30"}>30 Sek.</option>
            <option value="45" selected={@form[:clues_interval].value == "45"}>45 Sek.</option>
            <option value="60" selected={@form[:clues_interval].value == "60"}>60 Sek.</option>
          </select>
          <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-gray-500">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7">
              </path>
            </svg>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_word_types_selector(assigns) do
    ~H"""
    <details class="group/details" id="word-types-details">
      <summary class="flex items-center justify-between cursor-pointer list-none px-4 py-3 rounded-xl bg-gray-50 dark:bg-gray-900/50 hover:bg-gray-100 dark:hover:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 transition-all duration-200">
        <span class="text-sm font-semibold text-gray-700 dark:text-gray-300">
          Wortarten (optional)
        </span>
        <svg
          class="w-5 h-5 text-gray-500 transition-transform duration-200 group-open/details:rotate-180"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7">
          </path>
        </svg>
      </summary>
      <div class="mt-3 space-y-3" onclick="event.stopPropagation()">
        <div class="grid grid-cols-2 gap-3">
          <.checkbox_button
            id="word-type-noun"
            name="game[word_types][]"
            value="Noun"
            checked={"Noun" in (@form[:word_types].value || [])}
            label="Nomen"
          />

          <.checkbox_button
            id="word-type-verb"
            name="game[word_types][]"
            value="Verb"
            checked={"Verb" in (@form[:word_types].value || [])}
            label="Verb"
            gradient="from-blue-500 to-cyan-500"
          />

          <.checkbox_button
            id="word-type-adjective"
            name="game[word_types][]"
            value="Adjective"
            checked={"Adjective" in (@form[:word_types].value || [])}
            label="Adjektiv"
            gradient="from-green-500 to-emerald-500"
          />

          <.checkbox_button
            id="word-type-adverb"
            name="game[word_types][]"
            value="Adverb"
            checked={"Adverb" in (@form[:word_types].value || [])}
            label="Adverb"
            gradient="from-yellow-500 to-orange-500"
          />

          <.checkbox_button
            id="word-type-other"
            name="game[word_types][]"
            value="Other"
            checked={"Other" in (@form[:word_types].value || [])}
            label="Andere"
            gradient="from-pink-500 to-rose-500"
          />
        </div>
      </div>
    </details>
    """
  end

  defp render_grid_size_selector(assigns) do
    ~H"""
    <div class="space-y-3">
      <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
        Spielfeld Größe
      </label>
      <div class="grid grid-cols-2 gap-3">
        <.radio_button
          name="game[grid_size]"
          value="2"
          checked={@form[:grid_size].value == "2"}
          label="2x1"
        />

        <.radio_button
          name="game[grid_size]"
          value="4"
          checked={@form[:grid_size].value == "4"}
          label="2x2"
          gradient="from-blue-500 to-cyan-500"
        />

        <.radio_button
          name="game[grid_size]"
          value="9"
          checked={@form[:grid_size].value == "9" || !@form[:grid_size].value}
          label="3x3"
          gradient="from-indigo-500 to-purple-500"
        />

        <.radio_button
          name="game[grid_size]"
          value="16"
          checked={@form[:grid_size].value == "16"}
          label="4x4"
          gradient="from-orange-500 to-red-500"
        />
      </div>
    </div>
    """
  end

  defp validate_code_presence(""), do: {:error, "Bitte gib einen Einladungscode ein"}
  defp validate_code_presence(_code), do: :ok

  defp validate_code_length(code) do
    if String.length(code) == 6 do
      :ok
    else
      {:error, "Der Code muss 6 Ziffern haben"}
    end
  end

  defp assign_invite_error(socket, code, error_atom) when is_atom(error_atom) do
    error_message = game_error_message(error_atom)
    assign_invite_error(socket, code, error_message)
  end

  defp assign_invite_error(socket, code, error_message) when is_binary(error_message) do
    socket
    |> assign(:invite_error, error_message)
    |> assign(:invite_form, to_form(%{"code" => code}, as: :invite))
  end

  defp game_error_message(error_atom) do
    MimimiWeb.GameHelpers.invitation_error_message(error_atom)
  end

  defp has_waiting_games? do
    Games.count_waiting_games() > 0
  end

  defp validate_words_availability(socket, game_params) do
    rounds_count = parse_integer(game_params["rounds_count"], 3)
    grid_size = parse_integer(game_params["grid_size"], 9)
    word_types = Map.get(game_params, "word_types", [])

    word_types =
      case word_types do
        types when is_list(types) -> types
        _ -> []
      end

    if word_types == [] do
      socket
      |> assign(
        :words_error,
        "Bitte wähle mindestens eine Wortart aus, um ein Spiel zu erstellen."
      )
      |> assign(:can_create_game, false)
    else
      case Games.validate_word_availability(%{
             word_types: word_types,
             rounds_count: rounds_count,
             grid_size: grid_size
           }) do
        {:ok, _stats} ->
          socket
          |> assign(:words_error, nil)
          |> assign(:can_create_game, true)

        {:error, :insufficient_target_words} ->
          socket
          |> assign(
            :words_error,
            "Nicht genug Wörter mit ausreichend Hinweisen für die ausgewählten Wortarten verfügbar. Bitte wähle andere Wortarten oder reduziere die Anzahl der Runden."
          )
          |> assign(:can_create_game, false)

        {:error, :insufficient_distractor_words} ->
          socket
          |> assign(
            :words_error,
            "Nicht genug Wörter für die ausgewählte Spielfeldgröße verfügbar. Bitte wähle eine kleinere Spielfeldgröße oder andere Wortarten."
          )
          |> assign(:can_create_game, false)
      end
    end
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(value, _default) when is_integer(value), do: value
end
