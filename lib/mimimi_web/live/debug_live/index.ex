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
      erlang_version: get_erlang_version(),
      phoenix_version: Application.spec(:phoenix, :vsn) |> to_string(),
      app_version: Application.spec(:mimimi, :vsn) |> to_string(),
      deployment_timestamp: get_deployment_timestamp()
    }
  end

  defp get_erlang_version do
    # Get the full Erlang version including minor/patch
    # Parse from system_version which contains the full version string
    system_version = :erlang.system_info(:system_version) |> to_string()

    # Extract version from string like "Erlang/OTP 28 [erts-15.1] ..."
    case Regex.run(~r/Erlang\/OTP \d+ \[erts-([\d.]+)\]/, system_version) do
      [_, erts_version] ->
        # Extract major.minor from erts version (e.g., "15.1" from erts-15.1)
        case String.split(erts_version, ".") do
          [major, minor | _] ->
            # Map erts version to OTP release
            otp_release = System.otp_release()
            "#{otp_release}.#{minor}"
          _ ->
            System.otp_release()
        end
      _ ->
        System.otp_release()
    end
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
      |> Calendar.strftime("%d.%m.%Y %H:%M:%S UTC")
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
        <.page_header />

        <.system_info_card system_info={@system_info} />

        <.cache_card cache_stats={@cache_stats} />

        <%= if @loading do %>
          <.loading_card />
        <% else %>
          <.connection_status_card status={@stats.connection_status} />

          <.database_stats_card stats={@stats} />

          <.links_card />
        <% end %>
      </div>
    </div>
    """
  end

  defp page_header(assigns) do
    ~H"""
    <div class="text-center mb-10">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
        WortSchule Debug
      </h1>
      <p class="text-gray-500 dark:text-gray-400 text-sm">
        Database connection and table statistics
      </p>
    </div>
    """
  end

  defp system_info_card(assigns) do
    ~H"""
    <.glass_card class="p-8 mb-6">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
        System Information
      </h2>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.info_stat
          icon="💧"
          label="Elixir"
          value={@system_info.elixir_version}
          gradient="from-purple-500 to-pink-500"
        />
        <.info_stat
          icon="📡"
          label="Erlang/OTP"
          value={@system_info.erlang_version}
          gradient="from-red-500 to-pink-500"
        />
        <.info_stat
          icon="🔥"
          label="Phoenix"
          value={@system_info.phoenix_version}
          gradient="from-orange-500 to-red-500"
        />
        <.info_stat
          icon="📦"
          label="App Version"
          value={@system_info.app_version}
          gradient="from-green-500 to-emerald-500"
        />
        <.info_stat
          icon="⏰"
          label="Build Time"
          value={@system_info.deployment_timestamp}
          gradient="from-blue-500 to-cyan-500"
        />
      </div>
    </.glass_card>
    """
  end

  defp info_stat(assigns) do
    ~H"""
    <div class="flex items-center gap-3 p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl">
      <.gradient_icon_badge icon={@icon} gradient={@gradient} size="sm" class="mb-0" />
      <div>
        <p class="text-xs text-gray-500 dark:text-gray-400 font-semibold uppercase">
          {@label}
        </p>
        <p class="text-lg font-bold text-gray-900 dark:text-white">
          {@value}
        </p>
      </div>
    </div>
    """
  end

  defp cache_card(assigns) do
    ~H"""
    <.glass_card class="p-8 mb-6">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white">
          Image URL Cache
        </h2>
        <.gradient_button
          phx-click="clear_cache"
          gradient="from-red-600 via-red-500 to-orange-500"
          hover_gradient="from-red-700 via-red-600 to-orange-600"
          shadow_color="shadow-red-500/30"
          hover_shadow_color="shadow-red-500/40"
          size="sm"
          full_width={false}
          class="px-4 py-2"
        >
          Cache leeren
        </.gradient_button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.info_stat
          icon="📊"
          label="Total"
          value={@cache_stats.total}
          gradient="from-blue-500 to-cyan-500"
        />
        <.info_stat
          icon="✓"
          label="Aktiv"
          value={@cache_stats.active}
          gradient="from-green-500 to-emerald-500"
        />
        <.info_stat
          icon="⏳"
          label="Abgelaufen"
          value={@cache_stats.expired}
          gradient="from-orange-500 to-red-500"
        />
      </div>

      <p class="mt-4 text-sm text-gray-600 dark:text-gray-400">
        Der Cache speichert Bild-URLs für 24 Stunden, um API-Aufrufe zu minimieren.
      </p>
    </.glass_card>
    """
  end

  defp loading_card(assigns) do
    ~H"""
    <.glass_card class="p-8">
      <div class="text-center py-8">
        <div class="text-6xl mb-4 opacity-50">⏳</div>
        <p class="text-gray-600 dark:text-gray-400">Lade Statistiken...</p>
      </div>
    </.glass_card>
    """
  end

  defp connection_status_card(assigns) do
    ~H"""
    <.glass_card class="p-8 mb-6">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
        Connection Status
      </h2>
      <div class="flex items-center gap-3">
        <%= if @status == :connected do %>
          <.gradient_icon_badge
            icon="✓"
            gradient="from-green-500 to-emerald-500"
            size="sm"
            class="mb-0"
          />
          <div>
            <p class="text-lg font-semibold text-gray-900 dark:text-white">Connected</p>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              Database connection successful
            </p>
          </div>
        <% else %>
          <.gradient_icon_badge
            icon="✗"
            gradient="from-red-500 to-orange-500"
            size="sm"
            class="mb-0"
          />
          <div>
            <p class="text-lg font-semibold text-gray-900 dark:text-white">Error</p>
            <p class="text-sm text-red-600 dark:text-red-400 font-mono">
              {elem(@status, 1)}
            </p>
          </div>
        <% end %>
      </div>
    </.glass_card>
    """
  end

  defp database_stats_card(assigns) do
    ~H"""
    <.glass_card class="p-8 mb-6">
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
    </.glass_card>
    """
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="relative group overflow-hidden rounded-2xl">
      <div class={"absolute inset-0 bg-gradient-to-r #{@gradient} opacity-0 group-hover:opacity-10 transition-opacity duration-300"}>
      </div>
      <div class="relative flex items-center justify-between p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl transition-all duration-200">
        <div class="flex items-center gap-3">
          <.gradient_icon_badge icon={@icon} gradient={@gradient} size="sm" class="mb-0" />
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

  defp links_card(assigns) do
    ~H"""
    <.glass_card class="p-8">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">
        Links
      </h2>

      <div class="space-y-3">
        <a
          href="https://spiel.wort.schule/list_words"
          target="_blank"
          rel="noopener noreferrer"
          class="relative group overflow-hidden rounded-2xl block"
        >
          <div class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300">
          </div>
          <div class="relative flex items-center justify-between p-4 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-2xl group-hover:border-purple-400 dark:group-hover:border-purple-500 transition-all duration-200">
            <div class="flex items-center gap-3">
              <.gradient_icon_badge
                icon="📚"
                gradient="from-purple-500 to-pink-500"
                size="sm"
                class="mb-0"
              />
              <span class="font-semibold text-gray-900 dark:text-white">
                WortSchule Wortliste
              </span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-gray-500 dark:text-gray-400 font-mono">
                spiel.wort.schule
              </span>
              <span class="text-gray-400 dark:text-gray-500">↗</span>
            </div>
          </div>
        </a>
      </div>
    </.glass_card>
    """
  end
end
