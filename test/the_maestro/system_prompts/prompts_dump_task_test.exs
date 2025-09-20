defmodule TheMaestro.SystemPrompts.PromptsDumpTaskTest do
  use TheMaestro.DataCase

  alias Mix.Tasks.Maestro.Prompts.Dump, as: PromptsDump
  alias TheMaestro.SystemPrompts.Seeder

  @tmp_dir Path.join(System.tmp_dir!(), "maestro_prompts_dump_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)

    assert :ok == Seeder.seed!()

    Mix.Task.clear()

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "mix maestro.prompts.dump writes provider dumps" do
    PromptsDump.run(["--output", @tmp_dir])

    for provider <- ["openai", "anthropic", "gemini"] do
      path = Path.join(@tmp_dir, provider <> ".json")
      assert File.exists?(path)

      {:ok, payload} = File.read(path)
      assert {:ok, list} = Jason.decode(payload)
      assert is_list(list)
      assert Enum.all?(list, &is_map/1)
    end
  end
end
