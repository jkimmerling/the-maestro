defmodule TheMaestro.ProviderTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Provider

  describe "list_providers/0" do
    test "returns known providers" do
      providers = Provider.list_providers()
      assert :openai in providers
      assert :anthropic in providers
      assert :gemini in providers
      refute :behaviours in providers
    end
  end

  describe "resolve_module/2" do
    test "resolves OpenAI Streaming module" do
      assert {:ok, mod} = Provider.resolve_module(:openai, :streaming)
      assert mod == TheMaestro.Providers.OpenAI.Streaming
    end

    test "returns error for unknown provider" do
      assert {:error, :module_not_found} = Provider.resolve_module(:unknown, :streaming)
    end
  end

  describe "provider_capabilities/1" do
    test "returns capabilities struct" do
      assert {:ok, caps} = Provider.provider_capabilities(:openai)
      assert is_list(caps.auth_types)
      assert :streaming in caps.features
      assert :models in caps.features
    end
  end
end
