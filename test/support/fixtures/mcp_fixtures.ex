defmodule TheMaestro.MCPFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.MCP` context.
  """

  @doc """
  Generate a unique servers name.
  """
  def unique_server_name, do: "server-#{System.unique_integer([:positive])}"

  @doc """
  Generate a servers.
  """
  def server_fixture(attrs \\ %{}) do
    {:ok, server} =
      attrs
      |> Enum.into(%{
        args: ["--flag"],
        auth_token: "token",
        command: "./bin/tool",
        description: "some description",
        display_name: "Server",
        env: %{},
        headers: %{},
        is_enabled: true,
        metadata: %{},
        name: unique_server_name(),
        tags: ["prod"],
        transport: "stdio",
        url: nil,
        definition_source: "manual"
      })
      |> TheMaestro.MCP.create_server()

    server
  end
end
