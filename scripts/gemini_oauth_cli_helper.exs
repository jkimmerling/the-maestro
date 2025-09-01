#!/usr/bin/env elixir
# Helper for Gemini OAuth in headless or minimal environments.
#
# Usage:
#   mix run scripts/gemini_oauth_cli_helper.exs start <session_name>
#     - Generates an OAuth URL + PKCE, saves PKCE to ~/.maestro/gemini_pkce_<session>.json
#   mix run scripts/gemini_oauth_cli_helper.exs finish <session_name> <code>
#     - Loads PKCE, exchanges <code> for tokens, persists session, deletes PKCE file
#   mix run scripts/gemini_oauth_cli_helper.exs curl <session_name>
#     - Prints a curl command to POST the code to the local callback endpoint

Application.ensure_all_started(:logger)

alias TheMaestro.Auth

defmodule PKCEStore do
  @base Path.join(System.user_home!(), ".maestro")

  def path(session), do: Path.join(@base, "gemini_pkce_" <> session <> ".json")

  def save(session, pkce) do
    File.mkdir_p!(@base)
    File.write!(path(session), Jason.encode!(pkce, pretty: true))
  end

  def load(session) do
    case File.read(path(session)) do
      {:ok, body} -> Jason.decode!(body)
      _ -> nil
    end
  end

  def delete(session) do
    _ = File.rm(path(session))
    :ok
  end
end

defmodule Url do
  def build_gemini_auth_url(pkce) do
    client_id = System.get_env("GEMINI_OAUTH_CLIENT_ID") ||
      "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"

    redirect_uri = System.get_env("GEMINI_OAUTH_REDIRECT_URI") ||
      "http://localhost:1455/oauth2callback"

    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/userinfo.profile",
      "https://www.googleapis.com/auth/generative-language.retriever"
    ]

    params = %{
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "scope" => Enum.join(scopes, " "),
      "state" => pkce["code_verifier"] || pkce[:code_verifier],
      "code_challenge" => pkce["code_challenge"] || pkce[:code_challenge],
      "code_challenge_method" => pkce["code_challenge_method"] || pkce[:code_challenge_method],
      "access_type" => "offline",
      "prompt" => "consent"
    }

    base = System.get_env("GEMINI_AUTHORIZATION_ENDPOINT") ||
      "https://accounts.google.com/o/oauth2/v2/auth"

    base <> "?" <> URI.encode_query(params)
  end
end

defmodule Main do
  def run(["start", session]) when is_binary(session) do
    {:ok, {auth_url, pkce}} = Auth.generate_gemini_oauth_url()
    PKCEStore.save(session, Map.from_struct(pkce))

    IO.puts("\nGemini OAuth URL (open in browser):\n\n" <> auth_url <> "\n")
    IO.puts("Saved PKCE to: #{PKCEStore.path(session)}")
    IO.puts("\nWhen you get the authorization code, either:
  1) Finish directly:
     mix run scripts/gemini_oauth_cli_helper.exs finish #{session} AUTH_CODE

  2) Or POST to the local callback (if server is running):
     " <> curl_command(session) <> "\n")
  end

  def run(["finish", session, code]) do
    pkce = PKCEStore.load(session)

    if is_nil(pkce) do
      IO.puts("PKCE not found for session '#{session}'. Run 'start' first.")
      System.halt(2)
    end

    case Auth.finish_gemini_oauth(code, %{code_verifier: pkce["code_verifier"]}, session) do
      {:ok, _token} ->
        IO.puts("\n✅ OAuth complete. Saved session '#{session}'.")
        PKCEStore.delete(session)

      {:error, reason} ->
        IO.puts("\n❌ OAuth failed: #{inspect(reason)}")
        System.halt(2)
    end
  end

  def run(["curl", session]) do
    pkce = PKCEStore.load(session)
    if is_nil(pkce) do
      IO.puts("PKCE not found for session '#{session}'. Run 'start' first.")
      System.halt(2)
    end
    IO.puts(curl_command(session))
  end

  def run(_args) do
    IO.puts("""
Usage:
  mix run scripts/gemini_oauth_cli_helper.exs start <session>
  mix run scripts/gemini_oauth_cli_helper.exs finish <session> <code>
  mix run scripts/gemini_oauth_cli_helper.exs curl <session>
""")
    System.halt(1)
  end

  defp curl_command(session) do
    pkce = PKCEStore.load(session)
    code_verifier = pkce && (pkce["code_verifier"] || pkce[:code_verifier]) || "<PKCE_VERIFIER>"
    ~s|curl -sS -X POST http://localhost:4000/api/oauth/gemini/callback \
  -H 'content-type: application/json' \
  -d '{"code":"<AUTH_CODE>","session":"#{session}","state":"#{code_verifier}"}'|
  end
end

Main.run(System.argv())

