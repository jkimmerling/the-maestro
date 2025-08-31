defmodule TheMaestro.Provider do
  @moduledoc """
  Universal provider interface for authentication, streaming, and model operations.

  This module resolves provider-specific modules dynamically and exposes a
  consistent API surface across providers.
  """

  alias TheMaestro.Providers.Capabilities
  alias TheMaestro.Types

  @typedoc "Provider operation category"
  @type operation :: :oauth | :api_key | :streaming | :models

  @typedoc "Opaque session identifier"
  @type session_id :: Types.session_id()

  @typedoc "Chat messages"
  @type messages :: [map()]

  # Public API

  @spec create_session(Types.provider(), Types.auth_type(), keyword()) ::
          {:ok, session_id()} | {:error, term()}
  def create_session(provider, auth_type, opts \\ []) do
    if is_list(opts) do
      with :ok <- validate_provider(provider),
           :ok <- validate_auth_type(auth_type),
           :ok <- validate_create_session_opts(opts),
           {:ok, mod} <- resolve_module(provider, auth_type_to_operation(auth_type)) do
        if function_exported?(mod, :create_session, 1) do
          mod.create_session(opts)
        else
          {:error, :not_implemented}
        end
      else
        {:error, _} = err -> err
      end
    else
      {:error, :invalid_options}
    end
  end

  @spec delete_session(Types.provider(), Types.auth_type(), session_id()) ::
          :ok | {:error, term()}
  def delete_session(provider, auth_type, session_name) when is_binary(session_name) do
    with :ok <- validate_provider(provider),
         :ok <- validate_auth_type(auth_type) do
      # Delete named session from our storage for idempotency
      case TheMaestro.SavedAuthentication.delete_named_session(provider, auth_type, session_name) do
        :ok -> :ok
        {:error, :not_found} -> :ok
        {:error, _} = err -> err
      end
    end
  end

  @spec refresh_tokens(Types.provider(), session_id()) :: {:ok, map()} | {:error, term()}
  def refresh_tokens(provider, session_id) do
    with {:ok, mod} <- resolve_module(provider, :oauth),
         true <- function_exported?(mod, :refresh_tokens, 1) || {:error, :not_implemented} do
      mod.refresh_tokens(session_id)
    end
  end

  @spec list_models(Types.provider(), Types.auth_type(), session_id()) ::
          {:ok, [Types.model_id()]} | {:error, term()}
  def list_models(provider, auth_type, session_name) when is_binary(session_name) do
    with :ok <- validate_provider(provider),
         :ok <- validate_auth_type(auth_type),
         :ok <- ensure_session_exists(provider, auth_type, session_name),
         {:ok, mod} <- resolve_module(provider, :models) do
      if function_exported?(mod, :list_models, 1),
        do: mod.list_models(session_name),
        else: {:error, :not_implemented}
    else
      {:error, _} = err -> err
    end
  end

  @spec stream_chat(Types.provider(), session_id(), messages(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(provider, session_name, messages, opts \\ []) when is_list(messages) do
    with :ok <- validate_provider(provider),
         :ok <- ensure_session_exists_for_any_auth(provider, session_name),
         :ok <- validate_messages(messages),
         {:ok, mod} <- resolve_module(provider, :streaming) do
      if function_exported?(mod, :stream_chat, 3),
        do: mod.stream_chat(session_name, messages, opts),
        else: {:error, :not_implemented}
    else
      {:error, _} = err -> err
    end
  end

  @spec list_providers() :: [Types.provider()]
  def list_providers do
    # For now, return static list. In future, could scan filesystem for provider modules
    available_providers = [:openai, :anthropic, :gemini]

    # Filter to only return providers that have at least one working module
    Enum.filter(available_providers, &provider_has_modules?/1)
  end

  @spec provider_capabilities(Types.provider()) :: {:ok, Capabilities.t()} | {:error, term()}
  def provider_capabilities(provider) do
    with :ok <- validate_provider(provider) do
      # Basic introspection-based fallback. Provider modules may expose a
      # `capabilities/0` function for richer metadata; otherwise we return a
      # reasonable default based on known providers.
      default = %Capabilities{
        provider: provider,
        auth_types: [:oauth, :api_key],
        features: [:streaming, :models],
        limits: %{}
      }

      modules = [:oauth, :api_key, :streaming, :models]

      implemented =
        modules
        |> Enum.filter(fn op -> match?({:ok, _}, resolve_module(provider, op)) end)

      {:ok,
       %Capabilities{
         default
         | features: Enum.uniq(default.features ++ feature_from_ops(implemented))
       }}
    end
  end

  # Resolution helpers

  @spec resolve_module(Types.provider(), operation()) ::
          {:ok, module()} | {:error, :module_not_found}
  def resolve_module(provider, operation) do
    mod = build_module_path(provider, operation)

    if Code.ensure_loaded?(mod) do
      {:ok, mod}
    else
      {:error, :module_not_found}
    end
  end

  @spec build_module_path(Types.provider(), operation()) :: module()
  def build_module_path(provider, operation) do
    Module.concat([
      TheMaestro,
      :Providers,
      provider_to_module(provider),
      operation_to_module(operation)
    ])
  end

  @spec validate_provider_compliance(module()) :: :ok | {:error, [String.t()]}
  def validate_provider_compliance(mod) when is_atom(mod) do
    errors = []

    errors =
      if function_exported?(mod, :create_session, 1),
        do: errors,
        else: ["create_session/1 not implemented" | errors]

    errors =
      if function_exported?(mod, :delete_session, 1),
        do: errors,
        else: ["delete_session/1 not implemented" | errors]

    errors =
      if function_exported?(mod, :refresh_tokens, 1),
        do: errors,
        else: ["refresh_tokens/1 not implemented" | errors]

    errors =
      if function_exported?(mod, :stream_chat, 3),
        do: errors,
        else: ["stream_chat/3 not implemented" | errors]

    errors =
      if function_exported?(mod, :list_models, 1),
        do: errors,
        else: ["list_models/1 not implemented" | errors]

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  # Session name validation

  @doc """
  Validates a session name for use with named authentication sessions.

  Session names must:
  - Be 3-50 characters long
  - Contain only alphanumeric characters, underscores, and hyphens
  - Not be empty or nil

  ## Examples

      iex> TheMaestro.Provider.validate_session_name("work_claude")
      :ok
      
      iex> TheMaestro.Provider.validate_session_name("a")
      {:error, "Session name must be between 3 and 50 characters"}
      
      iex> TheMaestro.Provider.validate_session_name("invalid name!")
      {:error, "Session name must contain only letters, numbers, underscores, and hyphens"}
  """
  @spec validate_session_name(String.t() | nil) :: :ok | {:error, String.t()}
  def validate_session_name(nil), do: {:error, "Session name is required"}
  def validate_session_name(""), do: {:error, "Session name cannot be empty"}

  def validate_session_name(name) when is_binary(name) do
    cond do
      String.length(name) < 3 or String.length(name) > 50 ->
        {:error, "Session name must be between 3 and 50 characters"}

      not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, name) ->
        {:error, "Session name must contain only letters, numbers, underscores, and hyphens"}

      true ->
        :ok
    end
  end

  def validate_session_name(_), do: {:error, "Session name must be a string"}

  @doc """
  Normalizes a session name for consistent storage and retrieval.

  Converts the name to lowercase and replaces spaces with underscores.

  ## Examples

      iex> TheMaestro.Provider.normalize_session_name("Work Claude")
      "work_claude"
      
      iex> TheMaestro.Provider.normalize_session_name("PERSONAL-GPT")
      "personal-gpt"
  """
  @spec normalize_session_name(String.t()) :: String.t()
  def normalize_session_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(" ", "_")
  end

  # Internal helpers

  defp auth_type_to_operation(:oauth), do: :oauth
  defp auth_type_to_operation(:api_key), do: :api_key
  defp auth_type_to_operation(_), do: :invalid

  defp provider_to_module(:openai), do: OpenAI
  defp provider_to_module(:anthropic), do: Anthropic
  defp provider_to_module(:gemini), do: Gemini

  defp provider_to_module(other) do
    other
    |> to_string()
    |> Macro.camelize()
    |> String.to_atom()
  end

  defp operation_to_module(:oauth), do: OAuth
  defp operation_to_module(:api_key), do: APIKey
  defp operation_to_module(:streaming), do: Streaming
  defp operation_to_module(:models), do: Models
  defp operation_to_module(_), do: :invalid

  defp provider_has_modules?(provider) do
    [:oauth, :api_key, :streaming, :models]
    |> Enum.any?(fn operation ->
      case resolve_module(provider, operation) do
        {:ok, _mod} -> true
        {:error, :module_not_found} -> false
      end
    end)
  end

  defp feature_from_ops(ops) do
    ops
    |> Enum.flat_map(fn
      :streaming -> [:streaming]
      :models -> [:models]
      _ -> []
    end)
  end

  # ===== Validation helpers =====

  @spec validate_provider(term()) :: :ok | {:error, :invalid_provider}
  defp validate_provider(provider) when provider in [:openai, :anthropic, :gemini], do: :ok
  defp validate_provider(_), do: {:error, :invalid_provider}

  @spec validate_auth_type(term()) :: :ok | {:error, :invalid_auth_type}
  defp validate_auth_type(auth_type) when auth_type in [:oauth, :api_key], do: :ok
  defp validate_auth_type(_), do: {:error, :invalid_auth_type}

  @spec validate_create_session_opts(keyword()) :: :ok | {:error, term()}
  defp validate_create_session_opts(opts) do
    name = Keyword.get(opts, :name)
    credentials = Keyword.get(opts, :credentials)

    with :ok <- validate_session_name_presence_and_format(name),
         :ok <- validate_credentials_presence_and_shape(credentials) do
      :ok
    else
      {:error, _} = err -> err
    end
  end

  defp validate_session_name_presence_and_format(nil), do: {:error, :missing_session_name}

  defp validate_session_name_presence_and_format(name) do
    case validate_session_name(name) do
      :ok -> :ok
      {:error, _} -> {:error, :invalid_session_name}
    end
  end

  defp validate_credentials_presence_and_shape(nil), do: {:error, :missing_credentials}

  defp validate_credentials_presence_and_shape(%{} = cred) when map_size(cred) == 0,
    do: {:error, :invalid_credentials}

  defp validate_credentials_presence_and_shape(%{}), do: :ok
  defp validate_credentials_presence_and_shape(_), do: {:error, :invalid_credentials}

  @spec ensure_session_exists(Types.provider(), Types.auth_type(), String.t()) ::
          :ok | {:error, :session_not_found}
  defp ensure_session_exists(provider, auth_type, name) do
    case TheMaestro.SavedAuthentication.get_by_provider_and_name(provider, auth_type, name) do
      nil -> {:error, :session_not_found}
      _ -> :ok
    end
  end

  @spec ensure_session_exists_for_any_auth(Types.provider(), String.t()) ::
          :ok | {:error, :session_not_found}
  defp ensure_session_exists_for_any_auth(provider, name) do
    case Enum.any?([:oauth, :api_key], fn auth ->
           TheMaestro.SavedAuthentication.get_by_provider_and_name(provider, auth, name) != nil
         end) do
      true -> :ok
      false -> {:error, :session_not_found}
    end
  end

  @spec validate_messages(term()) :: :ok | {:error, term()}
  defp validate_messages([]), do: {:error, :empty_messages}

  defp validate_messages(list) when is_list(list) do
    if Enum.all?(list, &is_map/1), do: :ok, else: {:error, :invalid_messages}
  end

  defp validate_messages(_), do: {:error, :invalid_messages}
end
