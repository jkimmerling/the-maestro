defmodule TheMaestro.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.Agents.Agent

  @doc """
  Returns the list of agents.

  ## Examples

      iex> list_agents()
      [%Agent{}, ...]

  """
  def list_agents do
    Repo.all(Agent)
  end

  def list_agents_with_auth do
    Repo.all(from a in Agent, preload: [:saved_authentication, :base_system_prompt, :persona])
  end

  @doc """
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.

  ## Examples

      iex> get_agent!(123)
      %Agent{}

      iex> get_agent!(456)
      ** (Ecto.NoResultsError)

  """
  def get_agent!(id), do: Repo.get!(Agent, id)

  @doc """
  Creates a agent.

  ## Examples

      iex> create_agent(%{field: value})
      {:ok, %Agent{}}

      iex> create_agent(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_agent(attrs) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a agent.

  ## Examples

      iex> update_agent(agent, %{field: new_value})
      {:ok, %Agent{}}

      iex> update_agent(agent, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a agent.

  ## Examples

      iex> delete_agent(agent)
      {:ok, %Agent{}}

      iex> delete_agent(agent)
      {:error, %Ecto.Changeset{}}

  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.

  ## Examples

      iex> change_agent(agent)
      %Ecto.Changeset{data: %Agent{}}

  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    changeset = Agent.changeset(agent, attrs)

    # Prefill virtual JSON fields for form rendering when not explicitly provided
    changeset
    |> maybe_put_virtual(:tools_json, agent.tools)
    |> maybe_put_virtual(:mcps_json, agent.mcps)
    |> maybe_put_virtual(:memory_json, agent.memory)
  end

  defp maybe_put_virtual(%Ecto.Changeset{} = changeset, field, value) do
    case Ecto.Changeset.get_change(changeset, field) do
      nil -> Ecto.Changeset.put_change(changeset, field, Jason.encode!(value || %{}))
      _ -> changeset
    end
  end
end
