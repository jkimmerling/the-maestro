defmodule TheMaestro.MCP.CLI.Commands.ImportExport do
  @moduledoc """
  Import/Export commands for MCP CLI.

  Provides functionality to import and export MCP server configurations.
  """

  alias TheMaestro.MCP.{Config, ConfigValidator}
  alias TheMaestro.MCP.CLI

  @doc """
  Execute the import command.
  """
  def execute_import(args, options) do
    if Map.get(options, :help) do
      show_import_help()
      {:ok, :help}
    end

    case args do
      [file_path] ->
        import_configuration(file_path, options)

      [] ->
        CLI.print_error("Missing import file path")
        {:error, :missing_path}

      _ ->
        CLI.print_error("Invalid import command. Use --help for usage.")
        {:error, :invalid_args}
    end
  end

  @doc """
  Execute the export command.
  """
  def execute_export(args, options) do
    if Map.get(options, :help) do
      show_export_help()
      {:ok, :help}
    end

    case args do
      [file_path] ->
        export_configuration(file_path, options)

      [] ->
        # Export to stdout if no path provided
        export_configuration(:stdout, options)

      _ ->
        CLI.print_error("Invalid export command. Use --help for usage.")
        {:error, :invalid_args}
    end
  end

  @doc """
  Show help for the import command.
  """
  def show_import_help do
    IO.puts("""
    MCP Configuration Import

    Usage:
      maestro mcp import <file_path> [OPTIONS]

    Options:
      --format <format>        Import format (json, yaml, toml) [auto-detect]
      --merge                  Merge with existing configuration
      --overwrite              Overwrite existing servers with same names
      --validate               Validate configuration before importing
      --dry-run                Show what would be imported without applying
      --backup                 Create backup before importing
      --help                   Show this help message

    Examples:
      maestro mcp import servers.json
      maestro mcp import backup.yaml --merge --validate
      maestro mcp import config.toml --dry-run
      maestro mcp import servers.json --backup --overwrite
    """)
  end

  @doc """
  Show help for the export command.
  """
  def show_export_help do
    IO.puts("""
    MCP Configuration Export

    Usage:
      maestro mcp export [file_path] [OPTIONS]

    Options:
      --format <format>        Export format (json, yaml, toml) [json]
      --servers <names>        Export specific servers (comma-separated)
      --include-auth           Include authentication credentials
      --include-templates      Include template definitions
      --compress               Compress exported data
      --pretty                 Pretty-print output
      --help                   Show this help message

    Examples:
      maestro mcp export                          # Export to stdout
      maestro mcp export backup.json --pretty
      maestro mcp export servers.yaml --servers server1,server2
      maestro mcp export full-backup.json --include-auth --include-templates
    """)
  end

  ## Private Functions

  defp import_configuration(file_path, options) do
    dry_run = Map.get(options, :dry_run, false)
    action = if dry_run, do: "Would import", else: "Importing"

    CLI.print_info("#{action} configuration from '#{file_path}'...")

    # Create backup if requested
    if Map.get(options, :backup, false) && not dry_run do
      create_backup_before_import()
    end

    with {:ok, import_data} <- read_import_file(file_path, options),
         {:ok, validated_data} <- validate_import_data(import_data, options),
         {:ok, merge_plan} <- plan_configuration_merge(validated_data, options) do
      if dry_run do
        show_import_preview(merge_plan, options)
        {:ok, :dry_run}
      else
        apply_configuration_import(merge_plan, options)
      end
    else
      {:error, :file_not_found} ->
        CLI.print_error("Import file not found: #{file_path}")
        {:error, :file_not_found}

      {:error, :invalid_format} ->
        CLI.print_error("Invalid configuration format in import file")
        {:error, :invalid_format}

      {:error, :validation_failed, errors} ->
        CLI.print_error("Configuration validation failed:")

        Enum.each(errors, fn error ->
          IO.puts("  ❌ #{error}")
        end)

        {:error, :validation_failed}

      {:error, reason} ->
        CLI.print_error("Import failed: #{inspect(reason)}")
        {:error, :import_failed}
    end
  end

  defp export_configuration(destination, options) do
    format = Map.get(options, :format, "json")

    action = if destination == :stdout, do: "to stdout", else: "to '#{destination}'"
    CLI.print_info("Exporting configuration #{action}...")

    with {:ok, current_config} <- Config.load_configuration(),
         {:ok, export_data} <- prepare_export_data(current_config, options),
         {:ok, formatted_data} <- format_export_data(export_data, format, options) do
      case destination do
        :stdout ->
          IO.puts("")
          IO.puts(formatted_data)
          IO.puts("")
          {:ok, :stdout}

        file_path ->
          case write_export_file(file_path, formatted_data, options) do
            :ok ->
              file_size = byte_size(formatted_data)

              CLI.print_success("Configuration exported to '#{file_path}' (#{file_size} bytes)")

              # Show export summary
              show_export_summary(export_data, options)

              {:ok, file_path}

            {:error, reason} ->
              CLI.print_error("Failed to write export file: #{inspect(reason)}")
              {:error, :write_failed}
          end
      end
    else
      {:error, reason} ->
        CLI.print_error("Export failed: #{inspect(reason)}")
        {:error, :export_failed}
    end
  end

  # Import helper functions

  defp read_import_file(file_path, options) do
    case File.read(file_path) do
      {:ok, content} ->
        format = detect_file_format(file_path, options)
        parse_import_content(content, format)

      {:error, :enoent} ->
        {:error, :file_not_found}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  defp detect_file_format(file_path, options) do
    case Map.get(options, :format) do
      nil ->
        # Auto-detect from file extension
        case Path.extname(file_path) do
          ".json" -> :json
          ".yaml" -> :yaml
          ".yml" -> :yaml
          ".toml" -> :toml
          # Default to JSON
          _ -> :json
        end

      format_str ->
        case String.downcase(format_str) do
          "json" -> :json
          "yaml" -> :yaml
          "yml" -> :yaml
          "toml" -> :toml
          _ -> :json
        end
    end
  end

  defp parse_import_content(content, format) do
    try do
      case format do
        :json ->
          {:ok, Jason.decode!(content)}

        :yaml ->
          {:ok, YamlElixir.read_from_string!(content)}

        :toml ->
          # TOML parsing would require additional dependency
          {:error, :toml_not_supported}

        _ ->
          {:error, :unsupported_format}
      end
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp validate_import_data(import_data, options) do
    if Map.get(options, :validate, true) do
      errors = []

      # Validate overall structure
      errors = validate_import_structure(import_data, errors)

      # Validate each server configuration
      servers = Map.get(import_data, "servers", %{})

      {errors, _warnings} =
        Enum.reduce(servers, {errors, []}, fn {name, server}, {errs, warns} ->
          case ConfigValidator.validate_server_config(name, server) do
            {:ok, _} -> {errs, warns}
            {:error, validation_errors} -> {validation_errors ++ errs, warns}
          end
        end)

      if length(errors) > 0 do
        {:error, :validation_failed, errors}
      else
        {:ok, import_data}
      end
    else
      {:ok, import_data}
    end
  end

  defp validate_import_structure(import_data, errors) do
    errors =
      if is_map(import_data) do
        errors
      else
        ["Import data must be a JSON/YAML object" | errors]
      end

    errors =
      if Map.has_key?(import_data, "servers") do
        errors
      else
        ["Import data must contain 'servers' section" | errors]
      end

    servers = Map.get(import_data, "servers", %{})

    if is_map(servers) do
      errors
    else
      ["Servers section must be an object" | errors]
    end
  end

  defp plan_configuration_merge(import_data, options) do
    merge_mode = if Map.get(options, :merge, false), do: :merge, else: :replace
    overwrite = Map.get(options, :overwrite, false)

    case Config.load_configuration() do
      {:ok, current_config} ->
        import_servers = Map.get(import_data, "servers", %{})
        current_servers = current_config.servers

        # Plan the merge operation
        merge_plan = %{
          mode: merge_mode,
          overwrite: overwrite,
          new_servers: [],
          updated_servers: [],
          conflicting_servers: [],
          import_servers: import_servers,
          current_servers: current_servers
        }

        # Analyze server conflicts and updates
        final_plan =
          Enum.reduce(import_servers, merge_plan, fn {name, server}, plan ->
            cond do
              not Map.has_key?(current_servers, name) ->
                # New server
                %{plan | new_servers: [name | plan.new_servers]}

              overwrite ->
                # Will overwrite existing server
                %{plan | updated_servers: [name | plan.updated_servers]}

              merge_mode == :merge ->
                # Will merge with existing server
                %{plan | updated_servers: [name | plan.updated_servers]}

              true ->
                # Conflicting server (exists but no overwrite)
                %{plan | conflicting_servers: [name | plan.conflicting_servers]}
            end
          end)

        {:ok, final_plan}

      {:error, reason} ->
        {:error, {:config_load_error, reason}}
    end
  end

  defp show_import_preview(merge_plan, _options) do
    IO.puts("")
    IO.puts("  Import Preview:")

    if length(merge_plan.new_servers) > 0 do
      IO.puts("    New servers to create: #{length(merge_plan.new_servers)}")

      Enum.each(merge_plan.new_servers, fn name ->
        IO.puts("      + #{name}")
      end)
    end

    if length(merge_plan.updated_servers) > 0 do
      action = if merge_plan.overwrite, do: "overwrite", else: "update"
      IO.puts("    Servers to #{action}: #{length(merge_plan.updated_servers)}")

      Enum.each(merge_plan.updated_servers, fn name ->
        IO.puts("      ~ #{name}")
      end)
    end

    if length(merge_plan.conflicting_servers) > 0 do
      IO.puts("    Conflicting servers (skipped): #{length(merge_plan.conflicting_servers)}")

      Enum.each(merge_plan.conflicting_servers, fn name ->
        IO.puts("      ! #{name} (use --overwrite to replace)")
      end)
    end

    total_changes = length(merge_plan.new_servers) + length(merge_plan.updated_servers)
    IO.puts("")
    IO.puts("  Total changes: #{total_changes}")
  end

  defp apply_configuration_import(merge_plan, _options) do
    case Config.load_configuration() do
      {:ok, current_config} ->
        # Apply the merge plan
        updated_servers =
          Enum.reduce(
            merge_plan.new_servers ++ merge_plan.updated_servers,
            current_config.servers,
            fn name, servers ->
              import_server = Map.get(merge_plan.import_servers, name)

              if merge_plan.mode == :merge && Map.has_key?(servers, name) do
                # Merge with existing server
                existing_server = Map.get(servers, name)
                merged_server = Map.merge(existing_server, import_server)
                Map.put(servers, name, merged_server)
              else
                # Add new or replace existing server
                Map.put(servers, name, import_server)
              end
            end
          )

        updated_config = %{current_config | servers: updated_servers}

        case Config.save_configuration(updated_config) do
          :ok ->
            new_count = length(merge_plan.new_servers)
            updated_count = length(merge_plan.updated_servers)
            skipped_count = length(merge_plan.conflicting_servers)

            CLI.print_success("Configuration imported successfully")
            IO.puts("  New servers: #{new_count}")
            IO.puts("  Updated servers: #{updated_count}")

            if skipped_count > 0 do
              IO.puts("  Skipped (conflicts): #{skipped_count}")
            end

            {:ok, updated_config}

          {:error, reason} ->
            CLI.print_error("Failed to save imported configuration: #{inspect(reason)}")

            {:error, :save_failed}
        end

      {:error, reason} ->
        {:error, {:config_load_error, reason}}
    end
  end

  # Export helper functions

  defp prepare_export_data(current_config, options) do
    # Start with base configuration
    export_data = %{
      "version" => "1.0",
      "exported_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "servers" => %{}
    }

    # Filter servers if specific ones requested
    servers_to_export =
      case Map.get(options, :servers) do
        nil ->
          current_config.servers

        server_names_str ->
          server_names = String.split(server_names_str, ",") |> Enum.map(&String.trim/1)
          Map.take(current_config.servers, server_names)
      end

    # Prepare server data (potentially sanitizing sensitive information)
    sanitized_servers =
      if Map.get(options, :include_auth, false) do
        servers_to_export
      else
        # Remove sensitive authentication information
        servers_to_export
        |> Enum.map(fn {name, server} ->
          sanitized_server =
            server
            |> Map.delete(:api_key)
            |> Map.delete(:auth_token)
            |> Map.delete(:credentials)

          {name, sanitized_server}
        end)
        |> Map.new()
      end

    export_data = %{export_data | "servers" => sanitized_servers}

    # Add templates if requested
    export_data =
      if Map.get(options, :include_templates, false) do
        case get_available_templates() do
          {:ok, templates} ->
            Map.put(export_data, "templates", templates)

          _ ->
            export_data
        end
      else
        export_data
      end

    {:ok, export_data}
  end

  defp format_export_data(export_data, format, options) do
    pretty = Map.get(options, :pretty, false)

    try do
      case format do
        "json" ->
          if pretty do
            {:ok, Jason.encode!(export_data, pretty: true)}
          else
            {:ok, Jason.encode!(export_data)}
          end

        "yaml" ->
          {:ok, YamlElixir.write_to_string!(export_data)}

        "toml" ->
          {:error, :toml_not_supported}

        _ ->
          {:error, :unsupported_format}
      end
    rescue
      error -> {:error, {:format_error, error}}
    end
  end

  defp write_export_file(file_path, formatted_data, options) do
    # Create directory if it doesn't exist
    case Path.dirname(file_path) do
      "." -> :ok
      dir -> File.mkdir_p(dir)
    end

    # Compress if requested
    final_data =
      if Map.get(options, :compress, false) do
        :zlib.compress(formatted_data)
      else
        formatted_data
      end

    File.write(file_path, final_data)
  end

  defp show_export_summary(export_data, _options) do
    server_count = map_size(Map.get(export_data, "servers", %{}))
    has_templates = Map.has_key?(export_data, "templates")

    IO.puts("")
    IO.puts("  Export Summary:")
    IO.puts("    Servers exported: #{server_count}")

    if has_templates do
      template_count = length(Map.get(export_data, "templates", []))
      IO.puts("    Templates exported: #{template_count}")
    end
  end

  # Backup functions

  defp create_backup_before_import do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    backup_file = "mcp_config_backup_#{timestamp}.json"

    CLI.print_info("Creating backup: #{backup_file}")

    case execute_export([backup_file], %{format: "json", pretty: true}) do
      {:ok, _} ->
        CLI.print_success("Backup created: #{backup_file}")

      {:error, reason} ->
        CLI.print_warning("Failed to create backup: #{inspect(reason)}")
    end
  end

  # Template support (reused from Templates module)

  defp get_available_templates do
    # This would be extracted to a shared module in real implementation
    templates = [
      %{
        name: "openai-gpt",
        description: "OpenAI GPT API server",
        transport: "http",
        variables: ["api_key", "model"]
      }
    ]

    {:ok, templates}
  end
end
