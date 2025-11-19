defmodule MimimiWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: MimimiWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders a glassmorphism card container.

  ## Examples

      <.glass_card>
        Content here
      </.glass_card>

      <.glass_card class="p-6">
        Custom padding
      </.glass_card>
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def glass_card(assigns) do
    ~H"""
    <div
      class={[
        "backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl shadow-2xl border border-gray-200/50 dark:border-gray-700/50",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a gradient icon badge.

  ## Examples

      <.gradient_icon_badge icon="🎮" />
      <.gradient_icon_badge icon="👥" gradient="from-blue-500 to-cyan-500" />
      <.gradient_icon_badge icon="🏆" size="lg" gradient="from-yellow-500 to-orange-500" />
  """
  attr :icon, :string, required: true
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :string, default: nil

  def gradient_icon_badge(assigns) do
    sizes = %{
      "sm" => %{container: "w-12 h-12", icon: "text-2xl"},
      "md" => %{container: "w-16 h-16", icon: "text-3xl"},
      "lg" => %{container: "w-20 h-20", icon: "text-4xl"}
    }

    size_classes = Map.fetch!(sizes, assigns.size)
    assigns = assign(assigns, :size_classes, size_classes)

    ~H"""
    <div class={[
      "inline-flex items-center justify-center rounded-full bg-gradient-to-br shadow-lg mb-4",
      @gradient,
      @size_classes.container,
      @class
    ]}>
      <span class={@size_classes.icon}>{@icon}</span>
    </div>
    """
  end

  @doc """
  Renders a gradient button with shimmer effect.

  ## Examples

      <.gradient_button phx-click="action">Click me</.gradient_button>
      <.gradient_button gradient="from-green-500 to-emerald-500">Success</.gradient_button>
      <.gradient_button size="sm" gradient="from-blue-500 to-cyan-500">Small</.gradient_button>
  """
  attr :gradient, :string, default: "from-purple-600 via-purple-500 to-pink-500"
  attr :hover_gradient, :string, default: "from-purple-700 via-purple-600 to-pink-600"
  attr :shadow_color, :string, default: "shadow-purple-500/30"
  attr :hover_shadow_color, :string, default: "shadow-purple-500/40"
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :full_width, :boolean, default: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled phx-click phx-value-id type)
  slot :inner_block, required: true

  def gradient_button(assigns) do
    size_classes = %{
      "sm" => "py-2 text-sm",
      "md" => "py-4",
      "lg" => "py-5 text-lg"
    }

    assigns = assign(assigns, :size_class, Map.fetch!(size_classes, assigns.size))

    ~H"""
    <button
      class={[
        "relative bg-gradient-to-r text-white rounded-2xl shadow-xl hover:shadow-2xl hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 font-semibold overflow-hidden group",
        @gradient,
        "hover:#{@hover_gradient}",
        @shadow_color,
        "hover:#{@hover_shadow_color}",
        @size_class,
        @full_width && "w-full",
        @class
      ]}
      {@rest}
    >
      <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700">
      </div>
      <span class="relative">
        {render_slot(@inner_block)}
      </span>
    </button>
    """
  end

  @doc """
  Renders a glassmorphism input field with gradient hover effect.

  ## Examples

      <.glass_input name="username" placeholder="Enter username" />
      <.glass_input field={@form[:email]} type="email" gradient="from-blue-500 to-cyan-500" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :placeholder, :string, default: nil
  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(disabled form min max maxlength minlength pattern autocomplete inputmode required readonly)

  def glass_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> glass_input()
  end

  def glass_input(assigns) do
    ~H"""
    <div class="relative group">
      <div class={[
        "absolute inset-0 bg-gradient-to-r rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300",
        @gradient
      ]}>
      </div>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        placeholder={@placeholder}
        class={[
          "relative w-full px-4 py-3.5 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl focus:border-purple-500 dark:focus:border-purple-400 focus:ring-4 focus:ring-purple-100 dark:focus:ring-purple-900/30 transition-all duration-200 dark:text-white outline-none",
          @class
        ]}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Renders a stat card with icon and value.

  ## Examples

      <.stat_card icon="👥" label="Aktive Spiele" value={@active_games} />
      <.stat_card icon="⏳" label="Wartende Spiele" value={@waiting_games} gradient="from-blue-500 to-cyan-500" />
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :class, :string, default: nil

  def stat_card(assigns) do
    assigns = assign(assigns, :card_class, ["p-6 text-center", assigns[:class]])

    ~H"""
    <.glass_card class={@card_class}>
      <div class={[
        "inline-flex items-center justify-center w-16 h-16 rounded-full bg-gradient-to-br mb-4 shadow-lg",
        @gradient
      ]}>
        <span class="text-3xl">{@icon}</span>
      </div>
      <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
        {@value}
      </div>
      <div class="text-sm text-gray-600 dark:text-gray-400">
        {@label}
      </div>
    </.glass_card>
    """
  end

  @doc """
  Renders a player avatar with optional status indicator.

  ## Examples

      <.player_avatar avatar="🦊" />
      <.player_avatar avatar="🐼" status={:picked} />
      <.player_avatar avatar="🦁" status={:waiting} size="lg" />
  """
  attr :avatar, :string, required: true
  attr :status, :atom, default: nil, values: [nil, :picked, :waiting, :online]
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :string, default: nil
  attr :rest, :global

  def player_avatar(assigns) do
    sizes = %{
      "sm" => "w-12 h-12 text-2xl",
      "md" => "w-16 h-16 text-3xl",
      "lg" => "w-20 h-20 text-4xl"
    }

    status_indicators = %{
      picked: "✓",
      waiting: "⏳",
      online: "●"
    }

    assigns =
      assigns
      |> assign(:size_class, Map.fetch!(sizes, assigns.size))
      |> assign(:status_indicator, Map.get(status_indicators, assigns.status))

    ~H"""
    <div class={["relative inline-block", @class]} {@rest}>
      <div class={[
        "flex items-center justify-center rounded-full bg-gradient-to-br from-purple-100 to-pink-100 dark:from-purple-900/30 dark:to-pink-900/30",
        @size_class
      ]}>
        {@avatar}
      </div>
      <div
        :if={@status_indicator}
        class="absolute -top-1 -right-1 w-6 h-6 bg-gradient-to-br from-green-500 to-emerald-500 rounded-full flex items-center justify-center text-xs text-white shadow-lg"
      >
        {@status_indicator}
      </div>
    </div>
    """
  end

  @doc """
  Renders a progress bar with gradient fill.

  ## Examples

      <.progress_bar value={75} />
      <.progress_bar value={@percentage} gradient="from-green-500 to-emerald-500" />
  """
  attr :value, :integer, required: true
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :class, :string, default: nil

  def progress_bar(assigns) do
    ~H"""
    <div class={["w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden", @class]}>
      <div
        class={["h-full bg-gradient-to-r transition-all duration-500", @gradient]}
        style={"width: #{@value}%"}
      >
      </div>
    </div>
    """
  end

  @doc """
  Renders a page container with gradient background.

  ## Examples

      <.page_container>
        <.glass_card class="p-8">
          Content here
        </.glass_card>
      </.page_container>
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def page_container(assigns) do
    ~H"""
    <div
      class={[
        "min-h-screen flex items-center justify-center px-4 py-12 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a checkbox styled as a button with gradient effect when selected.

  ## Examples

      <.checkbox_button name="word_types[]" value="noun" checked={@form_data["noun"]} label="Nomen" />
      <.checkbox_button name="types[]" value="verb" checked={true} label="Verb" gradient="from-blue-500 to-cyan-500" />
  """
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :class, :string, default: nil
  attr :rest, :global

  def checkbox_button(assigns) do
    ~H"""
    <label class={["relative cursor-pointer", @class]}>
      <input
        type="checkbox"
        name={@name}
        value={@value}
        checked={@checked}
        class="hidden peer"
        {@rest}
      />
      <div class={[
        "relative overflow-hidden rounded-2xl p-4 text-center border-2 transition-all duration-200",
        "peer-checked:border-transparent peer-checked:text-white peer-checked:shadow-xl",
        "border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300",
        "hover:border-gray-300 dark:hover:border-gray-600"
      ]}>
        <div class={[
          "absolute inset-0 bg-gradient-to-r opacity-0 peer-checked:opacity-100 transition-opacity duration-200",
          @gradient
        ]}>
        </div>
        <span class="relative font-semibold">{@label}</span>
      </div>
    </label>
    """
  end

  @doc """
  Renders a radio button styled as a button with gradient effect when selected.

  ## Examples

      <.radio_button name="grid_size" value="2" checked={@grid_size == "2"} label="2×2" />
      <.radio_button name="size" value="4" checked={true} label="4×4" gradient="from-green-500 to-emerald-500" />
  """
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :gradient, :string, default: "from-purple-500 to-pink-500"
  attr :class, :string, default: nil
  attr :rest, :global

  def radio_button(assigns) do
    ~H"""
    <label class={["relative cursor-pointer", @class]}>
      <input
        type="radio"
        name={@name}
        value={@value}
        checked={@checked}
        class="hidden peer"
        {@rest}
      />
      <div class={[
        "relative overflow-hidden rounded-2xl p-4 text-center border-2 transition-all duration-200",
        "peer-checked:border-transparent peer-checked:text-white peer-checked:shadow-xl",
        "border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300",
        "hover:border-gray-300 dark:hover:border-gray-600"
      ]}>
        <div class={[
          "absolute inset-0 bg-gradient-to-r opacity-0 peer-checked:opacity-100 transition-opacity duration-200",
          @gradient
        ]}>
        </div>
        <span class="relative font-semibold">{@label}</span>
      </div>
    </label>
    """
  end

  @doc """
  Renders an error banner with icon and message.

  ## Examples

      <.error_banner message="Spielraum nicht gefunden" />
      <.error_banner message={@error} />
  """
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def error_banner(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-2 px-4 py-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-xl",
      @class
    ]}>
      <span class="text-lg">⚠️</span>
      <p class="text-sm text-red-600 dark:text-red-400 font-medium">{@message}</p>
    </div>
    """
  end

  @doc """
  Renders a loading spinner.

  ## Examples

      <.spinner />
      <.spinner class="h-16 w-16" />
      <.spinner color="border-blue-600 dark:border-blue-400" />
  """
  attr :class, :string, default: nil
  attr :color, :string, default: "border-purple-600 dark:border-purple-400"

  def spinner(assigns) do
    ~H"""
    <div class={[
      "animate-spin rounded-full border-b-2 mx-auto",
      @color,
      @class || "h-12 w-12"
    ]}>
    </div>
    """
  end

  @doc """
  Renders a divider with centered text.

  ## Examples

      <.divider_with_text text="oder" />
      <.divider_with_text text="ODER" />
  """
  attr :text, :string, required: true
  attr :class, :string, default: nil

  def divider_with_text(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-0 flex items-center">
        <div class="w-full border-t-2 border-gray-200 dark:border-gray-700"></div>
      </div>
      <div class="relative flex justify-center">
        <span class="px-4 text-sm font-semibold text-gray-500 dark:text-gray-400 bg-gradient-to-b from-indigo-50 to-white dark:from-gray-950 dark:to-gray-900">
          {@text}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(MimimiWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MimimiWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
