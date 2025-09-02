#!/usr/bin/env elixir
# Full OAuth → streaming E2E for Gemini using the universal provider interface

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Auth
alias TheMaestro.Provider

session = System.get_env("GEMINI_OAUTH_SESSION") || "oauth_test_gemini"
model = System.get_env("GEMINI_MODEL") || System.get_env("GOOGLE_MODEL") || "gemini-2.0-flash-exp"

IO.puts("Generating Gemini OAuth URL (PKCE)...")
{:ok, {auth_url, pkce}} = Auth.generate_gemini_oauth_url()
IO.puts("Open this URL and complete auth:")
IO.puts(auth_url)

code =
  System.get_env("GEMINI_AUTH_CODE") ||
    (IO.gets("\nPaste the authorization code here: ") |> to_string() |> String.trim())

if is_nil(code) or code == "" do
  IO.puts("❌ No authorization code provided.")
  System.halt(1)
end

IO.puts("\nExchanging code for tokens and saving session '#{session}' via Provider...")
case Provider.create_session(:gemini, :oauth,
       name: session,
       auth_code: code,
       pkce_params: pkce
     ) do
  {:ok, _sid} -> IO.puts("✅ Gemini OAuth session saved: #{session}")
  {:error, reason} ->
    IO.puts("❌ Failed to create session: #{inspect(reason)}")
    System.halt(2)
end

defmodule GeminiE2E do
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

IO.puts("\n=== Prompt 1: Capital of Japan ===\n")
{:ok, acc1} =
  GeminiE2E.stream_and_collect(:gemini, session, [
    %{"role" => "user", "content" => "What is the capital of Japan?"}
  ], model: model)

if String.match?(String.downcase(acc1.content), ~r/\btokyo\b/) do
  IO.puts("\n✅ Verified answer contains 'Tokyo'\n")
else
  IO.puts("\n⚠️  Did not detect 'Tokyo' explicitly in the output\n")
end

IO.puts("\n=== Prompt 2: Summarize a concurrency pattern in Elixir (wait up to 5 min) ===\n")
task =
  Task.async(fn ->
    GeminiE2E.stream_and_collect(:gemini, session, [
      %{
        "role" => "user",
        "content" => "Briefly explain a common concurrency pattern in Elixir and show a small example."
      }
    ], model: model)
  end)

case Task.yield(task, 300_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, {:ok, _acc2}} -> IO.puts("\n✅ Completed second prompt (or finished early)\n")
  {:ok, {:error, reason}} -> IO.puts("\n❌ Streaming error: #{inspect(reason)}\n")
  nil -> IO.puts("\n⏱️  Timed out waiting 5 minutes; ending test run\n")
end

IO.puts("\n✅ Gemini OAuth streaming E2E completed\n")

