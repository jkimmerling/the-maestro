defmodule TheMaestro.SystemPrompts.Renderer.Anthropic do
  @moduledoc """
  Converts resolved prompt stacks into Anthropic message blocks.
  """

  @doc """
  Render the stack into Anthropic block maps.

      iex> stack = %{prompts: [%{prompt: %{text: "Identity", metadata: %{}}, overrides: %{}}]}
      iex> TheMaestro.SystemPrompts.Renderer.Anthropic.render(stack)
      [%{"type" => "text", "text" => "Identity"}]
  """
  @spec render(%{prompts: list()}) :: [map()]
  def render(%{prompts: prompts}) when is_list(prompts) do
    prompts
    |> Enum.flat_map(fn entry ->
      entry
      |> ensure_overrides()
      |> blocks_for()
    end)
    |> Enum.reject(&is_nil/1)
  end

  def render(prompts) when is_list(prompts), do: render(%{prompts: prompts})

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

  defp blocks_for(%{prompt: prompt, overrides: overrides}) do
    metadata = Map.get(prompt, :metadata) || %{}
    normalized_overrides = stringify_keys_deep(overrides || %{})

    blocks =
      cond do
        is_list(normalized_overrides["blocks"]) -> normalized_overrides["blocks"]
        is_list(metadata["blocks"]) -> metadata["blocks"]
        true -> [%{"type" => "text", "text" => Map.get(prompt, :text) || ""}]
      end

    blocks
    |> Enum.map(&normalize_block/1)
    |> Enum.reject(&is_nil/1)
  end

  defp blocks_for(_), do: []

  defp normalize_block(block) when is_binary(block) do
    %{"type" => "text", "text" => block}
  end

  defp normalize_block(%{} = block) do
    block
    |> stringify_keys_deep()
    |> Map.put_new("type", "text")
    |> Map.update("text", "", fn
      nil -> ""
      value -> value
    end)
  end

  defp normalize_block(_), do: nil

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
