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
        {:noreply, push_navigate(socket, to: ~p"/dashboard/#{game.id}")}

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
    <div class="min-h-screen flex items-center justify-center px-4 py-8">
      <div class="w-full max-w-md">
        <h1 class="text-3xl font-bold text-center mb-8 dark:text-white">
          Neues Spiel
        </h1>

        <.form
          for={@form}
          id="game-setup-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <div>
            <label class="block text-lg font-medium mb-2 dark:text-white">
              Wie viele Runden?
            </label>
            <input
              type="number"
              name="game[rounds_count]"
              value={@form[:rounds_count].value || 3}
              min="1"
              max="20"
              class="w-full text-lg px-4 py-3 border-2 border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-purple-500 dark:bg-gray-800 dark:text-white appearance-none"
              style="height: 3.5rem;"
            />
          </div>

          <div>
            <label class="block text-lg font-medium mb-2 dark:text-white">
              Zeit für Hinweise
            </label>
            <select
              name="game[clues_interval]"
              class="w-full text-lg px-4 py-3 border-2 border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-purple-500 dark:bg-gray-800 dark:text-white"
              style="height: 3.5rem;"
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
          </div>

          <div>
            <label class="block text-lg font-medium mb-2 dark:text-white">
              Spielfeld Größe
            </label>
            <div class="grid grid-cols-2 gap-3">
              <button
                type="button"
                phx-click={JS.dispatch("click", to: "#grid-2")}
                class={[
                  "text-lg py-4 rounded-lg border-2 transition-all",
                  if(@form[:grid_size].value == "2",
                    do: "border-purple-500 bg-purple-100 dark:bg-purple-900",
                    else: "border-gray-300 dark:border-gray-600 hover:border-purple-300"
                  )
                ]}
              >
                2x1
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
                  "text-lg py-4 rounded-lg border-2 transition-all",
                  if(@form[:grid_size].value == "4",
                    do: "border-purple-500 bg-purple-100 dark:bg-purple-900",
                    else: "border-gray-300 dark:border-gray-600 hover:border-purple-300"
                  )
                ]}
              >
                2x2
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
                  "text-lg py-4 rounded-lg border-2 transition-all",
                  if(@form[:grid_size].value == "9" || !@form[:grid_size].value,
                    do: "border-purple-500 bg-purple-100 dark:bg-purple-900",
                    else: "border-gray-300 dark:border-gray-600 hover:border-purple-300"
                  )
                ]}
              >
                3x3
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
                  "text-lg py-4 rounded-lg border-2 transition-all",
                  if(@form[:grid_size].value == "16",
                    do: "border-purple-500 bg-purple-100 dark:bg-purple-900",
                    else: "border-gray-300 dark:border-gray-600 hover:border-purple-300"
                  )
                ]}
              >
                4x4
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

          <button
            type="submit"
            class="w-full text-xl font-bold py-4 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors"
          >
            Einladungslink generieren
          </button>
        </.form>
      </div>
    </div>
    """
  end
end
