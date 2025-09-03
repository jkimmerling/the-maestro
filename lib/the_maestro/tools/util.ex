defmodule TheMaestro.Tools.Util do
  @moduledoc """
  Utilities for tool execution (paths, safety, working roots).
  """

  @spec working_root(map()) :: String.t()
  def working_root(agent) do
    wd = agent[:working_directory] || agent["working_directory"] || File.cwd!()
    Path.expand(wd)
  end

  @spec abs_path(String.t(), String.t() | nil) :: String.t()
  def abs_path(root, nil), do: root

  def abs_path(root, path) when is_binary(path) do
    abs = if Path.type(path) == :absolute, do: path, else: Path.join(root, path)
    Path.expand(abs)
  end
end
