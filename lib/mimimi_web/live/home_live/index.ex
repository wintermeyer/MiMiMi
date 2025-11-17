defmodule MimimiWeb.HomeLive.Index do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Games.subscribe_to_active_games()
    end

    active_game_id = Map.get(session, "active_game_id")

    if active_game_id do
      case Games.get_game(active_game_id) do
        %{state: state} = game when state in ["waiting_for_players", "game_running"] ->
          player = Games.get_player_by_game_and_user(game.id, socket.assigns.current_user.id)
          is_host = game.host_user_id == socket.assigns.current_user.id

          cond do
            is_host ->
              {:ok, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}

            player ->
              {:ok, push_navigate(socket, to: ~p"/games/#{game.id}/current")}

            true ->
              mount_home_page(socket, session)
          end

        _ ->
          mount_home_page(socket, session)
      end
    else
      mount_home_page(socket, session)
    end
  end

  defp mount_home_page(socket, _session) do
    has_waiting_games = has_waiting_games?()

    {:ok,
     socket
     |> assign(
       :form,
       to_form(%{
         "rounds_count" => "3",
         "clues_interval" => "9",
         "grid_size" => "9",
         "word_types" => ["Noun"]
       })
     )
     |> assign(:invite_form, to_form(%{"code" => ""}, as: :invite))
     |> assign(:invite_error, nil)
     |> assign(:has_waiting_games, has_waiting_games)
     |> assign(:page_title, "MiMiMi")}
  end

  @impl true
  def handle_info(:game_count_changed, socket) do
    has_waiting_games = has_waiting_games?()
    {:noreply, assign(socket, :has_waiting_games, has_waiting_games)}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    {:noreply, assign(socket, :form, to_form(game_params, as: :game))}
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
    <div class="min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-md space-y-6">
        <%!-- Main Header --%>
        <div class="text-center">
          <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 mb-4 shadow-lg">
            <span class="text-4xl">🎮</span>
          </div>
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            MiMiMi
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            Wörter-Ratespiel
          </p>
        </div>
        <%!-- JOIN GAME SECTION - Only show when there are games waiting for players --%>
        <%= if @has_waiting_games do %>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <div class="text-center mb-6">
              <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-gradient-to-br from-green-500 to-emerald-500 mb-3 shadow-lg">
                <span class="text-3xl">🎯</span>
              </div>
              <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-1">
                Spiel beitreten
              </h2>
              <p class="text-gray-600 dark:text-gray-400 text-sm">
                Gib deinen Einladungscode ein
              </p>
            </div>

            <.form
              for={@invite_form}
              id="join-game-form"
              phx-change="validate_invite"
              phx-submit="join_game"
              class="space-y-4"
            >
              <div class="space-y-2">
                <div class="relative group">
                  <div class="absolute inset-0 bg-gradient-to-r from-green-500 to-emerald-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <input
                    type="text"
                    name="invite[code]"
                    value={@invite_form[:code].value || ""}
                    placeholder="123456"
                    maxlength="6"
                    inputmode="numeric"
                    pattern="[0-9]*"
                    autocomplete="off"
                    class="relative w-full text-center text-2xl font-bold tracking-widest px-4 py-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl focus:border-green-500 dark:focus:border-green-400 focus:ring-4 focus:ring-green-100 dark:focus:ring-green-900/30 transition-all duration-200 dark:text-white outline-none"
                  />
                </div>

                <%= if @invite_error do %>
                  <div class="flex items-center gap-2 px-4 py-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl">
                    <span class="text-lg">⚠️</span>
                    <p class="text-sm text-red-600 dark:text-red-400 font-medium">
                      {@invite_error}
                    </p>
                  </div>
                <% end %>
              </div>

              <button
                type="submit"
                class="relative w-full text-lg font-semibold py-4 bg-gradient-to-r from-green-600 via-green-500 to-emerald-500 hover:from-green-700 hover:via-green-600 hover:to-emerald-600 text-white rounded-2xl shadow-xl shadow-green-500/30 hover:shadow-2xl hover:shadow-green-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 overflow-hidden group"
              >
                <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
                </div>
                <span class="relative">Spiel beitreten</span>
              </button>
            </.form>
          </div>
          <%!-- DIVIDER --%>
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t-2 border-gray-200 dark:border-gray-700"></div>
            </div>
            <div class="relative flex justify-center">
              <span class="px-4 text-sm font-semibold text-gray-500 dark:text-gray-400 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
                oder
              </span>
            </div>
          </div>
        <% end %>
        <%!-- CREATE GAME SECTION --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
          <div class="text-center mb-6">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 mb-3 shadow-lg">
              <span class="text-3xl">✨</span>
            </div>
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
            <%!-- Rounds Input --%>
            <div class="space-y-2">
              <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
                Wie viele Runden?
              </label>
              <div class="relative group">
                <div class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                </div>
                <input
                  type="number"
                  name="game[rounds_count]"
                  value={@form[:rounds_count].value || 3}
                  min="1"
                  max="20"
                  class="relative w-full text-lg px-4 py-3.5 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl focus:border-purple-500 dark:focus:border-purple-400 focus:ring-4 focus:ring-purple-100 dark:focus:ring-purple-900/30 transition-all duration-200 dark:text-white outline-none"
                />
              </div>
            </div>

            <%!-- Time Select --%>
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
                  <option value="3" selected={@form[:clues_interval].value == "3"}>3 Sekunden</option>
                  <option value="6" selected={@form[:clues_interval].value == "6"}>6 Sekunden</option>
                  <option
                    value="9"
                    selected={@form[:clues_interval].value == "9" || !@form[:clues_interval].value}
                  >
                    9 Sekunden
                  </option>
                  <option value="10" selected={@form[:clues_interval].value == "10"}>
                    10 Sekunden
                  </option>
                  <option value="12" selected={@form[:clues_interval].value == "12"}>
                    12 Sekunden
                  </option>
                  <option value="15" selected={@form[:clues_interval].value == "15"}>
                    15 Sekunden
                  </option>
                  <option value="20" selected={@form[:clues_interval].value == "20"}>
                    20 Sekunden
                  </option>
                  <option value="30" selected={@form[:clues_interval].value == "30"}>
                    30 Sekunden
                  </option>
                  <option value="45" selected={@form[:clues_interval].value == "45"}>
                    45 Sekunden
                  </option>
                  <option value="60" selected={@form[:clues_interval].value == "60"}>
                    60 Sekunden
                  </option>
                </select>
                <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-4 text-gray-500">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    >
                    </path>
                  </svg>
                </div>
              </div>
            </div>

            <%!-- Word Types Selection --%>
            <div class="space-y-3">
              <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
                Wortarten
              </label>
              <div class="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#word-type-noun")}
                  class={[
                    "relative py-3 px-4 rounded-xl font-medium text-sm transition-all duration-300 overflow-hidden group",
                    if("Noun" in (@form[:word_types].value || []),
                      do:
                        "bg-gradient-to-br from-purple-500 to-pink-500 text-white shadow-lg shadow-purple-500/30",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">Nomen</span>
                </button>
                <input
                  type="checkbox"
                  id="word-type-noun"
                  name="game[word_types][]"
                  value="Noun"
                  checked={"Noun" in (@form[:word_types].value || [])}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#word-type-verb")}
                  class={[
                    "relative py-3 px-4 rounded-xl font-medium text-sm transition-all duration-300 overflow-hidden group",
                    if("Verb" in (@form[:word_types].value || []),
                      do:
                        "bg-gradient-to-br from-blue-500 to-cyan-500 text-white shadow-lg shadow-blue-500/30",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-blue-300 dark:hover:border-blue-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-blue-500 to-cyan-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">Verb</span>
                </button>
                <input
                  type="checkbox"
                  id="word-type-verb"
                  name="game[word_types][]"
                  value="Verb"
                  checked={"Verb" in (@form[:word_types].value || [])}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#word-type-adjective")}
                  class={[
                    "relative py-3 px-4 rounded-xl font-medium text-sm transition-all duration-300 overflow-hidden group",
                    if("Adjective" in (@form[:word_types].value || []),
                      do:
                        "bg-gradient-to-br from-green-500 to-emerald-500 text-white shadow-lg shadow-green-500/30",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-green-300 dark:hover:border-green-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-green-500 to-emerald-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">Adjektiv</span>
                </button>
                <input
                  type="checkbox"
                  id="word-type-adjective"
                  name="game[word_types][]"
                  value="Adjective"
                  checked={"Adjective" in (@form[:word_types].value || [])}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#word-type-adverb")}
                  class={[
                    "relative py-3 px-4 rounded-xl font-medium text-sm transition-all duration-300 overflow-hidden group",
                    if("Adverb" in (@form[:word_types].value || []),
                      do:
                        "bg-gradient-to-br from-yellow-500 to-orange-500 text-white shadow-lg shadow-yellow-500/30",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-yellow-300 dark:hover:border-yellow-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-yellow-500 to-orange-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">Adverb</span>
                </button>
                <input
                  type="checkbox"
                  id="word-type-adverb"
                  name="game[word_types][]"
                  value="Adverb"
                  checked={"Adverb" in (@form[:word_types].value || [])}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#word-type-other")}
                  class={[
                    "relative py-3 px-4 rounded-xl font-medium text-sm transition-all duration-300 overflow-hidden group",
                    if("Other" in (@form[:word_types].value || []),
                      do:
                        "bg-gradient-to-br from-pink-500 to-rose-500 text-white shadow-lg shadow-pink-500/30",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-pink-300 dark:hover:border-pink-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-pink-500 to-rose-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">Andere</span>
                </button>
                <input
                  type="checkbox"
                  id="word-type-other"
                  name="game[word_types][]"
                  value="Other"
                  checked={"Other" in (@form[:word_types].value || [])}
                  class="hidden"
                />
              </div>
            </div>

            <%!-- Grid Size Buttons --%>
            <div class="space-y-3">
              <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300">
                Spielfeld Größe
              </label>
              <div class="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#grid-2")}
                  class={[
                    "relative py-5 rounded-2xl font-semibold text-base transition-all duration-300 overflow-hidden group",
                    if(@form[:grid_size].value == "2",
                      do:
                        "bg-gradient-to-br from-purple-500 to-pink-500 text-white shadow-lg shadow-purple-500/50 scale-[1.02]",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-purple-300 dark:hover:border-purple-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">2x1</span>
                </button>
                <input
                  type="radio"
                  id="grid-2"
                  name="game[grid_size]"
                  value="2"
                  checked={@form[:grid_size].value == "2"}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#grid-4")}
                  class={[
                    "relative py-5 rounded-2xl font-semibold text-base transition-all duration-300 overflow-hidden group",
                    if(@form[:grid_size].value == "4",
                      do:
                        "bg-gradient-to-br from-blue-500 to-cyan-500 text-white shadow-lg shadow-blue-500/50 scale-[1.02]",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-blue-300 dark:hover:border-blue-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-blue-500 to-cyan-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">2x2</span>
                </button>
                <input
                  type="radio"
                  id="grid-4"
                  name="game[grid_size]"
                  value="4"
                  checked={@form[:grid_size].value == "4"}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#grid-9")}
                  class={[
                    "relative py-5 rounded-2xl font-semibold text-base transition-all duration-300 overflow-hidden group",
                    if(@form[:grid_size].value == "9" || !@form[:grid_size].value,
                      do:
                        "bg-gradient-to-br from-indigo-500 to-purple-500 text-white shadow-lg shadow-indigo-500/50 scale-[1.02]",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-indigo-300 dark:hover:border-indigo-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-indigo-500 to-purple-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">3x3</span>
                </button>
                <input
                  type="radio"
                  id="grid-9"
                  name="game[grid_size]"
                  value="9"
                  checked={@form[:grid_size].value == "9" || !@form[:grid_size].value}
                  class="hidden"
                />

                <button
                  type="button"
                  phx-click={JS.dispatch("click", to: "#grid-16")}
                  class={[
                    "relative py-5 rounded-2xl font-semibold text-base transition-all duration-300 overflow-hidden group",
                    if(@form[:grid_size].value == "16",
                      do:
                        "bg-gradient-to-br from-orange-500 to-red-500 text-white shadow-lg shadow-orange-500/50 scale-[1.02]",
                      else:
                        "bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:border-orange-300 dark:hover:border-orange-600 hover:shadow-md"
                    )
                  ]}
                >
                  <div class="absolute inset-0 bg-gradient-to-br from-orange-500 to-red-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                  </div>
                  <span class="relative">4x4</span>
                </button>
                <input
                  type="radio"
                  id="grid-16"
                  name="game[grid_size]"
                  value="16"
                  checked={@form[:grid_size].value == "16"}
                  class="hidden"
                />
              </div>
            </div>

            <%!-- Submit Button --%>
            <button
              type="submit"
              class="relative w-full text-lg font-semibold py-4 bg-gradient-to-r from-purple-600 via-purple-500 to-pink-500 hover:from-purple-700 hover:via-purple-600 hover:to-pink-600 text-white rounded-2xl shadow-xl shadow-purple-500/30 hover:shadow-2xl hover:shadow-purple-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 overflow-hidden group"
            >
              <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
              </div>
              <span class="relative">Einladungslink generieren</span>
            </button>
          </.form>
        </div>
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

  defp game_error_message(:not_found), do: "Ungültiger Code"
  defp game_error_message(:expired), do: "Dieser Code ist abgelaufen"
  defp game_error_message(:already_started), do: "Das Spiel hat bereits begonnen"
  defp game_error_message(:game_over), do: "Das Spiel ist bereits vorbei"
  defp game_error_message(:lobby_timeout), do: "Die Lobby-Zeit ist abgelaufen"
  defp game_error_message(_), do: "Ein Fehler ist aufgetreten"

  defp has_waiting_games? do
    Games.count_waiting_games() > 0
  end
end
