defmodule TheMaestro.PromptsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Prompts` context.
  """

  @doc """
  Generate a base_system_prompt.
  """
  def base_system_prompt_fixture(attrs \\ %{}) do
    {:ok, base_system_prompt} =
      attrs
      |> Enum.into(%{
        name: "some name",
        prompt_text: "some prompt_text"
      })
      |> TheMaestro.Prompts.create_base_system_prompt()

    base_system_prompt
  end
end
