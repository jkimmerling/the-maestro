defmodule TheMaestro.Providers.LLMProvider do
  @moduledoc """
  Behaviour for LLM (Large Language Model) providers.

  This behaviour defines a contract for interacting with different LLM providers
  in a model-agnostic way. All providers must implement the callbacks defined here
  to ensure consistent interfaces across different LLM services.
  """

  @typedoc """
  Authentication context containing credentials and configuration needed
  to authenticate with the LLM provider.
  """
  @type auth_context :: %{
          type: :api_key | :oauth | :service_account,
          credentials: map(),
          config: map()
        }

  @typedoc """
  A message in the conversation format expected by LLM providers.
  """
  @type message :: %{
          role: :user | :assistant | :system,
          content: String.t()
        }

  @typedoc """
  Options for text completion requests.
  """
  @type completion_opts :: %{
          temperature: float(),
          max_tokens: integer(),
          model: String.t()
        }

  @typedoc """
  Tool definition for function calling capabilities.
  """
  @type tool_definition :: %{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @typedoc """
  Options for tool-enabled completion requests.
  """
  @type tool_completion_opts :: %{
          temperature: float(),
          max_tokens: integer(),
          model: String.t(),
          tools: [tool_definition()]
        }

  @typedoc """
  Successful response from a text completion request.
  """
  @type completion_response :: %{
          content: String.t(),
          model: String.t(),
          usage: map()
        }

  @typedoc """
  Successful response from a tool-enabled completion request.
  """
  @type tool_completion_response :: %{
          content: String.t() | nil,
          tool_calls: [map()],
          model: String.t(),
          usage: map()
        }

  @typedoc """
  Model information returned by list_models/1.
  """
  @type model_info :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          context_length: integer() | nil,
          multimodal: boolean(),
          function_calling: boolean(),
          cost_tier: :economy | :balanced | :premium
        }

  @doc """
  Initializes authentication for the provider.

  This callback should handle different authentication methods (API keys, OAuth, service accounts)
  and return an auth_context that will be passed to subsequent requests.

  ## Parameters
    - `config`: Configuration map containing authentication details

  ## Returns
    - `{:ok, auth_context}`: Successfully initialized authentication
    - `{:error, reason}`: Authentication initialization failed
  """
  @callback initialize_auth(config :: map()) :: {:ok, auth_context()} | {:error, term()}

  @doc """
  Performs a text completion request.

  ## Parameters
    - `auth_context`: Authentication context from initialize_auth/1
    - `messages`: List of conversation messages
    - `opts`: Completion options

  ## Returns
    - `{:ok, completion_response}`: Successful completion
    - `{:error, reason}`: Request failed
  """
  @callback complete_text(auth_context(), [message()], completion_opts()) ::
              {:ok, completion_response()} | {:error, term()}

  @doc """
  Performs a tool-enabled completion request.

  This allows the LLM to call functions/tools as part of its response.

  ## Parameters
    - `auth_context`: Authentication context from initialize_auth/1
    - `messages`: List of conversation messages
    - `opts`: Tool completion options including available tools

  ## Returns
    - `{:ok, tool_completion_response}`: Successful completion (may include tool calls)
    - `{:error, reason}`: Request failed
  """
  @callback complete_with_tools(auth_context(), [message()], tool_completion_opts()) ::
              {:ok, tool_completion_response()} | {:error, term()}

  @doc """
  Refreshes authentication credentials if needed.

  This callback should handle token refresh for OAuth-based authentication
  or validate and refresh other credential types as needed.

  ## Parameters
    - `auth_context`: Current authentication context

  ## Returns
    - `{:ok, auth_context}`: Successfully refreshed authentication
    - `{:error, reason}`: Refresh failed
  """
  @callback refresh_auth(auth_context()) :: {:ok, auth_context()} | {:error, term()}

  @doc """
  Validates the current authentication status.

  ## Parameters
    - `auth_context`: Authentication context to validate

  ## Returns
    - `:ok`: Authentication is valid
    - `{:error, reason}`: Authentication is invalid or expired
  """
  @callback validate_auth(auth_context()) :: :ok | {:error, term()}

  @doc """
  Lists available models for the provider.

  This callback should fetch the current list of available models from the provider's API.

  ## Parameters
    - `auth_context`: Authentication context from initialize_auth/1

  ## Returns
    - `{:ok, [model_info]}`: Successfully retrieved model list
    - `{:error, reason}`: Failed to retrieve models
  """
  @callback list_models(auth_context()) :: {:ok, [model_info()]} | {:error, term()}
end
