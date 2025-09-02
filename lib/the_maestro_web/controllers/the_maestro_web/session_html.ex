defmodule TheMaestroWeb.TheMaestroWeb.SessionHTML do
  use TheMaestroWeb, :html

  embed_templates "session_html/*"

  @doc """
  Renders a session form.

  The form is defined in the template at
  session_html/session_form.html.heex
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :return_to, :string, default: nil

  def session_form(assigns)
end
