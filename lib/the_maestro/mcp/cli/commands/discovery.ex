defmodule TheMaestro.MCP.CLI.Commands.Discovery do
  @moduledoc """
  Server discovery and auto-configuration commands for MCP CLI.

  Provides functionality to automatically discover MCP servers on the network,
  scan for common server configurations, and set up servers with minimal manual configuration.
  """

  alias TheMaestro.MCP.{Config, ConnectionManager}
  alias TheMaestro.MCP.Config.ConfigValidator
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the discovery command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      [] ->
        run_full_discovery(options)

      ["scan"] ->
        run_network_scan(options)

      ["local"] ->
        discover_local_servers(options)

      ["templates"] ->
        show_available_templates(options)

      ["from-template", template_name] ->
        create_from_template(template_name, options)

      _ ->
        CLI.print_error("Invalid discovery command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the discovery command.
  """
  def show_help do
    IO.puts("""
    MCP Server Discovery & Auto-Configuration

    Usage:
      maestro mcp discover [SUBCOMMAND] [OPTIONS]

    Subcommands:
      (none)                       Run full discovery process
      scan                         Scan network for MCP servers
      local                        Discover local/filesystem-based servers
      templates                    Show available server templates
      from-template <name>         Create server from template

    Discovery Options:
      --network                    Enable network discovery
      --ports <ports>              Comma-separated list of ports to scan
      --timeout <ms>               Discovery timeout per host (default: 3000ms)
      --auto-add                   Automatically add discovered servers
      --dry-run                    Show what would be discovered without adding

    Network Options:
      --subnet <cidr>              Subnet to scan (e.g., 192.168.1.0/24)
      --hosts <hosts>              Specific hosts to scan (comma-separated)
      --protocols <protocols>      Protocols to check (http,https,stdio)

    Local Discovery Options:
      --paths <paths>              Additional paths to search for executables
      --recursive                  Recursively search directories
      --extensions <exts>          File extensions to consider (e.g., py,js,exe)

    Template Options:
      --list-all                   Show all available templates
      --category <category>        Filter templates by category
      --from <source>              Create template from existing server

    Examples:
      maestro mcp discover                          # Full discovery
      maestro mcp discover scan --network           # Network scan only
      maestro mcp discover local --recursive        # Deep local search
      maestro mcp discover templates                # List templates
      maestro mcp discover from-template python-server  # Create from template
      maestro mcp discover --auto-add --dry-run     # Preview auto-discovery
    """)
  end

  ## Private Functions - Discovery Orchestration

  defp run_full_discovery(options) do
    IO.puts("MCP Server Discovery")
    IO.puts("#{String.duplicate("=", 25)}")
    IO.puts("")

    CLI.print_if_verbose("Starting comprehensive server discovery...", options)

    discovered_servers = []

    # Local discovery
    CLI.print_if_verbose("Discovering local servers...", options)
    local_servers = discover_local_servers_internal(options)
    discovered_servers = discovered_servers ++ local_servers

    # Network discovery (if enabled)
    network_servers =
      if Map.get(options, :network) do
        CLI.print_if_verbose("Discovering network servers...", options)
        discover_network_servers_internal(options)
      else
        []
      end

    discovered_servers = discovered_servers ++ network_servers

    # Process discovery results
    process_discovery_results(discovered_servers, options)
  end

  defp run_network_scan(options) do
    IO.puts("Network MCP Server Scan")
    IO.puts("#{String.duplicate("=", 30)}")
    IO.puts("")

    CLI.print_if_verbose("Scanning network for MCP servers...", options)

    network_servers = discover_network_servers_internal(options)

    if Enum.empty?(network_servers) do
      CLI.print_info("No MCP servers found on the network.")
    else
      display_discovered_servers(network_servers, options)

      unless Map.get(options, :dry_run, false) do
        offer_to_add_servers(network_servers, options)
      end
    end
  end

  defp discover_local_servers(options) do
    IO.puts("Local MCP Server Discovery")
    IO.puts("#{String.duplicate("=", 35)}")
    IO.puts("")

    CLI.print_if_verbose("Searching for local MCP servers...", options)

    local_servers = discover_local_servers_internal(options)

    if Enum.empty?(local_servers) do
      CLI.print_info("No local MCP servers found.")
      IO.puts("")
      IO.puts("Try:")
      IO.puts("  - Use --paths to specify additional search directories")
      IO.puts("  - Use --recursive for deep directory search")
      IO.puts("  - Check if servers are installed in non-standard locations")
    else
      display_discovered_servers(local_servers, options)

      unless Map.get(options, :dry_run, false) do
        offer_to_add_servers(local_servers, options)
      end
    end
  end

  ## Local Server Discovery

  defp discover_local_servers_internal(options) do
    search_paths = get_search_paths(options)
    extensions = get_search_extensions(options)
    recursive = Map.get(options, :recursive, false)

    discovered_servers = []

    # Search common executable paths
    discovered_servers =
      discovered_servers ++ search_executable_paths(search_paths, extensions, recursive)

    # Search for known MCP server patterns
    discovered_servers = discovered_servers ++ search_known_patterns(search_paths, recursive)

    # Search Python packages for MCP servers
    discovered_servers = discovered_servers ++ search_python_packages()

    # Search Node.js packages for MCP servers
    discovered_servers = discovered_servers ++ search_nodejs_packages()

    # Remove duplicates and validate
    discovered_servers
    |> Enum.uniq_by(fn server -> server.identifier end)
    |> Enum.filter(fn server -> validate_discovered_server(server) end)
  end

  defp get_search_paths(options) do
    custom_paths =
      case Map.get(options, :paths) do
        nil -> []
        paths_string -> String.split(paths_string, ",") |> Enum.map(&String.trim/1)
      end

    default_paths = [
      "/usr/local/bin",
      "/usr/bin",
      "/opt",
      "~/bin",
      "./bin",
      "./scripts",
      "./tools"
    ]

    (default_paths ++ custom_paths)
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.dir?/1)
  end

  defp get_search_extensions(options) do
    case Map.get(options, :extensions) do
      # Empty string for extensionless files
      nil -> ["py", "js", "sh", "exe", ""]
      exts_string -> String.split(exts_string, ",") |> Enum.map(&String.trim/1)
    end
  end

  defp search_executable_paths(search_paths, extensions, recursive) do
    search_paths
    |> Enum.flat_map(fn path ->
      find_executables_in_path(path, extensions, recursive)
    end)
  end

  defp find_executables_in_path(path, extensions, recursive) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn file ->
          file_path = Path.join(path, file)

          cond do
            recursive and File.dir?(file_path) ->
              find_executables_in_path(file_path, extensions, recursive)

            File.regular?(file_path) and potential_mcp_server?(file, file_path, extensions) ->
              case analyze_potential_server(file_path) do
                {:ok, server_info} -> [server_info]
                {:error, _reason} -> []
              end

            true ->
              []
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  defp potential_mcp_server?(filename, file_path, extensions) do
    # Check file extension
    extension_match =
      case Path.extname(filename) do
        "." <> ext -> Enum.member?(extensions, ext)
        "" -> Enum.member?(extensions, "")
        _ -> false
      end

    # Check if executable
    executable =
      case File.stat(file_path) do
        # Check execute bits
        {:ok, %{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
        {:error, _} -> false
      end

    # Check filename patterns
    name_patterns = [
      ~r/mcp/i,
      ~r/server/i,
      ~r/service/i,
      ~r/agent/i,
      ~r/tool/i
    ]

    pattern_match =
      Enum.any?(name_patterns, fn pattern ->
        Regex.match?(pattern, filename)
      end)

    extension_match and (executable or pattern_match)
  end

  defp search_known_patterns(search_paths, recursive) do
    known_patterns = [
      # Python patterns
      %{pattern: ~r/.*mcp.*server.*\.py$/, type: :python},
      %{pattern: ~r/.*server.*mcp.*\.py$/, type: :python},

      # Node.js patterns
      %{pattern: ~r/.*mcp.*server.*\.js$/, type: :nodejs},
      %{pattern: ~r/.*server.*mcp.*\.js$/, type: :nodejs},

      # Shell script patterns
      %{pattern: ~r/.*mcp.*server.*\.sh$/, type: :shell},

      # Configuration files that might indicate MCP servers
      %{pattern: ~r/mcp.*config.*\.json$/, type: :config},
      %{pattern: ~r/.*mcp.*settings.*\.yaml$/, type: :config}
    ]

    search_paths
    |> Enum.flat_map(fn path ->
      find_files_by_patterns(path, known_patterns, recursive)
    end)
  end

  defp find_files_by_patterns(path, patterns, recursive) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn file ->
          file_path = Path.join(path, file)

          cond do
            recursive and File.dir?(file_path) ->
              find_files_by_patterns(file_path, patterns, recursive)

            File.regular?(file_path) ->
              matching_pattern =
                Enum.find(patterns, fn %{pattern: pattern} ->
                  Regex.match?(pattern, file)
                end)

              case matching_pattern do
                nil ->
                  []

                %{type: type} ->
                  case analyze_file_for_mcp_server(file_path, type) do
                    {:ok, server_info} -> [server_info]
                    {:error, _reason} -> []
                  end
              end

            true ->
              []
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  defp search_python_packages do
    # Check if Python is available
    case System.find_executable("python3") do
      nil ->
        []

      python_path ->
        # Try to list installed packages that might be MCP servers
        case System.cmd(python_path, ["-m", "pip", "list"], stderr_to_stdout: true) do
          {output, 0} ->
            parse_python_packages_for_mcp(output)

          {_output, _code} ->
            []
        end
    end
  rescue
    _ -> []
  end

  defp search_nodejs_packages do
    # Check if npm is available
    case System.find_executable("npm") do
      nil ->
        []

      _npm_path ->
        # Look for package.json files and check for MCP-related packages
        find_nodejs_mcp_packages()
    end
  rescue
    _ -> []
  end

  defp parse_python_packages_for_mcp(pip_output) do
    mcp_keywords = ["mcp", "server", "agent", "tool"]

    pip_output
    |> String.split("\n")
    |> Enum.filter(fn line ->
      line_lower = String.downcase(line)

      Enum.any?(mcp_keywords, fn keyword ->
        String.contains?(line_lower, keyword)
      end)
    end)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [package_name, version] ->
          %{
            identifier: "python-package-#{package_name}",
            name: package_name,
            type: :python_package,
            version: String.trim(version),
            command: "python3 -m #{package_name}",
            description: "Python MCP package: #{package_name}",
            confidence: 0.6,
            transport: :stdio
          }

        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp find_nodejs_mcp_packages do
    # Simple implementation - look for package.json files
    case File.ls(".") do
      {:ok, files} ->
        if Enum.member?(files, "package.json") do
          case analyze_nodejs_package(".") do
            {:ok, server_info} -> [server_info]
            {:error, _reason} -> []
          end
        else
          []
        end

      {:error, _reason} ->
        []
    end
  end

  ## Network Server Discovery

  defp discover_network_servers_internal(options) do
    hosts = get_scan_hosts(options)
    ports = get_scan_ports(options)
    protocols = get_scan_protocols(options)
    timeout = Map.get(options, :timeout, 3000)

    CLI.print_if_verbose(
      "Scanning #{length(hosts)} hosts on ports #{Enum.join(ports, ", ")}",
      options
    )

    hosts
    |> Enum.flat_map(fn host ->
      scan_host_for_mcp_servers(host, ports, protocols, timeout, options)
    end)
  end

  defp get_scan_hosts(options) do
    cond do
      hosts_option = Map.get(options, :hosts) ->
        String.split(hosts_option, ",") |> Enum.map(&String.trim/1)

      subnet_option = Map.get(options, :subnet) ->
        generate_hosts_from_subnet(subnet_option)

      true ->
        # Default to local network scan
        generate_local_network_hosts()
    end
  end

  defp get_scan_ports(options) do
    case Map.get(options, :ports) do
      # Common MCP ports
      nil ->
        [8080, 3000, 8000, 5000, 9000, 8181, 4000]

      ports_string ->
        String.split(ports_string, ",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_integer/1)
    end
  end

  defp get_scan_protocols(options) do
    case Map.get(options, :protocols) do
      nil ->
        ["http", "https"]

      protocols_string ->
        String.split(protocols_string, ",") |> Enum.map(&String.trim/1)
    end
  end

  defp generate_hosts_from_subnet(subnet) do
    # Basic CIDR parsing - in production would use a proper library
    case String.split(subnet, "/") do
      [base_ip, prefix] ->
        # Simple implementation for common subnets
        case {base_ip, prefix} do
          {base, "24"} ->
            [a, b, c, _d] = String.split(base, ".") |> Enum.map(&String.to_integer/1)
            for i <- 1..254, do: "#{a}.#{b}.#{c}.#{i}"

          _ ->
            # Fallback to single host
            [base_ip]
        end

      _ ->
        # Treat as single host
        [subnet]
    end
  end

  defp generate_local_network_hosts do
    # Try to detect local network and generate common hosts
    case System.cmd("hostname", ["-I"], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(String.trim(output), " ") |> hd() do
          ip when is_binary(ip) ->
            case String.split(ip, ".") do
              [a, b, c, _d] ->
                # Scan first 20 hosts in subnet
                for i <- 1..20, do: "#{a}.#{b}.#{c}.#{i}"

              _ ->
                ["127.0.0.1", "localhost"]
            end

          _ ->
            ["127.0.0.1", "localhost"]
        end

      {_output, _code} ->
        ["127.0.0.1", "localhost"]
    end
  rescue
    _ ->
      ["127.0.0.1", "localhost"]
  end

  defp scan_host_for_mcp_servers(host, ports, protocols, timeout, options) do
    CLI.print_if_verbose("Scanning #{host}...", options)

    ports
    |> Enum.flat_map(fn port ->
      protocols
      |> Enum.flat_map(fn protocol ->
        case check_mcp_server_at_endpoint(host, port, protocol, timeout) do
          {:ok, server_info} -> [server_info]
          {:error, _reason} -> []
        end
      end)
    end)
  end

  defp check_mcp_server_at_endpoint(host, port, protocol, timeout) do
    url = "#{protocol}://#{host}:#{port}"

    # Try common MCP endpoints
    mcp_endpoints = [
      "/mcp",
      "/mcp/v1",
      "/api/mcp",
      "/rpc",
      "/jsonrpc"
    ]

    mcp_endpoints
    |> Enum.find_value(fn endpoint ->
      full_url = url <> endpoint

      case test_mcp_endpoint(full_url, timeout) do
        {:ok, server_info} ->
          {:ok,
           Map.merge(server_info, %{
             identifier: "network-#{host}-#{port}",
             host: host,
             port: port,
             protocol: protocol,
             endpoint: endpoint,
             transport: if(protocol == "http", do: :http, else: :sse)
           })}

        {:error, _reason} ->
          nil
      end
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  defp test_mcp_endpoint(url, timeout) do
    headers = [
      {"User-Agent", "MCP-Discovery/1.0"},
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    # Try MCP handshake or discovery request
    case HTTPoison.get(url, headers, recv_timeout: timeout, timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, response} ->
            if looks_like_mcp_response?(response) do
              server_info = extract_server_info_from_response(response, url)
              {:ok, server_info}
            else
              {:error, :not_mcp_server}
            end

          {:error, _} ->
            {:error, :invalid_json}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  rescue
    _ ->
      {:error, :network_error}
  end

  ## Server Analysis Functions

  defp analyze_potential_server(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        server_info = analyze_file_content_for_mcp(content, file_path)
        {:ok, server_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_file_for_mcp_server(file_path, file_type) do
    case File.read(file_path) do
      {:ok, content} ->
        case file_type do
          :python -> analyze_python_file(content, file_path)
          :nodejs -> analyze_nodejs_file(content, file_path)
          :shell -> analyze_shell_file(content, file_path)
          :config -> analyze_config_file(content, file_path)
          _ -> {:error, :unsupported_type}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_nodejs_package(path) do
    package_json_path = Path.join(path, "package.json")

    case File.read(package_json_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, package_info} ->
            if mcp_nodejs_package?(package_info) do
              server_info = %{
                identifier: "nodejs-#{Map.get(package_info, "name", "unknown")}",
                name: Map.get(package_info, "name", "Unknown"),
                type: :nodejs_package,
                version: Map.get(package_info, "version", "unknown"),
                command: "npm start",
                description: Map.get(package_info, "description", "Node.js MCP server"),
                confidence: 0.7,
                transport: :stdio,
                working_directory: path
              }

              {:ok, server_info}
            else
              {:error, :not_mcp_package}
            end

          {:error, _reason} ->
            {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_file_content_for_mcp(content, file_path) do
    filename = Path.basename(file_path)

    # Analyze content for MCP patterns
    mcp_indicators = count_mcp_indicators(content)
    confidence = calculate_confidence(mcp_indicators)

    # Determine transport type from content
    transport = detect_transport_from_content(content)

    # Extract potential server information
    name = extract_server_name(content, filename)
    description = extract_server_description(content)

    %{
      identifier: "file-#{:erlang.phash2(file_path)}",
      name: name,
      type: :discovered_file,
      command: file_path,
      description: description,
      confidence: confidence,
      transport: transport,
      file_path: file_path
    }
  end

  defp analyze_python_file(content, file_path) do
    mcp_patterns = [
      ~r/import.*mcp/i,
      ~r/from.*mcp/i,
      ~r/MCPServer/i,
      ~r/def.*server/i,
      ~r/\.serve\(/i,
      ~r/json.*rpc/i
    ]

    pattern_matches =
      Enum.count(mcp_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if pattern_matches >= 2 do
      {:ok,
       %{
         identifier: "python-#{:erlang.phash2(file_path)}",
         name: Path.basename(file_path, ".py"),
         type: :python_script,
         command: "python3 #{file_path}",
         description: "Python MCP server script",
         confidence: min(pattern_matches * 0.3, 0.9),
         transport: :stdio,
         file_path: file_path
       }}
    else
      {:error, :insufficient_indicators}
    end
  end

  defp analyze_nodejs_file(content, file_path) do
    mcp_patterns = [
      ~r/require.*mcp/i,
      ~r/import.*mcp/i,
      ~r/MCPServer/i,
      ~r/\.listen\(/i,
      ~r/express/i,
      ~r/json.*rpc/i
    ]

    pattern_matches =
      Enum.count(mcp_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if pattern_matches >= 2 do
      {:ok,
       %{
         identifier: "nodejs-#{:erlang.phash2(file_path)}",
         name: Path.basename(file_path, ".js"),
         type: :nodejs_script,
         command: "node #{file_path}",
         description: "Node.js MCP server script",
         confidence: min(pattern_matches * 0.3, 0.9),
         transport: detect_nodejs_transport(content),
         file_path: file_path
       }}
    else
      {:error, :insufficient_indicators}
    end
  end

  defp analyze_shell_file(content, file_path) do
    mcp_patterns = [
      ~r/mcp/i,
      ~r/server/i,
      ~r/rpc/i,
      ~r/json/i
    ]

    pattern_matches =
      Enum.count(mcp_patterns, fn pattern ->
        Regex.match?(pattern, content)
      end)

    if pattern_matches >= 2 do
      {:ok,
       %{
         identifier: "shell-#{:erlang.phash2(file_path)}",
         name: Path.basename(file_path),
         type: :shell_script,
         command: "bash #{file_path}",
         description: "Shell script MCP server",
         confidence: min(pattern_matches * 0.25, 0.7),
         transport: :stdio,
         file_path: file_path
       }}
    else
      {:error, :insufficient_indicators}
    end
  end

  defp analyze_config_file(content, file_path) do
    # This would analyze configuration files that might define MCP servers
    {:ok,
     %{
       identifier: "config-#{:erlang.phash2(file_path)}",
       name: Path.basename(file_path),
       type: :config_reference,
       description: "Configuration file referencing MCP servers",
       confidence: 0.4,
       file_path: file_path
     }}
  end

  ## Analysis Helper Functions

  defp count_mcp_indicators(content) do
    indicators = [
      {~r/mcp/i, 2},
      {~r/server/i, 1},
      {~r/rpc/i, 2},
      {~r/json.*rpc/i, 3},
      {~r/protocol/i, 1},
      {~r/tool/i, 1},
      {~r/agent/i, 1}
    ]

    Enum.reduce(indicators, 0, fn {pattern, weight}, acc ->
      matches = length(Regex.scan(pattern, content))
      acc + matches * weight
    end)
  end

  defp calculate_confidence(indicator_score) do
    # Convert indicator score to confidence percentage
    min(indicator_score * 0.1, 1.0)
  end

  defp detect_transport_from_content(content) do
    cond do
      Regex.match?(~r/http/i, content) -> :http
      Regex.match?(~r/sse|server.*sent/i, content) -> :sse
      true -> :stdio
    end
  end

  defp detect_nodejs_transport(content) do
    cond do
      Regex.match?(~r/express|http\.createServer/i, content) -> :http
      Regex.match?(~r/sse|server.*sent/i, content) -> :sse
      true -> :stdio
    end
  end

  defp extract_server_name(content, filename) do
    # Try to extract server name from content
    name_patterns = [
      ~r/name.*=.*['""]([^'""]+)['"]/i,
      ~r/server.*name.*['""]([^'""]+)['"]/i,
      ~r/title.*['""]([^'""]+)['"]/i
    ]

    extracted_name =
      name_patterns
      |> Enum.find_value(fn pattern ->
        case Regex.run(pattern, content) do
          [_full, name] -> String.trim(name)
          _ -> nil
        end
      end)

    extracted_name || Path.basename(filename, Path.extname(filename))
  end

  defp extract_server_description(content) do
    description_patterns = [
      ~r/description.*['""]([^'""]+)['"]/i,
      ~r/"""([^"""]+)"""/,
      ~r/\/\*\*\s*\n\s*\*\s*([^\n*]+)/
    ]

    description_patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, content) do
        [_full, desc] -> String.trim(desc)
        _ -> nil
      end
    end) || "Discovered MCP server"
  end

  defp looks_like_mcp_response?(response) do
    # Check if the response looks like an MCP server response
    mcp_fields = ["jsonrpc", "method", "id", "result", "tools", "resources"]

    response_keys =
      if is_map(response) do
        Map.keys(response) |> Enum.map(&to_string/1)
      else
        []
      end

    # Check if response has MCP-like structure
    mcp_indicators =
      Enum.count(mcp_fields, fn field ->
        Enum.any?(response_keys, fn key ->
          String.contains?(String.downcase(key), String.downcase(field))
        end)
      end)

    mcp_indicators >= 1
  end

  defp extract_server_info_from_response(response, url) do
    name = Map.get(response, "name") || Map.get(response, "id") || "Network Server"
    description = Map.get(response, "description") || "Discovered network MCP server"
    version = Map.get(response, "version") || "unknown"

    %{
      name: name,
      type: :network_server,
      description: description,
      version: version,
      url: url,
      confidence: 0.8,
      discovered_at: DateTime.utc_now()
    }
  end

  defp mcp_nodejs_package?(package_info) do
    name = Map.get(package_info, "name", "")
    description = Map.get(package_info, "description", "")
    keywords = Map.get(package_info, "keywords", [])

    mcp_terms = ["mcp", "server", "agent", "tool", "protocol"]

    # Check name
    name_match =
      Enum.any?(mcp_terms, fn term ->
        String.contains?(String.downcase(name), term)
      end)

    # Check description
    desc_match =
      Enum.any?(mcp_terms, fn term ->
        String.contains?(String.downcase(description), term)
      end)

    # Check keywords
    keyword_match =
      Enum.any?(keywords, fn keyword ->
        Enum.any?(mcp_terms, fn term ->
          String.contains?(String.downcase(to_string(keyword)), term)
        end)
      end)

    name_match or desc_match or keyword_match
  end

  defp validate_discovered_server(server) do
    # Basic validation of discovered server
    server.confidence > 0.3 and
      String.length(server.name) > 0 and
      server.identifier != nil
  end

  ## Results Processing

  defp process_discovery_results(discovered_servers, options) do
    if Enum.empty?(discovered_servers) do
      CLI.print_info("No MCP servers discovered.")
      show_discovery_suggestions()
    else
      IO.puts("Discovery Results:")
      IO.puts("#{String.duplicate("=", 20)}")

      display_discovered_servers(discovered_servers, options)

      unless Map.get(options, :dry_run, false) do
        if Map.get(options, :auto_add, false) do
          auto_add_servers(discovered_servers, options)
        else
          offer_to_add_servers(discovered_servers, options)
        end
      end
    end
  end

  defp display_discovered_servers(servers, options) do
    # Sort by confidence
    sorted_servers = Enum.sort_by(servers, & &1.confidence, :desc)

    if CLI.verbose?(options) do
      # Detailed view
      Enum.each(sorted_servers, fn server ->
        display_detailed_server_info(server)
      end)
    else
      # Table view
      display_servers_table(sorted_servers)
    end
  end

  defp display_detailed_server_info(server) do
    IO.puts("")
    IO.puts("Server: #{server.name}")
    IO.puts("#{String.duplicate("-", String.length("Server: #{server.name}"))}")
    IO.puts("  Type: #{format_server_type(server.type)}")
    IO.puts("  Confidence: #{Float.round(server.confidence * 100, 1)}%")

    case server.type do
      :discovered_file ->
        IO.puts("  Command: #{server.command}")
        IO.puts("  File: #{server.file_path}")

      :network_server ->
        IO.puts("  URL: #{server.url}")
        IO.puts("  Host: #{server.host}:#{server.port}")

      :python_package ->
        IO.puts("  Package: #{server.name}")
        IO.puts("  Version: #{server.version}")
        IO.puts("  Command: #{server.command}")

      :nodejs_package ->
        IO.puts("  Package: #{server.name}")
        IO.puts("  Version: #{server.version}")

        if Map.has_key?(server, :working_directory) do
          IO.puts("  Directory: #{server.working_directory}")
        end

      _ ->
        if Map.has_key?(server, :command) do
          IO.puts("  Command: #{server.command}")
        end
    end

    IO.puts("  Transport: #{String.upcase(to_string(server.transport))}")
    IO.puts("  Description: #{server.description}")
  end

  defp display_servers_table(servers) do
    headers = ["Name", "Type", "Transport", "Confidence", "Description"]

    rows =
      Enum.map(servers, fn server ->
        [
          server.name,
          format_server_type(server.type),
          String.upcase(to_string(server.transport)),
          "#{Float.round(server.confidence * 100, 1)}%",
          truncate_text(server.description, 40)
        ]
      end)

    display_simple_table(headers, rows)

    IO.puts("")
    IO.puts("Found #{length(servers)} potential MCP servers")
    IO.puts("Use --verbose for detailed information")
  end

  defp offer_to_add_servers(servers, options) do
    unless CLI.quiet?(options) do
      IO.puts("")
      IO.write("Add discovered servers to configuration? [y/N]: ")

      case IO.read(:stdio, :line) do
        {:ok, input} ->
          case String.trim(String.downcase(input)) do
            "y" -> add_discovered_servers(servers, options)
            "yes" -> add_discovered_servers(servers, options)
            _ -> IO.puts("Discovery complete. No servers added.")
          end

        _ ->
          IO.puts("Discovery complete. No servers added.")
      end
    end
  end

  defp auto_add_servers(servers, options) do
    CLI.print_if_verbose("Auto-adding discovered servers...", options)

    # Only add high-confidence servers in auto-add mode
    high_confidence_servers =
      Enum.filter(servers, fn server ->
        server.confidence >= 0.7
      end)

    add_discovered_servers(high_confidence_servers, options)
  end

  defp add_discovered_servers(servers, options) do
    case Config.get_configuration() do
      {:ok, current_config} ->
        added_count = 0

        {updated_config, final_count} =
          Enum.reduce(servers, {current_config, added_count}, fn server, {config, count} ->
            case convert_discovered_to_config(server) do
              {:ok, server_name, server_config} ->
                case Config.add_server_config(config, server_name, server_config) do
                  updated_config when is_map(updated_config) ->
                    CLI.print_success("Added: #{server_name}")
                    {updated_config, count + 1}

                  {:error, :server_exists} ->
                    CLI.print_warning("Skipped: #{server_name} (already exists)")
                    {config, count}

                  {:error, reason} ->
                    CLI.print_error("Failed to add #{server_name}: #{reason}")
                    {config, count}
                end

              {:error, reason} ->
                CLI.print_error("Cannot convert server #{server.name}: #{reason}")
                {config, count}
            end
          end)

        if final_count > 0 do
          # Save updated configuration
          config_path = "./.maestro/mcp_settings.json"

          case Config.save_configuration(updated_config, config_path) do
            :ok ->
              CLI.print_success("Configuration updated with #{final_count} new servers")

              IO.puts("")
              IO.puts("Use 'maestro mcp list' to see all configured servers")
              IO.puts("Use 'maestro mcp status' to check server health")

            {:error, reason} ->
              CLI.print_error("Failed to save configuration: #{reason}")
          end
        else
          CLI.print_info("No servers were added")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load current configuration: #{reason}")
    end
  end

  defp convert_discovered_to_config(server) do
    server_name = generate_unique_server_name(server.name)

    base_config = %{
      "timeout" => 30_000,
      "trust" => false,
      "description" => server.description
    }

    transport_config =
      case server.transport do
        :stdio ->
          case server.type do
            :discovered_file ->
              %{"command" => server.command}

            :python_script ->
              %{"command" => server.command}

            :nodejs_script ->
              %{"command" => server.command}

            :shell_script ->
              %{"command" => server.command}

            :python_package ->
              %{"command" => server.command}

            :nodejs_package ->
              config = %{"command" => server.command}

              if Map.has_key?(server, :working_directory) do
                Map.put(config, "cwd", server.working_directory)
              else
                config
              end

            _ ->
              if Map.has_key?(server, :command) do
                %{"command" => server.command}
              else
                {:error, :no_command_specified}
              end
          end

        :http ->
          if Map.has_key?(server, :url) do
            %{"httpUrl" => server.url}
          else
            {:error, :no_url_specified}
          end

        :sse ->
          if Map.has_key?(server, :url) do
            %{"url" => server.url}
          else
            {:error, :no_url_specified}
          end
      end

    server_config = Map.merge(base_config, transport_config)
    {:ok, server_name, server_config}
  end

  defp generate_unique_server_name(base_name) do
    # Clean up the name and ensure uniqueness
    clean_name =
      base_name
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
      |> String.replace(~r/_+/, "_")
      |> String.trim_leading("_")
      |> String.trim_trailing("_")

    # Check if name already exists and add suffix if needed
    case Config.get_configuration() do
      {:ok, config} ->
        servers = get_in(config, ["mcpServers"]) || %{}

        if Map.has_key?(servers, clean_name) do
          # Find unique suffix
          suffix =
            1..99
            |> Enum.find(fn n ->
              candidate = "#{clean_name}_#{n}"
              not Map.has_key?(servers, candidate)
            end)

          if suffix do
            "#{clean_name}_#{suffix}"
          else
            "#{clean_name}_#{:os.system_time(:second)}"
          end
        else
          clean_name
        end

      {:error, _} ->
        clean_name
    end
  end

  ## Template Functions

  defp show_available_templates(options) do
    IO.puts("Available MCP Server Templates")
    IO.puts("#{String.duplicate("=", 35)}")
    IO.puts("")

    templates = get_available_templates()

    if Map.get(options, :list_all) do
      display_all_templates(templates, options)
    else
      category_filter = Map.get(options, :category)
      filtered_templates = filter_templates_by_category(templates, category_filter)
      display_templates_by_category(filtered_templates, options)
    end
  end

  defp create_from_template(template_name, options) do
    templates = get_available_templates()

    case find_template_by_name(templates, template_name) do
      nil ->
        CLI.print_error("Template '#{template_name}' not found.")
        IO.puts("")
        IO.puts("Available templates:")
        list_template_names(templates)

      template ->
        create_server_from_template(template, options)
    end
  end

  ## Template Data and Management

  defp get_available_templates do
    %{
      "python-basic" => %{
        name: "python-basic",
        category: "Python",
        description: "Basic Python MCP server",
        command: "python3 -m mcp_server",
        transport: "stdio",
        setup_instructions: "Install: pip install mcp-server-python"
      },
      "nodejs-express" => %{
        name: "nodejs-express",
        category: "Node.js",
        description: "Express.js HTTP MCP server",
        command: "node server.js",
        transport: "http",
        setup_instructions: "Install: npm install express mcp-sdk"
      },
      "file-operations" => %{
        name: "file-operations",
        category: "Tools",
        description: "File system operations server",
        command: "python3 -m file_mcp_server",
        transport: "stdio",
        setup_instructions: "Built-in file operations server"
      },
      "web-scraper" => %{
        name: "web-scraper",
        category: "Tools",
        description: "Web scraping and data extraction",
        command: "python3 -m web_scraper_mcp",
        transport: "stdio",
        setup_instructions: "Install: pip install requests beautifulsoup4"
      },
      "database-tools" => %{
        name: "database-tools",
        category: "Database",
        description: "Database query and management tools",
        command: "python3 -m db_mcp_server",
        transport: "stdio",
        setup_instructions: "Configure database connection"
      }
    }
  end

  ## Display and Helper Functions

  defp show_discovery_suggestions do
    IO.puts("")
    IO.puts("Discovery Tips:")
    IO.puts("- Use --network to scan for network-based MCP servers")
    IO.puts("- Use --recursive --paths /custom/path to search additional directories")
    IO.puts("- Use --extensions py,js,sh to search for specific file types")
    IO.puts("- Check if MCP servers are installed via pip or npm")
    IO.puts("- Look for existing MCP server documentation or repositories")
    IO.puts("")
    IO.puts("You can also create servers from templates:")
    IO.puts("  maestro mcp discover templates")
    IO.puts("  maestro mcp discover from-template python-basic")
  end

  defp format_server_type(:discovered_file), do: "File"
  defp format_server_type(:python_script), do: "Python"
  defp format_server_type(:nodejs_script), do: "Node.js"
  defp format_server_type(:shell_script), do: "Shell"
  defp format_server_type(:python_package), do: "Py Pkg"
  defp format_server_type(:nodejs_package), do: "JS Pkg"
  defp format_server_type(:network_server), do: "Network"
  defp format_server_type(:config_reference), do: "Config"
  defp format_server_type(type), do: String.capitalize(to_string(type))

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  defp truncate_text(text, _max_length), do: to_string(text)

  defp display_simple_table(headers, rows) do
    # Calculate column widths
    col_widths = calculate_column_widths(headers, rows)

    # Print headers
    header_line =
      headers
      |> Enum.with_index()
      |> Enum.map(fn {header, idx} ->
        String.pad_trailing(header, Enum.at(col_widths, idx))
      end)
      |> Enum.join(" | ")

    IO.puts(header_line)

    # Print separator
    separator =
      col_widths
      |> Enum.map(&String.duplicate("-", &1))
      |> Enum.join("-|-")

    IO.puts(separator)

    # Print rows
    Enum.each(rows, fn row ->
      row_line =
        row
        |> Enum.with_index()
        |> Enum.map(fn {cell, idx} ->
          String.pad_trailing(to_string(cell), Enum.at(col_widths, idx))
        end)
        |> Enum.join(" | ")

      IO.puts(row_line)
    end)
  end

  defp calculate_column_widths(headers, rows) do
    all_rows = [headers | rows]

    if Enum.empty?(all_rows) do
      []
    else
      num_cols = length(hd(all_rows))

      for col_idx <- 0..(num_cols - 1) do
        all_rows
        |> Enum.map(&Enum.at(&1, col_idx, ""))
        |> Enum.map(&String.length(to_string(&1)))
        |> Enum.max()
        # Minimum column width
        |> max(10)
      end
    end
  end

  # Template helper functions (simplified implementations)
  defp display_all_templates(templates, _options) do
    Enum.each(templates, fn {name, template} ->
      IO.puts("#{name}: #{template.description} (#{template.category})")
    end)
  end

  defp filter_templates_by_category(templates, nil), do: templates

  defp filter_templates_by_category(templates, category) do
    Map.filter(templates, fn {_name, template} ->
      String.downcase(template.category) == String.downcase(category)
    end)
  end

  defp display_templates_by_category(templates, _options) do
    templates
    |> Enum.group_by(fn {_name, template} -> template.category end)
    |> Enum.each(fn {category, category_templates} ->
      IO.puts("#{category}:")

      Enum.each(category_templates, fn {name, template} ->
        IO.puts("  #{name}: #{template.description}")
      end)

      IO.puts("")
    end)
  end

  defp find_template_by_name(templates, name) do
    case Map.get(templates, name) do
      nil -> nil
      template -> template
    end
  end

  defp list_template_names(templates) do
    templates
    |> Map.keys()
    |> Enum.sort()
    |> Enum.each(fn name ->
      IO.puts("  - #{name}")
    end)
  end

  defp create_server_from_template(template, options) do
    IO.puts("Creating server from template: #{template.name}")
    IO.puts("Description: #{template.description}")
    IO.puts("")

    # Get server name from user
    IO.write("Enter server name: ")

    case IO.read(:stdio, :line) do
      {:ok, input} ->
        server_name = String.trim(input)

        if String.length(server_name) > 0 do
          create_template_server(server_name, template, options)
        else
          CLI.print_error("Server name is required.")
        end

      _ ->
        CLI.print_error("Failed to read server name.")
    end
  end

  defp create_template_server(server_name, template, options) do
    server_config = %{
      "command" => template.command,
      "timeout" => 30_000,
      "trust" => false,
      "description" => template.description
    }

    # Add transport-specific configuration
    server_config =
      case template.transport do
        "http" ->
          # For HTTP servers, we'd need a URL - this is a simplified example
          server_config

        "sse" ->
          # For SSE servers, we'd need a URL - this is a simplified example
          server_config

        _ ->
          server_config
      end

    case Config.get_configuration() do
      {:ok, current_config} ->
        case Config.add_server_config(current_config, server_name, server_config) do
          updated_config when is_map(updated_config) ->
            config_path = "./.maestro/mcp_settings.json"

            case Config.save_configuration(updated_config, config_path) do
              :ok ->
                CLI.print_success("Server '#{server_name}' created from template")
                IO.puts("")
                IO.puts("Setup Instructions:")
                IO.puts("  #{template.setup_instructions}")
                IO.puts("")
                IO.puts("Next steps:")
                IO.puts("  maestro mcp status #{server_name}")
                IO.puts("  maestro mcp test #{server_name}")

              {:error, reason} ->
                CLI.print_error("Failed to save configuration: #{reason}")
            end

          {:error, :server_exists} ->
            CLI.print_error("Server '#{server_name}' already exists.")

          {:error, reason} ->
            CLI.print_error("Failed to create server: #{reason}")
        end

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{reason}")
    end
  end
end
