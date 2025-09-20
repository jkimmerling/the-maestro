defmodule TheMaestro.SystemPrompts.Renderer.OpenAI do
  @moduledoc """
  Converts resolved prompt stacks into the OpenAI instructions array.
  """

  @doc """
  Render a stack into the list of OpenAI instruction segments.

      iex> stack = %{prompts: [%{prompt: %{text: "Alpha", metadata: %{}}, overrides: %{}}]}
      iex> TheMaestro.SystemPrompts.Renderer.OpenAI.render(stack)
      [%{"type" => "text", "text" => "Alpha"}]

      iex> stack = %{prompts: [%{prompt: %{text: "Base", metadata: %{}}, overrides: %{"segments" => ["Override"]}}]}
      iex> TheMaestro.SystemPrompts.Renderer.OpenAI.render(stack)
      [%{"type" => "text", "text" => "Override"}]
  """
  @spec render(%{prompts: list()}) :: [map()]
  def render(%{prompts: prompts}) when is_list(prompts) do
    prompts
    |> Enum.flat_map(fn entry ->
      entry
      |> ensure_overrides()
      |> render_segments()
    end)
    |> Enum.reject(&is_nil/1)
  end

  def render(prompts) when is_list(prompts) do
    render(%{prompts: prompts})
  end

  defp ensure_overrides(%{overrides: overrides} = entry) when is_map(overrides) do
    entry
  end

  defp ensure_overrides(%{overrides: nil} = entry) do
    Map.put(entry, :overrides, %{})
  end

  defp ensure_overrides(entry) when is_map(entry) do
    Map.put_new(entry, :overrides, %{})
  end

  defp ensure_overrides(entry), do: entry

  defp render_segments(%{prompt: prompt, overrides: overrides}) do
    normalized_overrides = stringify_keys_deep(overrides || %{})
    metadata = Map.get(prompt, :metadata) || %{}

    segments = segments_for(normalized_overrides, metadata, Map.get(prompt, :text))

    segments
    |> Enum.map(&normalize_segment(&1, prompt, normalized_overrides))
    |> Enum.reject(&is_nil/1)
  end

  defp render_segments(_), do: []

  defp normalize_segment(segment, _prompt, overrides) when is_binary(segment) do
    %{"type" => "text", "text" => segment}
    |> merge_segment_defaults(overrides)
  end

  defp normalize_segment(%{} = segment, prompt, overrides) do
    segment
    |> stringify_keys_deep()
    |> Map.put_new("type", "text")
    |> Map.put_new("text", Map.get(prompt, :text) || "")
    |> merge_segment_defaults(overrides)
  end

  defp normalize_segment(_segment, _prompt, _overrides), do: nil

  defp merge_segment_defaults(segment, overrides) do
    case overrides["segment_defaults"] do
      map when is_map(map) -> Map.merge(map, segment)
      _ -> segment
    end
  end

  defp segments_for(overrides, metadata, text) do
    cond do
      is_list(overrides["segments"]) ->
        overrides["segments"]

      is_list(overrides["items"]) ->
        overrides["items"]

      is_list(metadata["openai_segments"]) ->
        metadata["openai_segments"]

      is_list(metadata["segments"]) ->
        metadata["segments"]

      is_list(metadata["items"]) ->
        metadata["items"]

      true ->
        text = text || ""
        if text == "", do: [], else: [text]
    end
  end

  defp stringify_keys_deep(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {stringify_key(k), stringify_keys_deep(v)} end)
    |> Enum.into(%{})
  end

  defp stringify_keys_deep(value) when is_list(value), do: Enum.map(value, &stringify_keys_deep/1)
  defp stringify_keys_deep(value), do: value

  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: to_string(key)
end
