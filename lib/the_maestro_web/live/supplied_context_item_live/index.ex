defmodule TheMaestroWeb.SuppliedContextItemLive.Index do
  use TheMaestroWeb, :live_view

  alias Phoenix.LiveView.JS
  alias TheMaestro.SuppliedContext
  alias TheMaestro.SystemPrompts

  @provider_filters [:all, :openai, :anthropic, :gemini, :shared]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} container_class={container_class(@filter_type)}>
      <.header>
        Listing Supplied context items
        <:actions>
          <.link phx-click="new" class="btn btn-primary">
            <.icon name="hero-plus" /> New Supplied context item
          </.link>
        </:actions>
      </.header>

      <div class="flex items-center gap-4 mb-4">
        <.link
          patch={~p"/supplied_context?type=persona"}
          class={tab_class(@filter_type == :persona)}
        >
          Personas
        </.link>
        <.link
          patch={~p"/supplied_context?type=system_prompt"}
          class={tab_class(@filter_type == :system_prompt)}
        >
          System Prompts
        </.link>
      </div>

      <%= if @filter_type == :system_prompt do %>
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for filter <- @provider_filters do %>
            <.link
              patch={provider_patch(@filter_type, filter)}
              class={provider_tab_class(filter, @provider_filter)}
            >
              {provider_label(filter)}
            </.link>
          <% end %>
        </div>

        <div
          id="system-prompts"
          class="mx-auto w-full max-w-[1600px] grid gap-6 sm:grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3"
        >
          <%= for {dom_id, prompt} <- @streams.supplied_context_items do %>
            <div
              id={dom_id}
              class="rounded-lg border border-slate-800 bg-slate-900/60 p-4 shadow-sm overflow-hidden"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="text-sm font-semibold text-slate-100 break-words">{prompt.name}</h3>
                    <span class="badge badge-xs text-slate-300">
                      {provider_label(prompt.provider)}
                    </span>
                    <span class="badge badge-xs text-slate-400">
                      {render_format_label(prompt.render_format)}
                    </span>
                    <%= if prompt.is_default do %>
                      <span class="badge badge-xs badge-info">Default</span>
                    <% end %>
                    <%= if prompt.immutable do %>
                      <span class="badge badge-xs badge-warn">
                        <.icon name="hero-lock-closed" class="mr-1 h-3 w-3" /> Immutable
                      </span>
                    <% end %>
                  </div>
                  <div class="mt-1 flex flex-wrap gap-2 text-[11px] text-slate-400">
                    <span>Version {prompt.version || "—"}</span>
                    <%= if prompt.labels && Map.has_key?(prompt.labels, "version") do %>
                      <span>Label v{Map.get(prompt.labels, "version")}</span>
                    <% end %>
                    <span>Position {prompt.position || 0}</span>
                    <%= if prompt.source_ref do %>
                      <span class="truncate" title={prompt.source_ref}>{prompt.source_ref}</span>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center gap-2 text-xs">
                  <.link phx-click="edit" phx-value-id={prompt.id} class="btn btn-xs">
                    <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Edit
                  </.link>
                  <.link
                    phx-click={
                      JS.push("delete", value: %{id: prompt.id})
                      |> JS.dispatch("phx:hide", to: "##{dom_id}")
                    }
                    data-confirm="Are you sure?"
                    class="btn btn-xs btn-danger"
                  >
                    <.icon name="hero-trash" class="h-3.5 w-3.5" />
                  </.link>
                </div>
              </div>

              <p class="mt-3 text-sm text-slate-300">{truncate_text(prompt.text, 220)}</p>

              <div class="mt-3">
                <button
                  type="button"
                  class="btn btn-xs"
                  phx-click={preview_toggle(preview_dom_id(prompt.id))}
                >
                  <.icon name="hero-eye" class="h-3.5 w-3.5" /> Preview
                </button>
                <div
                  id={preview_dom_id(prompt.id)}
                  class="mt-2 hidden rounded border border-slate-800 bg-slate-950/80 p-3 text-xs text-slate-200 overflow-x-auto max-h-80 overflow-y-auto"
                  phx-no-curly-interpolation
                >
                  <code class="block whitespace-pre-wrap break-words text-[11px] leading-relaxed">
                    {preview_payload(prompt)}
                  </code>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @streams.supplied_context_items == [] do %>
            <div class="rounded-lg border border-dashed border-slate-700 bg-slate-900/80 p-6 text-center text-sm text-slate-400">
              No system prompts match this filter.
            </div>
          <% end %>
        </div>
      <% else %>
        <.table
          id="supplied-context-items"
          rows={@streams.supplied_context_items}
          row_click={
            fn {_id, supplied_context_item} ->
              JS.navigate(~p"/supplied_context/#{supplied_context_item}")
            end
          }
        >
          <:col :let={{_id, supplied_context_item}} label="Name">{supplied_context_item.name}</:col>
          <:col :let={{_id, supplied_context_item}} label="Type">{supplied_context_item.type}</:col>
          <:col :let={{_id, supplied_context_item}} label="Version">
            {supplied_context_item.version}
          </:col>
          <:col :let={{_id, supplied_context_item}} label="Provider">
            {supplied_context_item.provider}
          </:col>
          <:col :let={{_id, supplied_context_item}} label="Labels">
            {inspect(supplied_context_item.labels)}
          </:col>
          <:action :let={{_id, supplied_context_item}}>
            <div class="sr-only">
              <.link navigate={~p"/supplied_context/#{supplied_context_item}"}>Show</.link>
            </div>
            <.link phx-click="edit" phx-value-id={supplied_context_item.id}>Edit</.link>
          </:action>
          <:action :let={{_dom_id, supplied_context_item}}>
            <.link
              phx-click="delete"
              phx-value-id={supplied_context_item.id}
              data-confirm="Are you sure?"
            >
              Delete
            </.link>
          </:action>
        </.table>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Supplied context items")
     |> assign(:filter_type, :persona)
     |> assign(:provider_filter, :all)
     |> assign(:provider_filters, @provider_filters)
     |> stream(:supplied_context_items, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    type = parse_type(Map.get(params, "type"))
    provider = parse_provider(Map.get(params, "provider"))
    provider = if type == :system_prompt, do: provider, else: :all

    items = load_items(type, provider)

    {:noreply,
     socket
     |> assign(:filter_type, type)
     |> assign(:provider_filter, provider)
     |> stream(:supplied_context_items, items, reset: true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    supplied_context_item = SuppliedContext.get_supplied_context_item!(id)
    {:ok, _} = SuppliedContext.delete_supplied_context_item(supplied_context_item)

    {:noreply, stream_delete(socket, :supplied_context_items, supplied_context_item)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/supplied_context/new")}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/supplied_context/#{id}/edit?return_to=index&type=#{socket.assigns.filter_type}&provider=#{socket.assigns.provider_filter}"
     )}
  end

  defp parse_type("persona"), do: :persona
  defp parse_type("system_prompt"), do: :system_prompt
  defp parse_type(_), do: :persona

  defp parse_provider("openai"), do: :openai
  defp parse_provider("anthropic"), do: :anthropic
  defp parse_provider("gemini"), do: :gemini
  defp parse_provider("shared"), do: :shared
  defp parse_provider(_), do: :all

  defp tab_class(true), do: "px-3 py-2 rounded border border-blue-500 text-blue-300"

  defp tab_class(false),
    do: "px-3 py-2 rounded border border-transparent text-slate-500 hover:text-slate-300"

  defp provider_tab_class(filter, filter),
    do: "px-2.5 py-1.5 text-xs rounded border border-emerald-500 text-emerald-300"

  defp provider_tab_class(_filter, _active),
    do:
      "px-2.5 py-1.5 text-xs rounded border border-transparent text-slate-400 hover:text-slate-200"

  defp provider_patch(:system_prompt, :all), do: ~p"/supplied_context?type=system_prompt"

  defp provider_patch(:system_prompt, provider),
    do: ~p"/supplied_context?type=system_prompt&provider=#{provider}"

  defp provider_patch(_type, _provider), do: ~p"/supplied_context"

  defp load_items(:persona, _provider), do: SuppliedContext.list_items(:persona)

  defp load_items(:system_prompt, provider) do
    include_shared? = provider != :shared
    provider_param = if provider == :all, do: :all, else: provider

    SuppliedContext.list_system_prompts(provider_param,
      include_shared: include_shared?,
      group_by_family: false
    )
  end

  defp provider_label(:all), do: "All"
  defp provider_label(:openai), do: "OpenAI"
  defp provider_label(:anthropic), do: "Anthropic"
  defp provider_label(:gemini), do: "Gemini"
  defp provider_label(:shared), do: "Shared"

  defp provider_label(provider) when is_atom(provider),
    do: provider |> Atom.to_string() |> String.capitalize()

  defp provider_label(provider) when is_binary(provider), do: provider |> String.capitalize()
  defp provider_label(other), do: inspect(other)

  defp render_format_label(:text), do: "Text"
  defp render_format_label(:anthropic_blocks), do: "Blocks"
  defp render_format_label(:gemini_parts), do: "Parts"
  defp render_format_label(other), do: Phoenix.Naming.humanize(other)

  defp truncate_text(nil, _), do: ""

  defp truncate_text(text, max) when is_binary(text) do
    String.slice(text, 0, max)
  end

  defp truncate_text(_text, _max), do: ""

  def preview_payload(prompt) do
    stack = %{prompts: [%{prompt: prompt, overrides: %{}}]}
    provider = effective_preview_provider(prompt)
    payload = render_preview_payload(provider, stack, prompt)
    encode_preview_payload(payload)
  end

  defp effective_preview_provider(%{provider: :shared, render_format: rf}),
    do: default_preview_provider(rf)

  defp effective_preview_provider(%{provider: other}), do: other

  defp render_preview_payload(:openai, stack, _prompt),
    do: SystemPrompts.render_for_provider(:openai, stack)

  defp render_preview_payload(:anthropic, stack, _prompt),
    do: SystemPrompts.render_for_provider(:anthropic, stack)

  defp render_preview_payload(:gemini, stack, _prompt),
    do: SystemPrompts.render_for_provider(:gemini, stack)

  defp render_preview_payload(_other, _stack, prompt), do: prompt.text || ""

  defp encode_preview_payload(bin) when is_binary(bin), do: bin
  defp encode_preview_payload(list) when is_list(list), do: Jason.encode!(list, pretty: true)
  defp encode_preview_payload(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp encode_preview_payload(other), do: inspect(other)

  defp default_preview_provider(:anthropic_blocks), do: :anthropic
  defp default_preview_provider(:gemini_parts), do: :gemini
  defp default_preview_provider(_), do: :openai

  defp preview_dom_id(id), do: "prompt-preview-#{id}"

  defp preview_toggle(dom_id), do: JS.toggle(to: "##{dom_id}")

  # Layout container width rules per tab
  defp container_class(:system_prompt), do: "mx-auto w-[80vw] max-w-[1600px] space-y-4"
  defp container_class(_), do: "mx-auto max-w-2xl space-y-4"
end
