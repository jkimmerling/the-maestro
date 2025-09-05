defmodule TheMaestroWeb.DirectoryPicker do
  use TheMaestroWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    start = assigns[:start_path] || File.cwd!() |> Path.expand()

    {:ok,
     socket |> assign(assigns) |> assign_new(:current_path, fn -> start end) |> load_dirs(start)}
  end

  defp load_dirs(socket, path) do
    {dirs, err} = list_dirs(path)

    socket
    |> assign(:current_path, path)
    |> assign(:entries, dirs)
    |> assign(:error, err)
  end

  defp list_dirs(path) do
    case File.ls(path) do
      {:ok, items} ->
        dirs =
          items
          |> Enum.map(&{&1, Path.join(path, &1)})
          |> Enum.filter(fn {_name, full} -> File.dir?(full) end)
          |> Enum.sort_by(&elem(&1, 0))

        {dirs, nil}

      {:error, reason} ->
        {[], to_string(reason)}
    end
  end

  @impl true
  def handle_event("up", _params, socket) do
    newp = socket.assigns.current_path |> Path.join("..") |> Path.expand()
    {:noreply, load_dirs(socket, newp)}
  end

  def handle_event("enter", %{"dir" => dir}, socket) do
    newp = Path.join(socket.assigns.current_path, dir) |> Path.expand()
    {:noreply, load_dirs(socket, newp)}
  end

  def handle_event("choose_here", _params, socket) do
    send(
      self(),
      {__MODULE__, :selected, socket.assigns.current_path, socket.assigns.context || :default}
    )

    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), {__MODULE__, :cancel, socket.assigns.context || :default})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-2">
      <div class="flex items-center justify-between mb-2">
        <div class="text-xs opacity-70 truncate">{@current_path}</div>
        <div class="space-x-2">
          <button class="btn btn-xs" phx-click="up" phx-target={@myself}>Up</button>
          <button class="btn btn-xs btn-primary" phx-click="choose_here" phx-target={@myself}>
            Choose here
          </button>
          <button class="btn btn-xs" phx-click="cancel" phx-target={@myself}>Cancel</button>
        </div>
      </div>
      <div :if={@error} class="alert alert-warning text-xs mb-2">Failed to list: {@error}</div>
      <ul class="menu bg-base-200 rounded">
        <%= for {name, _full} <- @entries do %>
          <li>
            <a phx-click="enter" phx-value-dir={name} phx-target={@myself}>
              <.icon name="hero-folder" class="w-4 h-4 mr-1" /> {name}
            </a>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
