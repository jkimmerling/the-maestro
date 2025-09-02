#!/usr/bin/env elixir
# Validate provider switching and session isolation within one app instance

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.Provider

defmodule SwitchTest do
  def ensure_api_session(provider, env_key, session, opts \\ []) do
    case System.get_env(env_key) do
      nil -> {:skip, {:missing_env, env_key}}
      "" -> {:skip, {:missing_env, env_key}}
      key ->
        {:ok, _} =
          Provider.create_session(provider, :api_key,
            name: session,
            credentials: %{api_key: key}
          )

        {:ok, session, opts}
    end
  end

  def run do
    # Sessions and models
    openai_oauth = System.get_env("OPENAI_OAUTH_SESSION") || "switch_openai_oauth"
    openai_api = System.get_env("OPENAI_API_SESSION") || "switch_openai_api"
    anthropic_oauth = System.get_env("ANTHROPIC_OAUTH_SESSION") || "switch_anthropic_oauth"
    gemini_oauth = System.get_env("GEMINI_OAUTH_SESSION") || "switch_gemini_oauth"

    openai_model = System.get_env("OPENAI_MODEL") || "gpt-4o"
    anthropic_model = System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"
    gemini_model = System.get_env("GEMINI_MODEL") || "gemini-2.0-flash-exp"

    # Require that OAuth sessions were previously created for each provider
    missing =
      [
        {:openai, openai_oauth},
        {:anthropic, anthropic_oauth},
        {:gemini, gemini_oauth}
      ]
      |> Enum.filter(fn {prov, sess} ->
        case Provider.stream_chat(prov, sess, [%{"role" => "user", "content" => "ping"}], model: "noop") do
          {:error, :session_not_found} -> true
          _ -> false
        end
      end)

    if missing != [] do
      IO.puts("⚠️  Missing OAuth sessions for: #{inspect(missing)} — create them with the full E2E scripts first.")
    end

    # Ensure API-key session for OpenAI if key present
    _ = ensure_api_session(:openai, "OPENAI_API_KEY", openai_api)

    # Switch scenarios
    test_message = %{"role" => "user", "content" => "Say hello briefly."}

    scenarios = [
      {:openai_oauth, :openai, openai_oauth, openai_model},
      {:openai_api, :openai, openai_api, openai_model},
      {:anthropic_oauth, :anthropic, anthropic_oauth, anthropic_model},
      {:gemini_oauth, :gemini, gemini_oauth, gemini_model}
    ]

    results =
      Enum.map(scenarios, fn {tag, prov, sess, model} ->
        case Provider.stream_chat(prov, sess, [test_message], model: model, timeout: 30_000) do
          {:ok, stream} ->
            len =
              stream
              |> TheMaestro.Streaming.parse_stream(prov)
              |> Enum.reduce(0, fn msg, acc ->
                case msg.type do
                  :content -> acc + String.length(msg.content || "")
                  _ -> acc
                end
              end)

            {tag, :ok, len}

          other -> {tag, other}
        end
      end)

    IO.inspect(results, label: "provider_switching_results")
    :ok
  end
end

SwitchTest.run()

