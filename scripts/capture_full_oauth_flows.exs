#!/usr/bin/env elixir

# Capture COMPLETE OAuth API flows by running actual agents
# This will show us exactly what gets sent to each provider

defmodule FullOAuthFlowCapture do
  @moduledoc """
  Captures the COMPLETE OAuth API flow for each provider.
  Shows every header, every parameter, every endpoint hit.
  """
  
  require Logger
  
  @test_prompt "list the files in your current directory"
  @capture_dir "oauth_full_flow_baseline"
  
  def run do
    setup()
    
    IO.puts("\n🔍 CAPTURING FULL OAUTH API FLOWS")
    IO.puts("=" <> String.duplicate("=", 70))
    IO.puts("This will run actual API calls and capture EVERYTHING\n")
    
    # Test each provider
    providers = [
      {"ClaudeAgent", "anthropic"},
      {"ChatGPTAgent", "openai"},
      {"GeminiAgent", "gemini"}
    ]
    
    for {agent, provider} <- providers do
      IO.puts("\n📦 Testing #{provider} OAuth with #{agent}...")
      capture_provider_flow(agent, provider)
    end
    
    IO.puts("\n✅ Complete! Check #{@capture_dir}/ for full API flows")
  end
  
  defp setup do
    File.mkdir_p!(@capture_dir)
    
    # Enable maximum debugging
    System.put_env("STREAM_LOG_EVENTS", "1")
    System.put_env("STREAM_LOG_UNKNOWN_EVENTS", "1")
    System.put_env("HTTP_DEBUG", "1")
    System.put_env("DEBUG_STREAM_EVENTS", "1")
  end
  
  defp capture_provider_flow(agent, provider) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    log_file = "#{@capture_dir}/#{provider}_full_flow_#{timestamp}.log"
    
    # Build the command with all debugging enabled
    cmd = """
    STREAM_LOG_EVENTS=1 \
    STREAM_LOG_UNKNOWN_EVENTS=1 \
    HTTP_DEBUG=1 \
    DEBUG_STREAM_EVENTS=1 \
    mix run scripts/e2e_tools_agent_run.exs "#{agent}" "#{@test_prompt}" 2>&1
    """
    
    IO.puts("  Running: #{agent}")
    IO.puts("  Logging to: #{log_file}")
    
    # Capture the complete output
    {output, exit_code} = System.cmd("bash", ["-c", cmd], 
      stderr_to_stdout: true,
      into: []
    )
    
    # Write raw output
    full_output = Enum.join(output, "")
    File.write!(log_file, full_output)
    
    # Parse and extract API calls
    api_calls = extract_api_calls(full_output)
    
    # Save structured API calls
    json_file = "#{@capture_dir}/#{provider}_api_calls_#{timestamp}.json"
    File.write!(json_file, Jason.encode!(api_calls, pretty: true))
    
    # Print summary
    if exit_code == 0 do
      IO.puts("  ✅ Success - #{length(api_calls)} API calls captured")
      IO.puts("  📄 Raw log: #{log_file}")
      IO.puts("  📄 API calls: #{json_file}")
    else
      IO.puts("  ❌ Failed with exit code #{exit_code}")
      IO.puts("  📄 Check log: #{log_file}")
    end
  end
  
  defp extract_api_calls(output) do
    # Parse the output for HTTP requests
    # Look for patterns like:
    # - HTTP request headers
    # - Request URLs
    # - Request bodies
    
    calls = []
    
    # Split into lines for processing
    lines = String.split(output, "\n")
    
    # Track current request being built
    current_request = %{}
    in_request = false
    
    Enum.reduce(lines, {calls, current_request, in_request}, fn line, {acc_calls, curr_req, in_req} ->
      cond do
        # Detect start of HTTP request
        String.contains?(line, "POST /v1/") or String.contains?(line, "GET /v1/") ->
          method_and_path = extract_method_and_path(line)
          new_req = Map.merge(curr_req, method_and_path)
          {acc_calls, new_req, true}
          
        # Detect headers
        in_req and String.contains?(line, ":") and not String.contains?(line, "{") ->
          case extract_header(line) do
            {key, value} ->
              headers = Map.get(curr_req, :headers, %{})
              new_headers = Map.put(headers, key, value)
              {acc_calls, Map.put(curr_req, :headers, new_headers), true}
            _ ->
              {acc_calls, curr_req, in_req}
          end
          
        # Detect JSON body
        in_req and String.starts_with?(String.trim(line), "{") ->
          case Jason.decode(line) do
            {:ok, body} ->
              {acc_calls, Map.put(curr_req, :body, body), true}
            _ ->
              {acc_calls, curr_req, in_req}
          end
          
        # End of request
        in_req and (String.trim(line) == "" or String.contains?(line, "Response")) ->
          if Map.keys(curr_req) != [] do
            new_req = Map.put(curr_req, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
            {[new_req | acc_calls], %{}, false}
          else
            {acc_calls, %{}, false}
          end
          
        true ->
          {acc_calls, curr_req, in_req}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
  
  defp extract_method_and_path(line) do
    cond do
      String.contains?(line, "POST") ->
        path = Regex.run(~r/POST\s+([^\s]+)/, line) |> List.last()
        %{method: "POST", path: path}
        
      String.contains?(line, "GET") ->
        path = Regex.run(~r/GET\s+([^\s]+)/, line) |> List.last()
        %{method: "GET", path: path}
        
      true ->
        %{}
    end
  end
  
  defp extract_header(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        {String.trim(key) |> String.downcase(), String.trim(value)}
      _ ->
        nil
    end
  end
end

# Run the capture
FullOAuthFlowCapture.run()