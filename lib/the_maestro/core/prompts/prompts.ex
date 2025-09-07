defmodule TheMaestro.Prompts do
  @moduledoc """
  The Prompts context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.Prompts.BaseSystemPrompt

  @doc """
  Returns the list of base_system_prompts.

  ## Examples

      iex> list_base_system_prompts()
      [%BaseSystemPrompt{}, ...]

  """
  def list_base_system_prompts do
    Repo.all(BaseSystemPrompt)
  end

  @doc """
  Gets a single base_system_prompt.

  Raises `Ecto.NoResultsError` if the Base system prompt does not exist.

  ## Examples

      iex> get_base_system_prompt!(123)
      %BaseSystemPrompt{}

      iex> get_base_system_prompt!(456)
      ** (Ecto.NoResultsError)

  """
  def get_base_system_prompt!(id), do: Repo.get!(BaseSystemPrompt, id)

  @doc """
  Creates a base_system_prompt.

  ## Examples

      iex> create_base_system_prompt(%{field: value})
      {:ok, %BaseSystemPrompt{}}

      iex> create_base_system_prompt(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_base_system_prompt(attrs) do
    %BaseSystemPrompt{}
    |> BaseSystemPrompt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a base_system_prompt.

  ## Examples

      iex> update_base_system_prompt(base_system_prompt, %{field: new_value})
      {:ok, %BaseSystemPrompt{}}

      iex> update_base_system_prompt(base_system_prompt, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_base_system_prompt(%BaseSystemPrompt{} = base_system_prompt, attrs) do
    base_system_prompt
    |> BaseSystemPrompt.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a base_system_prompt.

  ## Examples

      iex> delete_base_system_prompt(base_system_prompt)
      {:ok, %BaseSystemPrompt{}}

      iex> delete_base_system_prompt(base_system_prompt)
      {:error, %Ecto.Changeset{}}

  """
  def delete_base_system_prompt(%BaseSystemPrompt{} = base_system_prompt) do
    Repo.delete(base_system_prompt)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking base_system_prompt changes.

  ## Examples

      iex> change_base_system_prompt(base_system_prompt)
      %Ecto.Changeset{data: %BaseSystemPrompt{}}

  """
  def change_base_system_prompt(%BaseSystemPrompt{} = base_system_prompt, attrs \\ %{}) do
    BaseSystemPrompt.changeset(base_system_prompt, attrs)
  end
end
