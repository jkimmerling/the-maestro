defmodule TheMaestro.Domain.ProviderMetaTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Domain.ProviderMeta

  test "normalizes provider string and defaults" do
    {:ok, pm} =
      ProviderMeta.new(%{"provider" => "openai", "auth_type" => "oauth", "auth_name" => "acct"})

    assert pm.provider == :openai
    assert pm.auth_type == :oauth
    assert pm.auth_name == "acct"
  end

  test "falls back to :openai for unknown provider string" do
    {:ok, pm} = ProviderMeta.new(%{"provider" => "unknown"})
    assert pm.provider == :openai
  end

  test "new!/1 raises on invalid auth_type" do
    assert_raise ArgumentError, fn -> ProviderMeta.new!(%{"auth_type" => :bad}) end
  end
end
