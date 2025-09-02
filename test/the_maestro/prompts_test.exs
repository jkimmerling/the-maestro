defmodule TheMaestro.PromptsTest do
  use TheMaestro.DataCase

  alias TheMaestro.Prompts

  describe "base_system_prompts" do
    alias TheMaestro.Prompts.BaseSystemPrompt

    import TheMaestro.PromptsFixtures

    @invalid_attrs %{name: nil, prompt_text: nil}

    test "list_base_system_prompts/0 returns all base_system_prompts" do
      base_system_prompt = base_system_prompt_fixture()
      assert Prompts.list_base_system_prompts() == [base_system_prompt]
    end

    test "get_base_system_prompt!/1 returns the base_system_prompt with given id" do
      base_system_prompt = base_system_prompt_fixture()
      assert Prompts.get_base_system_prompt!(base_system_prompt.id) == base_system_prompt
    end

    test "create_base_system_prompt/1 with valid data creates a base_system_prompt" do
      valid_attrs = %{name: "some name", prompt_text: "some prompt_text"}

      assert {:ok, %BaseSystemPrompt{} = base_system_prompt} =
               Prompts.create_base_system_prompt(valid_attrs)

      assert base_system_prompt.name == "some name"
      assert base_system_prompt.prompt_text == "some prompt_text"
    end

    test "create_base_system_prompt/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Prompts.create_base_system_prompt(@invalid_attrs)
    end

    test "update_base_system_prompt/2 with valid data updates the base_system_prompt" do
      base_system_prompt = base_system_prompt_fixture()
      update_attrs = %{name: "some updated name", prompt_text: "some updated prompt_text"}

      assert {:ok, %BaseSystemPrompt{} = base_system_prompt} =
               Prompts.update_base_system_prompt(base_system_prompt, update_attrs)

      assert base_system_prompt.name == "some updated name"
      assert base_system_prompt.prompt_text == "some updated prompt_text"
    end

    test "update_base_system_prompt/2 with invalid data returns error changeset" do
      base_system_prompt = base_system_prompt_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Prompts.update_base_system_prompt(base_system_prompt, @invalid_attrs)

      assert base_system_prompt == Prompts.get_base_system_prompt!(base_system_prompt.id)
    end

    test "delete_base_system_prompt/1 deletes the base_system_prompt" do
      base_system_prompt = base_system_prompt_fixture()
      assert {:ok, %BaseSystemPrompt{}} = Prompts.delete_base_system_prompt(base_system_prompt)

      assert_raise Ecto.NoResultsError, fn ->
        Prompts.get_base_system_prompt!(base_system_prompt.id)
      end
    end

    test "change_base_system_prompt/1 returns a base_system_prompt changeset" do
      base_system_prompt = base_system_prompt_fixture()
      assert %Ecto.Changeset{} = Prompts.change_base_system_prompt(base_system_prompt)
    end
  end
end
