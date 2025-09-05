defmodule TheMaestro.Tools.ExecOutput do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  @moduledoc """
  Utility to format exec/apply_patch return payloads exactly like Codex:
  a JSON string with fields {"output": "...", "metadata": {"exit_code": int, "duration_seconds": float}}.

  The returned value is a STRING containing JSON (not a map), matching the
  Responses API FunctionCallOutput contract used by Codex.
  """

  @head_bytes 48_000
  @max_bytes 64_000

  @spec format(String.t(), integer(), number()) :: String.t()
  def format(aggregated_output_text, exit_code, duration_seconds)
      when is_integer(exit_code) and is_number(duration_seconds) do
    text = truncate_bytes(aggregated_output_text || "")

    %{
      "output" => text,
      "metadata" => %{
        "exit_code" => exit_code,
        "duration_seconds" => duration_seconds
      }
    }
    |> Jason.encode!()
  end

  defp truncate_bytes(s) when is_binary(s) do
    if byte_size(s) <= @max_bytes do
      s
    else
      head = binary_part(s, 0, @head_bytes)
      tail_size = max(@max_bytes - @head_bytes, 0)

      tail =
        if tail_size > 0 and byte_size(s) > @head_bytes do
          start = byte_size(s) - tail_size
          if start > 0, do: :binary.part(s, start, tail_size), else: ""
        else
          ""
        end

      omitted = max(byte_size(s) - @max_bytes, 0)
      marker = "\n[... omitted #{omitted} bytes ...]\n\n"
      take = max(@max_bytes - byte_size(head) - byte_size(marker), 0)
      head <> marker <> binary_part(tail, 0, min(byte_size(tail), take))
    end
  end
end
