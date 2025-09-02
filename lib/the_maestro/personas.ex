defmodule TheMaestro.Personas do
  @moduledoc """
  The Personas context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.Personas.Persona

  @doc """
  Returns the list of personas.

  ## Examples

      iex> list_personas()
      [%Persona{}, ...]

  """
  def list_personas do
    Repo.all(Persona)
  end

  @doc """
  Gets a single persona.

  Raises `Ecto.NoResultsError` if the Persona does not exist.

  ## Examples

      iex> get_persona!(123)
      %Persona{}

      iex> get_persona!(456)
      ** (Ecto.NoResultsError)

  """
  def get_persona!(id), do: Repo.get!(Persona, id)

  @doc """
  Creates a persona.

  ## Examples

      iex> create_persona(%{field: value})
      {:ok, %Persona{}}

      iex> create_persona(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_persona(attrs) do
    %Persona{}
    |> Persona.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a persona.

  ## Examples

      iex> update_persona(persona, %{field: new_value})
      {:ok, %Persona{}}

      iex> update_persona(persona, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_persona(%Persona{} = persona, attrs) do
    persona
    |> Persona.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a persona.

  ## Examples

      iex> delete_persona(persona)
      {:ok, %Persona{}}

      iex> delete_persona(persona)
      {:error, %Ecto.Changeset{}}

  """
  def delete_persona(%Persona{} = persona) do
    Repo.delete(persona)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking persona changes.

  ## Examples

      iex> change_persona(persona)
      %Ecto.Changeset{data: %Persona{}}

  """
  def change_persona(%Persona{} = persona, attrs \\ %{}) do
    Persona.changeset(persona, attrs)
  end
end
