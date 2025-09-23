defmodule MaestroTui do
  @moduledoc """
  Documentation for `MaestroTui`.
  """

  @doc "Basic smoke test call to list providers via the server API."
  @spec ping() :: {:ok, [String.t()]} | {:error, term()}
  def ping do
    MaestroTui.API.providers()
  end
end
