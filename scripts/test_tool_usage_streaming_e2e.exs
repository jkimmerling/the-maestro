#!/usr/bin/env elixir
# E2E: exercise function tools (shell and apply_patch) via OpenAI Responses API

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

session =
  System.get_env("OPENAI_OAUTH_SESSION") ||
    System.get_env("OPENAI_API_SESSION") ||
    "tool_e2e_session"

model = System.get_env("OPENAI_MODEL") || "gpt-4o"

defmodule Util do
  def stream_and_collect(provider, session, messages, opts \\ []) do
    case Provider.stream_chat(provider, session, messages, opts) do
      {:ok, stream} ->
        acc =
          stream
          |> TheMaestro.Streaming.parse_stream(:openai, log_unknown_events: true)
          |> Enum.reduce(%{content: "", tools: [], done: false}, fn msg, a ->
            case msg.type do
              :function_call ->
                IO.puts("tool_call: " <> inspect(msg.function_call))
                %{a | tools: a.tools ++ (msg.function_call || [])}

              :content ->
                IO.write(msg.content || "")
                %{a | content: a.content <> (msg.content || "")}

              :done ->
                IO.puts("\n(done)")
                %{a | done: true}

              _ -> a
            end
          end)

        {:ok, acc}

      {:error, reason} -> {:error, reason}
    end
  end
end

IO.puts("\n=== Tool E2E: shell (ls -la) ===\n")
{:ok, _acc1} =
  Util.stream_and_collect(:openai, session, [
    %{"role" => "user", "content" => "Use the shell tool to run ['bash','-lc','ls -la'] and then answer 'done'."}
  ], model: model)

IO.puts("\n=== Tool E2E: apply_patch (add file) ===\n")
patch = """
*** Begin Patch
*** Add File: tmp/tool_e2e.txt
+hello from apply_patch
*** End Patch
"""

prompt = "Use the apply_patch tool (function form) with arguments {\"input\":<patch>} to add tmp/tool_e2e.txt with one line. Patch follows:\n\n" <> patch

{:ok, _acc2} =
  Util.stream_and_collect(:openai, session, [
    %{"role" => "user", "content" => prompt}
  ], model: model)

IO.puts("\n✅ Tool E2E finished\n")

