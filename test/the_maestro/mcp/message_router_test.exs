defmodule TheMaestro.MCP.MessageRouterTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.MessageRouter

  describe "start_link/1" do
    test "starts message router with options" do
      assert {:ok, pid} = MessageRouter.start_link([])
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "send_request/4" do
    test "sends request and tracks response" do
      {:ok, router} = MessageRouter.start_link([])

      transport_pid =
        spawn(fn ->
          receive do
            {:send_message, _message} -> :ok
          end
        end)

      message = %{
        jsonrpc: "2.0",
        method: "test",
        params: %{}
      }

      assert {:ok, request_id} = MessageRouter.send_request(router, transport_pid, message, 5000)
      assert is_binary(request_id)

      GenServer.stop(router)
    end

    test "handles transport send failure" do
      {:ok, router} = MessageRouter.start_link([])

      # Dead transport
      transport_pid = spawn(fn -> :ok end)
      Process.exit(transport_pid, :kill)
      Process.sleep(10)

      message = %{
        jsonrpc: "2.0",
        method: "test",
        params: %{}
      }

      assert {:error, _reason} = MessageRouter.send_request(router, transport_pid, message, 5000)

      GenServer.stop(router)
    end
  end

  describe "handle_response/2" do
    test "correlates response with pending request" do
      {:ok, router} = MessageRouter.start_link([])

      # Mock transport that we can control
      test_process = self()

      transport_pid =
        spawn(fn ->
          receive do
            {:send_message, message} ->
              send(test_process, {:message_sent, message})
              :ok
          end
        end)

      request_message = %{
        jsonrpc: "2.0",
        method: "test",
        params: %{}
      }

      {:ok, request_id} = MessageRouter.send_request(router, transport_pid, request_message, 5000)

      # Simulate response
      response = %{
        "jsonrpc" => "2.0",
        "id" => request_id,
        "result" => %{"status" => "success"}
      }

      assert :ok = MessageRouter.handle_response(router, response)

      GenServer.stop(router)
    end

    test "handles response for unknown request" do
      {:ok, router} = MessageRouter.start_link([])

      response = %{
        "jsonrpc" => "2.0",
        "id" => "unknown-request-id",
        "result" => %{}
      }

      # Should not crash
      assert :ok = MessageRouter.handle_response(router, response)

      GenServer.stop(router)
    end
  end

  describe "handle_notification/2" do
    test "processes notification without response correlation" do
      {:ok, router} = MessageRouter.start_link([])

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list_changed",
        "params" => %{"server" => "test_server"}
      }

      assert :ok = MessageRouter.handle_notification(router, notification)

      GenServer.stop(router)
    end
  end

  describe "pending_requests/1" do
    test "returns count of pending requests" do
      {:ok, router} = MessageRouter.start_link([])

      # Create a transport that can handle multiple messages
      transport_pid =
        spawn(fn ->
          receive_loop = fn receive_loop ->
            receive do
              {:send_message, _} -> :ok
            end

            receive_loop.(receive_loop)
          end

          receive_loop.(receive_loop)
        end)

      assert MessageRouter.pending_requests(router) == 0

      {:ok, _id1} =
        MessageRouter.send_request(
          router,
          transport_pid,
          %{jsonrpc: "2.0", method: "test1"},
          5000
        )

      {:ok, _id2} =
        MessageRouter.send_request(
          router,
          transport_pid,
          %{jsonrpc: "2.0", method: "test2"},
          5000
        )

      assert MessageRouter.pending_requests(router) == 2

      GenServer.stop(router)
    end
  end

  describe "request timeout" do
    test "times out pending requests" do
      {:ok, router} = MessageRouter.start_link([])

      transport_pid =
        spawn(fn ->
          receive do
            {:send_message, _} -> :ok
          end
        end)

      {:ok, request_id} =
        MessageRouter.send_request(router, transport_pid, %{jsonrpc: "2.0", method: "test"}, 100)

      # Wait for timeout
      Process.sleep(150)

      # Request should be cleaned up
      assert MessageRouter.pending_requests(router) == 0

      GenServer.stop(router)
    end
  end
end
