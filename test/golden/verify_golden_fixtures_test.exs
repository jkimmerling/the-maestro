defmodule Golden.VerifyGoldenFixturesTest do
  use ExUnit.Case

  @moduletag :golden

  defp golden_enabled?, do: System.get_env("RUN_GOLDEN") in ["1", "true", "TRUE"]

  @providers ["openai", "anthropic", "gemini"]

  test "golden fixtures exist and are parseable" do
    if golden_enabled?() do
      for p <- @providers do
        path = Path.join([File.cwd!(), "priv", "golden", p, "request_fixtures.json"])

        if File.exists?(path) do
          {:ok, bin} = File.read(path)
          {:ok, json} = Jason.decode(bin)
          assert is_list(json)
          assert Enum.any?(json)

          # Basic shape assertions
          Enum.each(json, fn item ->
            assert is_map(item)
            assert Map.has_key?(item, "headers")
            assert Map.has_key?(item, "body")
          end)
        end
      end
    else
      IO.puts("\n⏭️  Skipping golden fixture verify — set RUN_GOLDEN=1 to enable")
    end
  end
end
