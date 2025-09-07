#!/usr/bin/env elixir

# Script to capture EXACT OAuth API calls for all providers
# This will create baseline logs for comparison after refactoring

defmodule OAuthAPICapture do
  @moduledoc """
  Captures the exact API calls made by each OAuth provider.
  CRITICAL: These captures will be used to ensure ZERO drift after refactoring.
  """

  require Logger

  @test_prompt "list the files in your directory"
  @capture_dir "oauth_api_captures"

  def run do
    setup_capture_dir()
    
    IO.puts("\n🔍 Starting OAuth API Call Capture...")
    IO.puts("=" <> String.duplicate("=", 70))
    
    # Test each provider
    providers = [
      {:anthropic, "ClaudeAgent"},
      {:openai, "ChatGPTAgent"},
      {:gemini, "GeminiAgent"}
    ]
    
    for {provider, agent} <- providers do
      IO.puts("\n📦 Testing #{provider} OAuth (#{agent})...")
      capture_provider_calls(provider, agent)
    end
    
    IO.puts("\n✅ Capture complete! Check #{@capture_dir}/ for results")
    generate_summary()
  end

  defp setup_capture_dir do
    File.mkdir_p!(@capture_dir)
    File.mkdir_p!("#{@capture_dir}/requests")
    File.mkdir_p!("#{@capture_dir}/responses")
  end

  defp capture_provider_calls(:anthropic, agent) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    # Hook into Req to capture the exact request
    capture_file = "#{@capture_dir}/requests/anthropic_oauth_#{timestamp}.json"
    
    # Create a custom Finch with telemetry hooks to capture requests
    setup_request_capture(:anthropic_finch, capture_file)
    
    # Run the agent
    result = run_agent_with_capture(agent, @test_prompt)
    
    # Log the result
    log_result(:anthropic, result, timestamp)
  end

  defp capture_provider_calls(:openai, agent) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    capture_file = "#{@capture_dir}/requests/openai_oauth_#{timestamp}.json"
    
    setup_request_capture(:openai_finch, capture_file)
    result = run_agent_with_capture(agent, @test_prompt)
    log_result(:openai, result, timestamp)
  end

  defp capture_provider_calls(:gemini, agent) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    capture_file = "#{@capture_dir}/requests/gemini_oauth_#{timestamp}.json"
    
    setup_request_capture(:gemini_finch, capture_file)
    result = run_agent_with_capture(agent, @test_prompt)
    log_result(:gemini, result, timestamp)
  end

  defp setup_request_capture(finch_name, capture_file) do
    # Attach telemetry handler to capture HTTP requests
    handler_id = "capture_#{finch_name}_#{System.unique_integer()}"
    
    :telemetry.attach(
      handler_id,
      [:finch, :request, :start],
      fn _event_name, _measurements, metadata, _config ->
        if metadata[:name] == finch_name do
          request_data = %{
            method: metadata[:method],
            scheme: metadata[:scheme],
            host: metadata[:host],
            port: metadata[:port],
            path: metadata[:path],
            headers: metadata[:headers],
            body: metadata[:body],
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          # Write to capture file
          File.write!(capture_file, Jason.encode!(request_data, pretty: true))
          
          # Also log to console for immediate visibility
          IO.puts("\n📸 Captured #{finch_name} request:")
          IO.puts("  Method: #{request_data.method}")
          IO.puts("  URL: #{request_data.scheme}://#{request_data.host}:#{request_data.port}#{request_data.path}")
          IO.puts("  Headers: #{inspect(request_data.headers, pretty: true, limit: :infinity)}")
          
          if request_data.body do
            IO.puts("  Body: #{inspect(request_data.body, pretty: true, limit: :infinity)}")
          end
        end
      end,
      nil
    )
    
    # Detach after a delay to ensure capture
    spawn(fn ->
      Process.sleep(10_000)
      :telemetry.detach(handler_id)
    end)
  end

  defp run_agent_with_capture(agent_module_str, prompt) do
    try do
      # Set up environment for detailed logging
      System.put_env("STREAM_LOG_EVENTS", "1")
      System.put_env("STREAM_LOG_UNKNOWN_EVENTS", "1")
      System.put_env("HTTP_DEBUG", "1")
      
      # Build the command to run the agent
      cmd = "mix run scripts/e2e_tools_agent_run.exs \"#{agent_module_str}\" \"#{prompt}\""
      
      IO.puts("  Running: #{cmd}")
      
      # Capture both stdout and stderr
      {output, exit_code} = System.cmd("bash", ["-c", cmd], 
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )
      
      %{
        success: exit_code == 0,
        output: output,
        exit_code: exit_code
      }
    rescue
      e ->
        %{
          success: false,
          error: Exception.format(:error, e, __STACKTRACE__)
        }
    end
  end

  defp log_result(provider, result, timestamp) do
    result_file = "#{@capture_dir}/responses/#{provider}_result_#{timestamp}.json"
    
    File.write!(result_file, Jason.encode!(result, pretty: true))
    
    if result.success do
      IO.puts("  ✅ #{provider} test successful")
    else
      IO.puts("  ❌ #{provider} test failed: #{inspect(result[:error])}")
    end
  end

  defp generate_summary do
    summary = """
    # OAuth API Call Capture Summary
    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    
    ## Purpose
    This capture provides the EXACT API calls made by each OAuth provider.
    ANY deviation from these calls after refactoring is a CRITICAL BUG.
    
    ## Captured Providers
    - Anthropic (ClaudeAgent) - OAuth with Claude Code headers
    - OpenAI (ChatGPTAgent) - OAuth with bearer tokens
    - Gemini (GeminiAgent) - OAuth with Google API client headers
    
    ## Files Generated
    - requests/: Contains exact HTTP requests with all headers and bodies
    - responses/: Contains responses and execution results
    
    ## Validation
    After any refactoring, run this script again and compare:
    1. All headers must match EXACTLY (order may vary but content must be identical)
    2. All request bodies must match EXACTLY
    3. All URLs and endpoints must match EXACTLY
    4. All authentication tokens format must match EXACTLY
    
    ## Critical Headers to Monitor
    
    ### Anthropic OAuth
    - Must have ALL x-stainless-* headers
    - Must have anthropic-dangerous-direct-browser-access
    - Must have exact anthropic-beta value with all features
    - Must have exact user-agent with claude-cli version
    
    ### OpenAI OAuth
    - Must have Bearer token in authorization
    - Must have organization headers if configured
    - Must have project headers if configured
    
    ### Gemini OAuth
    - Must have x-goog-api-client header
    - Must have Bearer token in authorization
    
    ## How to Compare
    ```bash
    # After refactoring, run:
    ./scripts/capture_oauth_api_calls.exs
    
    # Then compare:
    diff -r oauth_api_captures/ oauth_api_captures_after_refactor/
    ```
    
    ANY differences indicate a breaking change that MUST be reverted.
    """
    
    File.write!("#{@capture_dir}/SUMMARY.md", summary)
    IO.puts("\n📄 Summary written to #{@capture_dir}/SUMMARY.md")
  end
end

# Run the capture
OAuthAPICapture.run()