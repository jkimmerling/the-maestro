#!/usr/bin/env elixir
# Generic dual-prompt E2E streaming test for any provider/session

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

[provider_s, session | _rest] =
  case System.argv() do
    [p, s | _] -> [p, s]
    [p] -> [p, System.get_env("SESSION") || raise "Pass session name as 2nd arg or SESSION env"]
    _ ->
      IO.puts("Usage: mix run scripts/e2e_dual_prompt_stream_test.exs <provider> <session> [model]")
      System.halt(1)
  end

provider = String.to_atom(provider_s)
model = System.get_env("MODEL") || Enum.at(System.argv(), 2) || default_model(provider)

defp default_model(:openai), do: System.get_env("OPENAI_MODEL") || "gpt-4o"
defp default_model(:anthropic), do: System.get_env("ANTHROPIC_MODEL") || "claude-3-haiku-20240307"
defp default_model(:gemini), do: System.get_env("GEMINI_MODEL") || "gemini-1.5-flash"
defp default_model(_), do: "gpt-4o"

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

      {:error, reason} -> {:error, reason}
    end
  end
end

IO.puts("\n=== Prompt 1: Capital of France ===\n")
{:ok, acc1} =
  E2E.stream_and_collect(provider, session, [%{"role" => "user", "content" => "What is the capital of France?"}],
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
    E2E.stream_and_collect(provider, session, [
      %{"role" => "user", "content" => "How would you write a FastAPI application that handles Stripe-based subscriptions?"}
    ], model: model)
  end)

case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, {:ok, _acc2}} -> IO.puts("\n✅ Completed second prompt (or finished early)")
  {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}")
  nil -> IO.puts("\n⏱️  Timed out after 5 minutes; ending test run")
end

