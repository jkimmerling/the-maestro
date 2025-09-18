defmodule TheMaestroWeb.SystemPromptPickerComponent do
  @moduledoc """
  Displays per-provider system prompt selections with drag-and-drop ordering
  and controls to enable/disable or remove prompts.
  """

  use TheMaestroWeb, :live_component

  alias Phoenix.LiveView.JS

  @type provider :: :openai | :anthropic | :gemini

  attr :id, :string, required: true
  attr :providers, :list, required: true
  attr :active_provider, :atom, required: true
  attr :selected_by_provider, :map, required: true
  attr :library_by_provider, :map, required: true
  attr :selections, :map, default: %{}
  attr :disabled, :boolean, default: false

  def render(assigns) do
    active_list = Map.get(assigns.selected_by_provider, assigns.active_provider, [])

    available_list =
      available_for(assigns.library_by_provider, assigns.active_provider, active_list)

    assigns =
      assigns
      |> assign(:provider_labels, %{
        openai: "OpenAI",
        anthropic: "Anthropic",
        gemini: "Gemini"
      })
      |> assign(:active_list, active_list)
      |> assign(:available_list, available_list)

    ~H"""
    <section class="space-y-4" id={@id}>
      <header class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold tracking-wide text-slate-200 uppercase">
            System Prompts
          </h3>
          <button
            type="button"
            class="btn btn-xs"
            phx-click="prompt_picker:refresh"
            phx-value-provider={@active_provider}
            disabled={@disabled}
          >
            <.icon name="hero-arrow-path" class="h-4 w-4" />
            <span class="ml-1">Refresh Library</span>
          </button>
        </div>
        <p class="text-[13px] text-slate-400">
          Drag to reorder prompt segments. Immutable prompts stay locked at the top and enabled. Use the
          Add prompt selector to pull additional defaults or shared prompts into the stack.
        </p>
        <div class="flex gap-2">
          <%= for provider <- @providers do %>
            <button
              type="button"
              class={provider_tab_class(provider, @active_provider)}
              data-hotkey={provider_hotkey(provider)}
              data-hotkey-label={"Switch to #{Map.fetch!(@provider_labels, provider)}"}
              phx-click="prompt_picker:tab"
              phx-value-provider={provider}
              disabled={@disabled}
            >
              <span>{Map.fetch!(@provider_labels, provider)}</span>
              <span class="ml-2 text-xs text-slate-400">
                {length(Map.get(@selected_by_provider, provider, []))}
              </span>
            </button>
          <% end %>
        </div>
      </header>

      <div class="rounded-lg border border-slate-700 bg-slate-900/40">
        <div class="border-b border-slate-800 px-4 py-2 text-xs font-medium uppercase tracking-wide text-slate-300">
          Selected Prompts — {Map.fetch!(@provider_labels, @active_provider)}
        </div>

        <div class="px-3 py-2">
          <div
            id={sortable_id(@id, @active_provider)}
            class="flex flex-col gap-2"
            data-provider={@active_provider}
            phx-hook="PromptSortable"
            data-disabled={@disabled}
          >
            <%= if @active_list == [] do %>
              <div class="rounded border border-dashed border-slate-700 bg-slate-900/70 px-4 py-6 text-center text-sm text-slate-400">
                No prompts selected for this provider yet.
              </div>
            <% else %>
              <%= for entry <- @active_list do %>
                <div
                  id={entry_dom_id(@id, @active_provider, entry.id)}
                  class="rounded-lg border border-slate-800 bg-slate-900/80 p-3 shadow-sm"
                  data-prompt-id={entry.id}
                >
                  <div class="flex items-start justify-between gap-2">
                    <div class="flex flex-1 items-start gap-3">
                      <span
                        class="prompt-handle mt-1 inline-flex h-8 w-8 cursor-grab items-center justify-center rounded border border-slate-700 bg-slate-900 text-slate-400"
                        aria-label="Drag handle"
                      >
                        <.icon name="hero-bars-2" class="h-4 w-4" />
                      </span>
                      <div class="flex-1">
                        <div class="flex flex-wrap items-center gap-2">
                          <span class="text-sm font-semibold text-slate-100">
                            {entry.prompt.name}
                          </span>
                          <%= if entry.prompt.is_default do %>
                            <span class="badge badge-xs badge-info">Default</span>
                          <% end %>
                          <%= if entry.prompt.immutable do %>
                            <span
                              class="badge badge-xs badge-warn"
                              title="Prompt cannot be disabled or removed"
                            >
                              <.icon name="hero-lock-closed" class="mr-1 h-3 w-3" /> Immutable
                            </span>
                          <% end %>
                          <span class="badge badge-xs text-slate-300">
                            {format_render_format(entry.prompt.render_format)}
                          </span>
                          <%= if entry.prompt.provider == :shared do %>
                            <span class="badge badge-xs text-slate-400">Shared</span>
                          <% end %>
                        </div>
                        <div class="mt-1 flex flex-wrap gap-2 text-[11px] text-slate-400">
                          <span>Version {entry.prompt.version || "—"}</span>
                          <%= if entry.prompt.labels && Map.has_key?(entry.prompt.labels, "version") do %>
                            <span>Label v{Map.get(entry.prompt.labels, "version")}</span>
                          <% end %>
                          <%= if entry.prompt.source_ref do %>
                            <span class="truncate" title={entry.prompt.source_ref}>
                              {entry.prompt.source_ref}
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <div class="flex items-center gap-2">
                      <button
                        type="button"
                        class={toggle_button_class(entry.enabled)}
                        phx-click="prompt_picker:toggle"
                        phx-value-provider={@active_provider}
                        phx-value-id={entry.id}
                        disabled={@disabled or entry.prompt.immutable}
                      >
                        <.icon
                          name={if entry.enabled, do: "hero-pause", else: "hero-play"}
                          class="h-3.5 w-3.5"
                        />
                        <span class="ml-1 text-xs">
                          {if entry.enabled, do: "Disable", else: "Enable"}
                        </span>
                      </button>

                      <button
                        type="button"
                        class="btn btn-xs"
                        phx-click={preview_toggle_js(preview_dom_id(@id, @active_provider, entry.id))}
                      >
                        <.icon name="hero-eye" class="h-3.5 w-3.5" />
                        <span class="ml-1 text-xs">Preview</span>
                      </button>

                      <button
                        type="button"
                        class="btn btn-xs btn-danger"
                        phx-click="prompt_picker:remove"
                        phx-value-provider={@active_provider}
                        phx-value-id={entry.id}
                        disabled={@disabled or entry.prompt.immutable}
                      >
                        <.icon name="hero-trash" class="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </div>

                  <div
                    id={preview_dom_id(@id, @active_provider, entry.id)}
                    class="mt-3 hidden rounded border border-slate-800 bg-slate-950/80 p-3 text-xs text-slate-200"
                    phx-no-curly-interpolation
                  >
                    <code class="block whitespace-pre-wrap break-all text-[11px] leading-relaxed">
                      <%= preview_payload(@active_provider, entry) %>
                    </code>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div class="rounded-lg border border-slate-800 bg-slate-900/60 p-4">
        <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-300">
          Add Prompt
        </h4>
        <p class="mt-1 text-[12px] text-slate-400">
          Select a prompt below to append it to this provider's stack. Shared prompts may be added to
          any provider.
        </p>
        <div class="mt-3 flex flex-col gap-3 md:flex-row md:items-center">
          <.form
            for={%{}}
            id={add_form_id(@id, @active_provider)}
            phx-change="prompt_picker:add"
            phx-value-provider={@active_provider}
            phx-submit="prompt_picker:add"
          >
            <select
              name="prompt_id"
              class="input min-w-[16rem]"
              disabled={@disabled}
              value={Map.get(@selections, @active_provider, "")}
            >
              <option value="">Choose prompt…</option>
              <%= for prompt <- @available_list do %>
                <option value={prompt.id}>
                  {prompt.name} — {prompt_badge(prompt)}
                </option>
              <% end %>
            </select>
          </.form>
          <div class="flex flex-wrap gap-2 text-[11px] text-slate-500">
            <span class="badge badge-xs text-slate-300">Total {length(@available_list)}</span>
            <span class="badge badge-xs text-slate-400">
              Shared {count_shared(@available_list)}
            </span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp available_for(library_by_provider, active_provider, active_list) do
    taken = Enum.map(active_list, & &1.id) |> MapSet.new()

    library_by_provider
    |> Map.get(active_provider, [])
    |> Enum.reject(&MapSet.member?(taken, &1.id))
    |> Enum.sort_by(& &1.position, :asc)
  end

  defp sortable_id(base, provider), do: "#{base}-#{provider}-sortable"
  defp add_form_id(base, provider), do: "#{base}-#{provider}-add"
  defp entry_dom_id(base, provider, id), do: "#{base}-#{provider}-#{id}"
  defp preview_dom_id(base, provider, id), do: "#{base}-#{provider}-preview-#{id}"

  defp toggle_button_class(true), do: "btn btn-xs btn-ghost"
  defp toggle_button_class(false), do: "btn btn-xs btn-primary"

  defp provider_tab_class(provider, provider),
    do: "btn btn-xs btn-primary" <> " focus:ring focus:ring-blue-800"

  defp provider_tab_class(_provider, _active),
    do: "btn btn-xs btn-ghost"

  defp provider_hotkey(:openai), do: "shift+o"
  defp provider_hotkey(:anthropic), do: "shift+a"
  defp provider_hotkey(:gemini), do: "shift+g"

  defp preview_toggle_js(dom_id) do
    JS.toggle(%JS{}, to: "##{dom_id}")
  end

  defp format_render_format(:text), do: "Text"
  defp format_render_format(:anthropic_blocks), do: "Blocks"
  defp format_render_format(:gemini_parts), do: "Parts"
  defp format_render_format(other), do: Phoenix.Naming.humanize(other)

  defp prompt_badge(prompt) do
    provider = prompt.provider |> to_string() |> String.capitalize()
    version = prompt.labels && Map.get(prompt.labels, "version")

    cond do
      prompt.provider == :shared and version -> "Shared v#{version}"
      prompt.provider == :shared -> "Shared"
      version -> "#{provider} v#{version}"
      true -> provider
    end
  end

  defp count_shared(list), do: Enum.count(list, &(&1.provider == :shared))

  def preview_payload(provider, entry) do
    stack = %{prompts: [%{prompt: entry.prompt, overrides: entry.overrides || %{}}]}

    TheMaestro.SystemPrompts.render_for_provider(provider, stack)
    |> Jason.encode!(pretty: true)
    |> String.trim()
  end
end
