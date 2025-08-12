defmodule TheMaestroWeb.OAuthController do
  use TheMaestroWeb, :controller

  require Logger

  alias TheMaestro.Providers.Gemini

  @doc """
  Handles OAuth2 callback from Google OAuth service.

  This endpoint receives the authorization code from Google after user consent
  and exchanges it for access tokens, then caches them for future use.
  """
  def callback(conn, params) do
    Logger.info("OAuth callback received with params: #{inspect(Map.keys(params))}")

    cond do
      # Check for error in callback
      Map.has_key?(params, "error") ->
        error = Map.get(params, "error")
        error_description = Map.get(params, "error_description", "Unknown OAuth error")
        Logger.error("OAuth error: #{error} - #{error_description}")
        render_error_page(conn, "OAuth Error: #{error_description}")

      # Check for state mismatch (CSRF protection)
      !valid_state?(params) ->
        Logger.error("OAuth state mismatch - possible CSRF attack")
        render_error_page(conn, "Invalid state - possible CSRF attack")

      # Success case - we have the authorization code
      Map.has_key?(params, "code") ->
        code = Map.get(params, "code")
        handle_authorization_code(conn, code, params)

      # No code in response
      true ->
        Logger.error("No authorization code received")
        render_error_page(conn, "No authorization code received")
    end
  end

  defp valid_state?(params) do
    # Get state from params
    received_state = Map.get(params, "state")

    # For now, we'll accept any non-empty state
    # NOTE: In production, consider storing and validating the actual state value
    # using a secure session store or encrypted cookies for CSRF protection
    received_state && String.trim(received_state) != ""
  end

  defp handle_authorization_code(conn, code, _params) do
    Logger.info("Processing authorization code...")

    # Build the redirect URI for token exchange
    redirect_uri = build_redirect_uri(conn)

    case Gemini.exchange_authorization_code(code, redirect_uri) do
      {:ok, tokens} ->
        case Gemini.cache_oauth_credentials(tokens) do
          {:ok, _} ->
            Logger.info("OAuth flow completed successfully!")
            render_success_page(conn)

          {:error, reason} ->
            Logger.error("Failed to cache credentials: #{inspect(reason)}")
            render_error_page(conn, "Failed to save credentials")
        end

      {:error, reason} ->
        Logger.error("Failed to exchange authorization code: #{inspect(reason)}")
        render_error_page(conn, "Failed to exchange authorization code")
    end
  end

  defp build_redirect_uri(conn) do
    # Build the full redirect URI that matches what we sent to Google
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{scheme}://#{host}#{port}/oauth2callback"
  end

  defp render_success_page(conn) do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>The Maestro - Authentication Successful</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          text-align: center;
          padding: 50px 20px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          margin: 0;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          justify-content: center;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          background: rgba(255, 255, 255, 0.1);
          padding: 40px;
          border-radius: 20px;
          backdrop-filter: blur(10px);
          box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        h1 {
          color: #4ade80;
          font-size: 2.5rem;
          margin-bottom: 1rem;
        }
        p {
          font-size: 1.1rem;
          line-height: 1.6;
          margin-bottom: 1rem;
        }
        .success-icon {
          font-size: 4rem;
          margin-bottom: 1rem;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="success-icon">✅</div>
        <h1>Authentication Successful!</h1>
        <p>You have successfully authenticated The Maestro with Google.</p>
        <p>Your credentials have been securely cached for future use.</p>
        <p><strong>You can now close this browser tab and return to your terminal.</strong></p>
        <p>The demo will continue automatically.</p>
      </div>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  defp render_error_page(conn, error_message) do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>The Maestro - Authentication Error</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          text-align: center;
          padding: 50px 20px;
          background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
          color: white;
          margin: 0;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          justify-content: center;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          background: rgba(255, 255, 255, 0.1);
          padding: 40px;
          border-radius: 20px;
          backdrop-filter: blur(10px);
          box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        h1 {
          color: #fca5a5;
          font-size: 2.5rem;
          margin-bottom: 1rem;
        }
        p {
          font-size: 1.1rem;
          line-height: 1.6;
          margin-bottom: 1rem;
        }
        .error-icon {
          font-size: 4rem;
          margin-bottom: 1rem;
        }
        .error-details {
          background: rgba(0, 0, 0, 0.2);
          padding: 20px;
          border-radius: 10px;
          margin: 20px 0;
          font-family: monospace;
          word-break: break-word;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="error-icon">❌</div>
        <h1>Authentication Error</h1>
        <div class="error-details">#{html_escape(error_message)}</div>
        <p>Please close this tab and try the authentication process again.</p>
        <p>If the problem persists, please check your network connection and try again.</p>
      </div>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(400, html)
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#x27;")
  end
end
