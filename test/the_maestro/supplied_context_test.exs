defmodule TheMaestro.SuppliedContextTest do
  use TheMaestro.DataCase

  alias TheMaestro.SuppliedContext

  describe "supplied_context_items" do
    alias TheMaestro.SuppliedContext.SuppliedContextItem

    import TheMaestro.SuppliedContextFixtures

    @invalid_attrs %{
      name: nil,
      type: nil,
      version: nil,
      metadata: nil,
      text: nil,
      labels: nil,
      provider: nil,
      render_format: nil
    }

    test "list_supplied_context_items/0 returns all supplied_context_items" do
      supplied_context_item = supplied_context_item_fixture()
      assert SuppliedContext.list_supplied_context_items() == [supplied_context_item]
    end

    test "get_supplied_context_item!/1 returns the supplied_context_item with given id" do
      supplied_context_item = supplied_context_item_fixture()

      assert SuppliedContext.get_supplied_context_item!(supplied_context_item.id) ==
               supplied_context_item
    end

    test "create_supplied_context_item/1 with valid data creates a supplied_context_item" do
      valid_attrs = %{
        name: "some name",
        type: :persona,
        version: 42,
        metadata: %{},
        text: "some text",
        labels: %{},
        provider: :shared,
        render_format: :text
      }

      assert {:ok, %SuppliedContextItem{} = supplied_context_item} =
               SuppliedContext.create_supplied_context_item(valid_attrs)

      assert supplied_context_item.name == "some name"
      assert supplied_context_item.type == :persona
      assert supplied_context_item.version == 42
      assert supplied_context_item.metadata == %{}
      assert supplied_context_item.text == "some text"
      assert supplied_context_item.labels == %{}
      assert supplied_context_item.provider == :shared
      assert supplied_context_item.render_format == :text
      refute is_nil(supplied_context_item.family_id)
      assert supplied_context_item.editor == nil
      assert supplied_context_item.change_note == nil
    end

    test "create_supplied_context_item/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               SuppliedContext.create_supplied_context_item(@invalid_attrs)
    end

    test "update_supplied_context_item/2 with valid data updates the supplied_context_item" do
      supplied_context_item = supplied_context_item_fixture()
      original_family_id = supplied_context_item.family_id

      update_attrs = %{
        name: "some updated name",
        type: :system_prompt,
        version: 43,
        metadata: %{},
        text: "some updated text",
        labels: %{},
        provider: :anthropic,
        render_format: :anthropic_blocks
      }

      assert {:ok, %SuppliedContextItem{} = supplied_context_item} =
               SuppliedContext.update_supplied_context_item(supplied_context_item, update_attrs)

      assert supplied_context_item.name == "some updated name"
      assert supplied_context_item.type == :system_prompt
      assert supplied_context_item.version == 43
      assert supplied_context_item.metadata == %{}
      assert supplied_context_item.text == "some updated text"
      assert supplied_context_item.labels == %{}
      assert supplied_context_item.provider == :anthropic
      assert supplied_context_item.render_format == :anthropic_blocks
      assert supplied_context_item.family_id == original_family_id
    end

    test "update_supplied_context_item/2 with invalid data returns error changeset" do
      supplied_context_item = supplied_context_item_fixture()

      assert {:error, %Ecto.Changeset{}} =
               SuppliedContext.update_supplied_context_item(supplied_context_item, @invalid_attrs)

      assert supplied_context_item ==
               SuppliedContext.get_supplied_context_item!(supplied_context_item.id)
    end

    test "delete_supplied_context_item/1 deletes the supplied_context_item" do
      supplied_context_item = supplied_context_item_fixture()

      assert {:ok, %SuppliedContextItem{}} =
               SuppliedContext.delete_supplied_context_item(supplied_context_item)

      assert_raise Ecto.NoResultsError, fn ->
        SuppliedContext.get_supplied_context_item!(supplied_context_item.id)
      end
    end

    test "change_supplied_context_item/1 returns a supplied_context_item changeset" do
      supplied_context_item = supplied_context_item_fixture()

      assert %Ecto.Changeset{} =
               SuppliedContext.change_supplied_context_item(supplied_context_item)
    end
  end

  describe "provider scoped helpers" do
    import TheMaestro.SuppliedContextFixtures

    test "list_system_prompts/2 includes provider defaults and shared prompts in order" do
      shared =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :shared,
          position: 2,
          is_default: true,
          version: 1,
          text: "shared"
        })

      openai_default =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          position: 1,
          is_default: true,
          version: 3,
          text: "openai"
        })

      _non_default =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          position: 3,
          is_default: false,
          version: 4,
          text: "optional"
        })

      prompts = SuppliedContext.list_system_prompts(:openai, only_defaults: true)

      assert Enum.map(prompts, &{&1.id, &1.text}) ==
               [{openai_default.id, "openai"}, {shared.id, "shared"}]
    end

    test "get_default_prompt!/2 prefers provider-specific default and falls back to shared" do
      shared =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :shared,
          is_default: true,
          version: 1,
          name: "core",
          text: "shared core"
        })

      specific =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :anthropic,
          is_default: true,
          version: 2,
          name: shared.name,
          text: "anthropic core"
        })

      assert SuppliedContext.get_default_prompt!(:anthropic, shared.name).id == specific.id
      assert SuppliedContext.get_default_prompt!(:openai, shared.name).id == shared.id
    end

    test "caches list results but invalidates on prompt update" do
      prompt =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :gemini,
          is_default: true,
          version: 1,
          text: "v1"
        })

      assert [%{text: "v1"}] = SuppliedContext.list_system_prompts(:gemini, only_defaults: true)

      {:ok, _updated} = SuppliedContext.update_supplied_context_item(prompt, %{text: "v2"})

      assert [%{text: "v2"}] = SuppliedContext.list_system_prompts(:gemini, only_defaults: true)
    end
  end
end
