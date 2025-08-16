defmodule TheMaestro.Sessions do
  @moduledoc """
  Context for managing conversation session persistence.

  This module provides functionality to save and restore agent conversation sessions
  including message history, agent state, and metadata.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo
  alias TheMaestro.Sessions.ConversationSession
  alias TheMaestro.Models.Model

  @doc """
  Creates a conversation session.

  ## Examples

      iex> create_conversation_session(%{field: value})
      {:ok, %ConversationSession{}}
      
      iex> create_conversation_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_conversation_session(map()) ::
          {:ok, ConversationSession.t()} | {:error, Ecto.Changeset.t()}
  def create_conversation_session(attrs \\ %{}) do
    %ConversationSession{}
    |> ConversationSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single conversation session.

  Raises `Ecto.NoResultsError` if the conversation session does not exist.

  ## Examples

      iex> get_conversation_session!(123)
      %ConversationSession{}
      
      iex> get_conversation_session!(456)
      ** (Ecto.NoResultsError)
  """
  @spec get_conversation_session!(binary()) :: ConversationSession.t()
  def get_conversation_session!(id), do: Repo.get!(ConversationSession, id)

  @doc """
  Gets a conversation session by agent_id and session_name.

  ## Examples

      iex> get_conversation_session_by_agent_and_name("agent_123", "my_session")
      %ConversationSession{}
      
      iex> get_conversation_session_by_agent_and_name("agent_456", "nonexistent")
      nil
  """
  @spec get_conversation_session_by_agent_and_name(String.t(), String.t()) ::
          ConversationSession.t() | nil
  def get_conversation_session_by_agent_and_name(agent_id, session_name) do
    Repo.get_by(ConversationSession, agent_id: agent_id, session_name: session_name)
  end

  @doc """
  Updates a conversation session.

  ## Examples

      iex> update_conversation_session(conversation_session, %{field: new_value})
      {:ok, %ConversationSession{}}
      
      iex> update_conversation_session(conversation_session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_conversation_session(ConversationSession.t(), map()) ::
          {:ok, ConversationSession.t()} | {:error, Ecto.Changeset.t()}
  def update_conversation_session(%ConversationSession{} = conversation_session, attrs) do
    conversation_session
    |> ConversationSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation session.

  ## Examples

      iex> delete_conversation_session(conversation_session)
      {:ok, %ConversationSession{}}
      
      iex> delete_conversation_session(conversation_session)
      {:error, %Ecto.Changeset{}}
  """
  @spec delete_conversation_session(ConversationSession.t()) ::
          {:ok, ConversationSession.t()} | {:error, Ecto.Changeset.t()}
  def delete_conversation_session(%ConversationSession{} = conversation_session) do
    Repo.delete(conversation_session)
  end

  @doc """
  Lists conversation sessions for a given agent_id.

  ## Examples

      iex> list_sessions_for_agent("agent_123")
      [%ConversationSession{}, ...]
  """
  @spec list_sessions_for_agent(String.t()) :: [ConversationSession.t()]
  def list_sessions_for_agent(agent_id) do
    from(cs in ConversationSession,
      where: cs.agent_id == ^agent_id,
      order_by: [desc: cs.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists conversation sessions for a given user_id.

  ## Examples

      iex> list_sessions_for_user("user_123")
      [%ConversationSession{}, ...]
  """
  @spec list_sessions_for_user(String.t()) :: [ConversationSession.t()]
  def list_sessions_for_user(user_id) do
    from(cs in ConversationSession,
      where: cs.user_id == ^user_id,
      order_by: [desc: cs.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Saves an agent's current state as a conversation session.

  ## Parameters
    - agent_state: The current agent state struct
    - session_name: Name for the session (optional, defaults to timestamp)
    - user_id: User ID (optional, for authenticated sessions)

  ## Examples

      iex> save_session(agent_state, "my_conversation")
      {:ok, %ConversationSession{}}
      
      iex> save_session(agent_state, "duplicate_name")
      {:error, %Ecto.Changeset{}}
  """
  @spec save_session(TheMaestro.Agents.Agent.t(), String.t() | nil, String.t() | nil) ::
          {:ok, ConversationSession.t()} | {:error, Ecto.Changeset.t()}
  def save_session(agent_state, session_name \\ nil, user_id \\ nil) do
    session_name = session_name || generate_default_session_name()
    serialized_state = serialize_agent_state(agent_state)
    message_count = length(agent_state.message_history)

    attrs = %{
      session_name: session_name,
      agent_id: agent_state.agent_id,
      user_id: user_id,
      session_data: serialized_state,
      message_count: message_count
    }

    # Check if session with this name already exists for this agent
    case get_conversation_session_by_agent_and_name(agent_state.agent_id, session_name) do
      nil ->
        create_conversation_session(attrs)

      existing_session ->
        update_conversation_session(existing_session, attrs)
    end
  end

  @doc """
  Restores an agent session from a saved conversation session.

  ## Parameters
    - agent_id: The agent ID
    - session_name: The name of the session to restore

  ## Examples

      iex> restore_session("agent_123", "my_conversation")
      {:ok, %Agent{}}
      
      iex> restore_session("agent_456", "nonexistent")
      {:error, :not_found}
  """
  @spec restore_session(String.t(), String.t()) ::
          {:ok, TheMaestro.Agents.Agent.t()} | {:error, :not_found | :invalid_data}
  def restore_session(agent_id, session_name) do
    case get_conversation_session_by_agent_and_name(agent_id, session_name) do
      nil ->
        {:error, :not_found}

      session ->
        case deserialize_agent_state(session.session_data) do
          {:ok, agent_state} ->
            {:ok, agent_state}

          {:error, _reason} ->
            {:error, :invalid_data}
        end
    end
  end

  # Private functions

  defp generate_default_session_name do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[\s\-\.:Z]/, "")
    "session_#{timestamp}"
  end

  defp serialize_agent_state(agent_state) do
    # Convert the agent state to a serializable format
    serializable_state = %{
      agent_id: agent_state.agent_id,
      message_history: serialize_message_history(agent_state.message_history),
      loop_state: agent_state.loop_state,
      created_at: DateTime.to_iso8601(agent_state.created_at),
      llm_provider: module_to_atom(agent_state.llm_provider),
      auth_context: serialize_auth_context(agent_state.auth_context),
      model: serialize_model(Map.get(agent_state, :model))
    }

    Jason.encode!(serializable_state)
  end

  defp deserialize_agent_state(serialized_data) do
    data = Jason.decode!(serialized_data)

    {:ok, created_at, _} = DateTime.from_iso8601(data["created_at"])

    agent_state = %TheMaestro.Agents.Agent{
      agent_id: data["agent_id"],
      message_history: deserialize_message_history(data["message_history"]),
      loop_state: String.to_existing_atom(data["loop_state"]),
      created_at: created_at,
      llm_provider: atom_to_module(data["llm_provider"]),
      auth_context: deserialize_auth_context(data["auth_context"]),
      model: deserialize_model(Map.get(data, "model"))
    }

    {:ok, agent_state}
  rescue
    e in [Jason.DecodeError, ArgumentError, MatchError] ->
      {:error, e}
  end

  defp serialize_message_history(message_history) do
    Enum.map(message_history, fn message ->
      %{
        "type" => message.type,
        "role" => message.role,
        "content" => message.content,
        "timestamp" => DateTime.to_iso8601(message.timestamp)
      }
    end)
  end

  defp deserialize_message_history(serialized_messages) do
    Enum.map(serialized_messages, fn message ->
      {:ok, timestamp, _} = DateTime.from_iso8601(message["timestamp"])

      %{
        type: String.to_existing_atom(message["type"]),
        role: String.to_existing_atom(message["role"]),
        content: message["content"],
        timestamp: timestamp
      }
    end)
  end

  defp serialize_auth_context(nil), do: nil

  defp serialize_auth_context(auth_context) when is_map(auth_context) do
    # Convert auth_context to serializable format
    # Note: Be careful not to serialize sensitive credentials
    Map.take(auth_context, [:type])
  end

  defp deserialize_auth_context(nil), do: nil

  defp deserialize_auth_context(serialized_context) when is_map(serialized_context) do
    # Restore auth_context from serialized format
    # Note: Auth context will need to be re-initialized after restoration
    Map.new(serialized_context, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp module_to_atom(module) when is_atom(module) do
    module |> Atom.to_string() |> String.replace("Elixir.", "")
  end

  defp atom_to_module(module_string) when is_binary(module_string) do
    Module.concat([module_string])
  end

  defp serialize_model(nil), do: nil
  defp serialize_model(%Model{} = model) do
    Model.to_map(model)
  end
  defp serialize_model(legacy_model) do
    # Handle legacy model data that might be a string or map
    case legacy_model do
      model when is_binary(model) -> %{id: model, legacy: true}
      model when is_map(model) -> Map.put(model, :legacy, true)
      _ -> nil
    end
  end

  defp deserialize_model(nil), do: nil
  defp deserialize_model(%{legacy: true} = model_data) do
    # Handle legacy model data
    Model.from_legacy(model_data)
  end
  defp deserialize_model(model_data) when is_map(model_data) do
    # Handle Model struct data
    Model.from_legacy_map(model_data)
  end
  defp deserialize_model(model_data) when is_binary(model_data) do
    # Handle string model ID
    Model.from_legacy_string(model_data)
  end
  defp deserialize_model(_), do: nil
end
