defmodule TheMaestroWeb.Integration.OpenAIDefaultToolsTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Providers.OpenAI.Streaming, as: OpenAIStreaming

  defmodule CaptureAdapter do
    def stream_request(_req, opts) do
      json = Keyword.get(opts, :json, %{})
      names = Enum.map(json["tools"] || [], & &1["name"]) |> Enum.sort()
      send(self(), {:captured_openai_tools, names})
      {:ok, Stream.iterate(0, & &1) |> Stream.take(0)}
    end
  end

  test "openai default built-in tools are included by default" do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-default",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, _session} =
      Conversations.create_session(%{
        name: "OpenAI Default Tools",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, _} =
      OpenAIStreaming.stream_chat(
        "openai-default",
        [%{"role" => "user", "content" => "hello"}],
        streaming_adapter: __MODULE__.CaptureAdapter
      )

    assert_receive {:captured_openai_tools, names}, 1_000

    for required <- ["shell", "apply_patch", "web_search", "update_plan", "view_image"] do
      assert required in names
    end
  end
end
