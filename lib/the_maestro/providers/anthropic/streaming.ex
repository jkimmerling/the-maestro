defmodule TheMaestro.Providers.Anthropic.Streaming do
  @moduledoc """
  Anthropic streaming provider stub for Story 0.2/0.4.
  """
  @behaviour TheMaestro.Providers.Behaviours.Streaming
  require Logger
  alias TheMaestro.Providers.Http.ReqClientFactory
  alias TheMaestro.Providers.Http.StreamingAdapter
  alias TheMaestro.SavedAuthentication
  alias TheMaestro.Types

  @impl true
  @spec stream_chat(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_chat(session_id, messages, opts \\ []) do
    with true <- (is_list(messages) and messages != []) or {:error, :empty_messages},
         {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        base_body = %{
          "model" => model,
          "messages" => messages,
          "max_tokens" => Keyword.get(opts, :max_tokens, 512),
          "stream" => true
        }

        # Claude Code parity: add system prompt for OAuth tokens
        # Attach Claude Code tools and metadata for OAuth sessions so tool_use is allowed
        body =
          case auth_type do
            :oauth ->
              base_body
              |> Map.put("system", anthropic_system_blocks())
              |> Map.put("messages", transform_messages_for_claude_code(messages))
              |> Map.put("metadata", %{"user_id" => compute_user_id(session_id)})
              |> Map.put("tools", anthropic_tools())

            _ ->
              base_body
          end

        url = if auth_type == :oauth, do: "/v1/messages?beta=true", else: "/v1/messages"
        maybe_log_request(:initial, req, url, body)
        StreamingAdapter.stream_request(req, method: :post, url: url, json: body)
      end
    end
  end

  @impl true
  @spec parse_stream_event(map(), map()) :: {[map()], map()}
  def parse_stream_event(_event, state) do
    {[], state}
  end

  @doc """
  Stream a follow-up request that supplies tool results back to Anthropic.

  `messages` must be a full Anthropic messages array, typically including:
  - The prior user message
  - An assistant message with one or more `tool_use` blocks (ids must match)
  - A user message with corresponding `tool_result` blocks referencing `tool_use_id`
  """
  @spec stream_tool_followup(Types.session_id(), [map()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_tool_followup(session_id, messages, opts \\ []) when is_list(messages) do
    with {:ok, auth_type} <- detect_auth_type(session_id),
         {:ok, req} <- ReqClientFactory.create_client(:anthropic, auth_type, session: session_id) do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        {:error, :missing_model}
      else
        body =
          case auth_type do
            :oauth ->
              %{
                "model" => model,
                "messages" => transform_messages_for_claude_code(messages),
                "system" => anthropic_system_blocks(),
                "max_tokens" => Keyword.get(opts, :max_tokens, 512),
                "tools" => anthropic_tools(),
                "metadata" => %{"user_id" => compute_user_id(session_id)},
                "stream" => true
              }

            _ ->
              %{
                "model" => model,
                "messages" => messages,
                "max_tokens" => Keyword.get(opts, :max_tokens, 512),
                "tools" => anthropic_tools(),
                "metadata" => %{"user_id" => compute_user_id(session_id)},
                "stream" => true
              }
          end

        url = if auth_type == :oauth, do: "/v1/messages?beta=true", else: "/v1/messages"
        maybe_log_request(:followup, req, url, body)
        StreamingAdapter.stream_request(req, method: :post, url: url, json: body)
      end
    end
  end

  @spec detect_auth_type(String.t()) :: {:ok, :oauth | :api_key} | {:error, term()}
  defp detect_auth_type(session_id) do
    cond do
      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :oauth, session_id)) ->
        {:ok, :oauth}

      is_map(SavedAuthentication.get_by_provider_and_name(:anthropic, :api_key, session_id)) ->
        {:ok, :api_key}

      true ->
        {:error, :session_not_found}
    end
  end

  # ===== Tool definitions (Anthropic format) =====
  defp anthropic_tools do
    [
      task_tool(),
      bash_tool(),
      glob_tool(),
      grep_tool(),
      exit_plan_mode_tool(),
      read_tool(),
      edit_tool(),
      multi_edit_tool(),
      write_tool(),
      notebook_edit_tool(),
      web_fetch_tool(),
      todo_write_tool(),
      web_search_tool(),
      bash_output_tool(),
      kill_bash_tool()
    ]
  end

  defp bash_tool do
    %{
      "name" => "Bash",
      "description" =>
        "Executes a given bash command in a persistent shell session with optional timeout, ensuring proper handling and security measures.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string", "description" => "The command to execute"},
          "timeout" => %{"type" => "number", "description" => "Timeout in ms (optional)"},
          "description" => %{"type" => "string", "description" => "What this command does"},
          "run_in_background" => %{"type" => "boolean", "description" => "Run in background"}
        },
        "required" => ["command"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp task_tool do
    %{
      "name" => "Task",
      "description" => "Launch a new agent to handle complex, multi-step tasks autonomously.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "description" => %{"type" => "string"},
          "prompt" => %{"type" => "string"},
          "subagent_type" => %{"type" => "string"}
        },
        "required" => ["description", "prompt", "subagent_type"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp glob_tool do
    %{
      "name" => "Glob",
      "description" => "Fast file pattern matching tool.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp grep_tool do
    %{
      "name" => "Grep",
      "description" => "Search code using ripgrep.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "glob" => %{"type" => "string"},
          "output_mode" => %{
            "type" => "string",
            "enum" => ["content", "files_with_matches", "count"]
          },
          "-B" => %{"type" => "number"},
          "-A" => %{"type" => "number"},
          "-C" => %{"type" => "number"},
          "-n" => %{"type" => "boolean"},
          "-i" => %{"type" => "boolean"},
          "type" => %{"type" => "string"},
          "head_limit" => %{"type" => "number"},
          "multiline" => %{"type" => "boolean"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp exit_plan_mode_tool do
    %{
      "name" => "ExitPlanMode",
      "description" => "Exit plan mode when ready to code.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{"plan" => %{"type" => "string"}},
        "required" => ["plan"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp read_tool do
    %{
      "name" => "Read",
      "description" => "Read a file from the filesystem.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "offset" => %{"type" => "number"},
          "limit" => %{"type" => "number"}
        },
        "required" => ["file_path"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp edit_tool do
    %{
      "name" => "Edit",
      "description" => "Exact string replace in a file.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "old_string" => %{"type" => "string"},
          "new_string" => %{"type" => "string"},
          "replace_all" => %{"type" => "boolean"}
        },
        "required" => ["file_path", "old_string", "new_string"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp multi_edit_tool do
    %{
      "name" => "MultiEdit",
      "description" => "Multiple edits to one file.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "edits" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "old_string" => %{"type" => "string"},
                "new_string" => %{"type" => "string"},
                "replace_all" => %{"type" => "boolean"}
              },
              "required" => ["old_string", "new_string"],
              "additionalProperties" => false
            },
            "minItems" => 1
          }
        },
        "required" => ["file_path", "edits"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp write_tool do
    %{
      "name" => "Write",
      "description" => "Write a file.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "content" => %{"type" => "string"}
        },
        "required" => ["file_path", "content"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp notebook_edit_tool do
    %{
      "name" => "NotebookEdit",
      "description" => "Replace contents of a notebook cell.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "notebook_path" => %{"type" => "string"},
          "cell_id" => %{"type" => "string"},
          "new_source" => %{"type" => "string"},
          "cell_type" => %{"type" => "string", "enum" => ["code", "markdown"]},
          "edit_mode" => %{"type" => "string", "enum" => ["replace", "insert", "delete"]}
        },
        "required" => ["notebook_path", "new_source"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp web_fetch_tool do
    %{
      "name" => "WebFetch",
      "description" => "Fetch a URL and analyze with a prompt.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "format" => "uri"},
          "prompt" => %{"type" => "string"}
        },
        "required" => ["url", "prompt"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp todo_write_tool do
    %{
      "name" => "TodoWrite",
      "description" => "Create and manage a structured task list.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "todos" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "content" => %{"type" => "string", "minLength" => 1},
                "status" => %{
                  "type" => "string",
                  "enum" => ["pending", "in_progress", "completed"]
                },
                "activeForm" => %{"type" => "string", "minLength" => 1}
              },
              "required" => ["content", "status", "activeForm"],
              "additionalProperties" => false
            }
          }
        },
        "required" => ["todos"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp web_search_tool do
    %{
      "name" => "WebSearch",
      "description" => "Search the web for up-to-date information.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "minLength" => 2},
          "allowed_domains" => %{"type" => "array", "items" => %{"type" => "string"}},
          "blocked_domains" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["query"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp bash_output_tool do
    %{
      "name" => "BashOutput",
      "description" => "Retrieve output from a running background bash shell.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "bash_id" => %{"type" => "string"},
          "filter" => %{"type" => "string"}
        },
        "required" => ["bash_id"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp kill_bash_tool do
    %{
      "name" => "KillBash",
      "description" => "Kill a running background bash shell.",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{"shell_id" => %{"type" => "string"}},
        "required" => ["shell_id"],
        "additionalProperties" => false,
        "$schema" => "http://json-schema.org/draft-07/schema#"
      }
    }
  end

  defp compute_user_id(session_name) when is_binary(session_name) do
    seed = session_name

    hash =
      :crypto.hash(:sha256, seed)
      |> Base.encode16(case: :lower)

    "user_" <> String.slice(hash, 0, 64) <> "_account_cli_session_" <> Ecto.UUID.generate()
  end

  # Shape system as Claude Code expects: content blocks with ephemeral cache control
  defp anthropic_system_blocks do
    [
      %{
        "type" => "text",
        "text" => "You are Claude Code, Anthropic's official CLI for Claude.",
        "cache_control" => %{"type" => "ephemeral"}
      }
    ]
  end

  # Convert string-based messages to content blocks with ephemeral cache control for Claude Code OAuth
  defp transform_messages_for_claude_code(messages) when is_list(messages) do
    Enum.map(messages, fn m ->
      role = Map.get(m, "role") || Map.get(m, :role) || "user"
      content = Map.get(m, "content") || Map.get(m, :content) || ""

      blocks =
        cond do
          is_binary(content) ->
            [%{"type" => "text", "text" => content, "cache_control" => %{"type" => "ephemeral"}}]

          is_list(content) ->
            # If already content blocks, pass through
            content

          true ->
            [
              %{
                "type" => "text",
                "text" => to_string(content),
                "cache_control" => %{"type" => "ephemeral"}
              }
            ]
        end

      %{"role" => role, "content" => blocks}
    end)
  end

  defp maybe_log_request(tag, %Req.Request{} = req, url, body) do
    if System.get_env("HTTP_DEBUG") in ["1", "true", "TRUE"] do
      headers = sanitize_headers(Enum.into(req.headers, []))

      preview = %{
        "tools" => Enum.map(body["tools"] || [], &Map.get(&1, "name")),
        "messages" => Enum.map(body["messages"] || [], &Map.take(&1, ["role"])),
        "system_count" => body["system"] |> List.wrap() |> length()
      }

      IO.puts("\n📤 Anthropic #{inspect(tag)} request:")
      IO.puts("URL: #{url}")
      IO.puts("Headers: " <> inspect(headers))
      IO.puts("Payload preview: " <> inspect(preview))
    end
  end

  defp sanitize_headers(headers) do
    Enum.map(headers, fn {k, v} ->
      if String.downcase(k) == "authorization" do
        {k, redact_token(v)}
      else
        {k, v}
      end
    end)
  end

  defp redact_token("Bearer " <> rest) when is_binary(rest) do
    "Bearer " <> String.slice(rest, 0, 6) <> "…redacted"
  end

  defp redact_token(v), do: v
end
