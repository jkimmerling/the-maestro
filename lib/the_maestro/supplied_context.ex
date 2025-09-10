defmodule TheMaestro.SuppliedContext do
  @moduledoc """
  The SuppliedContext context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.SuppliedContext.SuppliedContextItem

  @doc """
  Returns the list of supplied_context_items.

  ## Examples

      iex> list_supplied_context_items()
      [%SuppliedContextItem{}, ...]

  """
  def list_supplied_context_items do
    Repo.all(SuppliedContextItem)
  end

  @doc """
  Convenience: list items filtered by `type` (:persona | :system_prompt).
  """
  def list_items(type) when type in [:persona, :system_prompt] do
    import Ecto.Query
    Repo.all(from i in SuppliedContextItem, where: i.type == ^type, order_by: [asc: i.name])
  end

  @doc """
  Gets a single supplied_context_item.

  Raises `Ecto.NoResultsError` if the Supplied context item does not exist.

  ## Examples

      iex> get_supplied_context_item!(123)
      %SuppliedContextItem{}

      iex> get_supplied_context_item!(456)
      ** (Ecto.NoResultsError)

  """
  def get_supplied_context_item!(id), do: Repo.get!(SuppliedContextItem, id)
  def get_item!(id), do: get_supplied_context_item!(id)

  @doc """
  Creates a supplied_context_item.

  ## Examples

      iex> create_supplied_context_item(%{field: value})
      {:ok, %SuppliedContextItem{}}

      iex> create_supplied_context_item(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_supplied_context_item(attrs) do
    %SuppliedContextItem{}
    |> SuppliedContextItem.changeset(attrs)
    |> Repo.insert()
  end

  def create_item(attrs), do: create_supplied_context_item(attrs)

  @doc """
  Updates a supplied_context_item.

  ## Examples

      iex> update_supplied_context_item(supplied_context_item, %{field: new_value})
      {:ok, %SuppliedContextItem{}}

      iex> update_supplied_context_item(supplied_context_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_supplied_context_item(%SuppliedContextItem{} = supplied_context_item, attrs) do
    supplied_context_item
    |> SuppliedContextItem.changeset(attrs)
    |> Repo.update()
  end

  def update_item(item, attrs), do: update_supplied_context_item(item, attrs)

  @doc """
  Deletes a supplied_context_item.

  ## Examples

      iex> delete_supplied_context_item(supplied_context_item)
      {:ok, %SuppliedContextItem{}}

      iex> delete_supplied_context_item(supplied_context_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_supplied_context_item(%SuppliedContextItem{} = supplied_context_item) do
    Repo.delete(supplied_context_item)
  end

  def delete_item(item), do: delete_supplied_context_item(item)

  @doc """
  Bulk delete by id list.
  """
  def delete_items(ids) when is_list(ids) do
    import Ecto.Query
    Repo.delete_all(from i in SuppliedContextItem, where: i.id in ^ids)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking supplied_context_item changes.

  ## Examples

      iex> change_supplied_context_item(supplied_context_item)
      %Ecto.Changeset{data: %SuppliedContextItem{}}

  """
  def change_supplied_context_item(%SuppliedContextItem{} = supplied_context_item, attrs \\ %{}) do
    SuppliedContextItem.changeset(supplied_context_item, attrs)
  end
end
