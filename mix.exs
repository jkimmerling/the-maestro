defmodule TheMaestro.MixProject do
  use Mix.Project

  def project do
    [
      app: :the_maestro,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      escript: escript(),
      dialyzer: dialyzer()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: application_mod(),
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Don't start the full Phoenix application when running as escript
  defp application_mod do
    # Check if we're building for escript by examining the environment
    case Mix.env() do
      :prod ->
        # In production, assume minimal startup for escript
        {TheMaestro.TUI.Application, []}

      _ ->
        # In dev/test, use full Phoenix application
        {TheMaestro.Application, []}
    end
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Configures the escript for building the TUI executable
  defp escript do
    [
      main_module: TheMaestro.TUI.CLI,
      name: "maestro_tui",
      # Embed compile-time flag that can be checked at runtime
      embed_elixir: true
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # LLM Provider Dependencies
      {:gemini_ex, "~> 0.2"},
      {:goth, "~> 1.3"},
      {:httpoison, "~> 2.0"},
      {:openai_ex, "~> 0.6"},
      {:anthropix, "~> 0.3"},
      # YAML parsing for OpenAPI specs and config files
      {:yaml_elixir, "~> 2.9"},
      {:ymlr, "~> 5.0"},
      # Testing Dependencies
      {:mock, "~> 0.3", only: :test},
      # TUI Dependencies - simple terminal interface without native deps
      {:io_ansi_table, "~> 1.0"},
      # Multimodal Processing Dependencies
      # Image Processing and OCR
      {:tesseract_ocr, "~> 0.1.5"},
      {:mogrify, "~> 0.9.3"},
      {:image, "~> 0.54"},
      {:ex_image_info, "~> 0.2.4"},
      # Audio Processing and Speech-to-Text
      {:bumblebee, "~> 0.6.0"},
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},
      # Document Processing
      {:porcelain, "~> 2.0"},
      {:ex_pdf_reader, "~> 0.1.0"},
      # Video Processing
      {:ffmpex, "~> 0.10.0"},
      # Code Analysis
      {:ex_tree_sitter, "~> 0.0.3"},
      # General utilities for multimodal processing
      {:temp, "~> 0.4"}
    ]
  end

  # Dialyzer configuration for static analysis
  defp dialyzer do
    [
      # Build PLT files for Dialyzer (Platform independent Learning Tool)
      plt_add_apps: [:mix, :ex_unit],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      # Only analyze our own code, not dependencies
      paths: ["_build/#{Mix.env()}/lib/the_maestro/ebin"],
      # Flags for Dialyzer analysis
      flags: [
        :unmatched_returns,
        :error_handling,
        :no_opaque
      ],
      # Ignore warnings file to track baseline while adding specs
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind the_maestro", "esbuild the_maestro"],
      "assets.deploy": [
        "tailwind the_maestro --minify",
        "esbuild the_maestro --minify",
        "phx.digest"
      ]
    ]
  end
end
