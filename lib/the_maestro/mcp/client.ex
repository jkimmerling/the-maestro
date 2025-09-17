defmodule TheMaestro.MCP.Client do
  @moduledoc """
  Thin wrapper around `:hermes_mcp` to talk to external MCP servers.

  Responsibilities (minimal MVP):
  - initialize/1 → returns %{capabilities, serverInfo, instructions?}
  - tools_list/1 → returns list of %{name, description?, inputSchema}
  - call_tool/3 → executes a tool by name with a map of args

  Connector config is sourced from the persisted MCP context (`mcp_servers`
  plus `session_mcp_servers`).
  """

  require Logger
  alias Hermes.MCP.Response, as: HermesResponse
  alias TheMaestro.MCP
  alias TheMaestro.MCP.Servers

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
    with {:ok, sup, client} <- start_client(session_id, server_key) do
      run_discovery(sup, client)
    end
  end

  @doc """
  Discover tools exposed by a specific `MCP.Servers` struct without needing a session binding.
  """
  @spec discover_server(Servers.t()) ::
          {:ok, %{tools: [tool_decl], instructions: nil}} | {:error, term()}
  def discover_server(%Servers{} = server) do
    with {:ok, sup, client} <- start_server_client(server) do
      run_discovery(sup, client)
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

  # Build and start a Hermes client supervisor from persisted MCP server bindings.
  defp start_client(session_id, server_key) do
    key = to_string(server_key)

    binding =
      session_id
      |> MCP.list_session_servers()
      |> Enum.find(fn binding ->
        binding.alias == key || binding.mcp_server.name == key
      end)

    with %{mcp_server: _server} = binding <- binding,
         {:ok, opts} <- transport_opts_for(binding) do
      case opts.transport do
        :stream_http -> start_stream_supervisor(opts.base_url, opts.endpoint, opts.headers)
        :stdio -> start_stdio_supervisor(opts)
      end
    else
      nil -> {:error, {:unknown_server, key}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_server_client(%Servers{} = server) do
    case transport_opts_for(%{mcp_server: server, metadata: %{}}) do
      {:ok, %{transport: :stream_http} = opts} ->
        start_stream_supervisor(opts.base_url, opts.endpoint, opts.headers)

      {:ok, %{transport: :stdio} = opts} ->
        start_stdio_supervisor(opts)

      {:error, reason} ->
        {:error, reason}
    end
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

  defp retry_list_tools(_client, 0, _sleep_ms), do: {:ok, []}

  defp retry_list_tools(client, attempts, sleep_ms) do
    case safe_list_tools(client) do
      {:ok, resp} ->
        m = HermesResponse.unwrap(resp)

        case m["tools"] do
          l when is_list(l) and l != [] ->
            {:ok, l}

          _ ->
            Process.sleep(sleep_ms)
            retry_list_tools(client, attempts - 1, sleep_ms)
        end

      {:error, reason} ->
        if attempts - 1 <= 0 do
          {:error, reason}
        else
          Process.sleep(sleep_ms)
          retry_list_tools(client, attempts - 1, sleep_ms)
        end
    end
  end

  defp wait_for_capabilities(_client, 0, _sleep_ms), do: :timeout

  defp wait_for_capabilities(client, attempts, sleep_ms) do
    case safe_get_server_capabilities(client) do
      {:ok, nil} ->
        Process.sleep(sleep_ms)
        wait_for_capabilities(client, attempts - 1, sleep_ms)

      {:ok, _caps} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_get_server_capabilities(client) do
    {:ok, Hermes.Client.Base.get_server_capabilities(client)}
  catch
    :exit, reason -> {:error, normalize_exit(reason)}
  end

  defp safe_list_tools(client) do
    Hermes.Client.Base.list_tools(client)
  catch
    :exit, reason -> {:error, normalize_exit(reason)}
  end

  defp normalize_exit({:shutdown, reason}), do: normalize_exit(reason)
  defp normalize_exit({:noproc, _} = reason), do: Exception.format_exit(reason)
  defp normalize_exit(reason), do: Exception.format_exit(reason)

  defp run_discovery(sup, client) do
    result =
      case wait_for_capabilities(client, 10, 500) do
        :ok ->
          client
          |> retry_list_tools(3, 300)
          |> wrap_tools_result()

        :timeout ->
          {:error, :server_initialization_timeout}

        {:error, reason} ->
          {:error, reason}
      end

    _ = Supervisor.stop(sup)
    result
  end

  defp wrap_tools_result({:ok, tools}), do: {:ok, %{tools: tools, instructions: nil}}
  defp wrap_tools_result({:error, reason}), do: {:error, reason}

  defp require_present(value, error_reason) do
    cond do
      is_binary(value) and String.trim(value) != "" -> {:ok, String.trim(value)}
      not is_nil(value) -> require_present(to_string(value), error_reason)
      true -> {:error, error_reason}
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

  defp transport_opts_for(%{mcp_server: %{transport: "stdio"} = server, metadata: metadata}) do
    metadata = metadata || %{}
    server_meta = server.metadata || %{}

    command = metadata["command"] || server.command || server_meta["command"]
    args = metadata["args"] || server.args || server_meta["args"] || []
    env = merge_envs(server.env, metadata["env"], server_meta["env"])
    cwd = metadata["cwd"] || server_meta["cwd"]

    with {:ok, executable} <- require_present(command, :missing_command) do
      {:ok,
       %{
         transport: :stdio,
         command: executable,
         args: normalize_arg_list(args),
         env: env,
         cwd: cwd
       }}
    end
  end

  defp transport_opts_for(%{mcp_server: server, metadata: metadata}) do
    metadata = metadata || %{}
    server_meta = server.metadata || %{}

    {base_from_url, endpoint_from_url} = split_url(server.url)

    base_url = metadata["base_url"] || server_meta["base_url"] || base_from_url

    endpoint =
      metadata["endpoint"] || server_meta["endpoint"] || endpoint_from_url ||
        default_endpoint(server.transport)

    headers =
      server.headers
      |> merge_headers(metadata["headers"])
      |> maybe_put_auth(server.auth_token)

    with {:ok, origin} <- require_present(base_url, :missing_base_url) do
      {:ok,
       %{
         transport: :stream_http,
         base_url: origin,
         endpoint: endpoint,
         headers: headers
       }}
    end
  end

  defp merge_headers(nil, overrides), do: merge_headers(%{}, overrides)
  defp merge_headers(map, nil), do: stringify_keys(map)

  defp merge_headers(map, overrides),
    do: stringify_keys(map) |> Map.merge(stringify_keys(overrides))

  defp merge_envs(primary, secondary, fallback) do
    primary = stringify_keys(primary || %{})
    secondary = stringify_keys(secondary || %{})
    fallback = stringify_keys(fallback || %{})

    fallback
    |> Map.merge(primary)
    |> Map.merge(secondary)
    |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, to_string(v)) end)
  end

  defp normalize_arg_list(list) when is_list(list) do
    list
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&to_string/1)
  end

  defp normalize_arg_list(value) when is_binary(value), do: [value]
  defp normalize_arg_list(_), do: []

  defp maybe_put_auth(headers, nil), do: headers

  defp maybe_put_auth(headers, token) do
    headers
    |> Map.put_new("Authorization", "Bearer #{token}")
  end

  defp stringify_keys(map) when is_map(map) do
    map |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)
  end

  defp default_endpoint("sse"), do: "/mcp"
  defp default_endpoint(_), do: "/mcp"

  defp split_url(nil), do: {nil, nil}

  defp split_url(url) when is_binary(url) do
    uri = URI.parse(url)

    base =
      %URI{uri | path: nil, query: nil, fragment: nil}
      |> URI.to_string()

    endpoint = uri.path || "/mcp"
    {base, endpoint}
  rescue
    _ -> {url, "/mcp"}
  end

  defp split_url(_), do: {nil, nil}

  defp start_stdio_supervisor(%{command: command} = opts) do
    args = opts.args || []
    env = opts.env || %{}
    cwd = opts.cwd

    transport_opts =
      [command: command, args: args, env: env]
      |> maybe_put_cwd(cwd)

    unique = :erlang.unique_integer([:positive])
    client_name = String.to_atom("MaestroHermesClient_" <> Integer.to_string(unique))
    transport_name = String.to_atom("MaestroHermesTransport_" <> Integer.to_string(unique))

    opts = [
      client_name: client_name,
      transport_name: transport_name,
      transport: {:stdio, transport_opts},
      client_info: %{"name" => "the-maestro-mcp-client", "version" => "0.0.1"},
      capabilities: %{"roots" => %{}},
      protocol_version: "2025-06-18"
    ]

    case Hermes.Client.Supervisor.start_link(TheMaestro.MCP.HermesDynamicClient, opts) do
      {:ok, sup} -> {:ok, sup, client_name}
      other -> other
    end
  end

  defp maybe_put_cwd(opts, nil), do: opts
  defp maybe_put_cwd(opts, cwd) when is_binary(cwd), do: Keyword.put(opts, :cwd, cwd)
  defp maybe_put_cwd(opts, _), do: opts
end
