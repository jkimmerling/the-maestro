defmodule TheMaestroWeb.Integration.AnthropicDefaultToolsTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Providers.Anthropic.Streaming, as: AnthStreaming

  defmodule CaptureAdapter do
    def stream_request(_req, opts) do
      json = Keyword.get(opts, :json, %{})
      names = Enum.map(json["tools"] || [], & &1["name"]) |> Enum.sort()
      send(self(), {:captured_anthropic_tools, names})
      {:ok, Stream.iterate(0, & &1) |> Stream.take(0)}
    end
  end

  test "anthropic default built-in tools are included by default" do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "anthropic",
        auth_type: :oauth,
        name: "anth-default",
        credentials: %{"access_token" => "tok"},
        expires_at: DateTime.utc_now()
      })

    {:ok, _session} =
      Conversations.create_session(%{
        name: "Anth Default Tools",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, _} =
      AnthStreaming.stream_chat(
        "anth-default",
        [%{"role" => "user", "content" => [%{"type" => "text", "text" => "hello"}]}],
        streaming_adapter: __MODULE__.CaptureAdapter
      )

    assert_receive {:captured_anthropic_tools, names}, 1_000

    # Spot-check a subset of known built-ins
    for required <- ["Bash", "Glob", "Grep", "Edit", "Write"] do
      assert required in names
    end
  end
end
