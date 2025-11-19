defmodule MimimiWeb.ListWordsLive.Index do
  use MimimiWeb, :live_view
  alias Mimimi.WortSchule

  @impl true
  def mount(_params, _session, socket) do
    max_keywords = WortSchule.get_max_keywords_count()
    max_keywords = max(max_keywords, 1)

    socket =
      socket
      |> assign(:page_title, "Wörter mit Bild und Stichwörtern")
      |> assign(:loading, true)
      |> assign(:total_count, 0)
      |> assign(:loaded_count, 0)
      |> assign(:words_map, %{})
      |> assign(:min_keywords, 1)
      |> assign(:max_keywords, max_keywords)
      |> stream(:words, [])

    if connected?(socket) do
      send(self(), :load_words)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_words, socket) do
    word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: socket.assigns.min_keywords)

    socket =
      socket
      |> assign(:total_count, length(word_ids))
      |> assign(:loading, length(word_ids) > 0)

    if length(word_ids) > 0 do
      load_words_async(word_ids)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:word_loaded, {:ok, word}}, socket) do
    loaded_count = socket.assigns.loaded_count + 1
    socket = update_loaded_count(socket, loaded_count)

    if word.image_url do
      add_word_to_stream(socket, word)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:word_loaded, {:error, _reason}}, socket) do
    increment_loaded_count(socket)
  end

  @impl true
  def handle_info(:word_failed, socket) do
    increment_loaded_count(socket)
  end

  @impl true
  def handle_event("filter_change", %{"min_keywords" => min_keywords_str}, socket) do
    min_keywords = String.to_integer(min_keywords_str)

    socket =
      socket
      |> assign(:min_keywords, min_keywords)
      |> assign(:loading, true)
      |> assign(:total_count, 0)
      |> assign(:loaded_count, 0)
      |> assign(:words_map, %{})
      |> stream(:words, [], reset: true)

    send(self(), :load_words)

    {:noreply, socket}
  end

  defp load_words_async(word_ids) do
    pid = self()

    spawn(fn ->
      word_ids
      |> Task.async_stream(
        fn word_id -> fetch_word_data(word_id) end,
        timeout: :infinity,
        max_concurrency: 10
      )
      |> Stream.each(fn
        {:ok, result} ->
          send(pid, {:word_loaded, result})

        {:exit, _reason} ->
          send(pid, :word_failed)
      end)
      |> Stream.run()
    end)
  end

  defp add_word_to_stream(socket, word) do
    words_map = Map.put(socket.assigns.words_map, word.name, word)

    sorted_words =
      words_map
      |> Map.values()
      |> Enum.sort_by(& &1.name)

    socket =
      socket
      |> assign(:words_map, words_map)
      |> stream(:words, sorted_words, reset: true)

    {:noreply, socket}
  end

  defp update_loaded_count(socket, loaded_count) do
    socket
    |> assign(:loaded_count, loaded_count)
    |> assign(:loading, loaded_count < socket.assigns.total_count)
  end

  defp increment_loaded_count(socket) do
    loaded_count = socket.assigns.loaded_count + 1

    {:noreply, update_loaded_count(socket, loaded_count)}
  end

  defp fetch_word_data(word_id) do
    case WortSchule.get_complete_word(word_id) do
      {:ok, word} ->
        if word.image_url do
          {:ok, Map.put(word, :dom_id, "word-#{word.id}")}
        else
          {:error, :no_image}
        end

      error ->
        error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_container class="!px-4">
      <div class="w-full max-w-6xl mx-auto">
        <div class="text-center mb-10">
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            Wörterliste
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            Alle Wörter mit Stichwörtern und Bildern
          </p>
        </div>

        <div class="mb-8 max-w-md mx-auto">
          <.glass_card class="p-6">
            <label class="block text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3">
              Mindestanzahl Stichwörter: {@min_keywords}
            </label>
            <form phx-change="filter_change" phx-debounce="300">
              <div class="relative group">
                <div class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300">
                </div>
                <input
                  type="range"
                  id="keyword-filter"
                  name="min_keywords"
                  min="1"
                  max={@max_keywords}
                  value={@min_keywords}
                  class="relative w-full h-2 bg-gray-200 dark:bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
                />
              </div>
              <div class="flex justify-between text-xs text-gray-500 dark:text-gray-400 mt-2">
                <span>1</span>
                <span>{@max_keywords}</span>
              </div>
            </form>
          </.glass_card>
        </div>

        <div class="mb-6 text-center">
          <p class="text-lg text-gray-600 dark:text-gray-400">
            <span class="font-semibold text-purple-600 dark:text-purple-400">{@loaded_count}</span>
            <%= if @total_count > 0 do %>
              von
              <span class="font-semibold text-purple-600 dark:text-purple-400">{@total_count}</span>
            <% end %>
            Wörter geladen
          </p>
          <%= if @loading do %>
            <.progress_bar
              value={if @total_count > 0, do: round(@loaded_count / @total_count * 100), else: 0}
              class="mt-3 max-w-md mx-auto"
            />
          <% end %>
        </div>

        <div
          id="words-grid"
          class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6"
          phx-update="stream"
        >
          <div
            :for={{dom_id, word} <- @streams.words}
            id={dom_id}
            phx-hook="WordCard"
            class="opacity-0 backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-6 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 hover:shadow-purple-500/20 hover:scale-[1.02] transition-all duration-300"
            data-word-card
          >
            <div class="relative aspect-square rounded-2xl overflow-hidden mb-4 bg-gray-100 dark:bg-gray-900">
              <img
                src={word.image_url}
                alt={word.name}
                class="w-full h-full object-cover"
                loading="eager"
              />
            </div>

            <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-3 text-center">
              {word.name}
            </h2>

            <div class="space-y-2">
              <h3 class="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">
                Stichwörter:
              </h3>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={keyword <- word.keywords}
                  class="inline-block px-3 py-1.5 bg-gradient-to-r from-purple-500/10 to-pink-500/10 dark:from-purple-500/20 dark:to-pink-500/20 border border-purple-200 dark:border-purple-700 rounded-full text-sm font-medium text-purple-700 dark:text-purple-300"
                >
                  {keyword.name}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div :if={@total_count == 0 && !@loading} class="text-center py-16">
          <.glass_card class="p-12">
            <div class="text-6xl mb-4 opacity-50">📭</div>
            <p class="text-xl text-gray-600 dark:text-gray-400">
              Keine Wörter mit Stichwörtern und Bildern gefunden
            </p>
          </.glass_card>
        </div>
      </div>
    </.page_container>
    """
  end
end
