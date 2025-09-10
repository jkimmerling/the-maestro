defmodule TheMaestro.Repo.Migrations.AddSavedAuthConstraints do
  use Ecto.Migration

  def change do
    # Add DB-level name format and length constraints for saved_authentications
    create constraint(:saved_authentications, :name_format, check: "name ~ '^[A-Za-z0-9_-]+$'")

    create constraint(:saved_authentications, :name_length,
             check: "char_length(name) >= 3 AND char_length(name) <= 50"
           )
  end
end
