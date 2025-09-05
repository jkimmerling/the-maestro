defmodule TheMaestro.PromptsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Prompts` context.
  """

  @doc """
  Generate a base_system_prompt.
  """
  def base_system_prompt_fixture(attrs \\ %{}) do
    # Ensure unique name per call to avoid unique constraint violations across tests
    default_name = "some name-" <> Ecto.UUID.generate()

    {:ok, base_system_prompt} =
      attrs
      |> Enum.into(%{
        name: default_name,
        prompt_text: "some prompt_text"
      })
      |> TheMaestro.Prompts.create_base_system_prompt()

    base_system_prompt
  end
end
