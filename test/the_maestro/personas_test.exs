defmodule TheMaestro.PersonasTest do
  use TheMaestro.DataCase

  alias TheMaestro.Personas

  describe "personas" do
    alias TheMaestro.Personas.Persona

    import TheMaestro.PersonasFixtures

    @invalid_attrs %{name: nil, prompt_text: nil}

    test "list_personas/0 includes newly created persona" do
      persona = persona_fixture()
      assert Enum.any?(Personas.list_personas(), &(&1.id == persona.id))
    end

    test "get_persona!/1 returns the persona with given id" do
      persona = persona_fixture()
      assert Personas.get_persona!(persona.id) == persona
    end

    test "create_persona/1 with valid data creates a persona" do
      valid_attrs = %{name: "some name-" <> Ecto.UUID.generate(), prompt_text: "some prompt_text"}

      assert {:ok, %Persona{} = persona} = Personas.create_persona(valid_attrs)
      assert persona.name == valid_attrs.name
      assert persona.prompt_text == "some prompt_text"
    end

    test "create_persona/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Personas.create_persona(@invalid_attrs)
    end

    test "update_persona/2 with valid data updates the persona" do
      persona = persona_fixture()

      update_attrs = %{
        name: "some updated name-" <> String.slice(Ecto.UUID.generate(), 0, 8),
        prompt_text: "some updated prompt_text"
      }

      assert {:ok, %Persona{} = persona} = Personas.update_persona(persona, update_attrs)
      assert persona.name == update_attrs.name
      assert persona.prompt_text == "some updated prompt_text"
    end

    test "update_persona/2 with invalid data returns error changeset" do
      persona = persona_fixture()
      assert {:error, %Ecto.Changeset{}} = Personas.update_persona(persona, @invalid_attrs)
      assert persona == Personas.get_persona!(persona.id)
    end

    test "delete_persona/1 deletes the persona" do
      persona = persona_fixture()
      assert {:ok, %Persona{}} = Personas.delete_persona(persona)
      assert_raise Ecto.NoResultsError, fn -> Personas.get_persona!(persona.id) end
    end

    test "change_persona/1 returns a persona changeset" do
      persona = persona_fixture()
      assert %Ecto.Changeset{} = Personas.change_persona(persona)
    end
  end
end
