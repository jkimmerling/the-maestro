defmodule TheMaestro.Tools.Registry do
  @moduledoc """
  Tool registry: declares the available tools and their parameter schemas.

  This module returns provider-agnostic metadata which translators convert
  into provider-specific declarations.
  """

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          flags: map()
        }

  @doc """
  Return the list of available tools for the given agent configuration.
  For now, returns the full Gemini-parity set; filtering is applied by Router/agent.tools.
  """
  @spec list_tools(map()) :: [tool()]
  def list_tools(agent) do
    all = [
      %{
        name: "run_shell_command",
        description: "Execute a shell command in the working directory.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "command" => %{"type" => "string"},
            "description" => %{"type" => "string"}
          },
          "required" => ["command"]
        },
        flags: %{writes_files: false, needs_confirmation: false}
      },
      %{
        name: "list_directory",
        description: "List directory entries with optional ignore patterns.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string"},
            "ignore" => %{"type" => "array", "items" => %{"type" => "string"}},
            "respect_git_ignore" => %{"type" => "boolean"}
          },
          "required" => ["path"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "read_file",
        description: "Read a file (text/images/PDF) with optional slice.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "absolute_path" => %{"type" => "string"},
            "offset" => %{"type" => "integer"},
            "limit" => %{"type" => "integer"}
          },
          "required" => ["absolute_path"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "write_file",
        description: "Write file with confirmation and atomic replace.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "file_path" => %{"type" => "string"},
            "content" => %{"type" => "string"}
          },
          "required" => ["file_path", "content"]
        },
        flags: %{writes_files: true, needs_confirmation: true}
      },
      %{
        name: "glob",
        description: "Find files by glob pattern.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{"type" => "string"},
            "path" => %{"type" => "string"},
            "case_sensitive" => %{"type" => "boolean"},
            "respect_git_ignore" => %{"type" => "boolean"}
          },
          "required" => ["pattern"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "search_file_content",
        description: "Search file content by regex with optional include glob.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{"type" => "string"},
            "path" => %{"type" => "string"},
            "include" => %{"type" => "string"}
          },
          "required" => ["pattern"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "replace",
        description: "Replace exact text in a file with confirmation.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "file_path" => %{"type" => "string"},
            "old_string" => %{"type" => "string"},
            "new_string" => %{"type" => "string"},
            "expected_replacements" => %{"type" => "integer"}
          },
          "required" => ["file_path", "old_string", "new_string"]
        },
        flags: %{writes_files: true, needs_confirmation: true}
      },
      %{
        name: "read_many_files",
        description: "Read multiple files by paths or globs and concatenate summaries.",
        parameters: %{
          "type" => "object",
          "properties" => %{"paths" => %{"type" => "array", "items" => %{"type" => "string"}}},
          "required" => ["paths"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "web_fetch",
        description: "Fetch and summarize content from URLs included in a prompt.",
        parameters: %{
          "type" => "object",
          "properties" => %{"prompt" => %{"type" => "string"}},
          "required" => ["prompt"]
        },
        flags: %{writes_files: false}
      },
      %{
        name: "google_web_search",
        description: "Search the web and return summarized results with sources.",
        parameters: %{
          "type" => "object",
          "properties" => %{"query" => %{"type" => "string"}},
          "required" => ["query"]
        },
        flags: %{writes_files: false}
      }
    ]

    case enabled_tools(agent) do
      [] -> all
      names -> Enum.filter(all, fn t -> t.name in names end)
    end
  end

  defp enabled_tools(%{} = agent) do
    tools = Map.get(agent, :tools) || Map.get(agent, "tools") || %{}

    case Map.get(tools, "enabled_tools") do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  defp enabled_tools(_), do: []
end

# End of TheMaestro.Tools.Registry
