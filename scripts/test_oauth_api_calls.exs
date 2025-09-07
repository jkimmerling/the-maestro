#!/usr/bin/env elixir

# Test and capture OAuth API calls for all providers
# This creates a baseline that MUST NOT change after refactoring

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)
Application.ensure_all_started(:telemetry)
Application.ensure_all_started(:the_maestro)

defmodule OAuthAPITester do
  @moduledoc """
  Tests and captures the EXACT OAuth API calls for each provider.
  Any deviation from these captures after refactoring is a CRITICAL BUG.
  """
  
  require Logger
  alias TheMaestro.AgentLoop
  
  @capture_dir "oauth_api_captures"
  @test_prompt "list the files in your current directory"
  
  def run do
    setup_capture_dir()
    setup_telemetry_hooks()
    
    IO.puts("\n🔍 TESTING AND CAPTURING OAUTH API CALLS")
    IO.puts("=" <> String.duplicate("=", 70))
    
    # Test each provider with their OAuth sessions
    providers = [
      {:anthropic, "personal_oauth_claude", "claude-3-5-sonnet-20241022"},
      {:openai, "personal_oauth_openai", "gpt-4o"},
      {:gemini, "personal_oauth_gemini", "gemini-2.0-flash-exp"}
    ]
    
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    
    for {provider, session, model} <- providers do
      IO.puts("\n📦 Testing #{provider} OAuth...")
      test_provider(provider, session, model, timestamp)
    end
    
    IO.puts("\n✅ Complete! Check #{@capture_dir}/ for results")
    generate_summary(timestamp)
  end
  
  defp setup_capture_dir do
    File.mkdir_p!(@capture_dir)
    File.mkdir_p!("#{@capture_dir}/requests")
    File.mkdir_p!("#{@capture_dir}/responses")
  end
  
  defp setup_telemetry_hooks do
    # Capture HTTP requests via telemetry
    :telemetry.attach_many(
      "oauth-capture",
      [
        [:finch, :request, :start],
        [:finch, :request, :stop],
        [:finch, :request, :exception]
      ],
      &handle_telemetry_event/4,
      nil
    )
  end
  
  defp handle_telemetry_event([:finch, :request, :start], _measurements, metadata, _config) do
    if metadata[:name] in [:anthropic_finch, :openai_finch, :gemini_finch] do
      request_data = %{
        pool: metadata[:name],
        method: metadata[:method],
        host: metadata[:host],
        port: metadata[:port],
        path: metadata[:path],
        headers: metadata[:headers],
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      
      # Store in process dictionary for later
      Process.put({:current_request, metadata[:name]}, request_data)
      
      IO.puts("  📸 Capturing #{metadata[:name]} request to #{metadata[:host]}#{metadata[:path]}")
    end
  end
  
  defp handle_telemetry_event([:finch, :request, :stop], measurements, metadata, _config) do
    if metadata[:name] in [:anthropic_finch, :openai_finch, :gemini_finch] do
      request_data = Process.get({:current_request, metadata[:name]})
      
      if request_data do
        # Add response info
        response_data = Map.merge(request_data, %{
          status: metadata[:status],
          response_time_ms: measurements[:duration] / 1_000_000,
          response_headers: metadata[:headers]
        })
        
        # Save to file
        provider = finch_to_provider(metadata[:name])
        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        file = "#{@capture_dir}/requests/#{provider}_#{timestamp}_#{:rand.uniform(1000)}.json"
        File.write!(file, Jason.encode!(response_data, pretty: true))
        
        Process.delete({:current_request, metadata[:name]})
      end
    end
  end
  
  defp handle_telemetry_event([:finch, :request, :exception], _measurements, metadata, _config) do
    if metadata[:name] in [:anthropic_finch, :openai_finch, :gemini_finch] do
      IO.puts("  ❌ Request failed: #{inspect(metadata[:kind])}")
      Process.delete({:current_request, metadata[:name]})
    end
  end
  
  defp finch_to_provider(:anthropic_finch), do: "anthropic"
  defp finch_to_provider(:openai_finch), do: "openai"
  defp finch_to_provider(:gemini_finch), do: "gemini"
  
  defp test_provider(provider, session, model, timestamp) do
    messages = [%{"role" => "user", "content" => @test_prompt}]
    
    IO.puts("  Session: #{session}")
    IO.puts("  Model: #{model}")
    IO.puts("  Running API call...")
    
    start_time = System.monotonic_time(:millisecond)
    
    result = case AgentLoop.run_turn(provider, session, model, messages) do
      {:ok, res} ->
        %{
          success: true,
          provider: provider,
          session: session,
          model: model,
          response: %{
            tools: res.tools,
            final_text: res.final_text,
            usage: res.usage
          },
          duration_ms: System.monotonic_time(:millisecond) - start_time
        }
        
      {:error, reason} ->
        %{
          success: false,
          provider: provider,
          session: session,
          model: model,
          error: inspect(reason),
          duration_ms: System.monotonic_time(:millisecond) - start_time
        }
    end
    
    # Save result
    result_file = "#{@capture_dir}/responses/#{provider}_result_#{timestamp}.json"
    File.write!(result_file, Jason.encode!(result, pretty: true))
    
    if result.success do
      IO.puts("  ✅ Success - Response received in #{result.duration_ms}ms")
    else
      IO.puts("  ❌ Failed: #{result.error}")
    end
  end
  
  defp generate_summary(timestamp) do
    # Read all captured requests
    request_files = Path.wildcard("#{@capture_dir}/requests/*.json")
    
    providers_summary = %{
      anthropic: [],
      openai: [],
      gemini: []
    }
    
    for file <- request_files do
      case File.read!(file) |> Jason.decode!() do
        %{"pool" => pool, "headers" => headers, "path" => path, "method" => method} = data ->
          provider = finch_to_provider(String.to_atom(pool))
          
          summary = %{
            method: method,
            path: path,
            headers: Enum.map(headers, fn {k, v} -> 
              # Mask sensitive values but keep structure
              value = if k in ["authorization", "x-api-key", "x-goog-api-key"] do
                "#{String.slice(v, 0, 20)}..."
              else
                v
              end
              "#{k}: #{value}"
            end),
            timestamp: data["timestamp"]
          }
          
          current = Map.get(providers_summary, String.to_atom(provider), [])
          providers_summary = Map.put(providers_summary, String.to_atom(provider), [summary | current])
      end
    end
    
    # Write summary
    summary_content = """
    # OAuth API Call Capture Summary
    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Capture ID: #{timestamp}
    
    ## CRITICAL REQUIREMENTS
    
    After ANY refactoring, these EXACT API calls must remain UNCHANGED:
    - All headers must be present (order may vary)
    - All header values must be identical
    - All endpoints must be the same
    - Request structure must be identical
    
    ## Captured API Calls
    
    ### Anthropic OAuth
    #{format_provider_summary(providers_summary.anthropic)}
    
    REQUIRED HEADERS:
    - All x-stainless-* headers MUST be present
    - anthropic-dangerous-direct-browser-access MUST be "true"
    - anthropic-beta MUST include all features
    - user-agent MUST contain "claude-cli"
    - authorization MUST be "Bearer sk-ant-oat..."
    
    ### OpenAI OAuth  
    #{format_provider_summary(providers_summary.openai)}
    
    REQUIRED HEADERS:
    - authorization MUST be "Bearer eyJ..."
    - openai-organization MAY be present if configured
    - user-agent MUST be "llxprt/1.0"
    
    ### Gemini OAuth
    #{format_provider_summary(providers_summary.gemini)}
    
    REQUIRED HEADERS:
    - authorization MUST be "Bearer ya29..."
    - x-goog-api-client MUST be present
    
    ## Validation Steps
    
    1. After refactoring, run this script again
    2. Compare the captured headers character by character
    3. Any missing or changed header is a BREAKING CHANGE
    4. Any changed endpoint is a BREAKING CHANGE
    
    ## Files Generated
    - requests/: Individual API request captures
    - responses/: API responses and results
    
    Run `diff -r oauth_api_captures/ oauth_api_captures_after/` to validate
    """
    
    File.write!("#{@capture_dir}/SUMMARY_#{timestamp}.md", summary_content)
    IO.puts("\n📄 Summary written to #{@capture_dir}/SUMMARY_#{timestamp}.md")
  end
  
  defp format_provider_summary(calls) do
    calls
    |> Enum.reverse()
    |> Enum.map(fn call ->
      """
      **#{call.method} #{call.path}**
      Headers:
      #{Enum.map(call.headers, fn h -> "  - #{h}" end) |> Enum.join("\n")}
      """
    end)
    |> Enum.join("\n")
  end
end

# Clean up any existing telemetry handlers
:telemetry.list_handlers([:finch, :request, :start])
|> Enum.each(fn handler -> :telemetry.detach(handler.id) end)

# Run the test
OAuthAPITester.run()