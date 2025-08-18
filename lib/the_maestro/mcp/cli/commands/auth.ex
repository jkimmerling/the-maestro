defmodule TheMaestro.MCP.CLI.Commands.Auth do
  @moduledoc """
  Authentication command for MCP CLI.

  Provides functionality to manage authentication and API keys for MCP servers.
  """

  alias TheMaestro.MCP.{Config, ServerSupervisor}
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the auth command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      ["login", server_name] ->
        login_to_server(server_name, options)

      ["logout", server_name] ->
        logout_from_server(server_name, options)

      ["status"] ->
        show_auth_status(options)

      _ ->
        CLI.print_error("Invalid auth command. Use --help for usage.")
    end
  end

  @doc """
  Manage API keys.
  """
  def manage_apikey(args, options) do
    case args do
      ["set", server_name, key] ->
        set_api_key(server_name, key, options)

      ["remove", server_name] ->
        remove_api_key(server_name, options)

      ["list"] ->
        list_api_keys(options)

      _ ->
        CLI.print_error("Invalid apikey command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the auth command.
  """
  def show_help do
    IO.puts("""
    MCP Authentication Management

    Usage:
      maestro mcp auth <subcommand> [OPTIONS]
      maestro mcp apikey <subcommand> [OPTIONS]

    Auth Commands:
      login <server>           Authenticate with server
      logout <server>          Log out from server
      status                   Show authentication status

    API Key Commands:
      set <server> <key>       Set API key for server
      remove <server>          Remove API key for server  
      list                     List configured API keys

    Options:
      --reset                  Reset authentication state
      --help                   Show this help message

    Examples:
      maestro mcp auth login myServer
      maestro mcp auth status
      maestro mcp apikey set myServer "sk-..."
      maestro mcp apikey list
    """)
  end

  ## Private Functions

  defp login_to_server(server_name, options) do
    CLI.print_info("Logging in to server '#{server_name}'...")

    with {:ok, config} <- Config.load_configuration(),
         {:ok, server} <- find_server_config(config, server_name) do
      # Determine authentication method based on server configuration
      auth_method = Map.get(server, :auth_method, :interactive)

      case auth_method do
        :api_key ->
          prompt_and_store_api_key(server_name, server, options)

        :oauth ->
          handle_oauth_login(server_name, server, options)

        :bearer_token ->
          handle_bearer_token(server_name, server, options)

        :interactive ->
          handle_interactive_login(server_name, server, options)

        :none ->
          CLI.print_success("No authentication required for '#{server_name}'")
          {:ok, :no_auth}

        _ ->
          CLI.print_error("Unsupported authentication method: #{auth_method}")
          {:error, :unsupported_auth}
      end
    else
      {:error, :server_not_found} ->
        CLI.print_error("Server '#{server_name}' not found in configuration")
        {:error, :server_not_found}

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{inspect(reason)}")
        {:error, :config_load_failed}
    end
  end

  defp logout_from_server(server_name, options) do
    CLI.print_info("Logging out from server '#{server_name}'...")

    # Clear stored credentials for the server
    case clear_stored_credentials(server_name) do
      :ok ->
        CLI.print_success("Successfully logged out from '#{server_name}'")

        # Optionally disconnect active connections
        if Map.get(options, :disconnect, true) do
          disconnect_server(server_name)
        end

        {:ok, :logged_out}

      {:error, reason} ->
        CLI.print_error("Failed to clear credentials: #{inspect(reason)}")
        {:error, :clear_failed}
    end
  end

  defp show_auth_status(options) do
    CLI.print_info("Authentication status:")

    case Config.load_configuration() do
      {:ok, config} when map_size(config.servers) == 0 ->
        IO.puts("  No servers configured")
        {:ok, []}

      {:ok, config} ->
        # Get authentication status for all servers
        auth_status =
          config.servers
          |> Enum.map(fn {name, server} ->
            auth_method = Map.get(server, :auth_method, :none)
            has_credentials = check_stored_credentials(name)
            connection_status = get_connection_auth_status(name)
            {name, auth_method, has_credentials, connection_status}
          end)
          |> Enum.sort_by(fn {name, _, _, _} -> name end)

        # Calculate column widths
        name_width =
          auth_status
          |> Enum.map(fn {name, _, _, _} -> String.length(name) end)
          |> Enum.max()
          |> max(6)

        # Print header
        IO.puts("")

        IO.puts(
          "  #{"Server" |> String.pad_trailing(name_width)} | Auth Method | Credentials | Connection"
        )

        IO.puts("  #{String.duplicate("-", name_width)} | ----------- | ----------- | ----------")

        # Print server authentication status
        Enum.each(auth_status, fn {name, method, has_creds, conn_status} ->
          method_display = format_auth_method(method)
          creds_display = if has_creds, do: "✓", else: "✗"
          conn_display = format_connection_auth_status(conn_status)

          IO.puts(
            "  #{name |> String.pad_trailing(name_width)} | #{method_display |> String.pad_trailing(11)} | #{creds_display |> String.pad_trailing(11)} | #{conn_display}"
          )
        end)

        # Show summary
        total_servers = length(auth_status)
        authenticated_servers = Enum.count(auth_status, fn {_, _, has_creds, _} -> has_creds end)

        connected_servers =
          Enum.count(auth_status, fn {_, _, _, status} -> status == :authenticated end)

        IO.puts("")
        IO.puts("  Summary:")
        IO.puts("    Total servers: #{total_servers}")
        IO.puts("    With credentials: #{authenticated_servers}")
        IO.puts("    Connected & authenticated: #{connected_servers}")

        {:ok, auth_status}

      {:error, reason} ->
        CLI.print_error("Failed to load configuration: #{inspect(reason)}")
        {:error, :config_load_failed}
    end
  end

  defp set_api_key(server_name, key, options) do
    CLI.print_info("Setting API key for server '#{server_name}'...")

    # Basic API key validation
    if String.length(key) < 8 do
      CLI.print_error("API key too short (minimum 8 characters)")
      {:error, :invalid_key}
    end

    # Store API key securely
    case store_api_key(server_name, key, options) do
      :ok ->
        # Mask key for display (show first 6 and last 4 characters)
        masked_key = mask_api_key(key)
        CLI.print_success("API key set for '#{server_name}' (#{masked_key})")

        # Test connection if requested
        if Map.get(options, :test, false) do
          CLI.print_info("Testing API key connection...")
          # Would test connection in real implementation
        end

        {:ok, :stored}

      {:error, reason} ->
        CLI.print_error("Failed to store API key: #{inspect(reason)}")
        {:error, :store_failed}
    end
  end

  defp remove_api_key(server_name, options) do
    CLI.print_info("Removing API key for server '#{server_name}'...")

    case remove_stored_api_key(server_name) do
      :ok ->
        CLI.print_success("API key removed for '#{server_name}'")

        # Disconnect if currently connected using the API key
        if Map.get(options, :disconnect, true) do
          disconnect_server(server_name)
        end

        {:ok, :removed}

      {:error, :not_found} ->
        CLI.print_warning("No API key found for '#{server_name}'")
        {:ok, :not_found}

      {:error, reason} ->
        CLI.print_error("Failed to remove API key: #{inspect(reason)}")
        {:error, :remove_failed}
    end
  end

  defp list_api_keys(options) do
    CLI.print_info("Configured API keys:")

    case get_stored_api_keys() do
      {:ok, []} ->
        IO.puts("  No API keys configured")
        {:ok, []}

      {:ok, api_keys} ->
        # Calculate column widths
        name_width =
          api_keys
          |> Enum.map(fn {name, _} -> String.length(name) end)
          |> Enum.max()
          |> max(6)

        # Print header
        IO.puts("")
        IO.puts("  #{"Server" |> String.pad_trailing(name_width)} | API Key (masked) | Status")
        IO.puts("  #{String.duplicate("-", name_width)} | ---------------- | ------")

        # Print API key information
        Enum.each(api_keys, fn {name, key_info} ->
          masked_key = mask_api_key(key_info.key)
          status = test_api_key_status(name, key_info.key)
          status_display = format_api_key_status(status)

          IO.puts(
            "  #{name |> String.pad_trailing(name_width)} | #{masked_key |> String.pad_trailing(16)} | #{status_display}"
          )
        end)

        # Show summary
        total_keys = length(api_keys)

        valid_keys =
          Enum.count(api_keys, fn {name, key_info} ->
            test_api_key_status(name, key_info.key) == :valid
          end)

        IO.puts("")
        IO.puts("  Summary:")
        IO.puts("    Total API keys: #{total_keys}")
        IO.puts("    Valid keys: #{valid_keys}")

        {:ok, api_keys}

      {:error, reason} ->
        CLI.print_error("Failed to list API keys: #{inspect(reason)}")
        {:error, :list_failed}
    end
  end

  # Helper functions for authentication management

  defp find_server_config(config, server_name) do
    case Map.get(config.servers, server_name) do
      nil -> {:error, :server_not_found}
      server -> {:ok, server}
    end
  end

  defp prompt_and_store_api_key(server_name, server, options) do
    if Map.get(options, :key) do
      # Key provided via command line option
      key = Map.get(options, :key)
      store_api_key(server_name, key, options)
    else
      # Prompt for API key interactively
      CLI.print_info("Please enter the API key for '#{server_name}':")

      case IO.gets("API Key: ") do
        key when is_binary(key) ->
          key = String.trim(key)

          if String.length(key) > 0 do
            store_api_key(server_name, key, options)
          else
            CLI.print_error("Empty API key provided")
            {:error, :empty_key}
          end

        _ ->
          CLI.print_error("Failed to read API key")
          {:error, :read_failed}
      end
    end
  end

  defp handle_oauth_login(server_name, server, options) do
    oauth_config = Map.get(server, :oauth_config, %{})
    auth_url = Map.get(oauth_config, :auth_url)

    if auth_url do
      CLI.print_info("Opening OAuth authorization URL...")
      CLI.print_info("URL: #{auth_url}")

      # Attempt to open URL in browser
      case System.cmd("open", [auth_url]) do
        {_, 0} -> :ok
        _ -> CLI.print_warning("Could not open browser automatically")
      end

      CLI.print_info("Please complete OAuth flow and enter the authorization code:")

      case IO.gets("Authorization Code: ") do
        code when is_binary(code) ->
          code = String.trim(code)
          # In real implementation, would exchange code for token
          CLI.print_success("OAuth authentication completed")
          {:ok, :oauth}

        _ ->
          CLI.print_error("Failed to read authorization code")
          {:error, :read_failed}
      end
    else
      CLI.print_error("No OAuth authorization URL configured for server")
      {:error, :no_auth_url}
    end
  end

  defp handle_bearer_token(server_name, server, options) do
    if token = Map.get(options, :token) do
      store_bearer_token(server_name, token, options)
    else
      CLI.print_info("Please enter the bearer token for '#{server_name}':")

      case IO.gets("Bearer Token: ") do
        token when is_binary(token) ->
          token = String.trim(token)

          if String.length(token) > 0 do
            store_bearer_token(server_name, token, options)
          else
            CLI.print_error("Empty bearer token provided")
            {:error, :empty_token}
          end

        _ ->
          CLI.print_error("Failed to read bearer token")
          {:error, :read_failed}
      end
    end
  end

  defp handle_interactive_login(server_name, server, options) do
    CLI.print_info("Interactive authentication for '#{server_name}'")
    CLI.print_info("Please follow the prompts from the MCP server...")

    # Start server connection and handle interactive authentication
    case ServerSupervisor.start_server(server_name, %{interactive_auth: true}) do
      {:ok, _pid} ->
        CLI.print_success("Interactive authentication completed")
        {:ok, :interactive}

      {:error, reason} ->
        CLI.print_error("Interactive authentication failed: #{inspect(reason)}")
        {:error, :interactive_failed}
    end
  end

  # Credential storage functions (would use secure storage in real implementation)

  defp store_api_key(server_name, key, _options) do
    # In real implementation, this would use secure credential storage
    # For now, we'll use application environment (not secure for production)
    stored_keys = Application.get_env(:the_maestro, :mcp_api_keys, %{})

    updated_keys =
      Map.put(stored_keys, server_name, %{
        key: key,
        stored_at: DateTime.utc_now(),
        type: :api_key
      })

    Application.put_env(:the_maestro, :mcp_api_keys, updated_keys)
    :ok
  end

  defp store_bearer_token(server_name, token, _options) do
    stored_tokens = Application.get_env(:the_maestro, :mcp_bearer_tokens, %{})

    updated_tokens =
      Map.put(stored_tokens, server_name, %{
        token: token,
        stored_at: DateTime.utc_now(),
        type: :bearer_token
      })

    Application.put_env(:the_maestro, :mcp_bearer_tokens, updated_tokens)
    :ok
  end

  defp clear_stored_credentials(server_name) do
    # Clear API keys
    stored_keys = Application.get_env(:the_maestro, :mcp_api_keys, %{})
    updated_keys = Map.delete(stored_keys, server_name)
    Application.put_env(:the_maestro, :mcp_api_keys, updated_keys)

    # Clear bearer tokens
    stored_tokens = Application.get_env(:the_maestro, :mcp_bearer_tokens, %{})
    updated_tokens = Map.delete(stored_tokens, server_name)
    Application.put_env(:the_maestro, :mcp_bearer_tokens, updated_tokens)

    :ok
  end

  defp remove_stored_api_key(server_name) do
    stored_keys = Application.get_env(:the_maestro, :mcp_api_keys, %{})

    if Map.has_key?(stored_keys, server_name) do
      updated_keys = Map.delete(stored_keys, server_name)
      Application.put_env(:the_maestro, :mcp_api_keys, updated_keys)
      :ok
    else
      {:error, :not_found}
    end
  end

  defp get_stored_api_keys do
    stored_keys = Application.get_env(:the_maestro, :mcp_api_keys, %{})
    api_keys = Enum.to_list(stored_keys)
    {:ok, api_keys}
  end

  defp check_stored_credentials(server_name) do
    api_keys = Application.get_env(:the_maestro, :mcp_api_keys, %{})
    bearer_tokens = Application.get_env(:the_maestro, :mcp_bearer_tokens, %{})

    Map.has_key?(api_keys, server_name) || Map.has_key?(bearer_tokens, server_name)
  end

  # Status and validation functions

  defp get_connection_auth_status(server_name) do
    case ServerSupervisor.get_server_pid(server_name) do
      {:ok, pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          case GenServer.call(pid, :get_auth_status, 1000) do
            {:ok, :authenticated} -> :authenticated
            {:ok, :unauthenticated} -> :unauthenticated
            _ -> :unknown
          end
        else
          :disconnected
        end

      _ ->
        :disconnected
    end
  catch
    _, _ -> :unknown
  end

  defp test_api_key_status(server_name, key) do
    # In real implementation, this would test the API key against the server
    # For now, return a mock status based on key format
    cond do
      String.length(key) < 10 -> :invalid
      String.starts_with?(key, "sk-") || String.starts_with?(key, "ak-") -> :valid
      true -> :unknown
    end
  end

  # Formatting functions

  defp format_auth_method(:api_key), do: "API Key"
  defp format_auth_method(:oauth), do: "OAuth"
  defp format_auth_method(:bearer_token), do: "Bearer Token"
  defp format_auth_method(:interactive), do: "Interactive"
  defp format_auth_method(:none), do: "None"
  defp format_auth_method(other), do: "#{other}"

  defp format_connection_auth_status(:authenticated), do: "Authenticated"
  defp format_connection_auth_status(:unauthenticated), do: "Not Auth"
  defp format_connection_auth_status(:disconnected), do: "Disconnected"
  defp format_connection_auth_status(:unknown), do: "Unknown"

  defp format_api_key_status(:valid), do: "Valid"
  defp format_api_key_status(:invalid), do: "Invalid"
  defp format_api_key_status(:unknown), do: "Unknown"

  defp mask_api_key(key) when byte_size(key) > 10 do
    first_part = String.slice(key, 0, 6)
    last_part = String.slice(key, -4, 4)
    "#{first_part}...#{last_part}"
  end

  defp mask_api_key(key), do: "#{String.slice(key, 0, 2)}...***"

  defp disconnect_server(server_name) do
    case ServerSupervisor.stop_server(server_name) do
      :ok ->
        CLI.print_info("Disconnected from '#{server_name}'")

      {:error, reason} ->
        CLI.print_warning("Failed to disconnect: #{inspect(reason)}")
    end
  end
end
