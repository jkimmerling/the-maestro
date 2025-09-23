defmodule MaestroTui.MixProject do
  use Mix.Project

  def project do
    [
      app: :maestro_tui,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MaestroTui.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    base = [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:finch, "~> 0.19"}
    ]

    if System.get_env("TUI_ENABLE_TUI") in ["1", "true", "TRUE"] do
      base ++ [{:ratatouille, "~> 0.5.1"}]
    else
      base
    end
  end
end
