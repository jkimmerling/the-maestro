defmodule TheMaestro.TUI.EmbeddedServer do
  @moduledoc """
  Minimal embedded web server for TUI OAuth device authorization flow.

  This server provides the necessary endpoints for OAuth device authorization
  without requiring the full Phoenix application to be running.
  """

  use GenServer
  require Logger

  @default_port 4001

  defmodule State do
    @moduledoc false
    defstruct [:port, :socket, :device_codes, :authorized_tokens]
  end

  ## Public API

  @doc """
  Starts the embedded server on the specified port.
  """
  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)

    GenServer.start_link(
      __MODULE__,
      %State{port: port, device_codes: %{}, authorized_tokens: %{}},
      name: __MODULE__
    )
  end

  @doc """
  Stops the embedded server.
  """
  def stop do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Gets the server's current port.
  """
  def get_port do
    GenServer.call(__MODULE__, :get_port)
  end

  @doc """
  Generates a device code for OAuth authorization.
  """
  def generate_device_code do
    GenServer.call(__MODULE__, :generate_device_code)
  end

  @doc """
  Polls for authorization status using a device code.
  """
  def poll_authorization(device_code) do
    GenServer.call(__MODULE__, {:poll_authorization, device_code})
  end

  @doc """
  Authorizes a device using the user code (called from web interface).
  """
  def authorize_device(user_code) do
    GenServer.call(__MODULE__, {:authorize_device, user_code})
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    case start_http_server(state.port) do
      {:ok, socket} ->
        Logger.info("TUI embedded server started on port #{state.port}")
        {:ok, %{state | socket: socket}}

      {:error, reason} ->
        Logger.error("Failed to start TUI embedded server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_call(:generate_device_code, _from, state) do
    device_code = generate_random_code(32)
    user_code = generate_user_code()
    # 10 minutes
    expires_in = 600
    # 5 seconds
    interval = 5

    verification_uri = "http://localhost:#{state.port}/auth/device"
    verification_uri_complete = "#{verification_uri}?user_code=#{user_code}"

    device_info = %{
      device_code: device_code,
      user_code: user_code,
      expires_at: System.system_time(:second) + expires_in,
      status: :pending
    }

    new_device_codes = Map.put(state.device_codes, device_code, device_info)

    response = %{
      "device_code" => device_code,
      "user_code" => user_code,
      "verification_uri" => verification_uri,
      "verification_uri_complete" => verification_uri_complete,
      "expires_in" => expires_in,
      "interval" => interval
    }

    {:reply, {:ok, response}, %{state | device_codes: new_device_codes}}
  end

  @impl true
  def handle_call({:poll_authorization, device_code}, _from, state) do
    case Map.get(state.device_codes, device_code) do
      nil ->
        {:reply, {:error, "invalid_grant"}, state}

      device_info ->
        current_time = System.system_time(:second)

        cond do
          current_time > device_info.expires_at ->
            {:reply, {:error, "expired_token"}, state}

          device_info.status == :authorized ->
            # Generate access token
            access_token = generate_random_code(64)

            new_tokens =
              Map.put(state.authorized_tokens, access_token, %{
                device_code: device_code,
                created_at: current_time
              })

            {:reply, {:ok, %{"access_token" => access_token}},
             %{state | authorized_tokens: new_tokens}}

          true ->
            {:reply, {:error, "authorization_pending"}, state}
        end
    end
  end

  @impl true
  def handle_call({:authorize_device, user_code}, _from, state) do
    # Find the device code by user code
    device_entry =
      Enum.find(state.device_codes, fn {_device_code, device_info} ->
        device_info.user_code == user_code
      end)

    case device_entry do
      {device_code, device_info} ->
        current_time = System.system_time(:second)

        if current_time <= device_info.expires_at do
          # Mark as authorized
          updated_device_info = %{device_info | status: :authorized}
          new_device_codes = Map.put(state.device_codes, device_code, updated_device_info)

          {:reply, :ok, %{state | device_codes: new_device_codes}}
        else
          {:reply, {:error, "expired"}, state}
        end

      nil ->
        {:reply, {:error, "invalid_user_code"}, state}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    response = handle_http_request(data, state)
    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end

    :ok
  end

  ## Private Functions

  defp start_http_server(port) do
    :gen_tcp.listen(port, [
      :binary,
      {:packet, :http_bin},
      {:active, true},
      {:reuseaddr, true}
    ])
  end

  defp handle_http_request(data, state) do
    try do
      case parse_http_request(data) do
        {:get, "/api/cli/auth/device", _query_params} ->
          # Device authorization endpoint
          case generate_device_code() do
            {:ok, response} ->
              json_response(200, response)

            {:error, reason} ->
              json_response(400, %{"error" => reason})
          end

        {:get, "/api/cli/auth/poll", query_params} ->
          # Polling endpoint
          device_code = Map.get(query_params, "device_code")

          case poll_authorization(device_code) do
            {:ok, response} ->
              json_response(200, response)

            {:error, reason} ->
              json_response(400, %{"error" => reason})
          end

        {:get, "/auth/device", query_params} ->
          # Device authorization page
          user_code = Map.get(query_params, "user_code", "")
          html_response(200, device_auth_page(user_code))

        {:post, "/auth/device", _query_params} ->
          # Handle device authorization form submission
          # For simplicity, we'll parse from the original data
          case extract_form_data_from_request(data) do
            %{"user_code" => user_code} ->
              case authorize_device_by_user_code(user_code, state) do
                :ok ->
                  html_response(200, success_page())

                {:error, _reason} ->
                  html_response(400, error_page())
              end

            _ ->
              html_response(400, error_page())
          end

        _ ->
          html_response(404, not_found_page())
      end
    rescue
      error ->
        Logger.error("Error handling HTTP request: #{inspect(error)}")
        html_response(500, error_page())
    end
  end

  defp parse_http_request(data) when is_binary(data) do
    case String.split(data, "\r\n", parts: 2) do
      [request_line | _] ->
        case String.split(request_line, " ", parts: 3) do
          [method, path_with_query, _version] ->
            method_atom = String.downcase(method) |> String.to_atom()
            {path, query_params} = parse_path_and_query(path_with_query)
            {method_atom, path, query_params}

          _ ->
            {:get, "/", %{}}
        end

      _ ->
        {:get, "/", %{}}
    end
  end

  defp parse_path_and_query(path_with_query) do
    case String.split(path_with_query, "?", parts: 2) do
      [path, query_string] ->
        query_params = URI.decode_query(query_string)
        {path, query_params}

      [path] ->
        {path, %{}}
    end
  end

  defp json_response(status, data) do
    body = Jason.encode!(data)

    """
    HTTP/1.1 #{status} OK\r
    Content-Type: application/json\r
    Content-Length: #{byte_size(body)}\r
    Access-Control-Allow-Origin: *\r
    \r
    #{body}
    """
  end

  defp html_response(status, body) do
    """
    HTTP/1.1 #{status} OK\r
    Content-Type: text/html\r
    Content-Length: #{byte_size(body)}\r
    \r
    #{body}
    """
  end

  defp device_auth_page(user_code) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>The Maestro - Device Authorization</title>
        <meta charset="UTF-8">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 500px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .header { text-align: center; margin-bottom: 30px; }
            .user-code { font-size: 24px; font-weight: bold; color: #007bff; text-align: center; padding: 15px; background: #f8f9fa; border: 2px dashed #007bff; border-radius: 4px; margin: 20px 0; }
            .btn { background: #007bff; color: white; border: none; padding: 12px 24px; border-radius: 4px; cursor: pointer; font-size: 16px; }
            .btn:hover { background: #0056b3; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🎭 The Maestro</h1>
                <h2>Device Authorization</h2>
            </div>
            
            <p>To authorize your TUI device, please confirm the user code matches:</p>
            
            <div class="user-code">#{user_code}</div>
            
            <p>If this code matches what you see in your terminal, click the button below to authorize:</p>
            
            <form method="POST" action="/auth/device" style="text-align: center;">
                <input type="hidden" name="user_code" value="#{user_code}">
                <button type="submit" class="btn">✅ Authorize Device</button>
            </form>
            
            <p style="font-size: 12px; color: #666; margin-top: 20px;">
                This page will automatically close after authorization. You can return to your terminal.
            </p>
        </div>
    </body>
    </html>
    """
  end

  defp success_page do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Authorization Successful</title>
        <meta charset="UTF-8">
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 500px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
            .success { color: #28a745; font-size: 48px; margin-bottom: 20px; }
        </style>
        <script>
            setTimeout(function() { window.close(); }, 3000);
        </script>
    </head>
    <body>
        <div class="container">
            <div class="success">✅</div>
            <h1>Authorization Successful!</h1>
            <p>Your device has been authorized successfully.</p>
            <p>You can now return to your terminal and continue using The Maestro TUI.</p>
            <p><em>This window will close automatically in 3 seconds.</em></p>
        </div>
    </body>
    </html>
    """
  end

  defp not_found_page do
    """
    <!DOCTYPE html>
    <html>
    <head><title>404 Not Found</title></head>
    <body>
        <h1>404 - Not Found</h1>
        <p>The requested resource was not found.</p>
    </body>
    </html>
    """
  end

  defp error_page do
    """
    <!DOCTYPE html>
    <html>
    <head><title>500 Internal Server Error</title></head>
    <body>
        <h1>500 - Internal Server Error</h1>
        <p>An error occurred while processing your request.</p>
    </body>
    </html>
    """
  end

  defp generate_random_code(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64(padding: false)
    |> binary_part(0, length)
  end

  defp generate_user_code do
    # Generate a human-friendly code like "ABCD-1234"
    letters = for _ <- 1..4, do: Enum.random(?A..?Z)
    numbers = for _ <- 1..4, do: Enum.random(?0..?9)

    letter_string = letters |> List.to_string()
    number_string = numbers |> List.to_string()

    letter_string <> "-" <> number_string
  end

  defp authorize_device_by_user_code(user_code, _state) do
    # Use the GenServer call to authorize the device
    authorize_device(user_code)
  end

  defp parse_form_data(body) do
    # Simple form data parsing for POST requests
    # In a real implementation, this would be more robust
    case String.split(body, "\r\n\r\n", parts: 2) do
      [_headers, form_body] ->
        URI.decode_query(form_body)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp extract_form_data_from_request(data) do
    # Extract form data from the full HTTP request
    case String.split(data, "\r\n\r\n", parts: 2) do
      [_headers, body] ->
        URI.decode_query(body)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end
end
