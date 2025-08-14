defmodule TheMaestro.Providers.Auth.SessionManager do
  @moduledoc """
  Multi-provider session management for authentication contexts.

  This module manages authentication sessions across different providers,
  handling session lifecycle, credential refresh, and provider switching.
  """

  use GenServer
  alias TheMaestro.Providers.Auth
  alias TheMaestro.Providers.Auth.ProviderAuth

  require Logger

  defmodule SessionState do
    @moduledoc false
    defstruct user_id: nil,
              active_provider: nil,
              provider_contexts: %{},
              last_activity: nil,
              created_at: nil
  end

  # Client API

  @doc """
  Starts a session manager for a specific user.

  ## Parameters
    - `user_id`: User identifier
    - `opts`: Optional GenServer options

  ## Returns
    - `{:ok, pid}`: Successfully started
    - `{:error, reason}`: Failed to start
  """
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(user_id, opts \\ []) do
    GenServer.start_link(__MODULE__, user_id, opts)
  end

  @doc """
  Sets the active provider for a session.

  ## Parameters
    - `session`: Session manager PID or name
    - `provider`: Provider to set as active
    - `method`: Optional authentication method preference

  ## Returns
    - `{:ok, auth_context}`: Successfully set active provider
    - `{:error, reason}`: Failed to set provider
  """
  @spec set_active_provider(pid(), ProviderAuth.provider(), ProviderAuth.auth_method() | nil) ::
          {:ok, map()} | {:error, term()}
  def set_active_provider(session, provider, method \\ nil) do
    GenServer.call(session, {:set_active_provider, provider, method})
  end

  @doc """
  Gets the current active provider and its authentication context.

  ## Parameters
    - `session`: Session manager PID or name

  ## Returns
    - `{:ok, {provider, auth_context}}`: Active provider found
    - `{:error, :no_active_provider}`: No active provider set
  """
  @spec get_active_provider(pid()) ::
          {:ok, {ProviderAuth.provider(), map()}} | {:error, :no_active_provider}
  def get_active_provider(session) do
    GenServer.call(session, :get_active_provider)
  end

  @doc """
  Gets authentication context for a specific provider.

  ## Parameters
    - `session`: Session manager PID or name
    - `provider`: Provider to get context for

  ## Returns
    - `{:ok, auth_context}`: Context found/loaded
    - `{:error, reason}`: Failed to get context
  """
  @spec get_provider_context(pid(), ProviderAuth.provider()) :: {:ok, map()} | {:error, term()}
  def get_provider_context(session, provider) do
    GenServer.call(session, {:get_provider_context, provider})
  end

  @doc """
  Refreshes credentials for all providers in the session.

  ## Parameters
    - `session`: Session manager PID or name

  ## Returns
    - `:ok`: All providers refreshed successfully
    - `{:error, failed_providers}`: Some providers failed to refresh
  """
  @spec refresh_all_credentials(pid()) :: :ok | {:error, [ProviderAuth.provider()]}
  def refresh_all_credentials(session) do
    GenServer.call(session, :refresh_all_credentials)
  end

  @doc """
  Lists all available providers for the user session.

  ## Parameters
    - `session`: Session manager PID or name

  ## Returns
    Map of providers to their authentication status
  """
  @spec list_session_providers(pid()) :: %{
          ProviderAuth.provider() => :authenticated | :needs_auth
        }
  def list_session_providers(session) do
    GenServer.call(session, :list_providers)
  end

  @doc """
  Clears/revokes credentials for a specific provider.

  ## Parameters
    - `session`: Session manager PID or name
    - `provider`: Provider to clear

  ## Returns
    - `:ok`: Credentials cleared
    - `{:error, reason}`: Failed to clear
  """
  @spec clear_provider(pid(), ProviderAuth.provider()) :: :ok | {:error, term()}
  def clear_provider(session, provider) do
    GenServer.call(session, {:clear_provider, provider})
  end

  # GenServer Callbacks

  @impl GenServer
  def init(user_id) do
    state = %SessionState{
      user_id: user_id,
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }

    Logger.info("Started session manager for user: #{user_id}")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:set_active_provider, provider, method}, _from, state) do
    case ensure_provider_context(state, provider, method) do
      {:ok, updated_state, auth_context} ->
        new_state = %{
          updated_state
          | active_provider: provider,
            last_activity: DateTime.utc_now()
        }

        Logger.info("Set active provider to #{provider} for user #{state.user_id}")
        {:reply, {:ok, auth_context}, new_state}

      {:error, reason} ->
        Logger.error("Failed to set active provider #{provider}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_active_provider, _from, state) do
    case state.active_provider do
      nil ->
        {:reply, {:error, :no_active_provider}, state}

      provider ->
        case Map.get(state.provider_contexts, provider) do
          nil ->
            {:reply, {:error, :context_not_found}, state}

          context ->
            updated_state = %{state | last_activity: DateTime.utc_now()}
            {:reply, {:ok, {provider, context}}, updated_state}
        end
    end
  end

  @impl GenServer
  def handle_call({:get_provider_context, provider}, _from, state) do
    case ensure_provider_context(state, provider, nil) do
      {:ok, updated_state, auth_context} ->
        new_state = %{updated_state | last_activity: DateTime.utc_now()}
        {:reply, {:ok, auth_context}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:refresh_all_credentials, _from, state) do
    {updated_contexts, failed_providers} = refresh_provider_contexts(state)

    updated_state = %{
      state
      | provider_contexts: updated_contexts,
        last_activity: DateTime.utc_now()
    }

    if Enum.empty?(failed_providers) do
      Logger.info("Successfully refreshed all provider credentials for user #{state.user_id}")
      {:reply, :ok, updated_state}
    else
      Logger.warning(
        "Failed to refresh some providers for user #{state.user_id}: #{inspect(failed_providers)}"
      )

      {:reply, {:error, failed_providers}, updated_state}
    end
  end

  @impl GenServer
  def handle_call(:list_providers, _from, state) do
    available_providers = Auth.get_available_providers()

    provider_status =
      Enum.into(available_providers, %{}, fn {provider, _methods} ->
        {provider, get_provider_status(state, provider)}
      end)

    updated_state = %{state | last_activity: DateTime.utc_now()}
    {:reply, provider_status, updated_state}
  end

  @impl GenServer
  def handle_call({:clear_provider, provider}, _from, state) do
    case Auth.revoke_credentials(state.user_id, provider) do
      :ok ->
        updated_contexts = Map.delete(state.provider_contexts, provider)

        active_provider =
          if state.active_provider == provider, do: nil, else: state.active_provider

        updated_state = %{
          state
          | provider_contexts: updated_contexts,
            active_provider: active_provider,
            last_activity: DateTime.utc_now()
        }

        Logger.info("Cleared provider #{provider} for user #{state.user_id}")
        {:reply, :ok, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private Functions

  defp ensure_provider_context(state, provider, method) do
    case Map.get(state.provider_contexts, provider) do
      nil ->
        load_provider_context(state, provider, method)

      existing_context ->
        # Validate existing context is still valid
        case validate_context(existing_context) do
          :ok ->
            {:ok, state, existing_context}

          {:error, _} ->
            # Context is invalid, reload
            load_provider_context(state, provider, method)
        end
    end
  end

  defp load_provider_context(state, provider, method) do
    case Auth.get_credentials(state.user_id, provider, method) do
      {:ok, auth_result} ->
        updated_contexts = Map.put(state.provider_contexts, provider, auth_result.auth_context)
        updated_state = %{state | provider_contexts: updated_contexts}
        {:ok, updated_state, auth_result.auth_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_context(%{credentials: %{expires_at: expires_at}}) when not is_nil(expires_at) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
      :ok
    else
      {:error, :expired}
    end
  end

  defp validate_context(_), do: :ok

  defp refresh_provider_contexts(state) do
    {updated_contexts, failed_providers} =
      state.provider_contexts
      |> Enum.reduce({%{}, []}, fn {provider, _context}, {acc_contexts, acc_failed} ->
        case Auth.get_credentials(state.user_id, provider) do
          {:ok, auth_result} ->
            {Map.put(acc_contexts, provider, auth_result.auth_context), acc_failed}

          {:error, _reason} ->
            {acc_contexts, [provider | acc_failed]}
        end
      end)

    {updated_contexts, failed_providers}
  end

  defp get_provider_status(state, provider) do
    if Map.has_key?(state.provider_contexts, provider) do
      :authenticated
    else
      case Auth.get_credentials(state.user_id, provider) do
        {:ok, _} -> :authenticated
        {:error, _} -> :needs_auth
      end
    end
  end
end
