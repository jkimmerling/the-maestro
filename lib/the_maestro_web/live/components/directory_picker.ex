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
     socket
     |> assign(assigns)
     |> assign_new(:current_path, fn -> start end)
     |> assign_new(:filter, fn -> "" end)
     |> assign_new(:cursor, fn -> 0 end)
     |> load_dirs(start)}
  end

  defp load_dirs(socket, path) do
    {dirs, err} = list_dirs(path)
    filtered = apply_filter(dirs, socket.assigns[:filter] || "")

    socket
    |> assign(:current_path, path)
    |> assign(:all_entries, dirs)
    |> assign(:entries, filtered)
    |> assign(:cursor, if(filtered == [], do: -1, else: 0))
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

  # Keyboard navigation helpers
  def handle_event("dp_nav", %{"op" => "up"}, socket), do: {:noreply, move_cursor(socket, -1)}
  def handle_event("dp_nav", %{"op" => "down"}, socket), do: {:noreply, move_cursor(socket, 1)}

  def handle_event("dp_nav", %{"op" => "home"}, socket),
    do: {:noreply, move_cursor(socket, :home)}

  def handle_event("dp_nav", %{"op" => "end"}, socket), do: {:noreply, move_cursor(socket, :end)}

  def handle_event("dp_nav", %{"op" => "page_up"}, socket),
    do: {:noreply, move_cursor(socket, {:jump, -10})}

  def handle_event("dp_nav", %{"op" => "page_down"}, socket),
    do: {:noreply, move_cursor(socket, {:jump, 10})}

  def handle_event("dp_nav", _params, socket), do: {:noreply, socket}

  defp clamp(n, minv, maxv) when is_integer(n) and is_integer(minv) and is_integer(maxv) do
    n |> max(minv) |> min(maxv)
  end

  defp move_cursor(socket, :home) do
    {len, _cur} = entries_len_cur(socket)
    assign(socket, :cursor, if(len == 0, do: -1, else: 0))
  end

  defp move_cursor(socket, :end) do
    {len, _cur} = entries_len_cur(socket)
    assign(socket, :cursor, if(len == 0, do: -1, else: len - 1))
  end

  defp move_cursor(socket, {:jump, j}) when is_integer(j), do: move_cursor_delta(socket, j)
  defp move_cursor(socket, delta) when is_integer(delta), do: move_cursor_delta(socket, delta)

  defp move_cursor_delta(socket, delta) do
    {len, cur} = entries_len_cur(socket)
    new_index = if len == 0, do: -1, else: clamp(cur + delta, 0, len - 1)
    assign(socket, :cursor, new_index)
  end

  defp entries_len_cur(socket) do
    entries = socket.assigns[:entries] || []
    len = length(entries)
    cur = socket.assigns[:cursor] || if(len == 0, do: -1, else: 0)
    {len, cur}
  end

  def handle_event("enter_selected", _params, socket) do
    entries = socket.assigns[:entries] || []
    cur = socket.assigns[:cursor] || -1

    case Enum.at(entries, cur) do
      {name, _full} when is_binary(name) -> handle_event("enter", %{"dir" => name}, socket)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("filter", %{"q" => q}, socket) do
    dirs = socket.assigns[:all_entries] || []
    filtered = apply_filter(dirs, q)

    {:noreply,
     assign(socket, filter: q, entries: filtered, cursor: if(filtered == [], do: -1, else: 0))}
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

  defp apply_filter(dirs, q) when is_binary(q) do
    qq = String.downcase(String.trim(q))

    if qq == "" do
      dirs
    else
      Enum.filter(dirs, fn {name, _} -> String.contains?(String.downcase(name), qq) end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="terminal-card terminal-border-amber p-4" phx-hook="DirPickerNav">
      <h4 class="text-xl font-bold text-amber-400 mb-3 glow">DIRECTORY BROWSER</h4>
      <div class="flex items-center justify-between mb-3">
        <div class="text-amber-300 text-sm truncate">Current Path: {@current_path}</div>
        <div class="space-x-2">
          <button class="px-3 py-1 rounded text-xs btn-amber" phx-click="up" phx-target={@myself}>
            UP
          </button>
          <button
            class="px-3 py-1 rounded text-xs btn-green"
            phx-click="choose_here"
            phx-target={@myself}
          >
            CHOOSE HERE
          </button>
          <button class="px-3 py-1 rounded text-xs btn-red" phx-click="cancel" phx-target={@myself}>
            CANCEL
          </button>
        </div>
      </div>
      <div class="mb-3">
        <input
          name="q"
          value={@filter}
          placeholder="Filter folders..."
          class="input-terminal dp-filter"
          phx-change="filter"
          phx-debounce="200"
          phx-target={@myself}
        />
      </div>
      <div :if={@error} class="terminal-card terminal-border-red p-2 text-xs text-red-300 mb-2">
        Failed to list: {@error}
      </div>
      <div
        class="space-y-1 text-green-400 dp-list"
        role="listbox"
        aria-activedescendant={if @cursor >= 0, do: "dp-#{@id}-#{@cursor}", else: nil}
      >
        <%= for {{name, _full}, idx} <- Enum.with_index(@entries) do %>
          <div
            id={"dp-#{@id}-#{idx}"}
            role="option"
            aria-selected={@cursor == idx}
            class={[
              "cursor-pointer flex items-center px-2 py-1 rounded outline-none",
              @cursor == idx && "bg-amber-600/10 text-green-300 glow",
              @cursor != idx && "hover:text-green-300"
            ]}
            phx-click="enter"
            phx-value-dir={name}
            phx-target={@myself}
            tabindex="-1"
            data-index={idx}
            data-name={name}
          >
            <.icon name="hero-folder" class="w-4 h-4 mr-1" /> {name}/
          </div>
        <% end %>
        <%= if @entries == [] do %>
          <div class="text-amber-300 text-sm opacity-80">(No subdirectories)</div>
        <% end %>
      </div>
    </div>
    """
  end
end
