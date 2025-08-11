defmodule TheMaestro.Tooling.Tool do
  @moduledoc """
  Behaviour for defining tools that can be used by the AI agent.

  Tools are capabilities that extend the agent's abilities to interact with
  the outside world, such as reading files, executing shell commands, or
  making API calls. All tools must implement this behaviour to ensure
  consistent interfaces.

  ## Example

      defmodule MyApp.Tools.Calculator do
        use TheMaestro.Tooling.Tool

        @impl true
        def definition do
          %{
            "name" => "calculate",
            "description" => "Performs basic arithmetic calculations",
            "parameters" => %{
              "type" => "object",
              "properties" => %{
                "expression" => %{
                  "type" => "string",
                  "description" => "Mathematical expression to evaluate (e.g., '2 + 2')"
                }
              },
              "required" => ["expression"]
            }
          }
        end

        @impl true
        def execute(%{"expression" => expression}) do
          # Implementation logic here
          {:ok, %{"result" => calculate(expression)}}
        end

        defp calculate(expression) do
          # Safe calculation logic
        end
      end
  """

  @typedoc """
  Tool definition following OpenAI Function Calling format.

  This structure defines the tool's name, description, and parameter schema
  that will be sent to the LLM provider to enable function calling.
  """
  @type definition :: %{
          required(String.t()) => String.t() | map()
        }

  @typedoc """
  JSON Schema definition for tool parameters.
  """
  @type parameter_schema :: map()

  @typedoc """
  Individual parameter property definition.
  """
  @type parameter_property :: map()

  @typedoc """
  Arguments passed to the tool execution function.

  These are the actual parameter values extracted from the LLM's function call.
  """
  @type arguments :: %{String.t() => term()}

  @typedoc """
  Result returned from tool execution.

  Tools should return either a success tuple with the result data,
  or an error tuple with a descriptive reason.
  """
  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the tool definition for this tool.

  The definition includes the tool's name, description, and parameter schema
  that will be sent to the LLM provider to enable function calling.

  ## Returns
    A map containing the tool definition following the OpenAI Function Calling format.
  """
  @callback definition() :: definition()

  @doc """
  Executes the tool with the provided arguments.

  This function implements the actual logic of the tool. It receives
  the arguments extracted from the LLM's function call and returns
  the result of executing the tool.

  ## Parameters
    - `arguments`: Map of parameter names to values

  ## Returns
    - `{:ok, result}`: Tool executed successfully
    - `{:error, reason}`: Tool execution failed
  """
  @callback execute(arguments()) :: result()

  @doc """
  Validates that the provided arguments match the tool's parameter schema.

  This is an optional callback that can be implemented to provide custom
  validation logic beyond basic JSON schema validation.

  ## Parameters
    - `arguments`: Map of parameter names to values

  ## Returns
    - `:ok`: Arguments are valid
    - `{:error, reason}`: Arguments are invalid
  """
  @callback validate_arguments(arguments()) :: :ok | {:error, term()}

  @optional_callbacks validate_arguments: 1

  @doc """
  Macro to use this behaviour and set up common functionality.

  This macro can be used by tool implementations to automatically
  get common functionality and ensure they implement the required callbacks.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour TheMaestro.Tooling.Tool

      @doc """
      Helper function to validate arguments against the tool's JSON schema.

      This provides basic validation that can be used by tools that don't
      need custom validation logic.
      """
      def validate_arguments(arguments) do
        definition = definition()
        schema = definition["parameters"]

        case validate_against_schema(arguments, schema) do
          :ok -> :ok
          {:error, reason} -> {:error, "Invalid arguments: #{reason}"}
        end
      end

      defp validate_against_schema(arguments, schema) do
        required_params = Map.get(schema, "required", [])
        properties = Map.get(schema, "properties", %{})

        # Check required parameters
        missing_required =
          Enum.filter(required_params, fn param ->
            not Map.has_key?(arguments, param)
          end)

        if length(missing_required) > 0 do
          {:error, "Missing required parameters: #{inspect(missing_required)}"}
        else
          # Basic type validation could be added here
          :ok
        end
      end

      defoverridable validate_arguments: 1
    end
  end
end
