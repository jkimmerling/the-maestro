defmodule MaestroTui.CLI do
  @moduledoc false
  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [
          ui: :boolean,
          provider: :string,
          auth_id: :string,
          model: :string,
          working_dir: :string,
          message: :string
        ]
      )

    if Keyword.get(opts, :ui) do
      case Code.ensure_loaded?(Ratatouille) do
        true -> MaestroTui.UI.run()
        false -> IO.puts(:stderr, "UI not available. Set TUI_ENABLE_TUI=1 and run deps.")
      end
    else
      case MaestroTui.Headless.run(opts) do
        :ok -> :ok
        {:error, r} -> IO.puts(:stderr, "error: #{inspect(r)}")
      end
    end
  end
end
