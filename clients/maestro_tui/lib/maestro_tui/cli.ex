defmodule MaestroTui.CLI do
  @moduledoc false
  def main(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [provider: :string, auth_id: :string, model: :string, working_dir: :string, message: :string])
    case MaestroTui.Headless.run(opts) do
      :ok -> :ok
      {:error, r} -> IO.puts(:stderr, "error: #{inspect(r)}")
    end
  end
end

