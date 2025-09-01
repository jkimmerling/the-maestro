#!/usr/bin/env elixir
# Full OAuth → streaming E2E for Anthropic (manual code entry)

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Auth
alias TheMaestro.Provider

session = System.get_env("ANTHROPIC_OAUTH_SESSION") || "oauth_test_anthropic"
model = System.get_env("ANTHROPIC_MODEL") || "claude-3-haiku-20240307"

IO.puts("Generating Anthropic OAuth URL (PKCE)...")
{:ok, {auth_url, pkce}} = Auth.generate_oauth_url()
IO.puts("Open this URL and complete auth:")
IO.puts(auth_url)

auth_code =
  System.get_env("ANTHROPIC_AUTH_CODE") ||
    IO.gets("\nPaste the authorization code here: ") |> to_string() |> String.trim()

IO.puts("\nExchanging code for tokens and saving session '#{session}'...")
{:ok, _token} = Auth.finish_anthropic_oauth(auth_code, pkce, session)

messages1 = [%{"role" => "user", "content" => "What is the capital of France?"}]
{:ok, stream1} = Provider.stream_chat(:anthropic, session, messages1, model: model)

acc1 =
  stream1
  |> TheMaestro.Streaming.parse_stream(:anthropic)
  |> Enum.reduce(%{content: ""}, fn msg, a ->
    case msg.type do
      :content -> IO.write(msg.content); %{a | content: a.content <> (msg.content || "")}
      _ -> a
    end
  end)

if String.match?(String.downcase(acc1.content), ~r/\bparis\b/) do
  IO.puts("\n✅ Verified answer contains 'Paris'")
else
  IO.puts("\n⚠️ Paris check did not match")
end

IO.puts("\n=== Prompt 2: FastAPI + Stripe (wait up to 5 min) ===\n")
task =
  Task.async(fn ->
    Provider.stream_chat(:anthropic, session, [
      %{"role" => "user", "content" => "How would you write a FastAPI application that handles Stripe-based subscriptions?"}
    ], model: model)
  end)

case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, {:ok, stream2}} ->
    stream2
    |> TheMaestro.Streaming.parse_stream(:anthropic)
    |> Enum.each(fn msg -> if msg.type == :content, do: IO.write(msg.content) end)
    IO.puts("\n✅ Completed second prompt (or finished early)")

  {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}")
  nil -> IO.puts("\n⏱️  Timed out after 5 minutes; ending test run")
end

