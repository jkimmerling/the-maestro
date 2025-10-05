defmodule TheMaestroWeb.Integration.OpenAIToolsSchemaParityTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.Providers.OpenAI.Streaming, as: OpenAIStreaming

  defmodule CaptureToolsAdapter do
    def stream_request(_req, opts) do
      json = Keyword.get(opts, :json, %{})
      tools = json["tools"] || []
      send(self(), {:captured_tools, tools})
      {:ok, Stream.iterate(0, & &1) |> Stream.take(0)}
    end
  end

  test "shell properties include escalated permissions and justification; apply_patch has codex instructions" do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-tools-schema",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, _session} =
      Conversations.create_session(%{
        name: "OpenAI Tools Schema",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    {:ok, _} =
      OpenAIStreaming.stream_chat(
        "openai-tools-schema",
        [%{"role" => "user", "content" => "hello"}],
        streaming_adapter: __MODULE__.CaptureToolsAdapter
      )

    assert_receive {:captured_tools, tools}, 1_000

    shell = Enum.find(tools, &(&1["name"] == "shell"))
    assert is_map(shell)
    props = get_in(shell, ["parameters", "properties"]) || %{}
    assert Map.get(props, "with_escalated_permissions") == %{"type" => "boolean"}
    assert Map.get(props, "justification") == %{"type" => "string"}
    assert get_in(shell, ["parameters", "required"]) |> Enum.member?("command")

    apply_patch = Enum.find(tools, &(&1["name"] == "apply_patch"))
    assert is_map(apply_patch)
    desc = Map.get(apply_patch, "description", "")

    assert String.contains?(
             desc,
             "You must prefix new lines with `+` even when creating a new file"
           )
  end
end
