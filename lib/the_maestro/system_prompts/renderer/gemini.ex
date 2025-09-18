defmodule TheMaestro.SystemPrompts.Renderer.Gemini do
  @moduledoc """
  Converts resolved prompt stacks into Gemini `systemInstruction` payloads.
  """

  @doc """
  Render the stack into a Gemini system instruction map.

      iex> stack = %{prompts: [%{prompt: %{text: "Guide", metadata: %{}}, overrides: %{}}]}
      iex> TheMaestro.SystemPrompts.Renderer.Gemini.render(stack)
      %{"role" => "user", "parts" => [%{"text" => "Guide"}]}
  """
  @spec render(%{prompts: list()}) :: map()
  def render(%{prompts: prompts}) when is_list(prompts) do
    parts =
      prompts
      |> Enum.flat_map(fn entry ->
        entry
        |> ensure_overrides()
        |> parts_for()
      end)
      |> Enum.reject(&is_nil/1)

    %{"role" => "user", "parts" => parts}
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

  defp parts_for(%{prompt: prompt, overrides: overrides}) do
    metadata = Map.get(prompt, :metadata) || %{}
    normalized_overrides = stringify_keys_deep(overrides || %{})

    parts =
      cond do
        is_list(normalized_overrides["parts"]) -> normalized_overrides["parts"]
        is_list(metadata["parts"]) -> metadata["parts"]
        true -> [%{"text" => Map.get(prompt, :text) || ""}]
      end

    parts
    |> Enum.map(&normalize_part/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parts_for(_), do: []

  defp normalize_part(part) when is_binary(part) do
    %{"text" => part}
  end

  defp normalize_part(%{} = part) do
    stringify_keys_deep(part)
  end

  defp normalize_part(_), do: nil

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
