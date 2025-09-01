#!/usr/bin/env elixir
# Minimal E2E streaming test for Anthropic Messages API via API key session

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider
alias TheMaestro.SavedAuthentication

session = System.get_env("ANTHROPIC_API_SESSION") || "enterprise_test_anthropic"
api_key = System.get_env("ANTHROPIC_API_KEY")

if is_nil(api_key) or api_key == "" do
  IO.puts("ANTHROPIC_API_KEY missing; export it and rerun")
  System.halt(1)
end

# Ensure named session exists/updated
{:ok, _} =
  case SavedAuthentication.get_by_provider_and_name(:anthropic, :api_key, session) do
    %SavedAuthentication{} ->
      SavedAuthentication.upsert_named_session(:anthropic, :api_key, session, %{
        credentials: %{api_key: api_key}
      })

    _ ->
      Provider.create_session(:anthropic, :api_key, name: session, credentials: %{"api_key" => api_key})
  end

model = System.get_env("ANTHROPIC_MODEL") || "claude-3-haiku-20240307"

defmodule E2EAnthropic do
  def stream_and_collect(provider, session, messages, opts \\ []) do
    debug = System.get_env("DEBUG") in ["1", "true", "TRUE"]
    case Provider.stream_chat(provider, session, messages, Keyword.merge([model: opts[:model]], opts)) do
      {:ok, stream} ->
        acc =
          stream
          |> TheMaestro.Streaming.parse_stream(:anthropic)
          |> Enum.reduce(%{content: "", done: false}, fn msg, a ->
            if debug, do: IO.inspect(msg, label: "stream msg")
            case msg.type do
              :content -> IO.write(msg.content); %{a | content: a.content <> (msg.content || "")}
              :done -> IO.puts("\n✅ Done"); %{a | done: true}
              _ -> a
            end
          end)

        {:ok, acc}

      {:error, reason} -> {:error, reason}
    end
  end
end

IO.puts("\n=== Prompt 1: Capital of France (Anthropic) ===\n")
{:ok, acc1} =
  E2EAnthropic.stream_and_collect(:anthropic, session, [
    %{"role" => "user", "content" => "What is the capital of France?"}
  ], model: model)

if String.match?(String.downcase(acc1.content), ~r/\bparis\b/) do
  IO.puts("\n✅ Verified answer contains 'Paris'\n")
else
  IO.puts("\n⚠️ Did not detect 'Paris' explicitly in the output\n")
end

IO.puts("\n=== Prompt 2: FastAPI + Stripe (wait up to 5 min) ===\n")
task =
  Task.async(fn ->
    E2EAnthropic.stream_and_collect(:anthropic, session, [
      %{"role" => "user", "content" => "How would you write a FastAPI application that handles Stripe-based subscriptions?"}
    ], model: model)
  end)

case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, {:ok, _acc2}} -> IO.puts("\n✅ Completed second prompt (or finished early)")
  {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}")
  nil -> IO.puts("\n⏱️  Timed out after 5 minutes; ending test run")
end

