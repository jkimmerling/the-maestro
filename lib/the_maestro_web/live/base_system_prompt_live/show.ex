defmodule TheMaestroWeb.BaseSystemPromptLive.Show do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Prompts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Base system prompt {@base_system_prompt.id}
        <:subtitle>This is a base_system_prompt record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/base_system_prompts"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/base_system_prompts/#{@base_system_prompt}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit base_system_prompt
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@base_system_prompt.name}</:item>
        <:item title="Prompt text">{@base_system_prompt.prompt_text}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Base system prompt")
     |> assign(:base_system_prompt, Prompts.get_base_system_prompt!(id))}
  end
end
