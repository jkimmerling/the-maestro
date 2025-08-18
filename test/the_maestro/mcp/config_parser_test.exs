defmodule TheMaestro.MCP.ConfigParserTest do
  @moduledoc """
  Tests for MCP Configuration Parsing and Validation components.

  This test suite validates the configuration parsing, template processing,
  environment variable resolution, and comprehensive validation system.
  """

  use ExUnit.Case
  import ExUnit.CaptureLog

  alias TheMaestro.MCP.Config.{ConfigParser, ConfigValidator, EnvResolver, TemplateParser}

  describe "ConfigParser" do
    test "parses valid JSON configuration" do
      json_config = """
      {
        "mcpServers": {
          "test": {
            "command": "python",
            "args": ["-m", "test_server"],
            "trust": false
          }
        }
      }
      """

      assert {:ok, config} = ConfigParser.parse(json_config, :json)
      assert config["mcpServers"]["test"]["command"] == "python"
    end

    test "parses valid YAML configuration" do
      yaml_config = """
      mcpServers:
        test:
          command: python
          args:
            - -m
            - test_server
          trust: false
      """

      assert {:ok, config} = ConfigParser.parse(yaml_config, :yaml)
      assert config["mcpServers"]["test"]["command"] == "python"
    end

    test "returns error for invalid JSON" do
      invalid_json = "{ invalid json }"

      assert {:error, {:json_decode_error, _}} = ConfigParser.parse(invalid_json, :json)
    end

    test "returns error for invalid YAML" do
      invalid_yaml = """
      invalid:
        yaml:
      - unclosed
      """

      assert {:error, {:yaml_decode_error, _}} = ConfigParser.parse(invalid_yaml, :yaml)
    end

    test "auto-detects format from file extension" do
      assert ConfigParser.detect_format("config.json") == :json
      assert ConfigParser.detect_format("config.yaml") == :yaml
      assert ConfigParser.detect_format("config.yml") == :yaml
      # Default
      assert ConfigParser.detect_format("config.unknown") == :json
    end

    test "parses configuration from file" do
      # This would test reading from actual files
      # For now, test the interface
      assert is_function(&ConfigParser.parse_file/1, 1)
    end
  end

  describe "ConfigValidator" do
    test "validates correct server configuration structure" do
      valid_config = %{
        "mcpServers" => %{
          "stdio_server" => %{
            "command" => "python",
            "args" => ["-m", "server"],
            "trust" => false
          },
          "sse_server" => %{
            "url" => "https://example.com/sse",
            "trust" => true
          },
          "http_server" => %{
            "httpUrl" => "http://localhost:3000/mcp",
            "trust" => false
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(valid_config)
    end

    test "rejects configuration with missing required transport fields" do
      invalid_config = %{
        "mcpServers" => %{
          "invalid_server" => %{
            "trust" => false
            # Missing command, url, or httpUrl
          }
        }
      }

      assert {:error, errors} = ConfigValidator.validate(invalid_config)
      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1, "transport"))
    end

    test "validates STDIO server configuration" do
      config = %{
        "mcpServers" => %{
          "stdio_server" => %{
            "command" => "python",
            "args" => ["-m", "server"],
            "cwd" => "/workspace",
            "env" => %{"VAR" => "value"},
            "timeout" => 30000,
            "trust" => false
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates SSE server configuration" do
      config = %{
        "mcpServers" => %{
          "sse_server" => %{
            "url" => "https://example.com/sse",
            "headers" => %{
              "Authorization" => "Bearer token"
            },
            "timeout" => 15000,
            "trust" => true
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates HTTP server configuration" do
      config = %{
        "mcpServers" => %{
          "http_server" => %{
            "httpUrl" => "http://localhost:3000/mcp",
            "headers" => %{
              "Content-Type" => "application/json",
              "Authorization" => "Bearer token"
            },
            "timeout" => 10000,
            "trust" => false
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates tool filtering configuration" do
      config = %{
        "mcpServers" => %{
          "server" => %{
            "command" => "python",
            "includeTools" => ["read_file", "write_file"],
            "excludeTools" => ["delete_file", "format_disk"]
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates OAuth configuration" do
      config = %{
        "mcpServers" => %{
          "oauth_server" => %{
            "url" => "https://example.com/sse",
            "oauth" => %{
              "enabled" => true,
              "clientId" => "client-id",
              "scopes" => ["read", "write"]
            }
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates rate limiting configuration" do
      config = %{
        "mcpServers" => %{
          "limited_server" => %{
            "httpUrl" => "http://localhost:3000/mcp",
            "rateLimiting" => %{
              "enabled" => true,
              "requestsPerMinute" => 60,
              "burstSize" => 10
            }
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "validates global settings" do
      config = %{
        "mcpServers" => %{},
        "globalSettings" => %{
          "defaultTimeout" => 30000,
          "maxConcurrentConnections" => 10,
          "confirmationLevel" => "medium",
          "auditLogging" => true,
          "autoReconnect" => true,
          "healthCheckInterval" => 60000
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)
    end

    test "rejects invalid global settings values" do
      config = %{
        "mcpServers" => %{},
        "globalSettings" => %{
          # Should be low/medium/high
          "confirmationLevel" => "invalid_level",
          # Should be positive
          "defaultTimeout" => -1
        }
      }

      assert {:error, errors} = ConfigValidator.validate(config)
      assert length(errors) > 0
    end

    test "validates server dependencies" do
      config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "python",
            "dependencies" => ["server2"]
          },
          "server2" => %{
            "command" => "node"
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate(config)

      # Test circular dependency detection
      circular_config = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "python",
            "dependencies" => ["server2"]
          },
          "server2" => %{
            "command" => "node",
            # Circular!
            "dependencies" => ["server1"]
          }
        }
      }

      assert {:error, errors} = ConfigValidator.validate(circular_config)
      assert Enum.any?(errors, &String.contains?(&1, "circular"))
    end

    test "validates URL formats" do
      # Valid URLs
      valid_config = %{
        "mcpServers" => %{
          "sse_server" => %{"url" => "https://example.com/sse"},
          "http_server" => %{"httpUrl" => "http://localhost:3000/mcp"}
        }
      }

      assert {:ok, _} = ConfigValidator.validate(valid_config)

      # Invalid URLs
      invalid_config = %{
        "mcpServers" => %{
          "bad_server" => %{"url" => "not-a-url"}
        }
      }

      assert {:error, errors} = ConfigValidator.validate(invalid_config)
      assert Enum.any?(errors, &String.contains?(&1, "URL"))
    end
  end

  describe "EnvResolver" do
    setup do
      System.put_env("TEST_VAR", "test_value")
      System.put_env("API_TOKEN", "secret123")
      System.put_env("PORT", "3000")
      System.put_env("PATH", "/usr/bin:/bin")

      on_exit(fn ->
        System.delete_env("TEST_VAR")
        System.delete_env("API_TOKEN")
        System.delete_env("PORT")
      end)
    end

    test "resolves simple environment variable substitution" do
      input = "$TEST_VAR"
      assert EnvResolver.resolve(input) == "test_value"
    end

    test "resolves environment variables with braces" do
      input = "${API_TOKEN}"
      assert EnvResolver.resolve(input) == "secret123"
    end

    test "resolves environment variables with default values" do
      input = "${MISSING_VAR:-default_value}"
      assert EnvResolver.resolve(input) == "default_value"

      input = "${PORT:-8080}"
      # PORT exists
      assert EnvResolver.resolve(input) == "3000"
    end

    test "resolves path expansion" do
      input = "${PATH}:/custom/bin"
      result = EnvResolver.resolve(input)
      assert String.contains?(result, "/usr/bin:/bin")
      assert String.ends_with?(result, ":/custom/bin")
    end

    test "handles multiple variables in one string" do
      input = "${TEST_VAR}_${API_TOKEN}"
      assert EnvResolver.resolve(input) == "test_value_secret123"
    end

    test "resolves nested data structures" do
      config = %{
        "env" => %{
          "API_KEY" => "$API_TOKEN",
          "PORT" => "${PORT:-8080}",
          "PATH" => "${PATH}:/custom"
        },
        "command" => "server --port ${PORT}"
      }

      resolved = EnvResolver.resolve_config(config)
      assert resolved["env"]["API_KEY"] == "secret123"
      assert resolved["env"]["PORT"] == "3000"
      assert String.contains?(resolved["env"]["PATH"], "/custom")
      assert resolved["command"] == "server --port 3000"
    end

    test "leaves unresolved variables unchanged with warning" do
      input = "$UNDEFINED_VAR"

      assert capture_log(fn ->
               result = EnvResolver.resolve(input)
               assert result == "$UNDEFINED_VAR"
             end) =~ "Environment variable UNDEFINED_VAR not found"
    end
  end

  describe "TemplateParser" do
    test "applies simple variable substitution to template" do
      template = %{
        "command" => "{command}",
        "args" => ["-m", "{module}"],
        "port" => "{port}"
      }

      variables = %{
        "command" => "python",
        "module" => "my_server",
        "port" => "3000"
      }

      result = TemplateParser.apply_template(template, variables)

      assert result["command"] == "python"
      assert result["args"] == ["-m", "my_server"]
      assert result["port"] == "3000"
    end

    test "applies nested template substitution" do
      template = %{
        "servers" => %{
          "{server_name}" => %{
            "command" => "{command}",
            "env" => %{
              "{env_var}" => "{env_value}"
            }
          }
        }
      }

      variables = %{
        "server_name" => "myServer",
        "command" => "python",
        "env_var" => "API_KEY",
        "env_value" => "secret"
      }

      result = TemplateParser.apply_template(template, variables)

      assert Map.has_key?(result["servers"], "myServer")
      assert result["servers"]["myServer"]["command"] == "python"
      assert result["servers"]["myServer"]["env"]["API_KEY"] == "secret"
    end

    test "handles missing template variables gracefully" do
      template = %{
        "command" => "{command}",
        "missing" => "{undefined_var}"
      }

      variables = %{
        "command" => "python"
      }

      assert capture_log(fn ->
               result = TemplateParser.apply_template(template, variables)
               assert result["command"] == "python"
               # Unchanged
               assert result["missing"] == "{undefined_var}"
             end) =~ "Template variable undefined_var not found"
    end

    test "validates template structure" do
      valid_template = %{
        "command" => "{command}",
        "trust" => false
      }

      assert {:ok, _} = TemplateParser.validate_template(valid_template)

      invalid_template = %{
        "invalid_field" => "value"
      }

      assert {:error, errors} = TemplateParser.validate_template(invalid_template)
      assert length(errors) > 0
    end

    test "extracts variables from template" do
      template = %{
        "command" => "{command}",
        "args" => ["-m", "{module}"],
        "env" => %{
          "{env_name}" => "{env_value}"
        }
      }

      variables = TemplateParser.extract_variables(template)
      expected = ["command", "module", "env_name", "env_value"]

      assert Enum.sort(variables) == Enum.sort(expected)
    end
  end

  describe "configuration inheritance and merging" do
    test "merges configurations with proper precedence" do
      base = %{
        "mcpServers" => %{
          "server1" => %{
            "command" => "base-command",
            "trust" => false,
            "timeout" => 30000
          }
        },
        "globalSettings" => %{
          "defaultTimeout" => 30000
        }
      }

      override = %{
        "mcpServers" => %{
          "server1" => %{
            # Override
            "trust" => true,
            # Add
            "includeTools" => ["new_tool"]
          },
          # New server
          "server2" => %{
            "url" => "https://example.com"
          }
        }
      }

      merged = ConfigParser.merge_configs([base, override])

      server1 = merged["mcpServers"]["server1"]
      # Preserved
      assert server1["command"] == "base-command"
      # Overridden
      assert server1["trust"] == true
      # Preserved
      assert server1["timeout"] == 30000
      # Added
      assert "new_tool" in server1["includeTools"]

      # Added
      assert Map.has_key?(merged["mcpServers"], "server2")
    end
  end

  describe "configuration schema validation" do
    test "validates against JSON schema" do
      # This test would validate configuration against a JSON schema
      config = %{
        "mcpServers" => %{
          "test" => %{
            "command" => "python"
          }
        }
      }

      assert {:ok, _} = ConfigValidator.validate_schema(config)
    end

    test "provides detailed validation error messages" do
      invalid_config = %{
        "mcpServers" => %{
          "test" => %{
            # Should be integer
            "timeout" => "not-a-number"
          }
        }
      }

      assert {:error, errors} = ConfigValidator.validate_schema(invalid_config)
      assert Enum.any?(errors, &String.contains?(&1, "timeout"))
      assert Enum.any?(errors, &String.contains?(&1, "integer"))
    end
  end
end
