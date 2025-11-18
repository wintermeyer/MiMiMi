defmodule MimimiWeb.GameComponents do
  @moduledoc """
  Provides game-specific UI components for the MiMiMi application.

  These components are designed for the glassmorphism game interface,
  including leaderboards, word cards, and player grids.
  """
  use Phoenix.Component
  import MimimiWeb.CoreComponents

  @doc """
  Renders a leaderboard with player rankings.

  ## Examples

      <.leaderboard players={@players} />
      <.leaderboard players={@players} show_position={true} />
  """
  attr :players, :list, required: true
  attr :show_position, :boolean, default: true
  attr :class, :string, default: nil

  def leaderboard(assigns) do
    ~H"""
    <div class={["space-y-3", @class]}>
      <div
        :for={{player, index} <- Enum.with_index(@players, 1)}
        class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50 flex items-center gap-4"
      >
        <div
          :if={@show_position}
          class="flex-shrink-0 w-8 h-8 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-white font-bold text-sm"
        >
          {index}
        </div>
        <div class="flex-shrink-0 w-12 h-12 rounded-full bg-gradient-to-br from-purple-100 to-pink-100 dark:from-purple-900/30 dark:to-pink-900/30 flex items-center justify-center text-2xl">
          {player.avatar}
        </div>
        <div class="flex-1 min-w-0">
          <div class="font-semibold text-gray-900 dark:text-white truncate">
            {player.name}
          </div>
        </div>
        <div class="flex-shrink-0 text-2xl font-bold text-purple-600 dark:text-purple-400">
          {player.points}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a word image card with optional label overlay.

  ## Examples

      <.word_card word={@word} />
      <.word_card word={@word} show_label={true} />
      <.word_card word={@word} selectable={true} phx-click="select" phx-value-id={@word.id} />
  """
  attr :word, :map, required: true
  attr :show_label, :boolean, default: false
  attr :selectable, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def word_card(assigns) do
    ~H"""
    <div
      class={[
        "relative aspect-square rounded-2xl overflow-hidden border-2 transition-all duration-200",
        @selectable && "cursor-pointer hover:scale-105",
        @selected && "border-purple-500 ring-4 ring-purple-100 dark:ring-purple-900/30",
        !@selected && "border-gray-200 dark:border-gray-700",
        @class
      ]}
      {@rest}
    >
      <img
        :if={@word.image_url}
        src={@word.image_url}
        alt={@word.name}
        class="w-full h-full object-cover"
      />
      <div
        :if={!@word.image_url}
        class="w-full h-full bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-800 flex items-center justify-center text-4xl"
      >
        ❓
      </div>
      <div
        :if={@show_label}
        class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent p-3 text-white font-semibold text-center"
      >
        {@word.name}
      </div>
    </div>
    """
  end

  @doc """
  Renders a grid of players with avatars.

  ## Examples

      <.player_grid players={@players} />
      <.player_grid players={@players} show_status={true} />
  """
  attr :players, :list, required: true
  attr :show_status, :boolean, default: false
  attr :class, :string, default: nil

  def player_grid(assigns) do
    ~H"""
    <div class={[
      "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4",
      @class
    ]}>
      <div :for={player <- @players} class="text-center">
        <.player_avatar
          avatar={player.avatar}
          status={@show_status && player_status(player)}
          class="mx-auto mb-2"
        />
        <div class="text-sm font-medium text-gray-900 dark:text-white truncate">
          {player.name}
        </div>
        <div :if={Map.has_key?(player, :points)} class="text-xs text-purple-600 dark:text-purple-400">
          {player.points} Punkte
        </div>
      </div>
    </div>
    """
  end

  defp player_status(%{picked: true}), do: :picked
  defp player_status(%{online: true}), do: :online
  defp player_status(_), do: :waiting

  @doc """
  Renders keyword reveal badges with progress indicators.

  ## Examples

      <.keyword_badges keywords={@keywords} revealed={2} />
  """
  attr :keywords, :list, required: true
  attr :revealed, :integer, default: 0
  attr :class, :string, default: nil

  def keyword_badges(assigns) do
    ~H"""
    <div class={["space-y-3", @class]}>
      <div :for={{keyword, index} <- Enum.with_index(@keywords)} class="relative">
        <%= cond do %>
          <% index < @revealed -> %>
            <%!-- Revealed keyword --%>
            <div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-2xl p-4 border border-gray-200/50 dark:border-gray-700/50">
              <div class="flex items-center gap-3">
                <div class="flex-shrink-0 w-10 h-10 rounded-full bg-gradient-to-br from-green-500 to-emerald-500 flex items-center justify-center text-white font-bold">
                  {index + 1}
                </div>
                <div class="flex-1 text-lg font-semibold text-gray-900 dark:text-white">
                  {keyword.name}
                </div>
              </div>
            </div>
          <% index == @revealed -> %>
            <%!-- Currently revealing --%>
            <div class="backdrop-blur-xl bg-gradient-to-br from-purple-500/20 to-pink-500/20 dark:from-purple-500/30 dark:to-pink-500/30 rounded-2xl p-4 border-2 border-purple-500 dark:border-purple-400 animate-pulse">
              <div class="flex items-center gap-3">
                <div class="flex-shrink-0 w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-white font-bold animate-bounce">
                  {index + 1}
                </div>
                <div class="flex-1">
                  <div class="h-6 bg-gradient-to-r from-purple-200 to-pink-200 dark:from-purple-700 dark:to-pink-700 rounded animate-pulse">
                  </div>
                </div>
              </div>
            </div>
          <% true -> %>
            <%!-- Upcoming keyword --%>
            <div class="backdrop-blur-xl bg-gray-100/50 dark:bg-gray-700/50 rounded-2xl p-4 border border-gray-200/50 dark:border-gray-600/50 opacity-60">
              <div class="flex items-center gap-3">
                <div class="flex-shrink-0 w-10 h-10 rounded-full bg-gray-300 dark:bg-gray-600 flex items-center justify-center text-gray-600 dark:text-gray-400 font-bold">
                  {index + 1}
                </div>
                <div class="flex-1">
                  <div class="h-6 bg-gray-200 dark:bg-gray-600 rounded"></div>
                </div>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state with icon and message.

  ## Examples

      <.empty_state icon="👥" message="Warte auf Spieler..." />
      <.empty_state icon="🎮" message="Keine Spiele gefunden" />
  """
  attr :icon, :string, required: true
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-12", @class]}>
      <div class="text-6xl mb-4 opacity-50">
        {@icon}
      </div>
      <p class="text-gray-600 dark:text-gray-400 text-lg">
        {@message}
      </p>
    </div>
    """
  end

  @doc """
  Renders a page header with gradient icon badge.

  ## Examples

      <.page_header icon="🎮" title="Neues Spiel" />
      <.page_header icon="👥" title="Dashboard" subtitle="Verwalte dein Spiel" />
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :class, :string, default: nil

  def page_header(assigns) do
    ~H"""
    <div class={["text-center mb-10", @class]}>
      <.gradient_icon_badge icon={@icon} gradient={@gradient} size="lg" />
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
        {@title}
      </h1>
      <p :if={@subtitle} class="text-gray-500 dark:text-gray-400 text-sm">
        {@subtitle}
      </p>
    </div>
    """
  end
end
