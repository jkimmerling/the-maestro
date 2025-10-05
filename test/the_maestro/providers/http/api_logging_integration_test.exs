defmodule TheMaestro.Providers.Http.ApiLoggingIntegrationTest do
  use ExUnit.Case, async: false

  alias TheMaestro.Providers.Http.StreamingAdapter

  defmodule TestServer do
    use Plug.Router

    plug :match
    plug :dispatch

    post "/v1/test" do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"ok":true}))
    end
  end

  setup do
    {:ok, pid} = Bandit.start_link(plug: TestServer, port: 0)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(pid)

    log_path =
      Path.join(System.tmp_dir!(), "api_logger_#{System.unique_integer([:positive])}.log")

    on_exit(fn ->
      System.delete_env("API_DEBUG_LOG")
      System.delete_env("API_DEBUG_LOG_FILE")
      File.rm(log_path)

      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, port: port, log_path: log_path}
  end

  test "writes request and response logs when enabled", %{port: port, log_path: log_path} do
    System.put_env("API_DEBUG_LOG", "1")
    System.put_env("API_DEBUG_LOG_FILE", log_path)

    req = Req.new(base_url: "http://localhost:#{port}")

    {:ok, stream} =
      StreamingAdapter.stream_request(req,
        method: :post,
        url: "/v1/test",
        json: %{"foo" => "bar"},
        provider: :openai,
        timeout: 5_000
      )

    Enum.to_list(stream)

    assert File.exists?(log_path)

    log = File.read!(log_path)

    assert log =~ "REQUEST #"
    assert log =~ "Provider: openai"
    assert log =~ "/v1/test"
    assert log =~ "\"foo\""
    assert log =~ "\"ok\""
  end
end
