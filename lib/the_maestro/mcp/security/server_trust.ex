defmodule TheMaestro.MCP.Security.ServerTrust do
  @moduledoc """
  Server trust record for MCP security framework.
  
  Represents the trust level and permissions for a specific MCP server.
  """
  
  alias TheMaestro.MCP.Security.TrustLevel
  
  @type t :: %__MODULE__{
    server_id: String.t(),
    trust_level: TrustLevel.server_level(),
    whitelist_tools: [String.t()],
    blacklist_tools: [String.t()],
    user_granted: boolean(),
    auto_granted: boolean(),
    expires_at: DateTime.t() | nil,
    granted_by: String.t() | nil,
    granted_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  defstruct [
    :server_id,
    trust_level: :untrusted,
    whitelist_tools: [],
    blacklist_tools: [],
    user_granted: false,
    auto_granted: false,
    expires_at: nil,
    granted_by: nil,
    granted_at: nil,
    updated_at: nil
  ]
  
  @doc """
  Creates a new server trust record.
  """
  @spec new(String.t(), TrustLevel.server_level(), String.t()) :: t()
  def new(server_id, trust_level, granted_by) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      server_id: server_id,
      trust_level: trust_level,
      user_granted: true,
      auto_granted: false,
      granted_by: granted_by,
      granted_at: now,
      updated_at: now
    }
  end
  
  @doc """
  Creates an auto-granted server trust record.
  """
  @spec auto_grant(String.t(), TrustLevel.server_level()) :: t()
  def auto_grant(server_id, trust_level) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      server_id: server_id,
      trust_level: trust_level,
      user_granted: false,
      auto_granted: true,
      granted_at: now,
      updated_at: now
    }
  end
  
  @doc """
  Adds a tool to the whitelist.
  """
  @spec add_to_whitelist(t(), String.t()) :: t()
  def add_to_whitelist(%__MODULE__{} = trust, tool_name) do
    updated_whitelist = 
      trust.whitelist_tools
      |> Enum.reject(&(&1 == tool_name))  # Remove if already present
      |> Enum.concat([tool_name])  # Add to end
      
    %{trust | 
      whitelist_tools: updated_whitelist,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Adds a tool to the blacklist.
  """
  @spec add_to_blacklist(t(), String.t()) :: t()
  def add_to_blacklist(%__MODULE__{} = trust, tool_name) do
    updated_blacklist =
      trust.blacklist_tools
      |> Enum.reject(&(&1 == tool_name))  # Remove if already present
      |> Enum.concat([tool_name])  # Add to end
      
    %{trust |
      blacklist_tools: updated_blacklist, 
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Removes a tool from the whitelist.
  """
  @spec remove_from_whitelist(t(), String.t()) :: t()
  def remove_from_whitelist(%__MODULE__{} = trust, tool_name) do
    updated_whitelist = Enum.reject(trust.whitelist_tools, &(&1 == tool_name))
    
    %{trust |
      whitelist_tools: updated_whitelist,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Removes a tool from the blacklist.
  """
  @spec remove_from_blacklist(t(), String.t()) :: t()
  def remove_from_blacklist(%__MODULE__{} = trust, tool_name) do  
    updated_blacklist = Enum.reject(trust.blacklist_tools, &(&1 == tool_name))
    
    %{trust |
      blacklist_tools: updated_blacklist,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates the trust level.
  """
  @spec update_trust_level(t(), TrustLevel.server_level()) :: t()
  def update_trust_level(%__MODULE__{} = trust, new_level) do
    %{trust |
      trust_level: new_level,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Checks if a tool is whitelisted.
  """
  @spec tool_whitelisted?(t(), String.t()) :: boolean()
  def tool_whitelisted?(%__MODULE__{} = trust, tool_name) do
    tool_name in trust.whitelist_tools
  end
  
  @doc """
  Checks if a tool is blacklisted.
  """
  @spec tool_blacklisted?(t(), String.t()) :: boolean()
  def tool_blacklisted?(%__MODULE__{} = trust, tool_name) do
    tool_name in trust.blacklist_tools
  end
  
  @doc """
  Checks if the trust has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
  
  @doc """
  Sets an expiration time for the trust.
  """
  @spec set_expiration(t(), DateTime.t()) :: t()
  def set_expiration(%__MODULE__{} = trust, expires_at) do
    %{trust |
      expires_at: expires_at,
      updated_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Removes the expiration time.
  """
  @spec clear_expiration(t()) :: t()
  def clear_expiration(%__MODULE__{} = trust) do
    %{trust |
      expires_at: nil,
      updated_at: DateTime.utc_now()
    }
  end
end