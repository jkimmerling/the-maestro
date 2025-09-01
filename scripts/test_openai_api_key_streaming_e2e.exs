#!/usr/bin/env elixir
# Minimal E2E streaming test for OpenAI Responses API via API key session

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

session = System.get_env("OPENAI_API_SESSION") || "enterprise_test"
api_key = System.get_env("OPENAI_API_KEY") || System.get_env("OPENAI_KEY")

if is_nil(api_key) or api_key == "" do
  IO.puts("❌ Set OPENAI_API_KEY before running this script.")
  System.halt(1)
end

# Create/update named session
{:ok, _} =
  Provider.create_session(:openai, :api_key,
    name: session,
    credentials: %{"api_key" => api_key}
  )

messages = [%{"role" => "user", "content" => "Say hello and then stop."}]

case Provider.stream_chat(:openai, session, messages, model: System.get_env("OPENAI_MODEL") || "gpt-4o") do
  {:ok, stream} ->
    stream
    |> TheMaestro.Streaming.parse_stream(:openai)
    |> Enum.each(fn msg -> IO.inspect(msg, label: "stream msg") end)
    IO.puts("✅ Streaming finished")

  {:error, reason} ->
    IO.puts("❌ Streaming error: #{inspect(reason)}")
end

