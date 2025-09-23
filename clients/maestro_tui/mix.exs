defmodule MaestroTui.MixProject do
  use Mix.Project

  def project do
    [
      app: :maestro_tui,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
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
      base ++ [
        {:ratatouille, "~> 0.5.1"},
        {:bypass, "~> 2.1", only: :test}
      ]
    else
      base ++ [{:bypass, "~> 2.1", only: :test}]
    end
  end

  defp releases do
    [
      maestro_tui: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
