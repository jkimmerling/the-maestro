defmodule Golden.CompareGoldenFixturesTest do
  use ExUnit.Case

  alias TheMaestro.{Auth, Conversations}

  @moduletag :golden

  @providers [:openai, :anthropic, :gemini]
  @names %{
    openai: System.get_env("OPENAI_SESSION_NAME") || "personal_oauth_openai",
    anthropic: System.get_env("ANTHROPIC_SESSION_NAME") || "personal_oauth_claude",
    gemini: System.get_env("GEMINI_SESSION_NAME") || "personal_oauth_gemini"
  }

  @dynamic_headers ~w(session_id chatgpt-account-id x-request-id request-id date cf-ray cf-visitor)
  @dynamic_body ~w(prompt_cache_key)

  @run_strict (System.get_env("RUN_GOLDEN_STRICT") in ["1", "true", "TRUE"])

  test "compare current request build with golden fixtures" do
    if @run_strict do
      for provider <- @providers do
        name = Map.fetch!(@names, provider)

      sa =
        Auth.get_by_provider_and_name(provider, :oauth, name) ||
          Auth.get_by_provider_and_name(provider, :api_key, name)

      if sa do
        session_id = ensure_session(sa.id, provider)

        path =
          Path.join([
            File.cwd!(),
            "priv",
            "golden",
            Atom.to_string(provider),
            "request_fixtures.json"
          ])

        if File.exists?(path) do
          {:ok, bin} = File.read(path)
          {:ok, fixtures} = Jason.decode(bin)

          # Only compare the first request of the first two turns
          wanted = fixtures |> Enum.take(2)

          current = build_current_requests(provider, session_id)
          current = Enum.take(current, length(wanted))

          Enum.zip(wanted, current)
          |> Enum.each(fn {exp, got} ->
            assert normalize(exp["headers"], @dynamic_headers) ==
                     normalize(got.headers, @dynamic_headers),
                   "headers mismatch for #{provider}"

            assert normalize(exp["body"], @dynamic_body) == normalize(got.body, @dynamic_body),
                   "body mismatch for #{provider}"
          end)
      end
    else
      IO.puts("\n⏭️  Skipping golden strict compare — set RUN_GOLDEN_STRICT=1 to enable")
      assert true
    end
  end
    end
  end

  defp ensure_session(auth_id, provider) do
    case Conversations.latest_session_for_auth_id(auth_id) do
      nil ->
        {:ok, s} =
          Conversations.create_session(%{
            auth_id: auth_id,
            model_id: default_model(provider),
            working_dir: File.cwd!()
          })

        s.id

      s ->
        s.id
    end
  end

  defp build_current_requests(:openai, session_id) do
    adapter = TheMaestro.Providers.Http.TestCaptureAdapter
    msgs1 = [%{role: "user", content: "hello"}]
    msgs2 = [%{role: "user", content: "please list the files in your current directory"}]

    _ =
      TheMaestro.Providers.OpenAI.Streaming.stream_chat(session_id, msgs1,
        streaming_adapter: adapter
      )

    req1 = receive_captured!()

    _ =
      TheMaestro.Providers.OpenAI.Streaming.stream_chat(session_id, msgs2,
        streaming_adapter: adapter
      )

    req2 = receive_captured!()
    [req1, req2]
  end

  defp build_current_requests(:anthropic, session_id) do
    adapter = TheMaestro.Providers.Http.TestCaptureAdapter
    msgs1 = [%{role: "user", content: "hello"}]
    msgs2 = [%{role: "user", content: "please list the files in your current directory"}]

    _ =
      TheMaestro.Providers.Anthropic.Streaming.stream_chat(session_id, msgs1,
        streaming_adapter: adapter
      )

    req1 = receive_captured!()

    _ =
      TheMaestro.Providers.Anthropic.Streaming.stream_chat(session_id, msgs2,
        streaming_adapter: adapter
      )

    req2 = receive_captured!()
    [req1, req2]
  end

  defp build_current_requests(:gemini, session_id) do
    adapter = TheMaestro.Providers.Http.TestCaptureAdapter
    msgs1 = [%{role: "user", content: "hello"}]
    msgs2 = [%{role: "user", content: "please list the files in your current directory"}]

    _ =
      TheMaestro.Providers.Gemini.Streaming.stream_chat(session_id, msgs1,
        streaming_adapter: adapter
      )

    req1 = receive_captured!()

    _ =
      TheMaestro.Providers.Gemini.Streaming.stream_chat(session_id, msgs2,
        streaming_adapter: adapter
      )

    req2 = receive_captured!()
    [req1, req2]
  end

  defp receive_captured! do
    receive do
      {:captured_request, req} -> req
    after
      2000 -> flunk("no request captured")
    end
  end

  defp normalize(%{} = map, ignore_keys) do
    map
    |> Enum.reject(fn {k, _} -> to_string(k) in ignore_keys end)
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_value(v, ignore_keys)} end)
    |> Enum.into(%{})
  end

  defp normalize([h | t], ignore), do: [normalize(h, ignore) | normalize(t, ignore)]
  defp normalize([], _), do: []
  defp normalize(v, _), do: v

  defp normalize_value(v, ignore) when is_map(v), do: normalize(v, ignore)
  defp normalize_value(v, ignore) when is_list(v), do: normalize(v, ignore)
  defp normalize_value(v, _), do: v

  defp default_model(:openai), do: "gpt-4o"
  defp default_model(:anthropic), do: "claude-3-5-sonnet-20240620"
  defp default_model(:gemini), do: "gemini-1.5-pro-latest"
end
