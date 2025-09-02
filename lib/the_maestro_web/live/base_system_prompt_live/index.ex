defmodule TheMaestroWeb.BaseSystemPromptLive.Index do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Prompts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Base system prompts
        <:actions>
          <.button variant="primary" navigate={~p"/base_system_prompts/new"}>
            <.icon name="hero-plus" /> New Base system prompt
          </.button>
        </:actions>
      </.header>

      <.table
        id="base_system_prompts"
        rows={@streams.base_system_prompts}
        row_click={
          fn {_id, base_system_prompt} ->
            JS.navigate(~p"/base_system_prompts/#{base_system_prompt}")
          end
        }
      >
        <:col :let={{_id, base_system_prompt}} label="Name">{base_system_prompt.name}</:col>
        <:col :let={{_id, base_system_prompt}} label="Prompt text">
          {base_system_prompt.prompt_text}
        </:col>
        <:action :let={{_id, base_system_prompt}}>
          <div class="sr-only">
            <.link navigate={~p"/base_system_prompts/#{base_system_prompt}"}>Show</.link>
          </div>
          <.link navigate={~p"/base_system_prompts/#{base_system_prompt}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, base_system_prompt}}>
          <.link
            phx-click={JS.push("delete", value: %{id: base_system_prompt.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Base system prompts")
     |> stream(:base_system_prompts, Prompts.list_base_system_prompts())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    base_system_prompt = Prompts.get_base_system_prompt!(id)
    {:ok, _} = Prompts.delete_base_system_prompt(base_system_prompt)

    {:noreply, stream_delete(socket, :base_system_prompts, base_system_prompt)}
  end
end
