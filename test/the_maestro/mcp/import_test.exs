defmodule TheMaestro.MCP.ImportTest do
  use ExUnit.Case, async: true

  alias TheMaestro.MCP.Import

  describe "parse_cli/1 add" do
    test "parses basic http server with defaults" do
      {:ok, {:upsert, [%{server: server}]}} =
        Import.parse_cli(
          "mcp add Docs --url https://api.example.com --header Authorization=token"
        )

      assert server.name == "docs"
      assert server.display_name == "Docs"
      assert server.transport == "stream-http"
      assert server.url == "https://api.example.com"
      assert server.headers == %{"Authorization" => "token"}
      assert server.is_enabled
      assert server.definition_source == "cli"
    end

    test "parses args, env, metadata and inline command" do
      metadata = Jason.encode!(%{"team" => "dev"})

      cmd =
        "claude mcp add Tools --command ./bin/run --arg=--foo --env PATH=/usr/bin --metadata '#{metadata}' --tag build --enabled -- ./bin/run --bar"

      {:ok, {:upsert, [%{server: server}]}} = Import.parse_cli(cmd)

      assert server.command == "./bin/run"
      assert server.args == ["--foo", "--bar"]
      assert server.env == %{"PATH" => "/usr/bin"}
      assert server.metadata == %{"team" => "dev"}
      assert server.tags == ["build"]
      assert server.transport == "stdio"
      assert server.definition_source == "cli"
    end

    test "resolves inline command when --command absent" do
      {:ok, {:upsert, [%{server: server}]}} =
        Import.parse_cli("mcp add local -- ./bin/run --flag")

      assert server.command == "./bin/run"
      assert server.args == ["--flag"]
      assert server.transport == "stdio"
      assert server.definition_source == "cli"
    end

    test "marks server disabled" do
      {:ok, {:upsert, [%{server: server}]}} =
        Import.parse_cli("mcp add disabled --disabled --command ./run")

      refute server.is_enabled
    end

    test "invalid metadata" do
      assert {:error, message} =
               Import.parse_cli("mcp add broken --metadata not-json --command ./run")

      assert message =~ "metadata"
    end
  end

  describe "parse_cli/1 remove" do
    test "returns remove sentinel" do
      assert {:ok, {:remove, ["old"]}} = Import.parse_cli("mcp remove OLD")
    end

    test "errors on missing name" do
      assert {:error, message} = Import.parse_cli("mcp remove")
      assert message =~ "missing"
    end
  end

  describe "parse_json/1" do
    test "handles nested mcp.servers list" do
      json = """
      {"mcp": {"servers": [{"name": "api", "url": "https://svc", "headers": {"X": 1}}]}}
      """

      {:ok, [server]} = Import.parse_json(json)
      assert server.name == "api"
      assert server.transport == "stream-http"
      assert server.headers == %{"X" => "1"}
    end

    test "merges unknown keys into metadata" do
      json = """
      {"mcpServers": {"tool": {"command": "./run", "extra": "value", "metadata": {"inner": true}}}}
      """

      {:ok, [server]} = Import.parse_json(json)
      assert server.command == "./run"
      assert server.metadata == %{"inner" => true, "extra" => "value"}
      assert server.definition_source == "json"
    end

    test "errors when name missing" do
      json = """
      {"servers": [{"url": "https://svc"}]}
      """

      assert {:error, message} = Import.parse_json(json)
      assert message =~ "missing"
    end
  end

  describe "parse_toml/1" do
    test "parses mcp_servers table" do
      toml = """
      [mcp_servers.cli]
      command = \"bin/cli\"
      args = [\"--debug\"]
      enabled = false
      headers = { X = \"1\" }
      """

      {:ok, [server]} = Import.parse_toml(toml)
      assert server.name == "cli"
      assert server.command == "bin/cli"
      assert server.args == ["--debug"]
      refute server.is_enabled
      assert server.headers == %{"X" => "1"}
      assert server.definition_source == "toml"
    end

    test "surfaces invalid entry" do
      toml = """
      [mcp_servers]
      bad = "value"
      """

      assert {:error, message} = Import.parse_toml(toml)
      assert message =~ "invalid"
    end
  end
end
