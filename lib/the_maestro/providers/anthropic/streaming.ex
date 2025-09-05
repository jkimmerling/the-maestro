defmodule TheMaestro.Providers.Anthropic.Streaming do
  @moduledoc """
  Anthropic streaming provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(session_id, messages, opts \\ []) do
    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        base_body = %{
          "model" => model,
          "messages" => messages,
          "max_tokens" => Keyword.get(opts, :max_tokens, 512),
          "tools" => anthropic_tools(),
          "tool_choice" => %{"type" => "any"},
          "stream" => true
        }

        # Claude Code parity: add system prompt for OAuth tokens
        body =
          case auth_type do
            :oauth ->
              Map.put(
                base_body,
                "system",
                "You are Claude Code, Anthropic's official CLI for Claude."
              )

            _ ->
              base_body
          end

        url = if auth_type == :oauth, do: "/v1/messages?beta=true", else: "/v1/messages"
        StreamingAdapter.stream_request(req, method: :post, url: url, json: body)
      end
    end
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(_event, state) do
    {[], state}
  end

  @doc """
  Stream a follow-up request that supplies tool results back to Anthropic.

  `messages` must be a full Anthropic messages array, typically including:
  - The prior user message
  - An assistant message with one or more `tool_use` blocks (ids must match)
  - A user message with corresponding `tool_result` blocks referencing `tool_use_id`
  """
  @spec stream_tool_followup(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_tool_followup(session_id, messages, opts \\ []) when is_list(messages) do
    with {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        body = %{
          "model" => model,
          "messages" => messages,
          "max_tokens" => Keyword.get(opts, :max_tokens, 512),
          "tools" => anthropic_tools(),
          "tool_choice" => %{"type" => "any"},
          "stream" => true
        }

        url = if auth_type == :oauth, do: "/v1/messages?beta=true", else: "/v1/messages"
        StreamingAdapter.stream_request(req, method: :post, url: url, json: body)
      end
    end
  end

  @spec detect_auth_type(String.t()) :: {:ok, :oauth | :api_key} | {:error, term()}
  defp detect_auth_type(session_id) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :oauth, session_id)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :api_key, session_id)) ->
        {:ok, :api_key}

      true ->
        {:error, :session_not_found}
    end
  end

  # ===== Tool definitions (Anthropic format) =====
  defp anthropic_tools do
    [shell_tool(), apply_patch_tool()]
  end

  defp shell_tool do
    %{
      # Anthropic tools: omit explicit type (defaults to tool schema) or set "type": "tool"
      "name" => "shell",
      "description" => "Runs a shell command and returns its output.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "The command to execute, e.g., ['bash','-lc','echo hi']."
          },
          "workdir" => %{"type" => "string", "description" => "Working directory (optional)."},
          "timeout_ms" => %{"type" => "number", "description" => "Timeout in ms (optional)."}
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  defp apply_patch_tool do
    %{
      "name" => "apply_patch",
      "description" => "Use the apply_patch tool to edit files in the workspace.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "input" => %{
            "type" => "string",
            "description" => "Entire contents of the apply_patch envelope."
          }
        },
        "required" => ["input"],
        "additionalProperties" => false
      }
    }
  end
end
