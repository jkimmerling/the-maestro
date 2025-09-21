defmodule TheMaestro.Tools.ProviderToolManifest do
  @moduledoc """
  UI-agnostic manifests of provider built-in tools and provider-specific
  declaration builders. Single source for tool surfaces across UI, REST, CLI.
  """

  # Public API

  @type provider :: :openai | :gemini | :anthropic
  @type inventory_item :: %{name: String.t(), description: String.t() | nil}

  @doc "List provider built-in tools for inventory (names + descriptions)."
  @spec list_builtin(provider()) :: [inventory_item()]
  def list_builtin(:openai) do
    [
      %{name: "shell", description: "Runs a shell command and returns its output"},
      %{name: "apply_patch", description: "Use the `apply_patch` tool to edit files."},
      %{name: "web_search", description: "Search the web (backend-configurable)."},
      %{name: "update_plan", description: "Update the active task plan checklist."},
      %{name: "view_image", description: "Attach a local image for this turn."}
    ]
  end

  def list_builtin(:gemini) do
    [
      %{name: "run_shell_command", description: "Execute a shell command."},
      %{name: "list_directory", description: "List files for a path."},
      %{name: "read_file", description: "Read a file."},
      %{name: "write_file", description: "Write a file."},
      %{name: "glob", description: "Find files by pattern."},
      %{name: "search_file_content", description: "Search files for a pattern."},
      %{name: "replace", description: "Replace text in a file (expected_replacements)."},
      %{name: "edit", description: "Alias for replace."},
      %{name: "read_many_files", description: "Read multiple files and concatenate."},
      %{name: "web_fetch", description: "Fetch a URL for analysis."},
      %{name: "google_web_search", description: "Search the web using Google."}
    ]
  end

  def list_builtin(:anthropic) do
    for {n, d} <- [
          {"Task", "Launch a sub-agent for multi-step tasks."},
          {"Bash", "Execute a bash command in a persistent shell."},
          {"Glob", "Fast file pattern matching tool."},
          {"Grep", "Search code using ripgrep."},
          {"ExitPlanMode", "Exit plan mode when ready to code."},
          {"Read", "Read a file."},
          {"Edit", "Edit a file (find/replace)."},
          {"MultiEdit", "Multiple edits to one file."},
          {"Write", "Write a file."},
          {"NotebookEdit", "Replace contents of a notebook."},
          {"WebFetch", "Fetch a URL and analyze with a prompt."},
          {"TodoWrite", "Create and manage a structured task list."},
          {"WebSearch", "Search the web for up-to-date information."},
          {"BashOutput", "Retrieve output from a running background bash shell."},
          {"KillBash", "Kill a running background bash shell."}
        ] do
      %{name: n, description: d}
    end
  end

  @doc "Provider-specific tool declaration list suitable for request payloads."
  @spec provider_decl_builtins(provider()) :: [map()]
  def provider_decl_builtins(:openai) do
    [openai_shell(), openai_apply_patch(), openai_web_search(), openai_update_plan(), openai_view_image()]
  end

  def provider_decl_builtins(:gemini) do
    [
      gemini_run_shell_command(),
      gemini_list_directory(),
      gemini_read_file(),
      gemini_write_file(),
      gemini_glob(),
      gemini_search_file_content(),
      gemini_replace(),
      gemini_edit_alias(),
      gemini_read_many_files(),
      gemini_web_fetch(),
      gemini_google_web_search()
    ]
  end

  def provider_decl_builtins(:anthropic) do
    # Anthropic uses TitleCase tool names with input_schema. Defer to provider module; here we only keep inventory unified.
    []
  end

  # ===== OpenAI declarations =====
  defp openai_shell do
    %{
      "type" => "function",
      "name" => "shell",
      "description" => "Runs a shell command and returns its output",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "array", "items" => %{"type" => "string"}},
          "workdir" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "number"}
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  defp openai_apply_patch do
    %{
      "type" => "function",
      "name" => "apply_patch",
      "description" => "Use the `apply_patch` tool to edit files.",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{"input" => %{"type" => "string"}},
        "required" => ["input"],
        "additionalProperties" => false
      }
    }
  end

  defp openai_web_search do
    %{
      "type" => "function",
      "name" => "web_search",
      "description" => "Search the web (backend-configurable).",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string"},
          "search_depth" => %{"type" => "string", "enum" => ["basic", "advanced"]},
          "allowed_domains" => %{"type" => "array", "items" => %{"type" => "string"}},
          "blocked_domains" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["query"],
        "additionalProperties" => false
      }
    }
  end

  defp openai_update_plan do
    %{
      "type" => "function",
      "name" => "update_plan",
      "description" => "Update the active task plan checklist.",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "explanation" => %{"type" => "string"},
          "plan" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "step" => %{"type" => "string"},
                "status" => %{"type" => "string", "enum" => ["pending", "in_progress", "completed"]}
              },
              "required" => ["step", "status"],
              "additionalProperties" => false
            }
          }
        },
        "required" => ["plan"],
        "additionalProperties" => false
      }
    }
  end

  defp openai_view_image do
    %{
      "type" => "function",
      "name" => "view_image",
      "description" => "Attach a local image (path) to this turn.",
      "strict" => false,
      "parameters" => %{
        "type" => "object",
        "properties" => %{"path" => %{"type" => "string"}},
        "required" => ["path"],
        "additionalProperties" => false
      }
    }
  end

  # ===== Gemini declarations =====
  defp obj(props, req), do: %{"type" => "object", "properties" => props, "required" => req}

  defp gemini_run_shell_command do
    %{
      "name" => "run_shell_command",
      "description" => "Execute a shell command.",
      "parameters" =>
        obj(
          %{"command" => %{"type" => "string"}, "directory" => %{"type" => "string"}},
          ["command"]
        )
    }
  end

  defp gemini_list_directory do
    %{
      "name" => "list_directory",
      "description" => "List directory.",
      "parameters" => obj(%{"path" => %{"type" => "string"}}, [])
    }
  end

  defp gemini_read_file do
    %{
      "name" => "read_file",
      "description" => "Read a file.",
      "parameters" =>
        obj(
          %{
            "path" => %{"type" => "string"},
            "offset" => %{"type" => "number"},
            "limit" => %{"type" => "number"}
          },
          ["path"]
        )
    }
  end

  defp gemini_write_file do
    %{
      "name" => "write_file",
      "description" => "Write a file.",
      "parameters" =>
        obj(
          %{"file_path" => %{"type" => "string"}, "content" => %{"type" => "string"}},
          ["file_path", "content"]
        )
    }
  end

  defp gemini_glob do
    %{
      "name" => "glob",
      "description" => "Find files by pattern.",
      "parameters" =>
        obj(
          %{
            "pattern" => %{"type" => "string"},
            "path" => %{"type" => "string"},
            "case_sensitive" => %{"type" => "boolean"},
            "respect_git_ignore" => %{"type" => "boolean"}
          },
          ["pattern"]
        )
    }
  end

  defp gemini_search_file_content do
    %{
      "name" => "search_file_content",
      "description" => "Search files.",
      "parameters" =>
        obj(
          %{
            "pattern" => %{"type" => "string"},
            "path" => %{"type" => "string"},
            "include" => %{"type" => "string"}
          },
          ["pattern"]
        )
    }
  end

  defp gemini_replace do
    %{
      "name" => "replace",
      "description" => "Replace text.",
      "parameters" =>
        obj(
          %{
            "file_path" => %{"type" => "string"},
            "old_string" => %{"type" => "string"},
            "new_string" => %{"type" => "string"},
            "expected_replacements" => %{"type" => "number", "minimum" => 1}
          },
          ["file_path", "old_string", "new_string"]
        )
    }
  end

  defp gemini_edit_alias do
    %{
      "name" => "edit",
      "description" => "Alias for replace.",
      "parameters" =>
        obj(
          %{
            "file_path" => %{"type" => "string"},
            "old_string" => %{"type" => "string"},
            "new_string" => %{"type" => "string"},
            "expected_replacements" => %{"type" => "number", "minimum" => 1}
          },
          ["file_path", "old_string", "new_string"]
        )
    }
  end

  defp gemini_read_many_files do
    %{
      "name" => "read_many_files",
      "description" => "Read multiple files.",
      "parameters" =>
        obj(
          %{"files" => %{"type" => "array", "items" => %{"type" => "string"}},
            "separator" => %{"type" => "string"}},
          ["files"]
        )
    }
  end

  defp gemini_web_fetch do
    %{
      "name" => "web_fetch",
      "description" => "Fetch a URL.",
      "parameters" => obj(%{"url" => %{"type" => "string"}}, ["url"])
    }
  end

  defp gemini_google_web_search do
    %{
      "name" => "google_web_search",
      "description" => "Google search.",
      "parameters" => obj(%{"query" => %{"type" => "string"}}, ["query"])
    }
  end
end

