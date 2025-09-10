defmodule TheMaestro.Domain.RequestMetaTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Domain.{RequestMeta, Usage}

  test "builds from map with usage" do
    {:ok, rm} =
      RequestMeta.new(%{
        provider: :openai,
        auth_type: :oauth,
        auth_name: "n",
        usage: %{prompt_tokens: 1, completion_tokens: 2}
      })

    assert %Usage{total_tokens: 3} = rm.usage
    assert rm.provider_meta.provider == :openai
  end

  test "new!/1 raises on invalid usage" do
    assert_raise ArgumentError, fn -> RequestMeta.new!(%{provider: :openai, usage: "bad"}) end
  end
end
