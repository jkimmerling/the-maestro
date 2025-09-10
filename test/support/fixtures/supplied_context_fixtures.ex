defmodule TheMaestro.SuppliedContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.SuppliedContext` context.
  """

  @doc """
  Generate a supplied_context_item.
  """
  def supplied_context_item_fixture(attrs \\ %{}) do
    {:ok, supplied_context_item} =
      attrs
      |> Enum.into(%{
        metadata: %{},
        # ensure uniqueness across tests to avoid unique index violations
        name: Map.get(attrs, :name, "some name-" <> Integer.to_string(:erlang.unique_integer([:positive, :monotonic]))),
        tags: %{},
        text: "some text",
        type: :persona,
        version: 42
      })
      |> TheMaestro.SuppliedContext.create_supplied_context_item()

    supplied_context_item
  end
end
