defmodule TheMaestro.MCP.Import do
  @moduledoc """
  Parsing helpers for ingesting MCP server definitions from CLI commands,
  JSON payloads, and TOML configuration files. All functions normalise the
  resulting attributes so they can be passed directly to
  `TheMaestro.MCP.ensure_servers_exist/1`.
  """

  alias TheMaestro.MCP.Servers

  @type server_attrs :: %{
          required(:name) => String.t(),
          required(:display_name) => String.t(),
          required(:transport) => String.t(),
          optional(:description) => String.t() | nil,
          optional(:url) => String.t() | nil,
          optional(:command) => String.t() | nil,
          optional(:args) => [String.t()],
          optional(:headers) => map(),
          optional(:env) => map(),
          optional(:metadata) => map(),
          optional(:tags) => [String.t()],
          optional(:auth_token) => String.t() | nil,
          optional(:is_enabled) => boolean()
        }

  @cli_strict [
    alias: :string,
    arg: :string,
    auth_token: :string,
    command: :string,
    description: :string,
    display_name: :string,
    env: :string,
    header: :string,
    metadata: :string,
    name: :string,
    tag: :string,
    transport: :string,
    url: :string,
    enabled: :boolean,
    disabled: :boolean
  ]

  @cli_keep [:arg, :env, :header, :tag]

  @known_keys ~w(name display_name description transport type url command args headers env metadata tags auth_token authToken enabled disabled is_enabled alias alias_name session_alias)

  @doc """
  Parse an MCP CLI command such as `mcp add <name> ...` or
  `claude mcp add <name> ...`. Returns

    * `{:ok, {:upsert, [%{server: server_attrs(), alias: String.t() | nil}]}}`
      for add-style commands
    * `{:ok, {:remove, [String.t()]}}` for removal commands

  Any parsing errors return `{:error, message}`.
  """
  @spec parse_cli(String.t()) ::
          {:ok, {:upsert, [%{server: server_attrs(), alias: String.t() | nil}]}}
          | {:ok, {:remove, [String.t()]}}
          | {:error, String.t()}
  def parse_cli(command) when is_binary(command) do
    command
    |> OptionParser.split()
    |> parse_cli_tokens()
  end

  defp parse_cli_tokens(["mcp", "add" | rest]), do: parse_cli_add(rest)
  defp parse_cli_tokens(["claude", "mcp", "add" | rest]), do: parse_cli_add(rest)
  defp parse_cli_tokens(["mcp", "remove" | rest]), do: parse_cli_remove(rest)
  defp parse_cli_tokens(["claude", "mcp", "remove" | rest]), do: parse_cli_remove(rest)
  defp parse_cli_tokens(_tokens), do: {:error, "unsupported MCP CLI command"}

  defp parse_cli_add(rest) do
    {option_tokens, command_tail} = split_inline(rest)

    case OptionParser.parse(option_tokens, strict: @cli_strict, keep: @cli_keep, aliases: []) do
      {opts, positional, []} ->
        do_parse_cli_add(opts, positional, command_tail)

      {_, _, invalid_opts} ->
        msg =
          invalid_opts
          |> Enum.map(fn {opt, _val} -> "--#{opt}" end)
          |> Enum.join(", ")

        {:error, "invalid options: #{msg}"}
    end
  end

  defp do_parse_cli_add(opts, positional, command_tail) do
    name = opts[:name] || List.first(positional)

    cond do
      is_nil(name) ->
        {:error, "missing server name"}

      length(positional) > 1 and is_nil(opts[:name]) ->
        {:error, "unexpected positional arguments: #{Enum.join(tl(positional), ", ")}"}

      true ->
        with {:ok, headers} <- parse_kv(opts, :header, "header"),
             {:ok, env} <- parse_kv(opts, :env, "env"),
             {:ok, metadata} <- parse_metadata(opts[:metadata]),
             {:ok, tags} <- parse_list(opts, :tag),
             {:ok, args_from_flags} <- parse_list(opts, :arg),
             {:ok, command, inline_args} <- resolve_command(opts, command_tail) do
          url = keyword_get(opts, :url)

          transport =
            Keyword.get(opts, :transport) ||
              default_transport(url, command)

          if is_nil(transport) do
            {:error, "transport is required when neither URL nor command is provided"}
          else
            server_attrs = %{
              name: Servers.normalize_name(name),
              display_name: String.trim(opts[:display_name] || to_string(name)),
              description: keyword_get(opts, :description),
              transport: normalize_transport(transport),
              url: url,
              command: command,
              args: Enum.uniq(args_from_flags ++ inline_args),
              headers: headers,
              env: env,
              metadata: metadata,
              tags: tags,
              auth_token: keyword_get(opts, :auth_token),
              is_enabled: determine_enabled(opts),
              definition_source: "cli"
            }

            {:ok, {:upsert, [%{server: server_attrs, alias: keyword_get(opts, :alias)}]}}
          end
        end
    end
  end

  defp parse_cli_remove(rest) do
    {opts, positional, invalid} =
      OptionParser.parse(rest, strict: [name: :string], aliases: [])

    cond do
      invalid != [] ->
        {:error, "invalid options: #{inspect(invalid)}"}

      name = opts[:name] || List.first(positional) ->
        {:ok, {:remove, [Servers.normalize_name(name)]}}

      true ->
        {:error, "missing server name"}
    end
  end

  @doc """
  Parse a JSON payload containing MCP server definitions. Accepts both string and
  map inputs. Returns `{:ok, [server_attrs()]}` or `{:error, message}`.
  """
  @spec parse_json(String.t() | map()) :: {:ok, [server_attrs()]} | {:error, String.t()}
  def parse_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, map} ->
        parse_json(map)

      {:error, %Jason.DecodeError{data: data, position: pos}} ->
        {:error, "invalid JSON near position #{pos}: #{inspect(data)}"}
    end
  end

  def parse_json(%{} = payload) do
    payload
    |> stringify_keys()
    |> extract_server_entries()
    |> normalize_entry_list("json")
  end

  def parse_json(_), do: {:error, "expected JSON object"}

  @doc """
  Parse a TOML payload with MCP server definitions.
  """
  @spec parse_toml(String.t()) :: {:ok, [server_attrs()]} | {:error, String.t()}
  def parse_toml(payload) when is_binary(payload) do
    case Toml.decode(payload) do
      {:ok, map} ->
        map
        |> stringify_keys()
        |> extract_server_entries()
        |> normalize_entry_list("toml")

      {:error, {:invalid_toml, message}} ->
        {:error, "invalid TOML: #{message}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  end

  defp normalize_entry_list({:error, reason}, _source), do: {:error, reason}

  defp normalize_entry_list({:ok, entries}, source) do
    entries
    |> Enum.map(&normalize_entry(&1, source))
    |> reduce_results()
  end

  defp extract_base_metadata(data) do
    data
    |> Map.get("metadata", %{})
    |> ensure_map("metadata")
  end

  defp extract_base_entry_attrs(data, hint_name, source) do
    name = data["name"] || hint_name

    if is_nil(name) do
      {:error, "server entry missing name"}
    else
      build_base_entry_attrs(data, name, source)
    end
  end

  defp build_base_entry_attrs(data, name, source) do
    display_name = data["display_name"] || data["displayName"] || name

    transport =
      data["transport"] || data["type"] || default_transport(data["url"], data["command"])

    if is_nil(transport) do
      {:error, "transport missing for server #{inspect(name)}"}
    else
      {:ok,
       %{
         name: name,
         display_name: display_name,
         transport: transport,
         description: data["description"],
         url: data["url"],
         command: data["command"],
         auth_token: data["auth_token"] || data["authToken"],
         definition_source: normalize_source(data["definition_source"], source)
       }}
    end
  end

  defp extract_structured_fields(data) do
    with {:ok, headers} <- ensure_string_map(Map.get(data, "headers", %{}), "headers"),
         {:ok, env} <- ensure_string_map(Map.get(data, "env", %{}), "env"),
         {:ok, metadata_extras} <- ensure_map(Map.drop(data, @known_keys), "metadata"),
         {:ok, args} <- ensure_string_list(Map.get(data, "args", []), "args"),
         {:ok, tags} <- ensure_string_list(Map.get(data, "tags", []), "tags") do
      {:ok,
       %{
         headers: headers,
         env: env,
         metadata_extras: metadata_extras,
         args: args,
         tags: tags
       }}
    end
  end

  defp resolve_enabled_flag(data) do
    case {Map.fetch(data, "enabled"), Map.fetch(data, "disabled"), Map.fetch(data, "is_enabled")} do
      {{:ok, value}, _, _} -> truthy?(value)
      {_, {:ok, value}, _} -> not truthy?(value)
      {_, _, {:ok, value}} -> truthy?(value)
      _ -> true
    end
  end

  defp normalize_entry({hint_name, raw}, source) do
    data = stringify_keys(raw)

    with {:ok, metadata} <- extract_base_metadata(data),
         {:ok, base_attrs} <- extract_base_entry_attrs(data, hint_name, source),
         {:ok, structured} <- extract_structured_fields(data) do
      merged_metadata = deep_merge_metadata(metadata, structured.metadata_extras)

      {:ok,
       %{
         name: Servers.normalize_name(base_attrs.name),
         display_name: String.trim(base_attrs.display_name),
         description: base_attrs.description,
         transport: normalize_transport(base_attrs.transport),
         url: base_attrs.url,
         command: base_attrs.command,
         args: structured.args,
         headers: structured.headers,
         env: structured.env,
         metadata: merged_metadata,
         tags: structured.tags,
         auth_token: base_attrs.auth_token,
         is_enabled: resolve_enabled_flag(data),
         definition_source: base_attrs.definition_source
       }}
    end
  end

  defp reduce_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, acc ++ [value]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
  end

  defp extract_server_entries(map) when is_map(map) do
    cond do
      servers = get_in(map, ["mcp", "servers"]) -> normalize_collection(servers)
      servers = map["mcp_servers"] -> normalize_collection(servers)
      servers = map["mcpServers"] -> normalize_collection(servers)
      servers = map["servers"] -> normalize_collection(servers)
      map == %{} -> {:error, "no MCP servers found"}
      Map.has_key?(map, "name") -> normalize_collection([map])
      true -> normalize_collection(map)
    end
  end

  defp extract_server_entries(_), do: {:error, "no MCP servers found"}

  defp normalize_collection(list) when is_list(list) do
    list
    |> Enum.map(fn
      %{} = entry -> {:ok, {normalize_name_hint(entry["name"] || entry[:name]), entry}}
      other -> {:error, {:invalid_entry, other}}
    end)
    |> reduce_normalized_collection()
  end

  defp normalize_collection(map) when is_map(map) do
    map
    |> Enum.map(fn {name, entry} ->
      if is_map(entry) do
        hint = entry["name"] || entry[:name] || name
        {:ok, {normalize_name_hint(hint), entry}}
      else
        {:error, {:invalid_entry, entry}}
      end
    end)
    |> reduce_normalized_collection()
  end

  defp normalize_collection(_), do: {:error, "no MCP servers found"}

  defp reduce_normalized_collection(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, tuple}, {:ok, acc} ->
        {:cont, {:ok, acc ++ [tuple]}}

      {:error, {:invalid_entry, entry}}, _ ->
        {:halt, {:error, "invalid server entry: #{inspect(entry)}"}}

      {:error, reason}, _ ->
        {:halt, {:error, inspect(reason)}}
    end)
  end

  defp normalize_name_hint(nil), do: nil
  defp normalize_name_hint(value) when is_binary(value), do: value
  defp normalize_name_hint(value), do: to_string(value)

  @source_aliases %{
    "command" => "cli",
    "cli" => "cli",
    "json" => "json",
    "toml" => "toml",
    "manual" => "manual"
  }

  defp normalize_source(value, fallback) do
    fallback = if is_nil(fallback), do: "manual", else: fallback
    normalized = normalize_source_input(value)

    case normalized do
      "" -> fallback
      other -> Map.get(@source_aliases, other, fallback_for_unknown(other, fallback))
    end
  end

  defp normalize_source_input(nil), do: ""

  defp normalize_source_input(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_source_input(value),
    do: value |> to_string() |> String.trim() |> String.downcase()

  defp fallback_for_unknown(_value, fallback), do: fallback

  defp parse_metadata(nil), do: {:ok, %{}}

  defp parse_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} ->
        {:ok, stringify_keys(map)}

      {:ok, _} ->
        {:error, "metadata must decode to an object"}

      {:error, %Jason.DecodeError{data: data, position: pos}} ->
        {:error, "invalid metadata JSON near position #{pos}: #{inspect(data)}"}
    end
  end

  defp parse_metadata(_), do: {:error, "metadata must be JSON string"}

  defp parse_list(opts, key) do
    values = Keyword.get_values(opts, key)
    {:ok, Enum.map(values, &String.trim/1) |> Enum.reject(&(&1 == ""))}
  end

  defp parse_kv(opts, key, label) do
    opts
    |> Keyword.get_values(key)
    |> Enum.reduce_while({:ok, %{}}, fn value, {:ok, acc} ->
      case String.split(value, "=", parts: 2) do
        [k, v] ->
          {:cont, {:ok, Map.put(acc, k, v)}}

        _ ->
          {:halt, {:error, "#{label} option must be KEY=VALUE"}}
      end
    end)
  end

  defp resolve_command(opts, []), do: {:ok, keyword_get(opts, :command), []}

  defp resolve_command(opts, [cmd | rest]) do
    chosen = opts[:command] || cmd
    {:ok, chosen, rest}
  end

  defp split_inline(tokens) do
    case Enum.split_while(tokens, &(&1 != "--")) do
      {head, []} -> {head, []}
      {head, [_ | tail]} -> {head, tail}
    end
  end

  defp keyword_get(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_binary(value) -> String.trim(value)
      value -> value
    end
  end

  defp determine_enabled(opts) do
    case {Keyword.get(opts, :enabled), Keyword.get(opts, :disabled)} do
      {true, _} -> true
      {_, true} -> false
      {false, _} -> false
      {_, false} -> true
      _ -> true
    end
  end

  defp default_transport(url, command) do
    cond do
      is_binary(url) and String.trim(url) != "" -> "stream-http"
      is_binary(command) and String.trim(command) != "" -> "stdio"
      true -> nil
    end
  end

  defp normalize_transport(nil), do: nil

  defp normalize_transport("http"), do: "stream-http"
  defp normalize_transport("HTTP"), do: "stream-http"
  defp normalize_transport(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_transport(value), do: value

  defp ensure_map(value, _label) when value == %{}, do: {:ok, %{}}
  defp ensure_map(%{} = map, _label), do: {:ok, stringify_keys(map)}
  defp ensure_map(nil, _label), do: {:ok, %{}}
  defp ensure_map(value, label), do: {:error, "#{label} must be a map, got #{inspect(value)}"}

  defp ensure_string_map(value, label) do
    case ensure_map(value, label) do
      {:ok, map} ->
        {:ok, Enum.into(map, %{}, fn {k, v} -> {to_string(k), to_string(v)} end)}

      other ->
        other
    end
  end

  defp ensure_string_list(value, _label) when is_list(value) do
    {:ok,
     value
     |> Enum.map(&to_string/1)
     |> Enum.map(&String.trim/1)
     |> Enum.reject(&(&1 == ""))}
  end

  defp ensure_string_list(value, label) when is_binary(value) do
    ensure_string_list(String.split(value, ","), label)
  end

  defp ensure_string_list(nil, _label), do: {:ok, []}
  defp ensure_string_list(_value, label), do: {:error, "#{label} must be a list of strings"}

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), stringify_keys(v)} end)
    |> Enum.into(%{})
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp deep_merge_metadata(%{} = left, %{} = right) do
    Map.merge(left, right, fn _k, v1, v2 -> deep_merge_metadata(v1, v2) end)
  end

  defp deep_merge_metadata(_left, right), do: right

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_), do: false
end
