defmodule TheMaestro.Tools.ExecOutput do
  @moduledoc false
  @head 48_000
  @max 64_000

  @spec format(String.t(), integer(), number()) :: String.t()
  def format(text, exit_code, duration) when is_integer(exit_code) and is_number(duration) do
    body = truncate(text || "")
    %{"output" => body, "metadata" => %{"exit_code" => exit_code, "duration_seconds" => duration}} |> Jason.encode!()
  end

  defp truncate(s) when byte_size(s) <= @max, do: s
  defp truncate(s) do
    head = :binary.part(s, 0, @head)
    omitted = byte_size(s) - @max
    marker = "\n[... omitted #{omitted} bytes ...]\n\n"
    tail_take = max(@max - byte_size(head) - byte_size(marker), 0)
    tail_start = byte_size(s) - tail_take
    head <> marker <> :binary.part(s, tail_start, tail_take)
  end
end

