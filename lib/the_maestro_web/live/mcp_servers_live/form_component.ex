defmodule TheMaestroWeb.MCPServersLive.FormComponent do
  use TheMaestroWeb, :live_component

  alias Ecto.Changeset
  alias TheMaestro.MCP
  alias TheMaestro.MCP.Import
  alias TheMaestro.MCP.Servers

  @impl true
  def update(assigns, socket) do
    allow_import_tabs = Map.get(assigns, :allow_import_tabs, true)

    mode =
      assigns
      |> requested_mode()
      |> sanitize_mode(allow_import_tabs)

    mode_options = mode_configurations(allow_import_tabs)

    raw_fields = build_raw_fields(assigns.server)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:allow_import_tabs, allow_import_tabs)
     |> assign(:mode_options, mode_options)
     |> assign(:mode, mode)
     |> assign(:form, to_form(MCP.change_server(assigns.server), as: :server))
     |> assign(:raw_fields, raw_fields)
     |> assign_new(:import_source, fn -> "" end)
     |> assign(:import_error, nil)
     |> assign(:import_preview, nil)
     |> assign(:import_result, nil)}
  end

  @impl true
  def handle_event("select_mode", params, socket) do
    {:noreply, switch_mode(socket, Map.get(params, "mode"))}
  end

  def handle_event("switch_mode", params, socket) do
    handle_event("select_mode", params, socket)
  end

  def handle_event("validate", %{"server" => params}, %{assigns: %{mode: :manual}} = socket) do
    case normalize_form_params(params) do
      {:ok, attrs, raw_fields} ->
        changeset =
          socket.assigns.server
          |> MCP.change_server(attrs)
          |> Map.put(:action, :validate)

        {:noreply,
         assign(socket, form: to_form(changeset, action: :validate), raw_fields: raw_fields)}

      {:error, field, message, attrs, raw_fields} ->
        changeset =
          socket.assigns.server
          |> MCP.change_server(attrs)
          |> Changeset.add_error(field, message)
          |> Map.put(:action, :validate)

        {:noreply,
         assign(socket, form: to_form(changeset, action: :validate), raw_fields: raw_fields)}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"server" => params}, %{assigns: %{mode: :manual}} = socket) do
    case normalize_form_params(params) do
      {:ok, attrs, raw_fields} ->
        save_server(socket, socket.assigns.action, attrs, raw_fields)

      {:error, field, message, attrs, raw_fields} ->
        changeset =
          socket.assigns.server
          |> MCP.change_server(attrs)
          |> Changeset.add_error(field, message)

        {:noreply, assign(socket, form: to_form(changeset), raw_fields: raw_fields)}
    end
  end

  def handle_event("save", _params, socket), do: {:noreply, socket}

  def handle_event("update_import", %{"import" => %{"payload" => payload}}, socket) do
    {:noreply,
     socket
     |> assign(:import_source, payload || "")
     |> assign(:import_preview, nil)
     |> assign(:import_error, nil)
     |> assign(:import_result, nil)}
  end

  def handle_event("update_import", %{"payload" => payload}, socket) do
    handle_event("update_import", %{"import" => %{"payload" => payload}}, socket)
  end

  def handle_event("update_import", %{"value" => payload}, socket) do
    handle_event("update_import", %{"import" => %{"payload" => payload}}, socket)
  end

  def handle_event("parse_import", %{"import" => %{"payload" => payload}}, socket) do
    normalized =
      payload
      |> Kernel.||("")
      |> String.trim()

    socket = assign(socket, :import_source, normalized)

    if normalized == "" do
      {:noreply, assign(socket, :import_error, "Paste content to parse.")}
    else
      case parse_payload(socket.assigns.mode, normalized) do
        {:ok, preview} ->
          {:noreply,
           socket
           |> assign(:import_preview, preview)
           |> assign(:import_error, nil)
           |> assign(:import_result, nil)}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:import_preview, nil)
           |> assign(:import_error, message)
           |> assign(:import_result, nil)}
      end
    end
  end

  def handle_event("parse_import", _params, socket),
    do:
      handle_event(
        "parse_import",
        %{"import" => %{"payload" => socket.assigns.import_source}},
        socket
      )

  def handle_event("save_import", _params, socket) do
    case ensure_preview(socket) do
      {:ok, preview, updated_socket} ->
        case apply_import(updated_socket.assigns.mode, preview) do
          {:ok, message} ->
            notify_parent({:imported, message})

            {:noreply,
             updated_socket
             |> assign(:import_source, "")
             |> assign(:import_preview, nil)
             |> assign(:import_result, message)
             |> assign(:import_error, nil)}

          {:error, %Changeset{} = changeset} ->
            {:noreply, assign(updated_socket, :import_error, format_changeset_error(changeset))}

          {:error, message} ->
            {:noreply, assign(updated_socket, :import_error, message)}
        end

      {:error, message, updated_socket} ->
        {:noreply, assign(updated_socket, :import_error, message)}
    end
  end

  def handle_event("cancel", _params, socket) do
    notify_parent({:canceled, socket.assigns.server})
    {:noreply, socket}
  end

  defp ensure_preview(%{assigns: %{import_preview: preview}} = socket) when preview != nil do
    {:ok, preview, socket}
  end

  defp ensure_preview(socket) do
    payload = String.trim(socket.assigns.import_source || "")

    if payload == "" do
      {:error, "Parse the payload before saving.", socket}
    else
      case parse_payload(socket.assigns.mode, payload) do
        {:ok, preview} ->
          {:ok, preview, assign(socket, :import_preview, preview)}

        {:error, message} ->
          {:error, message, assign(socket, :import_preview, nil)}
      end
    end
  end

  defp switch_mode(socket, nil), do: socket

  defp switch_mode(socket, mode_param) do
    mode = sanitize_mode(mode_param, socket.assigns.allow_import_tabs)

    socket =
      socket
      |> assign(:mode, mode)
      |> assign(:import_source, "")
      |> assign(:import_error, nil)
      |> assign(:import_preview, nil)
      |> assign(:import_result, nil)

    if mode == :manual do
      assign(socket, :form, to_form(MCP.change_server(socket.assigns.server), as: :server))
    else
      socket
    end
  end

  defp save_server(socket, :new, attrs, raw_fields) do
    case MCP.create_server(attrs) do
      {:ok, server} ->
        notify_parent({:saved, server})

        {:noreply,
         socket
         |> put_flash(:info, "Created #{server.display_name}.")
         |> assign(:raw_fields, build_raw_fields(server))}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), raw_fields: raw_fields)}
    end
  end

  defp save_server(socket, :edit, attrs, raw_fields) do
    case MCP.update_server(socket.assigns.server, attrs) do
      {:ok, server} ->
        notify_parent({:saved, server})

        # Prefetch and cache tools for this server so pickers respond instantly
        Task.start(fn ->
          case TheMaestro.MCP.Client.discover_server(server) do
            {:ok, %{tools: tools}} ->
              ttl_ms =
                case server.metadata do
                  %{} = md -> ((md["tool_cache_ttl_minutes"] || 60) |> to_int()) * 60_000
                  _ -> 60 * 60_000
                end

              _ = TheMaestro.MCP.ToolsCache.put(server.id, tools, ttl_ms)
              :ok

            _ ->
              :ok
          end
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Updated #{server.display_name}.")
         |> assign(:raw_fields, build_raw_fields(server))}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), raw_fields: raw_fields)}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp build_raw_fields(%Servers{} = server) do
    %{
      args_raw: to_lines(server.args),
      headers_raw: map_to_lines(server.headers),
      env_raw: map_to_lines(server.env),
      metadata_raw: encode_metadata(server.metadata),
      tags_raw: to_lines(server.tags)
    }
  end

  defp normalize_form_params(params) do
    raw = %{
      args_raw: Map.get(params, "args_raw", ""),
      headers_raw: Map.get(params, "headers_raw", ""),
      env_raw: Map.get(params, "env_raw", ""),
      metadata_raw: Map.get(params, "metadata_raw", ""),
      tags_raw: Map.get(params, "tags_raw", "")
    }

    base_attrs =
      params
      |> Map.take([
        "display_name",
        "name",
        "description",
        "transport",
        "url",
        "command",
        "auth_token"
      ])
      |> trim_values()
      |> Map.put("is_enabled", truthy?(params["is_enabled"]))
      |> Map.put("definition_source", "manual")

    with {:ok, args} <- parse_list(raw.args_raw, :args),
         {:ok, tags} <- parse_list(raw.tags_raw, :tags),
         {:ok, headers} <- parse_key_values(raw.headers_raw, :headers),
         {:ok, env} <- parse_key_values(raw.env_raw, :env),
         {:ok, metadata0} <- parse_metadata(raw.metadata_raw) do
      metadata =
        case Map.get(params, "tool_cache_ttl_minutes") do
          ttl when is_binary(ttl) ->
            if String.trim(ttl) != "" do
              Map.put(metadata0, "tool_cache_ttl_minutes", to_int(ttl))
            else
              metadata0
            end

          _ ->
            metadata0
        end

      attrs =
        base_attrs
        |> Map.put("args", args)
        |> Map.put("tags", tags)
        |> Map.put("headers", headers)
        |> Map.put("env", env)
        |> Map.put("metadata", metadata)

      {:ok, attrs, raw}
    else
      {:error, field, message} ->
        {:error, field, message, base_attrs, raw}
    end
  end

  defp parse_list(value, _field) when value in [nil, ""], do: {:ok, []}

  defp parse_list(value, _field) do
    list =
      value
      |> String.split(["\n", ","], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, list}
  end

  defp parse_key_values(value, _field) when value in [nil, ""], do: {:ok, %{}}

  defp parse_key_values(value, field) do
    value
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, acc} ->
      case String.split(line, "=", parts: 2) do
        [k, v] ->
          {:cont, {:ok, Map.put(acc, String.trim(k), String.trim(v))}}

        _ ->
          {:halt, {:error, field, "Each entry must be KEY=VALUE"}}
      end
    end)
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60

  defp parse_metadata(value) when value in [nil, ""] do
    {:ok, %{}}
  end

  defp parse_metadata(value) do
    case Jason.decode(value) do
      {:ok, %{} = map} ->
        {:ok, map}

      {:ok, _} ->
        {:error, :metadata, "Metadata JSON must decode to an object"}

      {:error, %Jason.DecodeError{data: data, position: pos}} ->
        {:error, :metadata, "Invalid JSON near position #{pos}: #{inspect(data)}"}
    end
  end

  defp parse_payload(:cli, payload), do: Import.parse_cli(payload)
  defp parse_payload(:json, payload), do: Import.parse_json(payload)
  defp parse_payload(:toml, payload), do: Import.parse_toml(payload)
  defp parse_payload(_, _), do: {:error, "Unsupported import mode"}

  defp apply_import(:cli, {:upsert, entries}) do
    attrs = Enum.map(entries, & &1.server)

    case MCP.ensure_servers_exist(attrs) do
      {:ok, servers} -> {:ok, "Upserted #{length(servers)} MCP server(s)."}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_import(:cli, {:remove, names}) do
    {:ok, count} = MCP.delete_servers_by_names(names)
    {:ok, "Removed #{count} MCP server(s)."}
  end

  defp apply_import(:json, entries) do
    case MCP.ensure_servers_exist(entries) do
      {:ok, servers} -> {:ok, "Upserted #{length(servers)} MCP server(s) from JSON."}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_import(:toml, entries) do
    case MCP.ensure_servers_exist(entries) do
      {:ok, servers} -> {:ok, "Upserted #{length(servers)} MCP server(s) from TOML."}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_import(_, _), do: {:error, "Nothing to import."}

  defp sanitize_mode(mode, allow_import_tabs) do
    mode =
      mode
      |> to_string()
      |> String.downcase()
      |> String.to_atom()

    cond do
      mode in [:manual] -> :manual
      allow_import_tabs and mode in [:cli, :json, :toml] -> mode
      true -> :manual
    end
  rescue
    ArgumentError -> :manual
  end

  defp requested_mode(assigns) do
    cond do
      Map.has_key?(assigns, :mode) && not is_nil(Map.get(assigns, :mode)) ->
        Map.get(assigns, :mode)

      server = Map.get(assigns, :server) ->
        Map.get(server, :definition_source) || :manual

      true ->
        :manual
    end
  end

  defp mode_configurations(true) do
    [
      %{
        id: :manual,
        label: "Form",
        description: "Edit display name, transport, and advanced fields directly.",
        tooltip:
          "Use the guided form when you want to tweak fields individually, including tags, headers, and environment variables."
      },
      %{
        id: :cli,
        label: "Command / CLI",
        description: "Paste `mcp add` or `claude mcp add` commands.",
        tooltip:
          "Parses CLI commands with flags like --transport, --header, --env, and inline args after --."
      },
      %{
        id: :json,
        label: "JSON",
        description: "Import servers from Cursor/OpenAI style JSON.",
        tooltip:
          "Handles payloads with mcp.servers / mcpServers arrays; unknown keys are captured in metadata."
      },
      %{
        id: :toml,
        label: "TOML",
        description: "Paste `[mcp_servers.*]` blocks from config files.",
        tooltip: "Each table becomes/updates a server; extra keys are stored in metadata."
      }
    ]
  end

  defp mode_configurations(false) do
    [
      %{
        id: :manual,
        label: "Form",
        description: "Edit this server's fields directly.",
        tooltip: "Existing servers must be edited via the form so we keep metadata intact."
      }
    ]
  end

  defp to_lines(nil), do: ""

  defp to_lines(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.join("\n")
  end

  defp map_to_lines(map) when map in [%{}, nil], do: ""

  defp map_to_lines(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("\n")
  end

  defp encode_metadata(map) when map in [%{}, nil], do: ""

  defp encode_metadata(map), do: Jason.encode!(map, pretty: true)

  defp trim_values(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      value = if is_binary(v), do: String.trim(v), else: v
      Map.put(acc, k, value)
    end)
  end

  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  defp format_changeset_error(changeset) do
    changeset
    |> Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, msgs} ->
      human = Phoenix.Naming.humanize(field)
      "#{human} #{Enum.join(msgs, ", ")}"
    end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={length(@mode_options) > 1} class="mb-4">
        <form id="mcp-mode-selector" phx-change="select_mode" phx-target={@myself}>
          <fieldset class="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
            <legend class="sr-only">Choose MCP input method</legend>
            <%= for option <- @mode_options do %>
              <label class={mode_card_class(@mode == option.id)} title={option.tooltip}>
                <input
                  type="radio"
                  id={"mode-#{option.id}"}
                  name="mode"
                  value={Atom.to_string(option.id)}
                  checked={@mode == option.id}
                  class="sr-only"
                />
                <div class="flex items-center justify-between">
                  <span class="text-sm font-semibold text-amber-100">{option.label}</span>
                  <.icon
                    :if={option.tooltip && option.tooltip != ""}
                    name="hero-question-mark-circle"
                    class="size-4 text-slate-400"
                  />
                </div>
                <p class="mt-1 text-xs text-slate-400">{option.description}</p>
              </label>
            <% end %>
          </fieldset>
        </form>
      </div>

      <%= if @mode == :manual do %>
        <.form
          for={@form}
          id="mcp-server-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="grid gap-4 md:grid-cols-2">
            <.input field={@form[:display_name]} label="Display name" />
            <.input
              field={@form[:name]}
              label="Canonical name"
              help="System-friendly unique identifier."
            />
            <.input
              field={@form[:description]}
              type="textarea"
              class="md:col-span-2"
              label="Description"
            />
            <.input
              field={@form[:transport]}
              type="select"
              options={transport_options()}
              label="Transport"
            />
            <.input field={@form[:is_enabled]} type="checkbox" label="Enabled" />
            <.input field={@form[:url]} label="Base URL" />
            <.input field={@form[:command]} label="Command" />
            <.input
              name="server[args_raw]"
              type="textarea"
              value={@raw_fields.args_raw}
              label="Arguments"
              help="One per line or comma-separated."
              class="md:col-span-2"
            />
            <.input
              name="server[headers_raw]"
              type="textarea"
              value={@raw_fields.headers_raw}
              label="Headers"
              help="KEY=VALUE per line."
              class="md:col-span-2"
            />
            <.input
              name="server[env_raw]"
              type="textarea"
              value={@raw_fields.env_raw}
              label="Environment variables"
              help="KEY=VALUE per line."
              class="md:col-span-2"
            />
            <.input
              name="server[tags_raw]"
              type="textarea"
              value={@raw_fields.tags_raw}
              label="Tags"
              help="Comma or newline separated."
            />
            <.input field={@form[:auth_token]} label="Auth token" />
            <.input
              name="server[tool_cache_ttl_minutes]"
              type="number"
              min="1"
              value={
                case @server.metadata do
                  %{} = md -> md["tool_cache_ttl_minutes"] || ""
                  _ -> ""
                end
              }
              label="Tool cache TTL (minutes)"
              help="Controls how long discovered tools are cached for quick pickers."
            />
            <.input
              name="server[metadata_raw]"
              type="textarea"
              value={@raw_fields.metadata_raw}
              label="Metadata (JSON)"
              class="md:col-span-2"
            />
          </div>

          <div class="mt-6 flex justify-end gap-2">
            <button type="button" class="btn btn-soft" phx-click="cancel" phx-target={@myself}>
              Cancel
            </button>
            <.button variant="primary" phx-disable-with="Saving...">Save</.button>
          </div>
        </.form>
      <% else %>
        <.form
          for={%{}}
          as={:import}
          id="mcp-import-form"
          phx-target={@myself}
          phx-change="update_import"
          phx-submit="parse_import"
        >
          <div class="space-y-4">
            <label class="text-sm font-medium text-slate-200" for="import-payload">
              {import_label(@mode)}
            </label>
            <textarea
              id="import-payload"
              name="payload"
              rows="10"
              class="textarea textarea-block w-full"
            >{@import_source}</textarea>
            <p :if={@import_error} class="text-xs text-red-400">{@import_error}</p>
            <div
              :if={@import_preview}
              class="rounded border border-amber-500/40 bg-black/40 p-4 text-xs text-amber-200"
            >
              {preview_block(@mode, @import_preview)}
            </div>
            <div class="mt-4 flex justify-end gap-2">
              <button type="button" class="btn btn-soft" phx-click="cancel" phx-target={@myself}>
                Cancel
              </button>
              <button type="submit" class="btn btn-soft">
                Preview
              </button>
              <button
                type="button"
                class="btn btn-primary"
                phx-click="save_import"
                phx-target={@myself}
              >
                Apply
              </button>
            </div>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end

  defp preview_block(:cli, {:remove, names}) do
    assigns = %{names: names}

    ~H"""
    <div>
      <p class="font-semibold text-amber-300">Pending removal:</p>
      <ul class="mt-2 list-disc pl-6">
        <li :for={name <- @names}>{name}</li>
      </ul>
    </div>
    """
  end

  defp preview_block(:cli, {:upsert, entries}) do
    assigns = %{entries: entries}

    ~H"""
    <div>
      <p class="font-semibold text-amber-300">Upserting servers:</p>
      <ul class="mt-2 list-disc pl-6">
        <li :for={entry <- @entries}>{entry.server.display_name || entry.server.name}</li>
      </ul>
    </div>
    """
  end

  defp preview_block(_mode, entries) when is_list(entries) do
    assigns = %{entries: entries}

    ~H"""
    <div>
      <p class="font-semibold text-amber-300">Servers to upsert:</p>
      <ul class="mt-2 list-disc pl-6">
        <li :for={entry <- @entries}>{entry.display_name || entry.name}</li>
      </ul>
    </div>
    """
  end

  defp preview_block(_, _), do: ""

  defp mode_card_class(true),
    do:
      "flex h-full cursor-pointer flex-col rounded-lg border border-amber-500/60 bg-black/40 p-3 shadow-inner ring-1 ring-amber-300/40 transition"

  defp mode_card_class(false),
    do:
      "flex h-full cursor-pointer flex-col rounded-lg border border-slate-800 bg-black/20 p-3 transition hover:border-amber-400/60"

  defp transport_options do
    [
      {"stdio", "stdio"},
      {"http", "http"},
      {"stream-http", "stream-http"},
      {"sse", "sse"}
    ]
  end

  defp import_label(:cli), do: "Paste CLI commands (mcp add/remove)."
  defp import_label(:json), do: "Paste JSON payload with mcp servers."
  defp import_label(:toml), do: "Paste TOML payload with [mcp_servers.*] tables."
  defp import_label(_), do: ""
end
