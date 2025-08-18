defmodule TheMaestro.MCP.Security.TrustManagerTest do
  use ExUnit.Case, async: false  # Changed to false to avoid GenServer conflicts
  
  alias TheMaestro.MCP.Security.{TrustManager, ServerTrust}
  
  setup do
    # Ensure clean state for each test
    if Process.whereis(TrustManager) do
      GenServer.stop(TrustManager, :normal, 5000)
    end
    
    :ok
  end

  describe "server_trust_level/1" do
    test "returns :untrusted for unknown servers" do
      {:ok, pid} = TrustManager.start_link([])
      
      assert GenServer.call(pid, {:server_trust_level, "unknown_server"}) == :untrusted
    end

    test "returns correct trust level for configured servers" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "filesystem_server", :trusted, "test_user"})
      assert GenServer.call(pid, {:server_trust_level, "filesystem_server"}) == :trusted
    end
  end

  describe "grant_server_trust/3" do
    test "grants trust to a server" do
      {:ok, pid} = TrustManager.start_link([])
      
      assert :ok = GenServer.call(pid, {:grant_server_trust, "test_server", :trusted, "user123"})
      assert GenServer.call(pid, {:server_trust_level, "test_server"}) == :trusted
    end

    test "creates server trust record with correct attributes" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "test_server", :sandboxed, "user123"})
      
      trust = GenServer.call(pid, {:get_server_trust, "test_server"})
      assert %ServerTrust{
        server_id: "test_server",
        trust_level: :sandboxed,
        user_granted: true,
        auto_granted: false
      } = trust
    end
  end

  describe "revoke_server_trust/2" do
    test "revokes trust from a server" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "test_server", :trusted, "user123"})
      assert GenServer.call(pid, {:server_trust_level, "test_server"}) == :trusted
      
      assert :ok = GenServer.call(pid, {:revoke_server_trust, "test_server", "user123"})
      assert GenServer.call(pid, {:server_trust_level, "test_server"}) == :untrusted
    end
  end

  describe "requires_confirmation?/3" do
    test "returns false for trusted servers with whitelisted tools" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "filesystem_server", :trusted, "user123"})
      GenServer.call(pid, {:whitelist_tool, "filesystem_server", "read_file", "user123"})
      
      tool = %{server_id: "filesystem_server", name: "read_file"}
      params = %{"path" => "/safe/path"}
      context = %{user_id: "user123", server_id: "filesystem_server"}
      
      refute GenServer.call(pid, {:requires_confirmation, tool, params, context})
    end

    test "returns true for untrusted servers" do
      {:ok, pid} = TrustManager.start_link([])
      
      tool = %{server_id: "untrusted_server", name: "dangerous_tool"}
      params = %{"command" => "rm -rf /"}
      context = %{user_id: "user123", server_id: "untrusted_server"}
      
      assert GenServer.call(pid, {:requires_confirmation, tool, params, context})
    end

    test "returns true when parameters contain sensitive paths" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "filesystem_server", :trusted, "user123"})
      
      tool = %{server_id: "filesystem_server", name: "read_file"}
      params = %{"path" => "/etc/passwd"}
      context = %{user_id: "user123", server_id: "filesystem_server"}
      
      assert GenServer.call(pid, {:requires_confirmation, tool, params, context})
    end
  end

  describe "whitelist_tool/3" do
    test "adds tool to server whitelist" do
      {:ok, pid} = TrustManager.start_link([])
      
      assert :ok = GenServer.call(pid, {:whitelist_tool, "filesystem_server", "read_file", "user123"})
      
      trust = GenServer.call(pid, {:get_server_trust, "filesystem_server"})
      assert "read_file" in trust.whitelist_tools
    end
  end

  describe "blacklist_tool/3" do
    test "adds tool to server blacklist" do
      {:ok, pid} = TrustManager.start_link([])
      
      assert :ok = GenServer.call(pid, {:blacklist_tool, "filesystem_server", "delete_file", "user123"})
      
      trust = GenServer.call(pid, {:get_server_trust, "filesystem_server"})
      assert "delete_file" in trust.blacklist_tools
    end

    test "blacklisted tools always require confirmation even if server is trusted" do
      {:ok, pid} = TrustManager.start_link([])
      
      GenServer.call(pid, {:grant_server_trust, "filesystem_server", :trusted, "user123"})
      GenServer.call(pid, {:blacklist_tool, "filesystem_server", "delete_file", "user123"})
      
      tool = %{server_id: "filesystem_server", name: "delete_file"}
      params = %{"path" => "/safe/path"}
      context = %{user_id: "user123", server_id: "filesystem_server"}
      
      assert GenServer.call(pid, {:requires_confirmation, tool, params, context})
    end
  end
end