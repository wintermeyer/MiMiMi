defmodule MimimiWeb.HomeLive.Index do
  use MimimiWeb, :live_view
  alias Mimimi.Games

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Games.subscribe_to_active_games()
    end

    {:ok,
     socket
     |> assign(
       :form,
       to_form(%{"rounds_count" => "3", "clues_interval" => "9", "grid_size" => "9"})
     )
     |> assign(:page_title, "Neues Spiel")}
  end

  @impl true
  def handle_info(:game_count_changed, socket) do
    {:noreply, assign(socket, :active_games, Games.count_active_games())}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    {:noreply, assign(socket, :form, to_form(game_params, as: :game))}
  end

  @impl true
  def handle_event("save", %{"game" => game_params}, socket) do
    rounds_count = String.to_integer(game_params["rounds_count"] || "3")
    clues_interval = String.to_integer(game_params["clues_interval"] || "9")
    grid_size = String.to_integer(game_params["grid_size"] || "9")

    case Games.create_game(socket.assigns.current_user.id, %{
           rounds_count: rounds_count,
           clues_interval: clues_interval,
           grid_size: grid_size
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
      <div class="w-full max-w-md">
        <%!-- Glassmorphism Header --%>
        <div class="text-center mb-10">
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            Neues Spiel
          </h1>
        </div>

        <%!-- Glassmorphism Form Card --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
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
end
