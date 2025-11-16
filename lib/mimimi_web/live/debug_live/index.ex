defmodule MimimiWeb.DebugLive.Index do
  use MimimiWeb, :live_view
  alias Mimimi.WortSchuleRepo, as: Repo
  alias Mimimi.WortSchule.Word
  alias Mimimi.WortSchule.ImageUrlCache
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(:loading, false)
        |> assign(:system_info, get_system_info())
        |> assign(:cache_stats, ImageUrlCache.stats())
        |> load_database_stats()
      else
        socket
        |> assign(:loading, true)
        |> assign(:system_info, get_system_info())
        |> assign(:cache_stats, %{total: 0, expired: 0, active: 0})
      end

    {:ok, assign(socket, :page_title, "WortSchule Debug")}
  end

  defp get_system_info do
    %{
      elixir_version: System.version(),
      phoenix_version: Application.spec(:phoenix, :vsn) |> to_string(),
      app_version: Application.spec(:mimimi, :vsn) |> to_string(),
      deployment_timestamp: get_deployment_timestamp()
    }
  end

  defp get_deployment_timestamp do
    # Try to get the build timestamp from the release or compiled beam file
    Application.get_env(:mimimi, :build_timestamp) || get_beam_compile_time()
  end

  defp get_beam_compile_time do
    # Fallback: check when the application was compiled
    # by looking at the beam file modification time
    with path when is_list(path) <- :code.which(Mimimi.Application),
         {:ok, %{mtime: mtime}} <- File.stat(path) do
      mtime
      |> NaiveDateTime.from_erl!()
      |> DateTime.from_naive!("Etc/UTC")
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
    else
      _ -> "Unknown"
    end
  end

  defp load_database_stats(socket) do
    stats = %{
      connection_status: check_connection(),
      words_total: count_table("words"),
      words_with_images: count_words_with_images(),
      words_with_keywords: count_words_with_keywords(),
      words_with_both: count_words_with_keywords_and_images(),
      keywords_total: count_table("keywords"),
      active_storage_attachments: count_table("active_storage_attachments"),
      active_storage_blobs: count_table("active_storage_blobs")
    }

    assign(socket, :stats, stats)
  end

  defp check_connection do
    try do
      Repo.query!("SELECT 1")
      :connected
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp count_table(table_name) do
    try do
      result = Repo.query!("SELECT COUNT(*) FROM #{table_name}")
      [[count]] = result.rows
      {:ok, count}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp count_words_with_images do
    try do
      query =
        from(w in Word,
          join: att in "active_storage_attachments",
          on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
          select: count(w.id, :distinct)
        )

      count = Repo.one(query)
      {:ok, count}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp count_words_with_keywords do
    try do
      query =
        from(w in Word,
          join: k in "keywords",
          on: k.word_id == w.id,
          select: count(w.id, :distinct)
        )

      count = Repo.one(query)
      {:ok, count}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp count_words_with_keywords_and_images do
    try do
      query =
        from(w in Word,
          join: att in "active_storage_attachments",
          on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
          join: k in "keywords",
          on: k.word_id == w.id,
          select: count(w.id, :distinct)
        )

      count = Repo.one(query)
      {:ok, count}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  @impl true
  def handle_event("clear_cache", _params, socket) do
    ImageUrlCache.clear()

    {:noreply,
     socket
     |> assign(:cache_stats, ImageUrlCache.stats())
     |> put_flash(:info, "Image URL Cache erfolgreich geleert")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
      <div class="w-full max-w-4xl mx-auto">
        <%!-- Header --%>
        <div class="text-center mb-10">
          <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 mb-4 shadow-lg">
            <span class="text-4xl">🔍</span>
          </div>
          <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
            WortSchule Debug
          </h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            Database connection and table statistics
          </p>
        </div>

        <%!-- System Info Card --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
            System Information
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 shadow-lg">
                <span class="text-xl">💧</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Elixir
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@system_info.elixir_version}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-orange-500 to-red-500 shadow-lg">
                <span class="text-xl">🔥</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Phoenix
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@system_info.phoenix_version}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-green-500 to-emerald-500 shadow-lg">
                <span class="text-xl">📦</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  App Version
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@system_info.app_version}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 shadow-lg">
                <span class="text-xl">⏰</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Build Time
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@system_info.deployment_timestamp}
                </p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Image URL Cache Card --%>
        <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-gray-900 dark:text-white">
              Image URL Cache
            </h2>
            <button
              phx-click="clear_cache"
              class="relative px-4 py-2 bg-gradient-to-r from-red-600 via-red-500 to-orange-500 hover:from-red-700 hover:via-red-600 hover:to-orange-600 text-white rounded-xl shadow-lg shadow-red-500/30 hover:shadow-xl hover:shadow-red-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 font-semibold overflow-hidden group"
            >
              <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
              </div>
              <span class="relative">Cache leeren</span>
            </button>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-cyan-500 shadow-lg">
                <span class="text-xl">📊</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Total
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@cache_stats.total}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-green-500 to-emerald-500 shadow-lg">
                <span class="text-xl">✓</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Aktiv
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@cache_stats.active}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-orange-500 to-red-500 shadow-lg">
                <span class="text-xl">⏳</span>
              </div>
              <div>
                <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
                  Abgelaufen
                </p>
                <p class="text-lg font-bold text-gray-900 dark:text-white">
                  {@cache_stats.expired}
                </p>
              </div>
            </div>
          </div>

          <p class="mt-4 text-sm text-gray-600 dark:text-gray-400">
            Der Cache speichert Bild-URLs für 24 Stunden, um API-Aufrufe zu minimieren.
          </p>
        </div>

        <%= if @loading do %>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <div class="text-center py-8">
              <div class="text-6xl mb-4 opacity-50">⏳</div>
              <p class="text-gray-600 dark:text-gray-400">Lade Statistiken...</p>
            </div>
          </div>
        <% else %>
          <%!-- Connection Status Card --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50 mb-6">
            <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
              Connection Status
            </h2>
            <div class="flex items-center gap-3">
              <%= if @stats.connection_status == :connected do %>
                <div class="flex items-center justify-center w-12 h-12 rounded-full bg-gradient-to-br from-green-500 to-emerald-500 shadow-lg">
                  <span class="text-2xl">✓</span>
                </div>
                <div>
                  <p class="text-lg font-semibold text-gray-900 dark:text-white">Connected</p>
                  <p class="text-sm text-gray-600 dark:text-gray-400">
                    Database connection successful
                  </p>
                </div>
              <% else %>
                <div class="flex items-center justify-center w-12 h-12 rounded-full bg-gradient-to-br from-red-500 to-orange-500 shadow-lg">
                  <span class="text-2xl">✗</span>
                </div>
                <div>
                  <p class="text-lg font-semibold text-gray-900 dark:text-white">Error</p>
                  <p class="text-sm text-red-600 dark:text-red-400 font-mono">
                    {elem(@stats.connection_status, 1)}
                  </p>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Tables Statistics Card --%>
          <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
            <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">
              Database Tables
            </h2>

            <div class="space-y-4">
              <.stat_row
                label="Words (Total)"
                value={@stats.words_total}
                icon="📝"
                gradient="from-purple-500 to-pink-500"
              />
              <.stat_row
                label="Words with Images"
                value={@stats.words_with_images}
                icon="🖼️"
                gradient="from-blue-500 to-cyan-500"
              />
              <.stat_row
                label="Words with Keywords"
                value={@stats.words_with_keywords}
                icon="🏷️"
                gradient="from-green-500 to-emerald-500"
              />
              <.stat_row
                label="Words with Keywords & Images"
                value={@stats.words_with_both}
                icon="✨"
                gradient="from-yellow-500 to-orange-500"
              />
              <.stat_row
                label="Keywords (Associations)"
                value={@stats.keywords_total}
                icon="🔗"
                gradient="from-indigo-500 to-purple-500"
              />
              <.stat_row
                label="Active Storage Attachments"
                value={@stats.active_storage_attachments}
                icon="📎"
                gradient="from-orange-500 to-red-500"
              />
              <.stat_row
                label="Active Storage Blobs"
                value={@stats.active_storage_blobs}
                icon="💾"
                gradient="from-pink-500 to-rose-500"
              />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="relative group overflow-hidden rounded-2xl">
      <div class={"absolute inset-0 bg-gradient-to-r #{@gradient} opacity-0 group-hover:opacity-10 transition-opacity duration-300"}>
      </div>
      <div class="relative flex items-center justify-between p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl transition-all duration-200">
        <div class="flex items-center gap-3">
          <div class={"flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br #{@gradient} shadow-lg"}>
            <span class="text-xl">{@icon}</span>
          </div>
          <span class="font-semibold text-gray-900 dark:text-white">{@label}</span>
        </div>
        <div class="text-right">
          <%= case @value do %>
            <% {:ok, count} -> %>
              <span class="text-2xl font-bold text-gray-900 dark:text-white">
                {count}
              </span>
            <% {:error, message} -> %>
              <span class="text-sm text-red-600 dark:text-red-400 font-mono max-w-xs truncate">
                Error: {message}
              </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
