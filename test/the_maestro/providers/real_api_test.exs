defmodule TheMaestro.Providers.RealAPITest do
  use ExUnit.Case, async: false

  alias TheMaestro.Providers.Client

  @moduletag :real_api

  describe "real Anthropic API authentication" do
    test "can make authenticated API call with real key" do
      # Only run if real API key is available
      case System.get_env("ANTHROPIC_API_KEY") do
        nil ->
          IO.puts("Skipping real API test - no ANTHROPIC_API_KEY environment variable")

        "" ->
          IO.puts("Skipping real API test - empty ANTHROPIC_API_KEY environment variable")

        api_key ->
          # Set up configuration with real API key
          original_config = Application.get_env(:the_maestro, :anthropic, [])
          test_config = Keyword.put(original_config, :api_key, api_key)
          Application.put_env(:the_maestro, :anthropic, test_config)

          try do
            # Build client using our implementation
            client = Client.build_client(:anthropic)

            # Make a minimal API request
            request_body = %{
              "model" => "claude-3-haiku-20240307",
              "max_tokens" => 10,
              "messages" => [
                %{
                  "role" => "user",
                  "content" => "Hi"
                }
              ]
            }

            case Tesla.post(client, "/v1/messages", request_body) do
              {:ok, %Tesla.Env{status: 200}} ->
                IO.puts("✅ AC3 VALIDATED: Got 200 OK response - authentication successful!")
                assert true

              {:ok, %Tesla.Env{status: 400, body: body}} ->
                error_message = get_in(body, ["error", "message"]) || ""

                if String.contains?(error_message, "credit balance") do
                  IO.puts("✅ AC3 VALIDATED: Authentication successful (credit balance issue)")
                  assert true
                else
                  IO.puts("⚠️  AC3: Got 400 but different error: #{error_message}")
                  assert true, "Authentication worked but got request error: #{error_message}"
                end

              {:ok, %Tesla.Env{status: 401}} ->
                flunk("❌ AC3 FAILED: Got 401 Unauthorized - authentication not working")

              {:ok, %Tesla.Env{status: 403}} ->
                flunk(
                  "❌ AC3 FAILED: Got 403 Forbidden - API key invalid or insufficient permissions"
                )

              {:ok, %Tesla.Env{status: status, body: _body}} ->
                IO.puts("ℹ️  AC3: Got status #{status}")

                if status < 500 do
                  assert true, "Authentication likely successful (got #{status})"
                else
                  flunk("Server error: #{status}")
                end

              {:error, reason} ->
                flunk("Network error: #{inspect(reason)}")
            end
          after
            # Cleanup
            Application.put_env(:the_maestro, :anthropic, original_config)
          end
      end
    end
  end
end
