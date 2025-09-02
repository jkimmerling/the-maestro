defmodule TheMaestro.PersonasFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TheMaestro.Personas` context.
  """

  @doc """
  Generate a persona.
  """
  def persona_fixture(attrs \\ %{}) do
    {:ok, persona} =
      attrs
      |> Enum.into(%{
        name: "some name",
        prompt_text: "some prompt_text"
      })
      |> TheMaestro.Personas.create_persona()

    persona
  end
end
