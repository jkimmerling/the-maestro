#!/usr/bin/env elixir
# OAuth streaming E2E for Anthropic using an existing named session

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

session = System.get_env("ANTHROPIC_OAUTH_SESSION") || "oauth_test_anthropic"
model = System.get_env("ANTHROPIC_MODEL") || "claude-3-haiku-20240307"

defmodule AnthropicOAuthE2E do
  def stream_and_collect(session, messages, opts \\ []) do
    case Provider.stream_chat(:anthropic, session, messages, Keyword.merge([model: opts[:model]], opts)) do
      {:ok, stream} ->
        acc =
          stream
          |> TheMaestro.Streaming.parse_stream(:anthropic)
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

IO.puts("\n=== Prompt 1: Capital of France (Anthropic OAuth) ===\n")
{:ok, acc1} = AnthropicOAuthE2E.stream_and_collect(session, [%{"role" => "user", "content" => "What is the capital of France?"}], model: model)

paris_ok? = String.match?(String.downcase(acc1.content), ~r/\bparis\b/)
IO.puts(if paris_ok?, do: "\n✅ Verified answer contains 'Paris'\n", else: "\n❌ Paris check failed\n")

IO.puts("\n=== Prompt 2: FastAPI + Stripe (wait up to 5 min) ===\n")
task =
  Task.async(fn ->
    AnthropicOAuthE2E.stream_and_collect(session, [%{"role" => "user", "content" => "How would you write a FastAPI application that handles Stripe-based subscriptions?"}], model: model)
  end)

acc2 =
  case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
    {:ok, {:ok, acc}} -> acc
    {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}"); %{content: ""}
    nil -> IO.puts("\n⏱️  Timed out after 5 minutes; ending test run"); %{content: ""}
  end

second_ok? = String.length(acc2.content) >= 120
IO.puts(if second_ok?, do: "\n✅ Completed second prompt\n", else: "\n❌ Second prompt produced insufficient content\n")

if !(paris_ok? and second_ok?) do
  System.halt(2)
end

