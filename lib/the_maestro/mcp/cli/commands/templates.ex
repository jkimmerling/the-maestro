defmodule TheMaestro.MCP.CLI.Commands.Templates do
  @moduledoc """
  Templates command for MCP CLI.

  Provides functionality to manage and apply MCP server configuration templates.
  """

  alias TheMaestro.MCP.Config
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the templates command.
  """
  def execute(args, options) do
    if Map.get(options, :help) do
      show_help()
      {:ok, :help}
    end

    case args do
      ["list"] ->
        list_templates(options)

      ["show", template_name] ->
        show_template(template_name, options)

      ["apply", template_name, server_name] ->
        apply_template(template_name, server_name, options)

      ["create", template_name] ->
        create_template(template_name, options)

      ["delete", template_name] ->
        delete_template(template_name, options)

      ["validate", template_name] ->
        validate_template(template_name, options)

      _ ->
        CLI.print_error("Invalid templates command. Use --help for usage.")
    end
  end

  @doc """
  Show help for the templates command.
  """
  def show_help do
    IO.puts("""
    MCP Configuration Templates

    Usage:
      maestro mcp templates <subcommand> [OPTIONS]

    Commands:
      list                     List available templates
      show <template>          Show template details
      apply <template> <name>  Apply template to create server
      create <template>        Create new template interactively
      delete <template>        Delete template
      validate <template>      Validate template format

    Options:
      --variables <vars>       Pass template variables (key=value,key2=value2)
      --force                  Force operations without confirmation
      --dry-run                Show what would be done without applying
      --help                   Show this help message

    Examples:
      maestro mcp templates list
      maestro mcp templates show openai-gpt
      maestro mcp templates apply openai-gpt myGPTServer --variables api_key=sk-xxx
      maestro mcp templates create custom-server
    """)
  end

  ## Private Functions

  defp list_templates(options) do
    CLI.print_info("Available MCP server templates:")

    case get_available_templates() do
      {:ok, []} ->
        IO.puts("  No templates available")
        {:ok, []}

      {:ok, templates} ->
        # Display templates in formatted table
        name_width =
          templates
          |> Enum.map(fn template -> String.length(template.name) end)
          |> Enum.max()
          |> max(8)

        desc_width =
          templates
          |> Enum.map(fn template -> String.length(template.description) end)
          |> Enum.max()
          |> max(11)
          # Cap description width
          |> min(50)

        # Print header
        IO.puts("")

        IO.puts(
          "  #{"Template" |> String.pad_trailing(name_width)} | #{"Description" |> String.pad_trailing(desc_width)} | Transport | Variables"
        )

        IO.puts(
          "  #{String.duplicate("-", name_width)} | #{String.duplicate("-", desc_width)} | --------- | ---------"
        )

        # Print template information
        Enum.each(templates, fn template ->
          desc_display = String.slice(template.description, 0, desc_width)
          transport = Map.get(template, :transport, "stdio")
          var_count = length(Map.get(template, :variables, []))

          IO.puts(
            "  #{template.name |> String.pad_trailing(name_width)} | #{desc_display |> String.pad_trailing(desc_width)} | #{transport |> String.pad_trailing(9)} | #{var_count} vars"
          )
        end)

        # Show categories summary
        categories =
          templates
          |> Enum.group_by(fn template -> Map.get(template, :category, "general") end)
          |> Enum.map(fn {category, temps} -> {category, length(temps)} end)
          |> Enum.sort_by(fn {category, _} -> category end)

        unless Enum.empty?(categories) do
          IO.puts("")
          IO.puts("  Categories:")

          Enum.each(categories, fn {category, count} ->
            IO.puts("    #{String.capitalize(category)}: #{count} template(s)")
          end)
        end

        {:ok, templates}

      {:error, reason} ->
        CLI.print_error("Failed to list templates: #{inspect(reason)}")
        {:error, :list_failed}
    end
  end

  defp show_template(template_name, options) do
    CLI.print_info("Template details: #{template_name}")

    case get_template(template_name) do
      {:ok, template} ->
        # Display comprehensive template information
        IO.puts("")
        IO.puts("  Name: #{template.name}")
        IO.puts("  Description: #{template.description}")
        IO.puts("  Category: #{Map.get(template, :category, "general")}")
        IO.puts("  Transport: #{Map.get(template, :transport, "stdio")}")
        IO.puts("  Version: #{Map.get(template, :version, "1.0")}")

        # Show variables
        variables = Map.get(template, :variables, [])

        if length(variables) > 0 do
          IO.puts("")
          IO.puts("  Variables:")

          Enum.each(variables, fn var ->
            required = if Map.get(var, :required, false), do: "(required)", else: "(optional)"
            default = Map.get(var, :default, "")
            default_text = if String.length(default) > 0, do: " [default: #{default}]", else: ""

            IO.puts("    #{var.name}: #{var.description} #{required}#{default_text}")
          end)
        else
          IO.puts("  Variables: None")
        end

        # Show configuration preview
        if Map.get(options, :verbose, false) do
          IO.puts("")
          IO.puts("  Configuration Template:")
          config_preview = format_template_config(template)
          IO.puts("    #{config_preview}")
        end

        # Show usage example
        IO.puts("")
        IO.puts("  Usage Example:")

        example_vars =
          variables
          |> Enum.filter(fn var -> Map.get(var, :required, false) end)
          |> Enum.map(fn var -> "#{var.name}=<value>" end)
          |> Enum.join(",")

        if String.length(example_vars) > 0 do
          IO.puts(
            "    maestro mcp templates apply #{template_name} myServer --variables #{example_vars}"
          )
        else
          IO.puts("    maestro mcp templates apply #{template_name} myServer")
        end

        {:ok, template}

      {:error, :not_found} ->
        CLI.print_error("Template '#{template_name}' not found")
        {:error, :not_found}

      {:error, reason} ->
        CLI.print_error("Failed to show template: #{inspect(reason)}")
        {:error, :show_failed}
    end
  end

  defp apply_template(template_name, server_name, options) do
    dry_run = Map.get(options, :dry_run, false)
    action = if dry_run, do: "Would apply", else: "Applying"

    CLI.print_info(
      "#{action} template '#{template_name}' to create server '#{server_name}'..."
    )

    with {:ok, template} <- get_template(template_name),
         {:ok, variables} <- parse_template_variables(options),
         {:ok, config} <- generate_server_config(template, server_name, variables) do
      if dry_run do
        # Show what would be created
        IO.puts("")
        IO.puts("  Generated Configuration:")
        IO.puts("  #{inspect(config, pretty: true, width: 80)}")

        IO.puts("")
        IO.puts("  Files that would be created/modified:")
        IO.puts("    - Configuration file updated")

        if template.transport == "stdio" && Map.get(template, :executable) do
          IO.puts("    - Executable: #{template.executable}")
        end

        {:ok, :dry_run}
      else
        # Apply template for real
        case save_server_configuration(server_name, config) do
          :ok ->
            CLI.print_success(
              "Server '#{server_name}' created from template '#{template_name}'"
            )

            # Show next steps
            IO.puts("")
            IO.puts("  Next steps:")
            IO.puts("    1. Review configuration: maestro mcp list #{server_name}")
            IO.puts("    2. Test connection: maestro mcp status #{server_name}")
            IO.puts("    3. List available tools: maestro mcp tools list #{server_name}")

            {:ok, config}

          {:error, reason} ->
            CLI.print_error("Failed to save configuration: #{inspect(reason)}")
            {:error, :save_failed}
        end
      end
    else
      {:error, :template_not_found} ->
        CLI.print_error("Template '#{template_name}' not found")
        {:error, :template_not_found}

      {:error, :invalid_variables} ->
        CLI.print_error("Invalid template variables provided")
        {:error, :invalid_variables}

      {:error, reason} ->
        CLI.print_error("Failed to apply template: #{inspect(reason)}")
        {:error, :apply_failed}
    end
  end

  defp create_template(template_name, options) do
    CLI.print_info("Creating new template: #{template_name}")

    # Interactive template creation
    IO.puts("")
    description = prompt_for_input("Template description: ")
    category = prompt_for_input("Category [general]: ", "general")
    transport = prompt_for_transport()

    # Build template configuration based on transport
    template_config =
      case transport do
        "stdio" -> create_stdio_template(template_name, description, category)
        "sse" -> create_sse_template(template_name, description, category)
        "http" -> create_http_template(template_name, description, category)
        _ -> {:error, :unsupported_transport}
      end

    case template_config do
      {:ok, template} ->
        # Save template
        case save_template(template) do
          :ok ->
            CLI.print_success("Template '#{template_name}' created successfully")

            IO.puts("")
            IO.puts("  Usage:")
            IO.puts("    maestro mcp templates show #{template_name}")
            IO.puts("    maestro mcp templates apply #{template_name} <server-name>")

            {:ok, template}

          {:error, reason} ->
            CLI.print_error("Failed to save template: #{inspect(reason)}")
            {:error, :save_failed}
        end

      {:error, reason} ->
        CLI.print_error("Failed to create template: #{inspect(reason)}")
        {:error, :create_failed}
    end
  end

  defp delete_template(template_name, options) do
    force = Map.get(options, :force, false)

    CLI.print_info("Deleting template: #{template_name}")

    # Check if template exists
    case get_template(template_name) do
      {:ok, _template} ->
        # Confirm deletion unless forced
        proceed =
          if force do
            true
          else
            CLI.print_warning(
              "This will permanently delete the template '#{template_name}'"
            )

            case IO.gets("Continue? (yes/no): ") do
              input when is_binary(input) ->
                String.trim(String.downcase(input)) in ["yes", "y"]

              _ ->
                false
            end
          end

        if proceed do
          case remove_template(template_name) do
            :ok ->
              CLI.print_success("Template '#{template_name}' deleted")
              {:ok, :deleted}

            {:error, reason} ->
              CLI.print_error("Failed to delete template: #{inspect(reason)}")
              {:error, :delete_failed}
          end
        else
          CLI.print_info("Template deletion cancelled")
          {:ok, :cancelled}
        end

      {:error, :not_found} ->
        CLI.print_error("Template '#{template_name}' not found")
        {:error, :not_found}

      {:error, reason} ->
        CLI.print_error("Failed to check template: #{inspect(reason)}")
        {:error, :check_failed}
    end
  end

  defp validate_template(template_name, options) do
    CLI.print_info("Validating template: #{template_name}")

    case get_template(template_name) do
      {:ok, template} ->
        # Comprehensive template validation
        errors = []
        warnings = []

        # Basic structure validation
        {errors, warnings} = validate_basic_structure(template, errors, warnings)

        # Transport-specific validation
        {errors, warnings} = validate_transport_config(template, errors, warnings)

        # Variable validation
        {errors, warnings} = validate_template_variables(template, errors, warnings)

        # Report validation results
        IO.puts("")

        if length(errors) == 0 && length(warnings) == 0 do
          CLI.print_success("Template '#{template_name}' is valid")
        else
          if length(errors) > 0 do
            IO.puts("  Errors:")

            Enum.each(errors, fn error ->
              IO.puts("    ❌ #{error}")
            end)
          end

          if length(warnings) > 0 do
            IO.puts("  Warnings:")

            Enum.each(warnings, fn warning ->
              IO.puts("    ⚠️  #{warning}")
            end)
          end
        end

        if length(errors) > 0 do
          {:error, :validation_failed}
        else
          {:ok, :valid}
        end

      {:error, :not_found} ->
        CLI.print_error("Template '#{template_name}' not found")
        {:error, :not_found}

      {:error, reason} ->
        CLI.print_error("Failed to load template: #{inspect(reason)}")
        {:error, :load_failed}
    end
  end

  # Helper functions for template management

  defp get_available_templates do
    # Return built-in templates (in real implementation, would load from filesystem)
    templates = [
      %{
        name: "openai-gpt",
        description: "OpenAI GPT API server with chat completions",
        category: "ai",
        transport: "http",
        version: "1.0",
        variables: [
          %{name: "api_key", description: "OpenAI API key", required: true},
          %{name: "model", description: "GPT model to use", required: false, default: "gpt-4"},
          %{
            name: "base_url",
            description: "API base URL",
            required: false,
            default: "https://api.openai.com/v1"
          }
        ]
      },
      %{
        name: "anthropic-claude",
        description: "Anthropic Claude API server",
        category: "ai",
        transport: "http",
        version: "1.0",
        variables: [
          %{name: "api_key", description: "Anthropic API key", required: true},
          %{
            name: "model",
            description: "Claude model to use",
            required: false,
            default: "claude-3-sonnet-20240229"
          }
        ]
      },
      %{
        name: "local-python",
        description: "Local Python script MCP server",
        category: "local",
        transport: "stdio",
        version: "1.0",
        variables: [
          %{name: "script_path", description: "Path to Python script", required: true},
          %{
            name: "python_path",
            description: "Python interpreter path",
            required: false,
            default: "python3"
          }
        ]
      },
      %{
        name: "database-mysql",
        description: "MySQL database connection server",
        category: "database",
        transport: "stdio",
        version: "1.0",
        variables: [
          %{name: "host", description: "MySQL host", required: true},
          %{name: "port", description: "MySQL port", required: false, default: "3306"},
          %{name: "database", description: "Database name", required: true},
          %{name: "username", description: "Database username", required: true},
          %{name: "password", description: "Database password", required: true}
        ]
      }
    ]

    {:ok, templates}
  end

  defp get_template(template_name) do
    case get_available_templates() do
      {:ok, templates} ->
        case Enum.find(templates, fn t -> t.name == template_name end) do
          nil -> {:error, :not_found}
          template -> {:ok, template}
        end

      error ->
        error
    end
  end

  defp parse_template_variables(options) do
    case Map.get(options, :variables) do
      nil ->
        {:ok, %{}}

      variables_str ->
        try do
          variables =
            variables_str
            |> String.split(",")
            |> Enum.map(fn pair ->
              case String.split(pair, "=", parts: 2) do
                [key, value] -> {String.trim(key), String.trim(value)}
                _ -> {:error, "Invalid variable format: #{pair}"}
              end
            end)

          if Enum.any?(variables, fn {key, _} -> key == :error end) do
            {:error, :invalid_format}
          else
            {:ok, Map.new(variables)}
          end
        rescue
          _ -> {:error, :parse_error}
        end
    end
  end

  defp generate_server_config(template, server_name, variables) do
    # Validate required variables
    required_vars =
      template.variables
      |> Enum.filter(fn var -> Map.get(var, :required, false) end)
      |> Enum.map(fn var -> var.name end)

    missing_vars = required_vars -- Map.keys(variables)

    if length(missing_vars) > 0 do
      CLI.print_error(
        "Missing required variables: #{Enum.join(missing_vars, ", ")}"
      )

      {:error, :missing_variables}
    else
      # Build server configuration
      config =
        case template.transport do
          "stdio" -> generate_stdio_config(template, server_name, variables)
          "http" -> generate_http_config(template, server_name, variables)
          "sse" -> generate_sse_config(template, server_name, variables)
          _ -> {:error, :unsupported_transport}
        end

      config
    end
  end

  defp generate_stdio_config(template, server_name, variables) do
    script_path = Map.get(variables, "script_path", "server.py")
    python_path = Map.get(variables, "python_path", "python3")

    config = %{
      name: server_name,
      transport: %{
        type: :stdio,
        command: python_path,
        args: [script_path]
      },
      capabilities: %{
        tools: true,
        resources: true,
        prompts: false
      },
      trust_level: :medium,
      timeout: 30_000,
      environment: variables
    }

    {:ok, config}
  end

  defp generate_http_config(template, server_name, variables) do
    api_key = Map.get(variables, "api_key")
    base_url = Map.get(variables, "base_url", "https://api.example.com")

    config = %{
      name: server_name,
      transport: %{
        type: :http,
        base_url: base_url,
        headers: %{
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        }
      },
      capabilities: %{
        tools: true,
        resources: true,
        prompts: true
      },
      trust_level: :high,
      timeout: 60_000,
      auth_method: :api_key,
      # Don't store API key in env
      environment: Map.delete(variables, "api_key")
    }

    {:ok, config}
  end

  defp generate_sse_config(template, server_name, variables) do
    base_url = Map.get(variables, "base_url", "https://api.example.com")

    config = %{
      name: server_name,
      transport: %{
        type: :sse,
        base_url: base_url,
        endpoint: "/mcp/sse"
      },
      capabilities: %{
        tools: true,
        resources: true,
        prompts: true
      },
      trust_level: :medium,
      timeout: 120_000,
      environment: variables
    }

    {:ok, config}
  end

  defp save_server_configuration(server_name, config) do
    # Load current configuration
    case Config.load_configuration() do
      {:ok, current_config} ->
        # Add new server to configuration
        updated_servers = Map.put(current_config.servers, server_name, config)
        updated_config = %{current_config | servers: updated_servers}

        # Save updated configuration
        Config.save_configuration(updated_config)

      {:error, reason} ->
        CLI.print_error("Failed to load current configuration: #{inspect(reason)}")
        {:error, :load_failed}
    end
  end

  # Template creation helpers

  defp prompt_for_input(prompt, default \\ nil) do
    case IO.gets(prompt) do
      input when is_binary(input) ->
        trimmed = String.trim(input)

        if String.length(trimmed) > 0 do
          trimmed
        else
          default || ""
        end

      _ ->
        default || ""
    end
  end

  defp prompt_for_transport do
    IO.puts("Available transports:")
    IO.puts("  1. stdio - Local executable")
    IO.puts("  2. http - HTTP/REST API")
    IO.puts("  3. sse - Server-Sent Events")

    case IO.gets("Select transport (1-3): ") do
      "1\n" -> "stdio"
      "2\n" -> "http"
      "3\n" -> "sse"
      # Default to stdio
      _ -> "stdio"
    end
  end

  defp create_stdio_template(name, description, category) do
    template = %{
      name: name,
      description: description,
      category: category,
      transport: "stdio",
      version: "1.0",
      variables: [
        %{name: "command", description: "Executable command", required: true},
        %{name: "args", description: "Command arguments", required: false, default: ""}
      ]
    }

    {:ok, template}
  end

  defp create_http_template(name, description, category) do
    template = %{
      name: name,
      description: description,
      category: category,
      transport: "http",
      version: "1.0",
      variables: [
        %{name: "base_url", description: "Base URL for HTTP API", required: true},
        %{name: "api_key", description: "API key for authentication", required: false}
      ]
    }

    {:ok, template}
  end

  defp create_sse_template(name, description, category) do
    template = %{
      name: name,
      description: description,
      category: category,
      transport: "sse",
      version: "1.0",
      variables: [
        %{name: "base_url", description: "Base URL for SSE endpoint", required: true},
        %{
          name: "endpoint",
          description: "SSE endpoint path",
          required: false,
          default: "/mcp/sse"
        }
      ]
    }

    {:ok, template}
  end

  # Template validation functions

  defp validate_basic_structure(template, errors, warnings) do
    errors =
      if Map.get(template, :name) do
        errors
      else
        ["Template missing required field: name" | errors]
      end

    errors =
      if Map.get(template, :description) do
        errors
      else
        ["Template missing required field: description" | errors]
      end

    warnings =
      if Map.get(template, :version) do
        warnings
      else
        ["Template missing version field" | warnings]
      end

    {errors, warnings}
  end

  defp validate_transport_config(template, errors, warnings) do
    transport = Map.get(template, :transport)

    cond do
      transport == nil ->
        {["Template missing transport configuration" | errors], warnings}

      transport not in ["stdio", "http", "sse"] ->
        {["Unsupported transport type: #{transport}" | errors], warnings}

      true ->
        {errors, warnings}
    end
  end

  defp validate_template_variables(template, errors, warnings) do
    variables = Map.get(template, :variables, [])

    # Check for duplicate variable names
    var_names = Enum.map(variables, fn var -> var.name end)
    duplicates = var_names -- Enum.uniq(var_names)

    errors =
      if length(duplicates) > 0 do
        ["Duplicate variable names: #{Enum.join(duplicates, ", ")}" | errors]
      else
        errors
      end

    # Check variable structure
    variable_errors =
      Enum.flat_map(variables, fn var ->
        cond do
          not Map.has_key?(var, :name) -> ["Variable missing name field"]
          not Map.has_key?(var, :description) -> ["Variable '#{var.name}' missing description"]
          true -> []
        end
      end)

    {variable_errors ++ errors, warnings}
  end

  defp format_template_config(template) do
    "Transport: #{template.transport}, Variables: #{length(template.variables)}"
  end

  # Template persistence (mock implementation)

  defp save_template(_template) do
    # In real implementation, would save to filesystem
    :ok
  end

  defp remove_template(_template_name) do
    # In real implementation, would remove from filesystem
    :ok
  end
end
