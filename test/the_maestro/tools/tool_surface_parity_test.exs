defmodule TheMaestro.Tools.ToolSurfaceParityTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Tools.{ProviderToolManifest, ToolSurface}

  test "openai builtins parity with manifest" do
    inv = ToolSurface.list_builtins(:openai) |> Enum.map(& &1.name) |> MapSet.new()
    man = ProviderToolManifest.list_builtin(:openai) |> Enum.map(& &1.name) |> MapSet.new()
    assert inv == man
  end

  test "gemini builtins parity with manifest" do
    inv = ToolSurface.list_builtins(:gemini) |> Enum.map(& &1.name) |> MapSet.new()
    man = ProviderToolManifest.list_builtin(:gemini) |> Enum.map(& &1.name) |> MapSet.new()
    assert inv == man
  end

  test "anthropic builtins parity with manifest" do
    inv = ToolSurface.list_builtins(:anthropic) |> Enum.map(& &1.name) |> MapSet.new()
    man = ProviderToolManifest.list_builtin(:anthropic) |> Enum.map(& &1.name) |> MapSet.new()
    assert inv == man
  end

  test "openai provider decl names equal manifest names (no MCP)" do
    decls = ToolSurface.resolve_for_provider_decl(:openai, Ecto.UUID.generate())
    names = MapSet.new(Enum.map(decls, & &1["name"]))
    man = MapSet.new(ProviderToolManifest.list_builtin(:openai) |> Enum.map(& &1.name))
    # Decl also includes MCP for a fake session id (none) → just builtins
    assert names == man
  end

  test "gemini provider decl names equal manifest names (no MCP)" do
    decls = ToolSurface.resolve_for_provider_decl(:gemini, Ecto.UUID.generate())
    names = MapSet.new(Enum.map(decls, & &1["name"]))
    man = MapSet.new(ProviderToolManifest.list_builtin(:gemini) |> Enum.map(& &1.name))
    assert names == man
  end
end
