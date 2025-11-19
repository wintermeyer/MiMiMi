defmodule MimimiWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MimimiWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a
          href="/"
          class="flex-1 flex w-fit items-center gap-2 text-2xl font-bold text-purple-600 dark:text-purple-400"
        >
          MiMiMi
        </a>
      </div>
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <.footer active_games={Map.get(assigns, :active_games, 0)} />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders the footer with copyright, active games count, legal links and funding information.
  """
  attr :active_games, :integer, default: 0

  def footer(assigns) do
    ~H"""
    <footer class="bg-white/90 dark:bg-gray-800/90 backdrop-blur-md border-t border-gray-200/50 dark:border-gray-700/50 px-4 py-4 mt-8">
      <div class="max-w-7xl mx-auto">
        <div class="flex flex-col sm:flex-row justify-between items-center gap-3 text-sm">
          <div class="flex flex-col sm:flex-row items-center gap-3">
            <div class="text-gray-600 dark:text-gray-400">
              © 2025 MiMiMi
            </div>
            <div class="hidden sm:block text-gray-300 dark:text-gray-600">•</div>
            <a
              href="https://wort.schule/seite/impressum"
              target="_blank"
              rel="noopener noreferrer"
              class="text-purple-600 dark:text-purple-400 hover:text-purple-700 dark:hover:text-purple-300 transition-colors duration-200"
            >
              Impressum
            </a>
          </div>

          <div class="flex items-center gap-3">
            <div class="text-gray-600 dark:text-gray-400">
              Aktive Spiele:
              <span class="font-bold text-purple-600 dark:text-purple-400">{@active_games}</span>
            </div>
            <div class="hidden sm:block text-gray-300 dark:text-gray-600">•</div>
            <div class="flex items-center gap-2">
              <span class="text-xs text-gray-500 dark:text-gray-500">Gefördert durch:</span>
              <img
                src="/images/BMBFSFJ_de_v1__Web_farbig.webp"
                alt="Bundesministerium für Familie, Senioren, Frauen und Jugend"
                class="h-24 w-auto"
              />
            </div>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
