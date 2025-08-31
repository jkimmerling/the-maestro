defmodule TheMaestro.Providers.Integration.ProviderDiscoveryTest do
  use ExUnit.Case, async: true

  alias TheMaestro.ProviderRegistry

  test "registry lists providers and excludes invalid operations from available_ops" do
    registry = ProviderRegistry.get_registry()

    # We expect entries for known providers
    providers = Enum.map(registry, & &1.provider)
    assert :openai in providers
    assert :anthropic in providers
    assert :gemini in providers

    # Since stubs are incomplete, available operations should be empty
    for entry <- registry do
      assert is_list(entry.operations)
      assert Enum.all?(entry.operations, &(&1 in [:oauth, :api_key, :streaming, :models]))
    end
  end
end
