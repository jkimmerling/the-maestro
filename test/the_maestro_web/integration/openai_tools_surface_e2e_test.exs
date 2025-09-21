defmodule TheMaestroWeb.Integration.OpenAIToolsSurfaceE2ETest do
  use TheMaestroWeb.ConnCase, async: true

  import Ecto.Query
  alias TheMaestro.Auth
  alias TheMaestro.Conversations

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-tools-surface",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "OpenAI Tools Surface",
        auth_id: saved_auth.id,
        working_dir: File.cwd!(),
        tools: %{"allowed" => %{"openai" => []}}
      })

    {:ok, %{session: session}}
  end

  defmodule CaptureAdapter do
    @behaviour TheMaestro.Providers.Http.StreamingAdapter

    @impl true
    def stream_request(_req, opts) do
      json = Keyword.get(opts, :json, %{})
      meta = %{
        tools_count: (json["tools"] || []) |> length(),
        tools_names: Enum.map(json["tools"] || [], & &1["name"]) |> Enum.sort()
      }

      send(self(), {:captured_openai_payload, meta})
      {:ok, Stream.iterate(0, & &1) |> Stream.take(0)}
    end
  end

  test "allowlist gates and surfaces update_plan, web_search, view_image", %{session: session} do
    # 1) Disallow all
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session.id), %{
        tools: %{"allowed" => %{"openai" => []}}
      })

    {:ok, _} =
      TheMaestro.Providers.OpenAI.Streaming.stream_chat(
        "openai-tools-surface",
        [%{"role" => "user", "content" => "hello"}],
        streaming_adapter: __MODULE__.CaptureAdapter
      )

    assert_receive {:captured_openai_payload, %{tools_count: 0}}, 2_000

    # 2) Allow each individually
    for name <- ["web_search", "update_plan", "view_image"] do
      {:ok, _} =
        Conversations.update_session(Conversations.get_session!(session.id), %{
          tools: %{"allowed" => %{"openai" => [name]}}
        })

      {:ok, _} =
        TheMaestro.Providers.OpenAI.Streaming.stream_chat(
          "openai-tools-surface",
          [%{"role" => "user", "content" => "ping"}],
          streaming_adapter: __MODULE__.CaptureAdapter
        )

      assert_receive {:captured_openai_payload,
                      %{tools_count: 1, tools_names: names}} when names == [name], 2_000
    end

    # 3) Allow all three together
    {:ok, _} =
      Conversations.update_session(Conversations.get_session!(session.id), %{
        tools: %{"allowed" => %{"openai" => ["web_search", "update_plan", "view_image"]}}
      })

    {:ok, _} =
      TheMaestro.Providers.OpenAI.Streaming.stream_chat(
        "openai-tools-surface",
        [%{"role" => "user", "content" => "list tools"}],
        streaming_adapter: __MODULE__.CaptureAdapter
      )

    assert_receive {:captured_openai_payload,
                    %{tools_count: 3, tools_names: ["update_plan", "view_image", "web_search"]}}, 2_000
  end
end
