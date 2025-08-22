defmodule TheMaestro.Prompts.EngineeringTools.VersionControlGit do
  @moduledoc """
  Real Git integration for prompt engineering version control.
  
  Provides actual Git operations for versioning, branching, merging,
  and history tracking of prompts and templates.
  """

  require Logger

  @type git_result :: {:ok, String.t()} | {:error, String.t()}
  @type repo_path :: String.t()

  @doc """
  Initializes a real Git repository for prompts.
  """
  @spec init_repository(String.t(), map()) :: {:ok, repo_path} | {:error, String.t()}
  def init_repository(path, config \\ %{}) do
    # Create directory if it doesn't exist
    case File.mkdir_p(path) do
      :ok ->
        # Initialize Git repository
        case run_git_command(path, ["init"]) do
          {:ok, _output} ->
            # Set initial configuration
            setup_initial_config(path, config)
            {:ok, path}
          
          {:error, reason} ->
            {:error, "Failed to initialize Git repository: #{reason}"}
        end
      
      {:error, reason} ->
        {:error, "Failed to create directory: #{reason}"}
    end
  end

  @doc """
  Creates a real commit with current changes.
  """
  @spec commit(repo_path, String.t(), String.t(), map()) :: 
    {:ok, String.t()} | {:error, String.t()}
  def commit(repo_path, message, author, options \\ %{}) do
    with :ok <- validate_repository(repo_path),
         {:ok, _} <- set_author_info(repo_path, author),
         {:ok, _} <- stage_all_changes(repo_path),
         {:ok, has_changes} <- check_staged_changes(repo_path) do
      
      if has_changes do
        case run_git_command(repo_path, ["commit", "-m", message]) do
          {:ok, output} ->
            commit_hash = extract_commit_hash(output)
            
            # Add tags if specified
            if options[:tag] do
              create_tag(repo_path, options[:tag], commit_hash)
            end
            
            {:ok, commit_hash}
          
          {:error, reason} ->
            {:error, "Commit failed: #{reason}"}
        end
      else
        {:error, "No changes to commit"}
      end
    end
  end

  @doc """
  Stages specific file changes for commit.
  """
  @spec stage_file(repo_path, String.t()) :: git_result
  def stage_file(repo_path, file_path) do
    with :ok <- validate_repository(repo_path),
         :ok <- validate_file_exists(repo_path, file_path) do
      run_git_command(repo_path, ["add", file_path])
    end
  end

  @doc """
  Stages all changes in the repository.
  """
  @spec stage_all_changes(repo_path) :: git_result
  def stage_all_changes(repo_path) do
    with :ok <- validate_repository(repo_path) do
      run_git_command(repo_path, ["add", "."])
    end
  end

  @doc """
  Creates a new branch from current HEAD or specified commit.
  """
  @spec create_branch(repo_path, String.t(), String.t() | nil) :: git_result
  def create_branch(repo_path, branch_name, from_commit \\ nil) do
    with :ok <- validate_repository(repo_path),
         false <- branch_exists?(repo_path, branch_name) do
      
      args = if from_commit do
        ["checkout", "-b", branch_name, from_commit]
      else
        ["checkout", "-b", branch_name]
      end
      
      run_git_command(repo_path, args)
    else
      true -> {:error, "Branch '#{branch_name}' already exists"}
      error -> error
    end
  end

  @doc """
  Switches to an existing branch.
  """
  @spec checkout_branch(repo_path, String.t()) :: git_result
  def checkout_branch(repo_path, branch_name) do
    with :ok <- validate_repository(repo_path),
         true <- branch_exists?(repo_path, branch_name) do
      run_git_command(repo_path, ["checkout", branch_name])
    else
      false -> {:error, "Branch '#{branch_name}' does not exist"}
      error -> error
    end
  end

  @doc """
  Merges one branch into current branch.
  """
  @spec merge_branch(repo_path, String.t(), map()) :: git_result
  def merge_branch(repo_path, source_branch, options \\ %{}) do
    with :ok <- validate_repository(repo_path),
         true <- branch_exists?(repo_path, source_branch) do
      
      merge_args = ["merge"]
      merge_args = if options[:no_ff], do: merge_args ++ ["--no-ff"], else: merge_args
      merge_args = if options[:squash], do: merge_args ++ ["--squash"], else: merge_args
      merge_args = merge_args ++ [source_branch]
      
      case run_git_command(repo_path, merge_args) do
        {:ok, output} ->
          # Check for merge conflicts
          if String.contains?(output, "CONFLICT") do
            conflicts = detect_merge_conflicts(repo_path)
            {:error, "Merge conflicts detected: #{inspect(conflicts)}"}
          else
            {:ok, output}
          end
        
        {:error, reason} ->
          {:error, "Merge failed: #{reason}"}
      end
    else
      false -> {:error, "Source branch '#{source_branch}' does not exist"}
      error -> error
    end
  end

  @doc """
  Creates a tag at the specified commit (or HEAD if not specified).
  """
  @spec create_tag(repo_path, String.t(), String.t() | nil) :: git_result
  def create_tag(repo_path, tag_name, commit_hash \\ nil) do
    with :ok <- validate_repository(repo_path),
         false <- tag_exists?(repo_path, tag_name) do
      
      args = if commit_hash do
        ["tag", tag_name, commit_hash]
      else
        ["tag", tag_name]
      end
      
      run_git_command(repo_path, args)
    else
      true -> {:error, "Tag '#{tag_name}' already exists"}
      error -> error
    end
  end

  @doc """
  Shows commit history for current branch or specified branch.
  """
  @spec show_history(repo_path, String.t() | nil, map()) :: {:ok, list(map())} | {:error, String.t()}
  def show_history(repo_path, branch \\ nil, options \\ %{}) do
    with :ok <- validate_repository(repo_path) do
      
      # Build log command arguments
      args = ["log", "--oneline", "--graph"]
      args = if options[:limit], do: args ++ ["-n", "#{options[:limit]}"], else: args
      args = if branch, do: args ++ [branch], else: args
      
      case run_git_command(repo_path, args) do
        {:ok, output} ->
          commits = parse_git_log(output)
          {:ok, commits}
        
        {:error, reason} ->
          {:error, "Failed to get history: #{reason}"}
      end
    end
  end

  @doc """
  Shows differences between two commits, branches, or HEAD.
  """
  @spec diff(repo_path, String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def diff(repo_path, from_ref, to_ref \\ nil) do
    with :ok <- validate_repository(repo_path) do
      
      args = if to_ref do
        ["diff", from_ref, to_ref]
      else
        ["diff", from_ref]
      end
      
      case run_git_command(repo_path, args) do
        {:ok, output} ->
          {:ok, output}
        
        {:error, reason} ->
          {:error, "Failed to generate diff: #{reason}"}
      end
    end
  end

  @doc """
  Reverts a commit by creating a new commit that undoes the changes.
  """
  @spec revert_commit(repo_path, String.t(), String.t()) :: git_result
  def revert_commit(repo_path, commit_hash, author) do
    with :ok <- validate_repository(repo_path),
         {:ok, _} <- set_author_info(repo_path, author) do
      
      case run_git_command(repo_path, ["revert", "--no-edit", commit_hash]) do
        {:ok, output} ->
          revert_hash = extract_commit_hash(output)
          {:ok, revert_hash}
        
        {:error, reason} ->
          {:error, "Revert failed: #{reason}"}
      end
    end
  end

  @doc """
  Gets current repository status.
  """
  @spec status(repo_path) :: {:ok, map()} | {:error, String.t()}
  def status(repo_path) do
    with :ok <- validate_repository(repo_path) do
      
      with {:ok, status_output} <- run_git_command(repo_path, ["status", "--porcelain"]),
           {:ok, branch_output} <- run_git_command(repo_path, ["branch", "--show-current"]) do
        
        status_info = %{
          current_branch: String.trim(branch_output),
          modified_files: parse_status_output(status_output),
          has_staged_changes: String.contains?(status_output, "M ") or String.contains?(status_output, "A "),
          has_unstaged_changes: String.contains?(status_output, " M") or String.contains?(status_output, "??"),
          clean: String.trim(status_output) == ""
        }
        
        {:ok, status_info}
      end
    end
  end

  @doc """
  Lists all branches in the repository.
  """
  @spec list_branches(repo_path) :: {:ok, list(String.t())} | {:error, String.t()}
  def list_branches(repo_path) do
    with :ok <- validate_repository(repo_path) do
      case run_git_command(repo_path, ["branch", "--list"]) do
        {:ok, output} ->
          branches = output
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(&String.replace(&1, ~r/^\*\s*/, ""))
          
          {:ok, branches}
        
        {:error, reason} ->
          {:error, "Failed to list branches: #{reason}"}
      end
    end
  end

  @doc """
  Lists all tags in the repository.
  """
  @spec list_tags(repo_path) :: {:ok, list(String.t())} | {:error, String.t()}
  def list_tags(repo_path) do
    with :ok <- validate_repository(repo_path) do
      case run_git_command(repo_path, ["tag", "--list"]) do
        {:ok, output} ->
          tags = output
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          
          {:ok, tags}
        
        {:error, reason} ->
          {:error, "Failed to list tags: #{reason}"}
      end
    end
  end

  # Private helper functions

  defp run_git_command(repo_path, args) do
    try do
      {output, exit_code} = System.cmd("git", args, [
        cd: repo_path,
        stderr_to_stdout: true
      ])
      
      case exit_code do
        0 -> {:ok, output}
        _ -> {:error, output}
      end
    rescue
      e in ErlangError ->
        {:error, "Git command failed: #{Exception.message(e)}"}
    end
  end

  defp validate_repository(repo_path) do
    if File.exists?(Path.join(repo_path, ".git")) do
      :ok
    else
      {:error, "Not a Git repository: #{repo_path}"}
    end
  end

  defp validate_file_exists(repo_path, file_path) do
    full_path = Path.join(repo_path, file_path)
    if File.exists?(full_path) do
      :ok
    else
      {:error, "File does not exist: #{file_path}"}
    end
  end

  defp setup_initial_config(repo_path, config) do
    # Set default branch if specified
    if initial_branch = config[:initial_branch] do
      run_git_command(repo_path, ["checkout", "-b", initial_branch])
    end
    
    # Set user info if specified
    if author = config[:author] do
      set_author_info(repo_path, author)
    end
    
    # Create initial README if requested
    if config[:create_readme] do
      readme_path = Path.join(repo_path, "README.md")
      File.write!(readme_path, "# Prompt Engineering Repository\n\nInitialized by TheMaestro")
      run_git_command(repo_path, ["add", "README.md"])
      run_git_command(repo_path, ["commit", "-m", "Initial commit"])
    end
  end

  defp set_author_info(repo_path, author) do
    case author do
      %{name: name, email: email} ->
        with {:ok, _} <- run_git_command(repo_path, ["config", "user.name", name]),
             {:ok, _} <- run_git_command(repo_path, ["config", "user.email", email]) do
          {:ok, "Author configured"}
        end
      
      name when is_binary(name) ->
        run_git_command(repo_path, ["config", "user.name", name])
      
      _ ->
        {:error, "Invalid author format"}
    end
  end

  defp check_staged_changes(repo_path) do
    case run_git_command(repo_path, ["diff", "--cached", "--quiet"]) do
      {:ok, _} -> {:ok, false}  # No staged changes
      {:error, _} -> {:ok, true}  # Has staged changes (exit code 1 means diff found)
    end
  end

  defp branch_exists?(repo_path, branch_name) do
    case run_git_command(repo_path, ["show-ref", "--verify", "refs/heads/#{branch_name}"]) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp tag_exists?(repo_path, tag_name) do
    case run_git_command(repo_path, ["show-ref", "--tags", tag_name]) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp detect_merge_conflicts(repo_path) do
    case run_git_command(repo_path, ["diff", "--name-only", "--diff-filter=U"]) do
      {:ok, output} ->
        output
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
      
      {:error, _} ->
        []
    end
  end

  defp extract_commit_hash(commit_output) do
    # Extract commit hash from commit output
    case Regex.run(~r/\[[\w\s]+\s+(\w{7,})\]/, commit_output) do
      [_, hash] -> hash
      _ -> 
        # Try alternative format
        case Regex.run(~r/^(\w{7,})/, commit_output) do
          [_, hash] -> hash
          _ -> "unknown"
        end
    end
  end

  defp parse_git_log(log_output) do
    log_output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_log_line/1)
  end

  defp parse_log_line(line) do
    # Parse format: "* abc1234 (origin/main) Commit message"
    case Regex.run(~r/^\*?\s*(\w+)\s+(?:\([^)]+\))?\s*(.+)$/, line) do
      [_, hash, message] ->
        %{
          commit_hash: hash,
          message: String.trim(message),
          short_hash: String.slice(hash, 0, 7)
        }
      _ ->
        %{
          commit_hash: "unknown",
          message: line,
          short_hash: "unknown"
        }
    end
  end

  defp parse_status_output(status_output) do
    status_output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_status_line/1)
  end

  defp parse_status_line(line) do
    # Parse format: " M filename" or "A  filename"
    case Regex.run(~r/^(.)(.) (.+)$/, line) do
      [_, staged, unstaged, filename] ->
        %{
          file: filename,
          staged: parse_status_code(staged),
          unstaged: parse_status_code(unstaged)
        }
      _ ->
        %{file: line, staged: :unknown, unstaged: :unknown}
    end
  end

  defp parse_status_code(code) do
    case code do
      "M" -> :modified
      "A" -> :added
      "D" -> :deleted
      "R" -> :renamed
      "C" -> :copied
      "U" -> :unmerged
      "?" -> :untracked
      " " -> :unchanged
      _ -> :unknown
    end
  end
end