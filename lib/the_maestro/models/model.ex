defmodule TheMaestro.Models.Model do
  @moduledoc """
  Standardized model data structure for all LLM providers.
  
  This struct provides a consistent interface for model data across all providers,
  eliminating the need for defensive programming and type checking throughout
  the application.
  """

  defstruct [
    :id,                # String - "claude-sonnet-4-20250514" 
    :name,              # String - "Claude 4 Sonnet"
    :description,       # String - "Most intelligent model..."
    :provider,          # Atom - :anthropic, :openai, :google
    :context_length,    # Integer - 200000
    :cost_tier,         # Atom - :economy, :balanced, :premium
    :multimodal,        # Boolean
    :function_calling,  # Boolean
    :capabilities       # List - ["text", "code", "analysis"]
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    provider: atom(),
    context_length: non_neg_integer(),
    cost_tier: :economy | :balanced | :premium,
    multimodal: boolean(),
    function_calling: boolean(),
    capabilities: [String.t()]
  }

  @doc """
  Creates a new Model struct from a map with atom keys.
  
  ## Examples
  
      iex> TheMaestro.Models.Model.new(%{
      ...>   id: "claude-3-5-sonnet-20241022",
      ...>   name: "Claude 3.5 Sonnet",
      ...>   description: "Most intelligent model",
      ...>   provider: :anthropic,
      ...>   context_length: 200_000,
      ...>   cost_tier: :premium,
      ...>   multimodal: true,
      ...>   function_calling: true,
      ...>   capabilities: ["text", "code"]
      ...> })
      %TheMaestro.Models.Model{
        id: "claude-3-5-sonnet-20241022",
        name: "Claude 3.5 Sonnet",
        # ...
      }
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id),
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      provider: Map.get(attrs, :provider),
      context_length: Map.get(attrs, :context_length),
      cost_tier: Map.get(attrs, :cost_tier),
      multimodal: Map.get(attrs, :multimodal, false),
      function_calling: Map.get(attrs, :function_calling, false),
      capabilities: Map.get(attrs, :capabilities, [])
    }
  end

  @doc """
  Converts a legacy map with mixed key types to a Model struct.
  
  Handles maps with atom keys, string keys, or mixed keys.
  
  ## Examples
  
      iex> TheMaestro.Models.Model.from_legacy_map(%{
      ...>   "id" => "claude-3-5-sonnet-20241022",
      ...>   "name" => "Claude 3.5 Sonnet",
      ...>   :provider => :anthropic
      ...> })
      %TheMaestro.Models.Model{id: "claude-3-5-sonnet-20241022", ...}
  """
  @spec from_legacy_map(map()) :: t()
  def from_legacy_map(map) when is_map(map) do
    %__MODULE__{
      id: get_key(map, [:id, "id"]),
      name: get_key(map, [:name, "name"]),
      description: get_key(map, [:description, "description"]),
      provider: get_key(map, [:provider, "provider"]),
      context_length: get_key(map, [:context_length, "context_length"]),
      cost_tier: get_key(map, [:cost_tier, "cost_tier"]),
      multimodal: get_key(map, [:multimodal, "multimodal"], false),
      function_calling: get_key(map, [:function_calling, "function_calling"], false),
      capabilities: get_key(map, [:capabilities, "capabilities"], [])
    }
  end

  @doc """
  Converts a legacy string model ID to a basic Model struct.
  
  When only an ID is available, creates a minimal Model struct
  with the ID as both id and name.
  
  ## Examples
  
      iex> TheMaestro.Models.Model.from_legacy_string("claude-3-5-sonnet-20241022")
      %TheMaestro.Models.Model{
        id: "claude-3-5-sonnet-20241022",
        name: "claude-3-5-sonnet-20241022",
        # other fields will be nil/defaults
      }
  """
  @spec from_legacy_string(String.t()) :: t()
  def from_legacy_string(id) when is_binary(id) do
    %__MODULE__{
      id: id,
      name: id,
      description: nil,
      provider: nil,
      context_length: nil,
      cost_tier: nil,
      multimodal: false,
      function_calling: false,
      capabilities: []
    }
  end

  @doc """
  Converts any legacy model data (map or string) to a Model struct.
  
  This is the main conversion function that handles all legacy formats.
  
  ## Examples
  
      iex> TheMaestro.Models.Model.from_legacy(%{id: "model-1", name: "Model 1"})
      %TheMaestro.Models.Model{id: "model-1", name: "Model 1", ...}
      
      iex> TheMaestro.Models.Model.from_legacy("model-1")
      %TheMaestro.Models.Model{id: "model-1", name: "model-1", ...}
  """
  @spec from_legacy(String.t() | map()) :: t()
  def from_legacy(data) when is_binary(data), do: from_legacy_string(data)
  def from_legacy(data) when is_map(data), do: from_legacy_map(data)

  @doc """
  Enriches a basic Model struct with additional provider information.
  
  Used when converting from legacy string IDs to add missing metadata.
  """
  @spec enrich_with_provider_info(t(), atom()) :: t()
  def enrich_with_provider_info(%__MODULE__{} = model, provider) when is_atom(provider) do
    %{model | provider: provider}
    |> maybe_set_default_capabilities()
    |> maybe_set_default_context_length()
  end

  @doc """
  Returns the display name for a model.
  
  Uses the name field if available, falls back to id.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%__MODULE__{id: id}), do: id

  @doc """
  Converts a Model struct to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = model) do
    Map.from_struct(model)
  end

  # Private helper functions

  defp get_key(map, keys, default \\ nil) do
    Enum.find_value(keys, default, fn key ->
      Map.get(map, key)
    end)
  end

  defp maybe_set_default_capabilities(%__MODULE__{capabilities: caps} = model) when caps == [] or is_nil(caps) do
    %{model | capabilities: ["text"]}
  end
  defp maybe_set_default_capabilities(model), do: model

  defp maybe_set_default_context_length(%__MODULE__{context_length: nil} = model) do
    %{model | context_length: 8192}
  end
  defp maybe_set_default_context_length(model), do: model
end