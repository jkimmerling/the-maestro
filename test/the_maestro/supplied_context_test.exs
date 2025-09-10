defmodule TheMaestro.SuppliedContextTest do
  use TheMaestro.DataCase

  alias TheMaestro.SuppliedContext

  describe "supplied_context_items" do
    alias TheMaestro.SuppliedContext.SuppliedContextItem

    import TheMaestro.SuppliedContextFixtures

    @invalid_attrs %{name: nil, type: nil, version: nil, metadata: nil, text: nil, tags: nil}

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
        tags: %{}
      }

      assert {:ok, %SuppliedContextItem{} = supplied_context_item} =
               SuppliedContext.create_supplied_context_item(valid_attrs)

      assert supplied_context_item.name == "some name"
      assert supplied_context_item.type == :persona
      assert supplied_context_item.version == 42
      assert supplied_context_item.metadata == %{}
      assert supplied_context_item.text == "some text"
      assert supplied_context_item.tags == %{}
    end

    test "create_supplied_context_item/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               SuppliedContext.create_supplied_context_item(@invalid_attrs)
    end

    test "update_supplied_context_item/2 with valid data updates the supplied_context_item" do
      supplied_context_item = supplied_context_item_fixture()

      update_attrs = %{
        name: "some updated name",
        type: :system_prompt,
        version: 43,
        metadata: %{},
        text: "some updated text",
        tags: %{}
      }

      assert {:ok, %SuppliedContextItem{} = supplied_context_item} =
               SuppliedContext.update_supplied_context_item(supplied_context_item, update_attrs)

      assert supplied_context_item.name == "some updated name"
      assert supplied_context_item.type == :system_prompt
      assert supplied_context_item.version == 43
      assert supplied_context_item.metadata == %{}
      assert supplied_context_item.text == "some updated text"
      assert supplied_context_item.tags == %{}
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
end
