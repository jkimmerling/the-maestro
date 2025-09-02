#!/usr/bin/env elixir
# Validate that universal streaming interface yields content across providers

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

msg = %{"role" => "user", "content" => "Explain what idempotency means in APIs, in one sentence."}

providers = [
  {:openai, System.get_env("OPENAI_OAUTH_SESSION") || "oauth_test_openai", System.get_env("OPENAI_MODEL") || "gpt-4o"},
  {:anthropic, System.get_env("ANTHROPIC_OAUTH_SESSION") || "oauth_test_anthropic", System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"},
  {:gemini, System.get_env("GEMINI_OAUTH_SESSION") || "oauth_test_gemini", System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"}
]

results =
  Enum.map(providers, fn {prov, sess, model} ->
    case Provider.stream_chat(prov, sess, [msg], model: model, timeout: 30_000) do
      {:ok, stream} ->
        content =
          stream
          |> TheMaestro.Streaming.parse_stream(prov)
          |> Enum.reduce("", fn msg, acc -> if msg.type == :content, do: acc <> (msg.content || ""), else: acc end)

        {prov, :ok, String.length(String.trim(content))}

      {:error, reason} ->
        {prov, :error, reason}
    end
  end)

IO.inspect(results, label: "streaming_consistency_results")

