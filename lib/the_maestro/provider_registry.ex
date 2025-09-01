defmodule TheMaestro.ProviderRegistry do
  @moduledoc """
  Provider registry that handles automatic discovery and validation on startup.

  This GenServer:
  1. Scans for available provider modules on application start
  2. Validates behavior compliance for discovered providers
  3. Caches provider registry for runtime performance
  4. Logs discovered providers and their capabilities during startup
  """

  use GenServer
  require Logger

  alias TheMaestro.Provider
  alias TheMaestro.Types

  @typedoc "Provider registry entry"
  @type registry_entry :: %{
          provider: Types.provider(),
          operations: [Provider.operation()],
          capabilities: map(),
          compliance_status: :valid | :invalid,
          errors: [String.t()]
        }

  # Client API

  @doc """
  Starts the provider registry GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the cached provider registry.
  """
  @spec get_registry() :: [registry_entry()]
  def get_registry do
    GenServer.call(__MODULE__, :get_registry)
  end

  @doc """
  Gets registry entry for a specific provider.
  """
  @spec get_provider(Types.provider()) :: registry_entry() | nil
  def get_provider(provider) do
    GenServer.call(__MODULE__, {:get_provider, provider})
  end

  @doc """
  Forces a refresh of the provider registry.
  """
  @spec refresh_registry() :: :ok
  def refresh_registry do
    GenServer.cast(__MODULE__, :refresh_registry)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("[ProviderRegistry] Starting provider discovery and validation...")

    registry = discover_and_validate_providers()
    log_registry_results(registry)

    {:ok, %{registry: registry}}
  end

  @impl true
  def handle_call(:get_registry, _from, state) do
    {:reply, state.registry, state}
  end

  @impl true
  def handle_call({:get_provider, provider}, _from, state) do
    entry = Enum.find(state.registry, &(&1.provider == provider))
    {:reply, entry, state}
  end

  @impl true
  def handle_cast(:refresh_registry, _state) do
    Logger.info("[ProviderRegistry] Refreshing provider registry...")
    registry = discover_and_validate_providers()
    log_registry_results(registry)
    {:noreply, %{registry: registry}}
  end

  # Private Functions

  @spec discover_and_validate_providers() :: [registry_entry()]
  defp discover_and_validate_providers do
    potential_providers = TheMaestro.Provider.list_providers()
    operations = [:oauth, :api_key, :streaming, :models]

    Enum.map(potential_providers, fn provider ->
      {available_ops, errors} = discover_provider_operations(provider, operations)

      {:ok, caps} = Provider.provider_capabilities(provider)
      capabilities = Map.from_struct(caps)

      compliance_status = if Enum.empty?(errors), do: :valid, else: :invalid

      %{
        provider: provider,
        operations: available_ops,
        capabilities: capabilities,
        compliance_status: compliance_status,
        errors: errors
      }
    end)
  end

  @spec discover_provider_operations(Types.provider(), [Provider.operation()]) ::
          {[Provider.operation()], [String.t()]}
  defp discover_provider_operations(provider, operations) do
    results = Enum.map(operations, &validate_operation(provider, &1))

    available_ops =
      results
      |> Enum.filter(fn {_op, status, _errors} -> status == :valid end)
      |> Enum.map(fn {op, _status, _errors} -> op end)

    all_errors =
      results
      |> Enum.flat_map(fn {_op, _status, errors} -> errors end)

    {available_ops, all_errors}
  end

  @spec validate_operation(Types.provider(), Provider.operation()) ::
          {Provider.operation(), :valid | :found_but_invalid | :not_found, [String.t()]}
  defp validate_operation(provider, operation) do
    case Provider.resolve_module(provider, operation) do
      {:ok, mod} ->
        case Provider.validate_provider_compliance(mod) do
          :ok ->
            {operation, :valid, []}

          {:error, compliance_errors} ->
            {operation, :found_but_invalid, compliance_errors}
        end

      {:error, :module_not_found} ->
        {operation, :not_found,
         ["Module not found: #{inspect(Provider.build_module_path(provider, operation))}"]}
    end
  end

  @spec log_registry_results([registry_entry()]) :: :ok
  defp log_registry_results(registry) do
    valid_providers = Enum.filter(registry, &(&1.compliance_status == :valid))
    invalid_providers = Enum.filter(registry, &(&1.compliance_status == :invalid))

    Logger.info(
      "[ProviderRegistry] Discovery complete: #{length(valid_providers)} valid, #{length(invalid_providers)} invalid providers"
    )

    # Log valid providers
    Enum.each(valid_providers, fn entry ->
      operations_str = entry.operations |> Enum.map(&to_string/1) |> Enum.join(", ")
      Logger.info("[ProviderRegistry] ✅ #{entry.provider}: [#{operations_str}]")
    end)

    # Log invalid providers with errors
    Enum.each(invalid_providers, fn entry ->
      operations_str = entry.operations |> Enum.map(&to_string/1) |> Enum.join(", ")

      Logger.warning(
        "[ProviderRegistry] ❌ #{entry.provider}: [#{operations_str}] - #{length(entry.errors)} issues"
      )

      Enum.each(entry.errors, fn error ->
        Logger.warning("[ProviderRegistry]   - #{error}")
      end)
    end)

    :ok
  end
end
