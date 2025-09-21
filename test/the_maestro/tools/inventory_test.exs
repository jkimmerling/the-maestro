defmodule TheMaestro.Tools.InventoryTest do
  use TheMaestro.DataCase, async: true

  import TheMaestro.MCPFixtures

  alias TheMaestro.Tools.Inventory

  describe "list_for_provider_with_servers/3" do
    test "merges builtins with MCP tools from selected servers" do
      server =
        server_fixture(%{
          display_name: "Context7",
          name: "context7",
          transport: "stdio"
        })

      cache_fun = fn ->
        {:ok,
         %{
           "openai" => [
             %{
               "name" => "resolve-library-id",
               "description" => "Resolve library id",
               "source" => "mcp",
               "server_label" => "Context7"
             },
             %{
               "name" => "get-library-docs",
               "description" => "Get docs",
               "source" => "mcp",
               "server_label" => "Context7"
             }
           ]
         }}
      end

      inventory =
        Inventory.list_for_provider_with_servers([server.id], :openai, cache_fetch_fun: cache_fun)

      assert Enum.any?(inventory, &(&1.name == "resolve-library-id" && &1.source == :mcp))
      assert Enum.any?(inventory, &(&1.name == "get-library-docs" && &1.source == :mcp))
      assert Enum.any?(inventory, &(&1.name == "shell" && &1.source == :builtin))

      assert Enum.all?(Enum.filter(inventory, &(&1.source == :mcp)), fn item ->
               item.server_label == "Context7"
             end)
    end

    test "matches cached tools by server label case-insensitively" do
      server =
        server_fixture(%{
          display_name: "Context7",
          name: "context7",
          transport: "stdio"
        })

      cache_fun = fn ->
        {:ok,
         %{
           "gemini" => [
             %{
               "name" => "resolve-library-id",
               "description" => "Resolve library id",
               "source" => "mcp",
               "server_label" => "context7"
             }
           ]
         }}
      end

      inventory =
        Inventory.list_for_provider_with_servers([server.id], :gemini, cache_fetch_fun: cache_fun)

      assert [%{name: "resolve-library-id", source: :mcp, server_label: "Context7"}] =
               Enum.filter(inventory, &(&1.source == :mcp))
    end
  end
end
