defmodule MaestroTui.HeadlessFlowTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  setup do
    {:ok, _pid} = start_supervised({Finch, name: MaestroTui.Finch})
    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"
    env = System.put_env(%{"TUI_API_BASE_URL" => base, "TUI_API_TOKEN" => "0000000000000000"})

    on_exit(fn -> System.put_env(env) end)

    {:ok, tmp} = BriefTemp.dir()
    {:ok, bypass: bypass, base_url: base, tmp: tmp}
  end

  test "function_call -> local IO tool -> POST tool result", %{bypass: bypass, tmp: tmp} do
    # Providers
    Bypass.expect(bypass, "GET", "/api/providers", fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(200, ~s({"providers":["openai"]}))
    end)

    # Auths
    Bypass.expect(bypass, "GET", "/api/providers/openai/saved_auths", fn conn ->
      body = %{"auths" => [%{"id" => "auth1", "label" => "Auth 1", "auth_type" => "api_key"}]}
      conn |> json(200, body)
    end)

    # Models
    Bypass.expect(bypass, "GET", "/api/providers/openai/saved_auths/auth1/models", fn conn ->
      conn |> json(200, %{"models" => ["gpt-4o"]})
    end)

    # Create session
    Bypass.expect(bypass, "POST", "/api/sessions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "\"tool_runtime\":\"remote\""
      conn |> json(200, %{"session_id" => "s1"})
    end)

    # Start turn
    Bypass.expect(bypass, "POST", "/api/sessions/s1/turns", fn conn ->
      conn |> json(202, %{"stream_id" => "t1", "thread_id" => "th1", "model" => "gpt-4o", "provider" => "openai"})
    end)

    # Frames SSE
    Bypass.expect(bypass, "GET", "/api/sessions/s1/turns/t1/frames", fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)

      fcalls = %{
        "data" => %{
          "kind" => "function_call",
          "payload" => %{
            "calls" => [
              %{"id" => "c1", "name" => "WriteFile", "arguments" => Jason.encode!(%{"path" => "tool_test.txt", "content" => "hello"})}
            ]
          }
        }
      }

      :ok = Plug.Conn.chunk(conn, "data: " <> Jason.encode!(fcalls) <> "\n\n")

      completed = %{"data" => %{"kind" => "final", "payload" => %{}}}
      :ok = Plug.Conn.chunk(conn, "data: " <> Jason.encode!(completed) <> "\n\n")
      conn
    end)

    # Tool results receiver
    parent = self()
    Bypass.expect(bypass, "POST", "/api/sessions/s1/turns/t1/tools/results", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:tool_result_posted, body})
      conn |> Plug.Conn.resp(202, "")
    end)

    out =
      capture_io(fn ->
        assert :ok =
                 MaestroTui.Headless.run(
                   provider: "openai",
                   auth_id: "auth1",
                   model: "gpt-4o",
                   working_dir: tmp,
                   message: "test"
                 )
      end)

    assert_receive {:tool_result_posted, body}, 1000
    assert body =~ "\"call_id\":\"c1\""
    assert File.read!(Path.join(tmp, "tool_test.txt")) == "hello"
    assert is_binary(out)
  end

  defp json(conn, status, map) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(map))
  end
end

defmodule BriefTemp do
  @moduledoc false
  def dir do
    base = Path.join(System.tmp_dir!(), "maestro_tui_test_" <> uuid())
    File.mkdir_p!(base)
    {:ok, base}
  end

  defp uuid do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
