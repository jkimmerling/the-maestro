defmodule TheMaestroWeb.CliAuthController do
  @moduledoc """
  CLI Device Authorization Flow Controller
  
  This controller implements the OAuth 2.0 Device Authorization Grant (RFC 8628)
  for CLI authentication. It provides endpoints for:
  
  1. Device code generation - CLI requests device code and user verification URL
  2. User authorization - Browser-based endpoint where user authorizes device
  3. Token polling - CLI polls for completion and receives access token
  
  The flow matches the requirements from Epic 2, Story 2.5 and follows
  standard device authorization patterns used by tools like GitHub CLI.
  """
  
  use TheMaestroWeb, :controller
  
  require Logger
  
  # Device code configuration
  @device_code_length 8
  @user_code_length 6  
  @device_code_expiry_minutes 15
  @polling_interval_seconds 5
  
  # In-memory store for device codes (in production, use Redis or database)
  @device_codes_store :device_codes_store
  
  def init_device_codes_store do
    case :ets.whereis(@device_codes_store) do
      :undefined ->
        :ets.new(@device_codes_store, [:named_table, :public, :set])
      _ ->
        :ok
    end
  end
  
  @doc """
  POST /api/cli/auth/device
  
  Generates a device code and user verification URL for CLI authentication.
  The CLI client displays the URL and user_code to the user, who then
  visits the URL in their browser to authorize the device.
  
  Returns:
  - device_code: Used by CLI for polling
  - user_code: Short code displayed to user
  - verification_uri: URL user visits to authorize
  - verification_uri_complete: URL with user_code pre-filled
  - expires_in: Expiry time in seconds
  - interval: Polling interval in seconds
  """
  def device(conn, _params) do
    init_device_codes_store()
    
    # Generate unique codes
    device_code = generate_device_code()
    user_code = generate_user_code()
    
    # Calculate expiry
    expires_at = DateTime.add(DateTime.utc_now(), @device_code_expiry_minutes * 60, :second)
    expires_in = @device_code_expiry_minutes * 60
    
    # Store device code info
    device_info = %{
      device_code: device_code,
      user_code: user_code,
      expires_at: expires_at,
      authorized: false,
      access_token: nil,
      error: nil
    }
    
    :ets.insert(@device_codes_store, {device_code, device_info})
    
    Logger.info("Generated device code for CLI authentication: #{user_code}")
    
    # Build verification URIs
    base_url = build_base_url(conn)
    verification_uri = "#{base_url}/api/cli/auth/authorize"
    verification_uri_complete = "#{verification_uri}?user_code=#{user_code}"
    
    json(conn, %{
      device_code: device_code,
      user_code: user_code,
      verification_uri: verification_uri,
      verification_uri_complete: verification_uri_complete,
      expires_in: expires_in,
      interval: @polling_interval_seconds
    })
  end
  
  @doc """
  GET /api/cli/auth/authorize
  
  Browser-based endpoint where the user authorizes the device.
  Displays a form asking the user to enter their user_code and authorize.
  """
  def authorize(conn, params) do
    init_device_codes_store()
    user_code = Map.get(params, "user_code", "")
    
    render(conn, :authorize, layout: false, user_code: user_code)
  end
  
  @doc """
  POST /api/cli/auth/authorize
  
  Processes the user's authorization. User submits their user_code,
  and if valid, we redirect them through OAuth flow.
  """
  def authorize_post(conn, %{"user_code" => user_code}) do
    init_device_codes_store()
    
    case find_device_by_user_code(user_code) do
      {:ok, device_info} ->
        # Check if expired
        if DateTime.compare(DateTime.utc_now(), device_info.expires_at) == :gt do
          render_error(conn, "Device code has expired. Please start the process again.")
        else
          # Store the device_code in session for OAuth callback
          conn
          |> put_session(:pending_device_code, device_info.device_code)
          |> put_session(:user_code, user_code)
          |> redirect(external: "/auth/google?state=device_auth")
        end
        
      {:error, :not_found} ->
        render_error(conn, "Invalid user code. Please check the code and try again.")
    end
  end
  
  @doc """
  GET /api/cli/auth/poll?device_code=<device_code>
  
  Polling endpoint for CLI to check if user has completed authorization.
  
  Returns:
  - access_token: If authorization complete
  - error: If expired or denied
  - Still pending: HTTP 428 (Precondition Required) with retry info
  """
  def poll(conn, %{"device_code" => device_code}) do
    init_device_codes_store()
    
    case :ets.lookup(@device_codes_store, device_code) do
      [{^device_code, device_info}] ->
        cond do
          # Check if expired
          DateTime.compare(DateTime.utc_now(), device_info.expires_at) == :gt ->
            :ets.delete(@device_codes_store, device_code)
            conn
            |> put_status(400)
            |> json(%{error: "expired_token", error_description: "Device code has expired"})
          
          # Check if there's an error
          device_info.error ->
            :ets.delete(@device_codes_store, device_code)
            conn
            |> put_status(400)
            |> json(%{error: device_info.error, error_description: "Authorization failed"})
          
          # Check if authorized and we have access token
          device_info.authorized and device_info.access_token ->
            :ets.delete(@device_codes_store, device_code)
            json(conn, %{
              access_token: device_info.access_token,
              token_type: "Bearer",
              expires_in: 3600
            })
          
          # Still pending
          true ->
            conn
            |> put_status(428) # Precondition Required
            |> json(%{
              error: "authorization_pending",
              error_description: "User has not yet completed authorization",
              interval: @polling_interval_seconds
            })
        end
        
      [] ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_request", error_description: "Invalid device code"})
    end
  end
  
  @doc """
  Callback function to complete device authorization after OAuth success.
  This should be called from the OAuth callback when state=device_auth.
  """
  def complete_device_authorization(conn, access_token) do
    init_device_codes_store()
    
    case get_session(conn, :pending_device_code) do
      nil ->
        Logger.error("No pending device code in session")
        {:error, :no_pending_device_code}
        
      device_code ->
        case :ets.lookup(@device_codes_store, device_code) do
          [{^device_code, device_info}] ->
            # Update with access token
            updated_info = %{device_info | 
              authorized: true, 
              access_token: access_token
            }
            :ets.insert(@device_codes_store, {device_code, updated_info})
            
            # Clear from session
            conn = 
              conn
              |> delete_session(:pending_device_code)
              |> delete_session(:user_code)
            
            Logger.info("Device authorization completed for user code: #{device_info.user_code}")
            {:ok, conn}
            
          [] ->
            Logger.error("Device code not found: #{device_code}")
            {:error, :device_code_not_found}
        end
    end
  end
  
  @doc """
  Marks a device authorization as failed.
  This should be called from OAuth callback on failure when state=device_auth.
  """
  def fail_device_authorization(conn, error) do
    init_device_codes_store()
    
    case get_session(conn, :pending_device_code) do
      nil ->
        {:error, :no_pending_device_code}
        
      device_code ->
        case :ets.lookup(@device_codes_store, device_code) do
          [{^device_code, device_info}] ->
            # Update with error
            updated_info = %{device_info | error: error}
            :ets.insert(@device_codes_store, {device_code, updated_info})
            
            # Clear from session
            conn = 
              conn
              |> delete_session(:pending_device_code)
              |> delete_session(:user_code)
              
            {:ok, conn}
            
          [] ->
            {:error, :device_code_not_found}
        end
    end
  end
  
  # Private helper functions
  
  defp generate_device_code do
    # Generate a longer, URL-safe device code for internal use
    @device_code_length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
  
  defp generate_user_code do
    # Generate a short, human-readable code for display to user
    chars = ~c"23456789ABCDEFGHJKLMNPQRSTUVWXYZ" # Excludes confusing chars like 0, O, 1, I
    
    for _ <- 1..@user_code_length do
      Enum.random(chars)
    end
    |> List.to_string()
  end
  
  defp find_device_by_user_code(user_code) do
    # Scan ETS table to find device by user_code
    match_spec = [
      {{:"$1", %{user_code: :"$2", expires_at: :"$3", authorized: :"$4", device_code: :"$5", access_token: :"$6", error: :"$7"}}, 
       [{:==, :"$2", user_code}], 
       [%{device_code: :"$5", user_code: :"$2", expires_at: :"$3", authorized: :"$4", access_token: :"$6", error: :"$7"}]}
    ]
    
    case :ets.select(@device_codes_store, match_spec) do
      [device_info] -> {:ok, device_info}
      [] -> {:error, :not_found}
    end
  end
  
  defp build_base_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    
    "#{scheme}://#{host}#{port}"
  end
  
  defp render_error(conn, error_message) do
    render(conn, :error, layout: false, error_message: error_message)
  end
end