defmodule TheMaestro.MCP.Client do
  @moduledoc """
  Thin wrapper around `:hermes_mcp` to talk to external MCP servers.

  Responsibilities (minimal MVP):
  - initialize/1 → returns %{capabilities, serverInfo, instructions?}
  - tools_list/1 → returns list of %{name, description?, inputSchema}
  - call_tool/3 → executes a tool by name with a map of args

  Connector config for MVP is taken from the Session `mcps` map under:
    %{
      "context7" => %{
        "transport" => "stream" | "http",
        "base_url" => "https://...",    # for stream/http
        "endpoint" => "/mcp" | "/api/mcp",
        "headers" => %{...}
      }
    }
  For now we only implement HTTP (non-stream) and Streamable HTTP.
  """

  require Logger
  alias Hermes.MCP.Response, as: HermesResponse
  alias TheMaestro.Conversations

  @type connector_id :: String.t()
  @type server_key :: String.t() | atom()
  @type tool_decl :: %{required(String.t()) => any()}

  @doc """
  Perform initialize + tools/list against a named server key configured on the Session.
  Returns {:ok, %{tools: [tool_decl], instructions: String.t() | nil}}.
  """
  @spec discover(String.t(), server_key()) ::
          {:ok, %{tools: [tool_decl], instructions: String.t() | nil}} | {:error, term()}
  def discover(session_id, server_key) do
    case start_client(session_id, server_key) do
      {:ok, sup, client} ->
        tools = retry_list_tools(client, 3, 300)
        _ = Supervisor.stop(sup)
        {:ok, %{tools: tools, instructions: nil}}

      {:error, _} = err ->
        err

      other ->
        other
    end
  end

  @doc """
  Call a tool by name with args (map). Returns {:ok, payload_string} | {:error, reason}.
  We return string payloads to fit our functionResponse.response handling.
  """
  @spec call_tool(String.t(), server_key(), String.t(), map()) ::
          {:ok, String.t()} | {:error, String.t()}
  def call_tool(session_id, server_key, tool_name, args) do
    with {:ok, sup, client_name} <- start_client(session_id, server_key) do
      # Ensure handshake is fully initialized (server_capabilities present)
      _ = wait_for_capabilities(client_name, 5, 200)

      result =
        try do
          Hermes.Client.Base.call_tool(client_name, to_string(tool_name), args)
        rescue
          e -> {:error, e}
        end

      _ = Supervisor.stop(sup)

      case result do
        {:ok, resp} ->
          {:ok, resp |> HermesResponse.unwrap() |> encode_result()}

        {:error, %Hermes.MCP.Error{reason: reason, message: msg, data: data}} ->
          {:error, format_mcp_error(reason, msg, data)}

        {:error, e} ->
          {:error, Exception.message(e)}
      end
    end
  end

  # Build and start a Hermes client supervisor from Session config `mcps` map.
  defp start_client(session_id, server_key) do
    s = Conversations.get_session!(session_id)
    key = to_string(server_key)
    cfg = (s.mcps || %{})[key] || (s.mcps || %{})[String.to_atom(key)] || %{}

    {transport, base_url, endpoint, headers} = resolve_connector_config(cfg)

    case transport do
      "stream" -> start_stream_supervisor(base_url, endpoint, headers)
      "http" -> start_stream_supervisor(base_url, endpoint, headers)
      other -> {:error, {:unsupported_transport, other}}
    end
  end

  defp resolve_connector_config(cfg) when is_map(cfg) do
    transport = (cfg["transport"] || cfg[:transport] || "stream") |> to_string()
    base_url = cfg["base_url"] || cfg[:base_url]
    endpoint = cfg["endpoint"] || cfg[:endpoint] || "/mcp"
    headers = cfg["headers"] || cfg[:headers] || %{}
    {transport, base_url, endpoint, headers}
  end

  defp start_stream_supervisor(nil, _p, _h), do: {:error, :missing_base_url}

  defp start_stream_supervisor(base_url, endpoint, headers) do
    # Create a unique name for the ad-hoc client and its transport
    unique = :erlang.unique_integer([:positive])
    client_name = String.to_atom("MaestroHermesClient_" <> Integer.to_string(unique))
    transport_name = String.to_atom("MaestroHermesTransport_" <> Integer.to_string(unique))

    # Use our static client module
    mod = TheMaestro.MCP.HermesDynamicClient

    opts = [
      client_name: client_name,
      transport_name: transport_name,
      transport: {:streamable_http, [base_url: base_url, mcp_path: endpoint, headers: headers]},
      client_info: %{"name" => "the-maestro-mcp-client", "version" => "0.0.1"},
      capabilities: %{"roots" => %{}},
      protocol_version: "2025-06-18"
    ]

    case Hermes.Client.Supervisor.start_link(mod, opts) do
      {:ok, sup} -> {:ok, sup, client_name}
      other -> other
    end
  end

  defp encode_result(%{} = value), do: Jason.encode!(value)

  # unwrap handled inline for Dialyzer friendliness

  defp retry_list_tools(_client, 0, _sleep_ms), do: []

  defp retry_list_tools(client, attempts, sleep_ms) do
    case Hermes.Client.Base.list_tools(client) do
      {:ok, resp} ->
        m = HermesResponse.unwrap(resp)

        case m["tools"] do
          l when is_list(l) and l != [] ->
            l

          _ ->
            Process.sleep(sleep_ms)
            retry_list_tools(client, attempts - 1, sleep_ms)
        end

      _ ->
        Process.sleep(sleep_ms)
        retry_list_tools(client, attempts - 1, sleep_ms)
    end
  end

  defp wait_for_capabilities(_client, 0, _sleep_ms), do: :timeout

  defp wait_for_capabilities(client, attempts, sleep_ms) do
    case Hermes.Client.Base.get_server_capabilities(client) do
      nil ->
        Process.sleep(sleep_ms)
        wait_for_capabilities(client, attempts - 1, sleep_ms)

      _ ->
        :ok
    end
  end

  defp format_mcp_error(reason, msg, data) do
    base = to_string(reason)

    parts =
      [base, msg]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.join(": ")

    if data && map_size(data) > 0 do
      parts <> " " <> encode_result(data)
    else
      parts
    end
  end
end
