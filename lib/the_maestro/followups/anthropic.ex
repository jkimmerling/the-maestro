defmodule TheMaestro.Followups.Anthropic do
  @moduledoc """
  Builder for Anthropic follow-up messages that adhere to the Golden Standard.

  Produces an append-only messages array:
  prior history ++ [assistant(text? + tool_use...), user(tool_result...)]
  """

  alias TheMaestro.Tools.Runtime

  @type call ::
          %{
            required(:id) => String.t(),
            required(:name) => String.t(),
            required(:arguments) => String.t()
          }
          | %{required(String.t()) => String.t()}

  @spec build([map()], [call()], String.t(), keyword()) :: {[map()], list()}
  def build(original_messages, calls, prior_answer_text \\ "", opts \\ []) do
    base_cwd = Keyword.get(opts, :base_cwd, File.cwd!())
    outputs = compute_outputs(calls, Keyword.get(opts, :outputs), base_cwd)
    tool_uses = build_tool_uses(calls)
    tool_results = build_tool_results(outputs)
    assistant_blocks = build_assistant_blocks(prior_answer_text, tool_uses)
    anth_messages = original_messages ++ [%{"role" => "assistant", "content" => assistant_blocks}, %{"role" => "user", "content" => tool_results}]
    {anth_messages, outputs}
  end

  defp compute_outputs(_calls, provided, _cwd) when is_list(provided), do: provided

  defp compute_outputs(calls, nil, base_cwd) do
    Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
      case Runtime.exec(name, args, base_cwd) do
        {:ok, payload} -> {id, {:ok, payload}}
        {:error, reason} -> {id, {:error, to_string(reason)}}
      end
    end)
  end

  defp build_tool_uses(calls) do
    Enum.map(calls, fn %{"id" => id, "name" => name, "arguments" => args} ->
      input = case Jason.decode(args || "") do
        {:ok, parsed} -> parsed
        _ -> %{}
      end

      %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
    end)
  end

  defp build_tool_results(outputs) do
    Enum.map(outputs, fn {id, result} ->
      case result do
        {:ok, payload} -> %{"type" => "tool_result", "tool_use_id" => id, "content" => payload}
        {:error, reason} -> %{"type" => "tool_result", "tool_use_id" => id, "content" => to_string(reason)}
      end
    end)
  end

  defp build_assistant_blocks(prior_answer_text, tool_uses) do
    text_block =
      case String.trim(to_string(prior_answer_text || "")) do
        "" -> []
        txt -> [%{"type" => "text", "text" => txt, "cache_control" => %{"type" => "ephemeral"}}]
      end

    text_block ++ tool_uses
  end
end
