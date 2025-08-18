defmodule TheMaestro.MCP.Security.TrustLevel do
  @moduledoc """
  Trust level definitions for MCP security framework.
  
  Defines the different trust levels and their meanings within the security model.
  """
  
  @type server_level :: :trusted | :untrusted | :sandboxed
  @type tool_level :: :always_allow | :confirm_once | :confirm_always | :blocked  
  @type user_level :: :admin | :standard | :restricted
  
  @type t :: %__MODULE__{
    server_level: server_level(),
    tool_level: tool_level(),
    user_level: user_level()
  }
  
  defstruct [
    :server_level,
    :tool_level, 
    :user_level
  ]
  
  @doc """
  Returns the default trust level for new servers.
  """
  @spec default_server_level() :: server_level()
  def default_server_level, do: :untrusted
  
  @doc """
  Returns the default tool level for new tools.
  """
  @spec default_tool_level() :: tool_level()
  def default_tool_level, do: :confirm_always
  
  @doc """
  Returns the default user level for new users.
  """
  @spec default_user_level() :: user_level()  
  def default_user_level, do: :standard
  
  @doc """
  Validates if a trust level combination is valid.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = trust_level) do
    valid_server_level?(trust_level.server_level) and
    valid_tool_level?(trust_level.tool_level) and
    valid_user_level?(trust_level.user_level)
  end
  
  @doc """
  Checks if server level is valid.
  """
  @spec valid_server_level?(term()) :: boolean()
  def valid_server_level?(level) when level in [:trusted, :untrusted, :sandboxed], do: true
  def valid_server_level?(_), do: false
  
  @doc """
  Checks if tool level is valid.
  """
  @spec valid_tool_level?(term()) :: boolean()
  def valid_tool_level?(level) when level in [:always_allow, :confirm_once, :confirm_always, :blocked], do: true
  def valid_tool_level?(_), do: false
  
  @doc """
  Checks if user level is valid.
  """
  @spec valid_user_level?(term()) :: boolean() 
  def valid_user_level?(level) when level in [:admin, :standard, :restricted], do: true
  def valid_user_level?(_), do: false
end