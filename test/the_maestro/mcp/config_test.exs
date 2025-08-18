defmodule TheMaestro.MCP.ConfigTest do
  @moduledoc """
  Tests for MCP Configuration Management system.

  This test suite validates the comprehensive MCP configuration management
  system including file-based configuration, validation, environment variable
  resolution, and configuration merging.
  """

  use ExUnit.Case
  import ExUnit.CaptureLog

  alias TheMaestro.MCP.Config

  @tmp_dir Path.join([System.tmp_dir!(), "maestro_config_test"])

  setup do
    # Create temp directory for test files
    File.mkdir_p!(@tmp_dir)

    # Ensure PubSub is available for configuration reload operations
    unless Process.whereis(TheMaestro.PubSub) do
      {:ok, _} = Supervisor.start_link([{Phoenix.PubSub, name: TheMaestro.PubSub}], strategy: :one_for_one)
    end

    on_exit(fn ->
      File.rm_rf(@tmp_dir)
    end)

    {:ok, tmp_dir: @tmp_dir}
  end

  describe "load_configuration/1" do
    test "loads valid configuration from file", %{tmp_dir: tmp_dir} do
      config_path = Path.join(tmp_dir, "mcp_settings.json")

      config_content = %{
        "mcpServers" => %{
          "fileSystem" => %{
            "command" => "python",
            "args" => ["-m", "filesystem_mcp_server"],
            "env" => %{
              "ALLOWED_DIRS" => "/tmp,/workspace"
            },
            "trust" => false,
            "includeTools" => ["read_file", "write_file"]
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30_000,
          "confirmationLevel" => "medium"
        }
      }

      File.write!(config_path, Jason.encode!(config_content))

      assert {:ok, loaded_config} = Config.load_configuration(config_path)
      assert loaded_config["mcpServers"]["fileSystem"]["command"] == "python"
      assert loaded_config["globalSettings"]["defaultTimeout"] == 30_000
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} = Config.load_configuration("/non/existent/path")
    end

    test "returns error for invalid JSON", %{tmp_dir: tmp_dir} do
      config_path = Path.join(tmp_dir, "invalid.json")
      File.write!(config_path, "{ invalid json }")

      assert {:error, {:json_decode_error, _}} = Config.load_configuration(config_path)
    end

    test "loads configuration with inheritance hierarchy", %{tmp_dir: tmp_dir} do
      # Global config
      global_config = Path.join(tmp_dir, "global_mcp_settings.json")

      global_content = %{
        "mcpServers" => %{
          "globalServer" => %{
            "command" => "global-server",
            "trust" => false
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30_000
        }
      }

      File.write!(global_config, Jason.encode!(global_content))

      # Project config
      project_config = Path.join(tmp_dir, "project_mcp_settings.json")

      project_content = %{
        "mcpServers" => %{
          "projectServer" => %{
            "command" => "project-server",
            "trust" => true
          },
          "globalServer" => %{
            # Override global setting
            "trust" => true
          }
        }
      }

      File.write!(project_config, Jason.encode!(project_content))

      assert {:ok, merged_config} = Config.load_configuration([global_config, project_config])

      # Should have both servers
      assert Map.has_key?(merged_config["mcpServers"], "globalServer")
      assert Map.has_key?(merged_config["mcpServers"], "projectServer")

      # Global server trust should be overridden
      assert merged_config["mcpServers"]["globalServer"]["trust"] == true
    end
  end

  describe "validate_configuration/1" do
    test "validates correct configuration structure" do
      valid_config = %{
        "mcpServers" => %{
          "test" => %{
            "command" => "python",
            "args" => ["-m", "test_server"],
            "trust" => false
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30_000
        }
      }

      assert {:ok, _} = Config.validate_configuration(valid_config)
    end

    test "rejects configuration with missing required fields" do
      invalid_config = %{
        "mcpServers" => %{
          "test" => %{
            # Missing command/url
            "trust" => false
          }
        }
      }

      assert {:error, errors} = Config.validate_configuration(invalid_config)
      assert length(errors) > 0
    end

    test "validates transport-specific configurations" do
      stdio_config = %{
        "mcpServers" => %{
          "stdio_server" => %{
            "command" => "python",
            "args" => ["-m", "server"],
            "cwd" => "/tmp",
            "timeout" => 30_000
          }
        }
      }

      sse_config = %{
        "mcpServers" => %{
          "sse_server" => %{
            "url" => "https://example.com/sse",
            "headers" => %{"Authorization" => "Bearer token"}
          }
        }
      }

      http_config = %{
        "mcpServers" => %{
          "http_server" => %{
            "httpUrl" => "http://localhost:3000/mcp",
            "headers" => %{"Content-Type" => "application/json"}
          }
        }
      }

      assert {:ok, _} = Config.validate_configuration(stdio_config)
      assert {:ok, _} = Config.validate_configuration(sse_config)
      assert {:ok, _} = Config.validate_configuration(http_config)
    end

    test "validates security settings" do
      config = %{
        "mcpServers" => %{
          "secure_server" => %{
            "command" => "python",
            "trust" => false,
            "includeTools" => ["safe_tool"],
            "excludeTools" => ["dangerous_tool"],
            "rateLimiting" => %{
              "enabled" => true,
              "requestsPerMinute" => 60
            }
          }
        }
      }

      assert {:ok, validated} = Config.validate_configuration(config)
      server = validated["mcpServers"]["secure_server"]
      assert server["trust"] == false
      assert "safe_tool" in server["includeTools"]
      assert "dangerous_tool" in server["excludeTools"]
    end
  end

  describe "resolve_environment_variables/1" do
    setup do
      # Set test environment variables
      System.put_env("TEST_API_KEY", "secret123")
      System.put_env("TEST_DB_URL", "postgres://localhost/test")
      System.put_env("PATH", "/usr/bin:/bin")

      on_exit(fn ->
        System.delete_env("TEST_API_KEY")
        System.delete_env("TEST_DB_URL")
      end)
    end

    test "resolves simple environment variable substitution" do
      config = %{
        "mcpServers" => %{
          "test" => %{
            "env" => %{
              "API_KEY" => "$TEST_API_KEY"
            }
          }
        }
      }

      resolved = Config.resolve_environment_variables(config)
      assert resolved["mcpServers"]["test"]["env"]["API_KEY"] == "secret123"
    end

    test "resolves environment variables with default values" do
      config = %{
        "mcpServers" => %{
          "test" => %{
            "env" => %{
              "DEBUG" => "${DEBUG:-false}",
              "PORT" => "${MISSING_VAR:-3000}"
            }
          }
        }
      }

      resolved = Config.resolve_environment_variables(config)
      assert resolved["mcpServers"]["test"]["env"]["DEBUG"] == "false"
      assert resolved["mcpServers"]["test"]["env"]["PORT"] == "3000"
    end

    test "resolves path expansion" do
      config = %{
        "mcpServers" => %{
          "test" => %{
            "env" => %{
              "CUSTOM_PATH" => "${PATH}:/custom/bin"
            }
          }
        }
      }

      resolved = Config.resolve_environment_variables(config)
      custom_path = resolved["mcpServers"]["test"]["env"]["CUSTOM_PATH"]
      assert String.contains?(custom_path, "/usr/bin:/bin")
      assert String.ends_with?(custom_path, ":/custom/bin")
    end

    test "handles missing environment variables gracefully" do
      config = %{
        "mcpServers" => %{
          "test" => %{
            "env" => %{
              "MISSING" => "$UNDEFINED_VAR"
            }
          }
        }
      }

      assert capture_log(fn ->
               resolved = Config.resolve_environment_variables(config)
               assert resolved["mcpServers"]["test"]["env"]["MISSING"] == "$UNDEFINED_VAR"
             end) =~ "Environment variable UNDEFINED_VAR not found"
    end
  end

  describe "merge_configurations/1" do
    test "merges multiple configurations with proper precedence" do
      base_config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "base-command",
            "trust" => false,
            "timeout" => 30_000
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30_000,
          "confirmationLevel" => "low"
        }
      }

      override_config = %{
        "mcpServers" => %{
          "server1" => %{
            # Override
            "trust" => true,
            # Add new field
            "includeTools" => ["new_tool"]
          },
          # Add new server
          "server2" => %{
            "command" => "new-server"
          }
        },
        "globalSettings" => %{
          # Override
          "confirmationLevel" => "high"
        }
      }

      merged = Config.merge_configurations([base_config, override_config])

      server1 = merged["mcpServers"]["server1"]
      # Preserved
      assert server1["command"] == "base-command"
      # Overridden
      assert server1["trust"] == true
      # Preserved
      assert server1["timeout"] == 30_000
      # Added
      assert "new_tool" in server1["includeTools"]

      # New server added
      assert Map.has_key?(merged["mcpServers"], "server2")
      # Overridden
      assert merged["globalSettings"]["confirmationLevel"] == "high"
    end
  end

  describe "get_server_config/2" do
    test "retrieves specific server configuration" do
      config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "test-command"
          },
          "server2" => %{
            "url" => "https://example.com"
          }
        }
      }

      assert {:ok, server_config} = Config.get_server_config(config, "server1")
      assert server_config["command"] == "test-command"

      assert {:error, :not_found} = Config.get_server_config(config, "nonexistent")
    end
  end

  describe "update_server_config/3" do
    test "updates existing server configuration" do
      config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "old-command",
            "trust" => false
          }
        }
      }

      updates = %{
        "command" => "new-command",
        "timeout" => 60_000
      }

      updated_config = Config.update_server_config(config, "server1", updates)
      server = updated_config["mcpServers"]["server1"]

      assert server["command"] == "new-command"
      assert server["timeout"] == 60_000
      # Preserved
      assert server["trust"] == false
    end

    test "returns error for non-existent server" do
      config = %{"mcpServers" => %{}}

      assert {:error, :server_not_found} =
               Config.update_server_config(config, "nonexistent", %{"trust" => true})
    end
  end

  describe "reload_configuration/0" do
    test "reloads configuration and notifies subscribers", %{tmp_dir: tmp_dir} do
      # Create a valid config file in the current directory (one of the default paths)
      project_config_dir = Path.join(tmp_dir, ".maestro")
      File.mkdir_p!(project_config_dir)

      # Change to tmp directory so ./.maestro/mcp_settings.json will be found
      original_cwd = File.cwd!()
      File.cd!(tmp_dir)

      on_exit(fn ->
        File.cd!(original_cwd)
      end)

      project_config_path = Path.join(project_config_dir, "mcp_settings.json")

      config_content = %{
        "mcpServers" => %{
          "test_server" => %{
            "command" => "python",
            "args" => ["-m", "test_server"],
            "trust" => false
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30_000
        }
      }

      File.write!(project_config_path, Jason.encode!(config_content))

      assert :ok = Config.reload_configuration()
    end
  end

  describe "save_configuration/2" do
    test "saves configuration to file", %{tmp_dir: tmp_dir} do
      config = %{
        "mcpServers" => %{
          "test" => %{
            "command" => "python"
          }
        }
      }

      config_path = Path.join(tmp_dir, "saved_config.json")

      assert :ok = Config.save_configuration(config, config_path)
      assert File.exists?(config_path)

      {:ok, loaded} = Jason.decode(File.read!(config_path))
      assert loaded["mcpServers"]["test"]["command"] == "python"
    end
  end

  describe "configuration templates" do
    test "applies template to server configuration" do
      template = %{
        "command" => "{command}",
        "args" => ["-m", "{module}"],
        "timeout" => 30_000,
        "trust" => false
      }

      variables = %{
        "command" => "python",
        "module" => "my_server"
      }

      applied = Config.apply_template(template, variables)

      assert applied["command"] == "python"
      assert applied["args"] == ["-m", "my_server"]
      assert applied["timeout"] == 30_000
    end
  end
end
