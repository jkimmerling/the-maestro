defmodule Mix.Tasks.Maestro.Prompts.Dump do
  @moduledoc """
  Dump the current default prompt stack for each provider to JSON files.
  """
  use Mix.Task

  @shortdoc "Dump canonical provider prompts to disk"
  @switches [output: :string]

  alias TheMaestro.SystemPrompts

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    output_dir = opts[:output] |> default_output() |> Path.expand()

    File.mkdir_p!(output_dir)

    providers = [:openai, :anthropic, :gemini]

    Enum.each(providers, fn provider ->
      dump_provider(provider, output_dir)
    end)

    Mix.shell().info("Wrote provider prompts to #{output_dir}")
  end

  defp default_output(nil), do: "priv/system_prompts/dump"
  defp default_output(path), do: path

  defp dump_provider(provider, output_dir) do
    %{prompts: prompts} = SystemPrompts.default_stack(provider)

    payload =
      Enum.map(prompts, fn %{prompt: prompt, overrides: overrides} ->
        %{
          id: prompt.id,
          name: prompt.name,
          provider: prompt.provider,
          render_format: prompt.render_format,
          immutable: prompt.immutable,
          is_default: prompt.is_default,
          position: prompt.position,
          version: prompt.version,
          source_ref: prompt.source_ref,
          labels: prompt.labels,
          metadata: prompt.metadata,
          text: prompt.text,
          overrides: overrides
        }
      end)

    file = Path.join(output_dir, "#{provider}.json")
    File.write!(file, Jason.encode!(payload, pretty: true))
  end
end
