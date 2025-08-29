#!/usr/bin/env elixir

# Simple OAuth callback server for manual testing
# Runs on localhost:8080 to receive OpenAI OAuth callbacks

defmodule OAuthCallbackServer do
  require Logger

  def start_server do
    {:ok, listen_socket} = :gen_tcp.listen(8080, [
      :binary,
      {:packet, 0},
      {:active, false},
      {:reuseaddr, true}
    ])

    IO.puts("🚀 OAuth callback server started on http://localhost:8080")
    IO.puts("📋 Waiting for OAuth callback from OpenAI...")
    IO.puts("🌐 Visit the OAuth URL in your browser to complete authorization")
    IO.puts("")

    accept_connections(listen_socket)
  end

  defp accept_connections(listen_socket) do
    case :gen_tcp.accept(listen_socket, 30_000) do  # 30 second timeout
      {:ok, client_socket} ->
        spawn(fn -> handle_connection(client_socket) end)
        accept_connections(listen_socket)

      {:error, :timeout} ->
        IO.puts("⏰ Server timeout - no OAuth callback received within 30 seconds")
        :gen_tcp.close(listen_socket)

      {:error, reason} ->
        IO.puts("❌ Server error: #{inspect(reason)}")
        :gen_tcp.close(listen_socket)
    end
  end

  defp handle_connection(client_socket) do
    case :gen_tcp.recv(client_socket, 0, 5000) do
      {:ok, request} ->
        handle_request(client_socket, request)

      {:error, reason} ->
        IO.puts("❌ Request error: #{inspect(reason)}")
        :gen_tcp.close(client_socket)
    end
  end

  defp handle_request(client_socket, request) do
    request_lines = String.split(request, "\r\n")
    request_line = List.first(request_lines)
    
    IO.puts("📥 Received request: #{request_line}")

    case extract_oauth_params(request_line) do
      {:ok, code, state} ->
        IO.puts("")
        IO.puts("✅ OAuth callback received successfully!")
        IO.puts("🔑 Authorization code: #{code}")
        IO.puts("🎲 State parameter: #{state}")
        IO.puts("")
        IO.puts("📋 Copy this authorization code for token exchange:")
        IO.puts("#{code}")
        IO.puts("")

        send_success_response(client_socket)
        
        # Give user time to copy the code
        Process.sleep(2000)
        :gen_tcp.close(client_socket)
        System.halt(0)

      {:error, reason} ->
        IO.puts("❌ Failed to extract OAuth parameters: #{reason}")
        send_error_response(client_socket)
        :gen_tcp.close(client_socket)
    end
  end

  defp extract_oauth_params(request_line) do
    case String.split(request_line, " ") do
      ["GET", path, _version] ->
        case String.split(path, "?", parts: 2) do
          ["/auth/callback", query_string] ->
            params = parse_query_string(query_string)
            
            case {Map.get(params, "code"), Map.get(params, "state")} do
              {code, state} when is_binary(code) and is_binary(state) ->
                {:ok, code, state}
              
              {nil, _} ->
                {:error, "Missing authorization code"}
              
              {_, nil} ->
                {:error, "Missing state parameter"}
            end

          _ ->
            {:error, "Invalid callback path"}
        end

      _ ->
        {:error, "Invalid HTTP request format"}
    end
  end

  defp parse_query_string(query_string) do
    query_string
    |> String.split("&")
    |> Enum.map(fn param ->
      case String.split(param, "=", parts: 2) do
        [key, value] -> {URI.decode(key), URI.decode(value)}
        [key] -> {URI.decode(key), ""}
      end
    end)
    |> Map.new()
  end

  defp send_success_response(client_socket) do
    response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/html\r
    Connection: close\r
    \r
    <!DOCTYPE html>
    <html>
    <head>
        <title>OAuth Authorization Successful</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            .success { color: #28a745; }
            .code { background: #f8f9fa; padding: 10px; border-radius: 5px; font-family: monospace; }
        </style>
    </head>
    <body>
        <h1 class="success">✅ OAuth Authorization Successful!</h1>
        <p>Authorization code has been captured by the server.</p>
        <p>Check your terminal for the authorization code to continue.</p>
        <p><em>You can close this window now.</em></p>
    </body>
    </html>
    """
    
    :gen_tcp.send(client_socket, response)
  end

  defp send_error_response(client_socket) do
    response = """
    HTTP/1.1 400 Bad Request\r
    Content-Type: text/html\r
    Connection: close\r
    \r
    <!DOCTYPE html>
    <html>
    <head>
        <title>OAuth Authorization Failed</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
            .error { color: #dc3545; }
        </style>
    </head>
    <body>
        <h1 class="error">❌ OAuth Authorization Failed</h1>
        <p>Unable to process OAuth callback.</p>
        <p>Please check the server logs for details.</p>
    </body>
    </html>
    """
    
    :gen_tcp.send(client_socket, response)
  end
end

# Start the server
OAuthCallbackServer.start_server()