#!/usr/bin/env elixir
# Minimal E2E streaming test for OpenAI Responses API via API key session

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

session = System.get_env("OPENAI_API_SESSION") || "enterprise_test"
api_key = System.get_env("OPENAI_API_KEY") || System.get_env("OPENAI_KEY")
model = System.get_env("OPENAI_MODEL") || "gpt-4o"

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

defmodule E2E do
  def stream_and_collect(provider, session, messages, opts \\ []) do
    case Provider.stream_chat(provider, session, messages, opts) do
      {:ok, stream} ->
        acc =
          stream
          |> TheMaestro.Streaming.parse_stream(provider)
          |> Enum.reduce(%{content: "", done: false}, fn msg, a ->
            case msg.type do
              :content -> IO.write(msg.content); %{a | content: a.content <> (msg.content || "")}
              :done -> IO.puts("\n✅ Done"); %{a | done: true}
              _ -> a
            end
          end)

        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

IO.puts("\n=== Prompt 1: Capital of France ===\n")
{:ok, acc1} =
  E2E.stream_and_collect(:openai, session, [%{"role" => "user", "content" => "What is the capital of France?"}],
    model: model
  )

if String.match?(String.downcase(acc1.content), ~r/\bparis\b/) do
  IO.puts("\n✅ Verified answer contains 'Paris'\n")
else
  IO.puts("\n⚠️ Did not detect 'Paris' explicitly in the output\n")
end

IO.puts("\n=== Prompt 2: FastAPI + Stripe (wait up to 5 min) ===\n")
task =
  Task.async(fn ->
    E2E.stream_and_collect(:openai, session, [
      %{"role" => "user", "content" => "How would you write a FastAPI application that handles Stripe-based subscriptions?"}
    ], model: model)
  end)

case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, {:ok, _acc2}} -> IO.puts("\n✅ Completed second prompt (or finished early)\n")
  {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}\n")
  nil -> IO.puts("\n⏱️  Timed out waiting 5 minutes; ending test run\n")
end
