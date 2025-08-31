defmodule TheMaestro.Streaming.AnthropicHandler do
  @moduledoc """
  Anthropic Claude-specific streaming event handler.

  Handles Anthropic Claude API streaming events, including:
  - Text content deltas
  - Tool use streaming
  - Usage statistics
  - Error conditions

  ## Anthropic Event Types

  Based on Anthropic's MessageStreamEvent format:
  - `message_start` - Initial message with usage info
  - `content_block_start` - Start of content block (text or tool_use)
  - `content_block_delta` - Content deltas (text_delta or input_json_delta)
  - `content_block_stop` - End of content block
  - `message_delta` - Message metadata updates (usage)
  - `message_stop` - End of message

  ## State Management

  The handler maintains state to track:
  - Current tool use blocks being assembled
  - Usage statistics updates
  - Content block types and states

  ## Tool Use Support

  Anthropic streams tool use calls across multiple events:
  1. `content_block_start` with tool_use type and metadata
  2. Multiple `content_block_delta` events with input JSON deltas
  3. `content_block_stop` to complete the tool use

  """

  use TheMaestro.Streaming.StreamHandler

  require Logger

  # Process dictionary keys for state management
  @current_tool_call_key :anthropic_current_tool_call
  @current_usage_key :anthropic_current_usage

  @doc """
  Handle Anthropic streaming events.
  """
  def handle_event(%{event_type: "error", data: error_data}, _opts) do
    [error_message("Stream error: #{error_data}")]
  end

  def handle_event(%{event_type: "done", data: "[DONE]"}, _opts) do
    # Clean up state and emit done message
    cleanup_state()
    [done_message()]
  end

  def handle_event(%{event_type: event_type, data: data}, opts)
      when event_type in ["message", "delta"] do
    case safe_json_decode(data) do
      {:ok, event} -> handle_anthropic_event(event, opts)
      {:error, reason} -> [error_message(reason)]
    end
  end

  def handle_event(_event, _opts) do
    # Ignore unknown event types
    []
  end

  # Handle parsed Anthropic events
  defp handle_anthropic_event(%{"type" => "message_start"} = event, _opts) do
    # Extract initial usage information
    messages = []

    if usage = get_in(event, ["message", "usage"]) do
      current_usage = %{
        input_tokens: Map.get(usage, "input_tokens", 0),
        output_tokens: Map.get(usage, "output_tokens", 0)
      }

      put_current_usage(current_usage)

      # Emit initial usage message
      usage_msg =
        usage_message(%{
          prompt_tokens: current_usage.input_tokens,
          completion_tokens: current_usage.output_tokens,
          total_tokens: current_usage.input_tokens + current_usage.output_tokens
        })

      [usage_msg | messages]
    else
      messages
    end
  end

  defp handle_anthropic_event(%{"type" => "content_block_start"} = event, _opts) do
    case get_in(event, ["content_block", "type"]) do
      "tool_use" -> handle_tool_use_start(event)
      _ -> []
    end
  end

  defp handle_anthropic_event(%{"type" => "content_block_delta"} = event, _opts) do
    case get_in(event, ["delta", "type"]) do
      "text_delta" -> handle_text_delta(event)
      "input_json_delta" -> handle_tool_input_delta(event)
      _ -> []
    end
  end

  defp handle_anthropic_event(%{"type" => "content_block_stop"} = _event, _opts) do
    # Complete any pending tool call
    handle_tool_use_complete()
  end

  defp handle_anthropic_event(%{"type" => "message_delta"} = event, _opts) do
    # Update usage information
    handle_usage_update(event)
  end

  defp handle_anthropic_event(%{"type" => "message_stop"} = _event, _opts) do
    # Clean up state and emit final usage
    messages = []

    if current_usage = get_current_usage() do
      usage_msg =
        usage_message(%{
          prompt_tokens: current_usage.input_tokens,
          completion_tokens: current_usage.output_tokens,
          total_tokens: current_usage.input_tokens + current_usage.output_tokens
        })

      _messages = [usage_msg | messages]
    end

    cleanup_state()
    [done_message() | messages]
  end

  defp handle_anthropic_event(event, _opts) do
    # Log unknown events for debugging
    Logger.debug("Unknown Anthropic event type: #{inspect(event)}")
    []
  end

  # Handle text content deltas
  defp handle_text_delta(event) do
    case get_in(event, ["delta", "text"]) do
      nil -> []
      text -> [content_message(text)]
    end
  end

  # Handle tool use block start
  defp handle_tool_use_start(event) do
    content_block = Map.get(event, "content_block", %{})

    tool_call = %{
      id: Map.get(content_block, "id"),
      name: Map.get(content_block, "name"),
      input: ""
    }

    put_current_tool_call(tool_call)
    # Don't emit until complete
    []
  end

  # Handle tool input JSON deltas
  defp handle_tool_input_delta(event) do
    if current_tool_call = get_current_tool_call() do
      partial_json = get_in(event, ["delta", "partial_json"]) || ""
      updated_call = %{current_tool_call | input: current_tool_call.input <> partial_json}
      put_current_tool_call(updated_call)
    end

    # Don't emit until complete
    []
  end

  alias TheMaestro.Streaming.{Function, FunctionCall}

  # Complete tool use
  defp handle_tool_use_complete do
    if current_tool_call = get_current_tool_call() do
      # Parse the completed input JSON
      input =
        case Jason.decode(current_tool_call.input) do
          {:ok, parsed} -> parsed
          {:error, _} -> current_tool_call.input
        end

      # Create function call message in OpenAI format for consistency
      function_call = %FunctionCall{
        id: current_tool_call.id,
        function: %Function{name: current_tool_call.name, arguments: Jason.encode!(input)}
      }

      # Clear current tool call
      put_current_tool_call(nil)

      [function_call_message([function_call])]
    else
      []
    end
  end

  # Handle usage updates
  defp handle_usage_update(event) do
    if usage = get_in(event, ["usage"]) do
      current_usage = get_current_usage() || %{input_tokens: 0, output_tokens: 0}

      updated_usage = %{
        input_tokens: Map.get(usage, "input_tokens", current_usage.input_tokens),
        output_tokens: Map.get(usage, "output_tokens", current_usage.output_tokens)
      }

      put_current_usage(updated_usage)

      # Emit updated usage
      usage_msg =
        usage_message(%{
          prompt_tokens: updated_usage.input_tokens,
          completion_tokens: updated_usage.output_tokens,
          total_tokens: updated_usage.input_tokens + updated_usage.output_tokens
        })

      [usage_msg]
    else
      []
    end
  end

  # State management helpers
  defp get_current_tool_call do
    Process.get(@current_tool_call_key)
  end

  defp put_current_tool_call(tool_call) do
    if tool_call do
      Process.put(@current_tool_call_key, tool_call)
    else
      Process.delete(@current_tool_call_key)
    end
  end

  defp get_current_usage do
    Process.get(@current_usage_key)
  end

  defp put_current_usage(usage) do
    Process.put(@current_usage_key, usage)
  end

  defp cleanup_state do
    Process.delete(@current_tool_call_key)
    Process.delete(@current_usage_key)
  end
end
