defmodule TheMaestro.Conversations.Translator do
  @moduledoc """
  Provider-agnostic chat translators.
  """

  @type canonical :: map()
  @type provider :: :openai | :anthropic | :gemini
  @type canonical_event :: map()

  @spec to_provider(canonical(), provider()) :: {:ok, list()} | {:error, term()}
  def to_provider(%{"messages" => msgs}, :openai), do: {:ok, Enum.map(msgs, &to_openai_msg/1)}
  def to_provider(%{"messages" => msgs}, :anthropic), do: {:ok, Enum.map(msgs, &to_openai_msg/1)}
  def to_provider(%{"messages" => msgs}, :gemini), do: {:ok, Enum.map(msgs, &to_gemini_msg/1)}
  def to_provider(_c, _), do: {:error, :invalid_canonical}

  @spec from_provider(map() | list() | binary(), provider()) ::
          {:ok, canonical()} | {:error, term()}
  def from_provider(text, _provider) when is_binary(text) do
    {:ok,
     %{
       "messages" => [
         %{"role" => "assistant", "content" => [%{"type" => "text", "text" => text}]}
       ]
     }}
  end

  def from_provider(msgs, :gemini) when is_list(msgs) do
    {:ok,
     %{
       "messages" =>
         Enum.map(msgs, fn %{"role" => role, "parts" => parts} ->
           %{"role" => role, "content" => Enum.map(parts, &gemini_part_to_text/1)}
         end)
     }}
  end

  def from_provider(msgs, _provider) when is_list(msgs) do
    {:ok,
     %{
       "messages" =>
         Enum.map(msgs, fn %{"role" => role, "content" => content} ->
           %{"role" => role, "content" => [%{"type" => "text", "text" => to_string(content)}]}
         end)
     }}
  end

  def from_provider(_payload, _), do: {:error, :unsupported_payload}

  @doc """
  Normalize provider-specific function calls/events into canonical event maps.

  Canonical event forms produced:
  - %{type: "function_call", calls: [%{"id" => id, "name" => name, "arguments" => args_json}]}
  - %{type: "function_call_output", "call_id" => id, "output" => output_json}
  - %{type: "usage", usage: %{prompt_tokens: n, completion_tokens: n, total_tokens: n}}
  - %{type: "content", delta: binary}
  """
  @spec events_to_canonical(provider(), any()) :: {:ok, [canonical_event()]} | {:error, term()}
  def events_to_canonical(:openai, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &openai_evt/1)}
  end

  def events_to_canonical(:anthropic, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &anthropic_evt/1)}
  end

  def events_to_canonical(:gemini, evts) when is_list(evts) do
    {:ok, Enum.flat_map(evts, &gemini_evt/1)}
  end

  def events_to_canonical(_, _), do: {:error, :unsupported_events}

  defp to_openai_msg(%{"role" => role} = m) do
    text = extract_text(m)
    %{"role" => role, "content" => text}
  end

  defp to_gemini_msg(%{"role" => role} = m) do
    text = extract_text(m)
    %{"role" => role, "parts" => [%{"text" => text}]}
  end

  defp extract_text(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{"type" => "text", "text" => t} -> t
      %{"text" => t} -> t
      t when is_binary(t) -> t
      _ -> ""
    end)
    |> Enum.join("\n")
  end

  defp extract_text(%{"content" => t}) when is_binary(t), do: t
  defp extract_text(_), do: ""
  defp gemini_part_to_text(%{"text" => t}), do: %{"type" => "text", "text" => t}
  defp gemini_part_to_text(%{"inlineData" => _}), do: %{"type" => "text", "text" => "[binary]"}
  defp gemini_part_to_text(_), do: %{"type" => "text", "text" => ""}

  # ==== Provider event normalizers ====
  defp openai_evt(%{type: :function_call, function_call: calls}) when is_list(calls) do
    [
      %{
        type: "function_call",
        calls:
          for %{id: id, function: %{name: name, arguments: args}} <- calls do
            %{"id" => id, "name" => name, "arguments" => args || ""}
          end
      }
    ]
  end

  defp openai_evt(%{type: :usage, usage: usage}) when is_map(usage) do
    [%{type: "usage", usage: usage}]
  end

  defp openai_evt(%{type: :content, content: delta}) when is_binary(delta),
    do: [%{type: "content", delta: delta}]

  defp openai_evt(_), do: []

  defp anthropic_evt(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    json = Jason.encode!(input)
    [%{type: "function_call", calls: [%{"id" => id, "name" => name, "arguments" => json}]}]
  end

  defp anthropic_evt(%{"type" => "input_json_delta", "delta" => delta}) when is_binary(delta) do
    [%{type: "content", delta: delta}]
  end

  defp anthropic_evt(%{"type" => "message_delta", "usage" => usage}) when is_map(usage) do
    # Map anthropic usage (input_tokens/output_tokens) to canonical keys when present
    usage2 =
      usage
      |> Map.new()
      |> case do
        %{"input_tokens" => p, "output_tokens" => c} ->
          %{prompt_tokens: p, completion_tokens: c, total_tokens: (p || 0) + (c || 0)}

        %{:input_tokens => p, :output_tokens => c} ->
          %{prompt_tokens: p, completion_tokens: c, total_tokens: (p || 0) + (c || 0)}

        other ->
          other
      end

    [%{type: "usage", usage: usage2}]
  end

  defp anthropic_evt(_), do: []

  defp gemini_evt(%{"functionCall" => %{"name" => name} = fc}) do
    args = Map.get(fc, "args") || %{}

    [
      %{
        type: "function_call",
        calls: [
          %{"id" => Ecto.UUID.generate(), "name" => name, "arguments" => Jason.encode!(args)}
        ]
      }
    ]
  end

  defp gemini_evt(%{"candidates" => _} = _chunk), do: []

  defp gemini_evt(%{"text" => delta}) when is_binary(delta),
    do: [%{type: "content", delta: delta}]

  defp gemini_evt(_), do: []
end
