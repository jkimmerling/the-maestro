defmodule TheMaestro.Domain.StreamEvent do
  @moduledoc """
  Canonical streaming event consumed by Sessions.Manager and LiveView.

  Wraps provider-specific event maps in a stable, typed envelope while keeping
  the raw map for debugging/tracing.
  """

  alias TheMaestro.Domain.{ToolCall, Usage}

  @enforce_keys [:type]
  defstruct type: :content,
            content: nil,
            tool_calls: [],
            usage: nil,
            raw: %{}

  @type type :: :content | :function_call | :usage | :done | :error
  @type t :: %__MODULE__{
          type: type(),
          content: String.t() | nil,
          tool_calls: [ToolCall.t()],
          usage: Usage.t() | nil,
          raw: map()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(raw) when is_map(raw) do
    {:ok,
     %__MODULE__{
       type: normalize_type(Map.get(raw, :type) || Map.get(raw, "type")),
       content: Map.get(raw, :content) || Map.get(raw, "content"),
       tool_calls: build_tool_calls(raw),
       usage: build_usage(raw),
       raw: raw
     }}
  end

  @spec new!(map()) :: t()
  def new!(raw) do
    {:ok, ev} = new(raw)
    ev
  end

  @doc """
  Convenience accessor for `content`.
  """
  @spec content(t()) :: String.t() | nil
  def content(%__MODULE__{content: c}), do: c

  @doc """
  Convenience accessor for `usage`.
  """
  @spec usage(t()) :: Usage.t() | nil
  def usage(%__MODULE__{usage: u}), do: u

  @doc """
  Convenience accessor for `tool_calls`.
  """
  @spec tool_calls(t()) :: [ToolCall.t()]
  def tool_calls(%__MODULE__{tool_calls: tc}), do: tc || []

  defp normalize_type(t) when t in [:content, :function_call, :usage, :done, :error], do: t

  defp normalize_type(t) when is_binary(t) do
    case t do
      "content" -> :content
      "function_call" -> :function_call
      "usage" -> :usage
      "done" -> :done
      "error" -> :error
      _ -> :content
    end
  end

  defp normalize_type(_), do: :content

  defp build_usage(raw) do
    usage = Map.get(raw, :usage) || Map.get(raw, "usage")
    if is_map(usage), do: Usage.new!(usage), else: nil
  end

  defp build_tool_calls(raw) do
    calls = Map.get(raw, :tool_calls) || Map.get(raw, "tool_calls") || []
    if is_list(calls), do: Enum.flat_map(calls, &wrap_call/1), else: []
  end

  defp wrap_call(%ToolCall{} = c), do: [c]

  defp wrap_call(m) when is_map(m) do
    case ToolCall.new(m) do
      {:ok, c} -> [c]
      _ -> []
    end
  end

  defp wrap_call(_), do: []
end
