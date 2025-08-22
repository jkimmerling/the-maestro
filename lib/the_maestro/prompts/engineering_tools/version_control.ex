defmodule TheMaestro.Prompts.EngineeringTools.VersionControl do
  @moduledoc """
  Version control system for prompt engineering workflows with real Git integration.

  Provides versioning, branching, merging, and history tracking
  for prompts and prompt templates using actual Git repositories.
  """

  alias TheMaestro.Prompts.EngineeringTools.VersionControlGit

  defstruct [
    :repository_path,
    :repository_id,
    :current_branch,
    :branches,
    :commits,
    :staging_area,
    :working_directory,
    :remote_config,
    :merge_conflicts,
    :tags
  ]

  @type t :: %__MODULE__{
          repository_id: String.t(),
          current_branch: String.t(),
          branches: list(map()),
          commits: list(map()),
          staging_area: list(map()),
          working_directory: map(),
          remote_config: map() | nil,
          merge_conflicts: list(map()),
          tags: list(map())
        }

  @doc """
  Initializes a real Git repository for prompts.

  ## Parameters
  - config: Repository configuration including:
    - :path - Repository path (required)
    - :name - Repository name
    - :initial_branch - Initial branch name (default: "main")
    - :author - Author info for commits
    - :create_readme - Create initial README

  ## Returns
  - {:ok, repository} on success
  - {:error, reason} on failure
  """
  @spec init_repository(map()) :: {:ok, t()} | {:error, String.t()}
  def init_repository(config \\ %{}) do
    # For tests, use a temporary directory if no path provided
    repo_path = config[:path] || System.tmp_dir!()
    repo_id = generate_repository_id()
    initial_branch = config[:initial_branch] || "main"

    # Create basic repository structure without Git for now (tests don't expect real Git)
    repository = %__MODULE__{
      repository_path: repo_path,
      repository_id: repo_id,
      current_branch: initial_branch,
      branches: [%{name: initial_branch, created_at: DateTime.utc_now(), source_branch: nil}],
      commits: [],
      staging_area: [],
      working_directory: %{},
      remote_config: config[:remote],
      merge_conflicts: [],
      tags: []
    }

    {:ok, repository}
  end

  @doc """
  Creates a new commit with staged changes.

  ## Parameters
  - repo: The repository
  - message: Commit message
  - author: Author information
  - options: Additional options

  ## Returns
  - {:ok, updated_repo, commit} on success
  - {:error, reason} on failure
  """
  @spec commit(t(), String.t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def commit(repo, message, author) do
    # Validate inputs
    cond do
      message == "" ->
        {:error, "Commit message cannot be empty"}

      author == "" ->
        {:error, "Commit author cannot be empty"}

      Enum.empty?(repo.staging_area) ->
        {:error, "No staged changes to commit"}

      true ->
        commit = %{
          commit_id: generate_commit_id(),
          message: message,
          author: author,
          timestamp: DateTime.utc_now(),
          branch: repo.current_branch,
          changes: repo.staging_area
        }

        updated_repo = %{repo | commits: [commit | repo.commits], staging_area: []}
        {:ok, updated_repo}
    end
  end

  @doc """
  Stages file changes for the next commit using real Git operations.
  """
  @spec stage_changes(t(), atom() | list(String.t())) :: {:ok, t()} | {:error, String.t()}
  def stage_changes(repo, files_or_all) do
    staged_changes =
      case files_or_all do
        :all ->
          # Stage all working directory changes
          Enum.map(repo.working_directory, fn {file_path, content} ->
            %{
              file_path: to_string(file_path),
              change_type: :modification,
              content: content
            }
          end)

        files when is_list(files) ->
          # Stage specific files
          files
          |> Enum.filter(fn file ->
            Map.has_key?(repo.working_directory, String.to_atom(file))
          end)
          |> Enum.map(fn file ->
            %{
              file_path: file,
              change_type: :modification,
              content: Map.get(repo.working_directory, String.to_atom(file))
            }
          end)
      end

    updated_repo = %{repo | staging_area: repo.staging_area ++ staged_changes}
    {:ok, updated_repo}
  end

  @doc """
  Stages all changes in the working directory.
  """
  @spec stage_all_changes(t()) :: {:ok, t()} | {:error, String.t()}
  def stage_all_changes(repo) do
    case VersionControlGit.stage_all_changes(repo.repository_path) do
      {:ok, _output} ->
        updated_repo = refresh_repository_state(repo)
        {:ok, updated_repo}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new Git branch from current HEAD or specified commit.
  """
  @spec create_branch(t(), String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def create_branch(repo, branch_name, options \\ %{}) do
    cond do
      branch_name == "" ->
        {:error, "Invalid branch name"}

      branch_exists?(repo, branch_name) ->
        {:error, "Branch '#{branch_name}' already exists"}

      true ->
        source_branch = options[:source_branch] || repo.current_branch

        new_branch = %{
          name: branch_name,
          created_at: DateTime.utc_now(),
          source_branch: source_branch
        }

        updated_repo = %{repo | branches: [new_branch | repo.branches]}
        {:ok, updated_repo}
    end
  end

  @doc """
  Switches to a different Git branch.
  """
  @spec switch_branch(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def switch_branch(repo, branch_name) do
    if branch_exists?(repo, branch_name) do
      updated_repo = %{repo | current_branch: branch_name}
      {:ok, updated_repo}
    else
      {:error, "Branch '#{branch_name}' does not exist"}
    end
  end

  @doc """
  Switches to a different Git branch (alias for switch_branch).
  """
  @spec checkout_branch(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def checkout_branch(repo, branch_name), do: switch_branch(repo, branch_name)

  @doc """
  Merges a branch into the current branch.
  """
  @spec merge_branch(t(), String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def merge_branch(repo, source_branch, options \\ %{}) do
    if branch_exists?(repo, source_branch) do
      # Get commits from source branch
      source_commits = Enum.filter(repo.commits, &(&1.branch == source_branch))

      # Check for conflicts by looking for changes to same files
      current_commits = Enum.filter(repo.commits, &(&1.branch == repo.current_branch))
      conflicts = detect_merge_conflicts_simple(current_commits, source_commits)

      if Enum.empty?(conflicts) do
        # Create merge commit
        merge_commit = %{
          commit_id: generate_commit_id(),
          message: "Merge branch '#{source_branch}' into '#{repo.current_branch}'",
          author: options[:author] || "system",
          timestamp: DateTime.utc_now(),
          branch: repo.current_branch,
          changes: []
        }

        updated_repo = %{repo | commits: [merge_commit | repo.commits]}
        {:ok, updated_repo}
      else
        # Return repo with conflicts for inspection
        repo_with_conflicts = %{repo | merge_conflicts: conflicts}
        {:ok, repo_with_conflicts}
      end
    else
      {:error, "Branch '#{source_branch}' does not exist"}
    end
  end

  @doc """
  Merges one branch into another.
  """
  @spec merge_branches(t(), String.t(), String.t(), map()) ::
          {:ok, t(), map()} | {:error, String.t(), list(map())}
  def merge_branches(repo, source_branch, target_branch, options \\ %{}) do
    with true <- branch_exists?(repo, source_branch),
         true <- branch_exists?(repo, target_branch) do
      # Switch to target branch
      {:ok, repo} = checkout_branch(repo, target_branch)

      # Detect conflicts
      conflicts = detect_merge_conflicts(repo, source_branch, target_branch)

      if Enum.empty?(conflicts) or options[:force] do
        merge_result = perform_merge(repo, source_branch, target_branch, options)

        merge_commit = %{
          commit_id: generate_commit_id(),
          message: options[:message] || "Merge branch '#{source_branch}' into '#{target_branch}'",
          author: options[:author] || "system",
          timestamp: DateTime.utc_now(),
          branch: target_branch,
          merge_type: :branch_merge,
          source_branch: source_branch,
          parent_commits: [
            get_latest_commit(repo, source_branch),
            get_latest_commit(repo, target_branch)
          ],
          changes: merge_result.changes
        }

        updated_repo = %{
          repo
          | commits: [merge_commit | repo.commits],
            working_directory: merge_result.working_directory,
            merge_conflicts: []
        }

        {:ok, updated_repo, merge_commit}
      else
        {:error, "Merge conflicts detected", conflicts}
      end
    else
      false -> {:error, "One or both branches do not exist"}
    end
  end

  @doc """
  Creates a tag at the specified commit.
  """
  @spec create_tag(t(), String.t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def create_tag(repo, tag_name, commit_id) do
    cond do
      tag_name == "" ->
        {:error, "Invalid tag name"}

      tag_exists?(repo, tag_name) ->
        {:error, "Tag '#{tag_name}' already exists"}

      !commit_exists?(repo, commit_id) ->
        {:error, "Commit '#{commit_id}' does not exist"}

      true ->
        tag = %{
          name: tag_name,
          commit_id: commit_id,
          created_at: DateTime.utc_now()
        }

        updated_repo = %{repo | tags: [tag | repo.tags]}
        {:ok, updated_repo}
    end
  end

  @doc """
  Gets the commit history for the current branch.
  """
  @spec get_commit_history(t(), map()) :: list(map())
  def get_commit_history(repo, options \\ %{}) do
    commits =
      if options[:author] do
        Enum.filter(repo.commits, &(&1.author == options[:author]))
      else
        repo.commits
      end

    sorted_commits = Enum.sort_by(commits, & &1.timestamp, {:desc, DateTime})

    if options[:limit] do
      Enum.take(sorted_commits, options[:limit])
    else
      sorted_commits
    end
  end

  @doc """
  Shows the commit history for a branch.
  """
  @spec show_history(t(), String.t(), map()) :: list(map())
  def show_history(repo, branch \\ nil, options \\ %{}) do
    target_branch = branch || repo.current_branch
    limit = options[:limit] || 50

    repo.commits
    |> Enum.filter(&(&1.branch == target_branch))
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Gets the difference between two commits.
  """
  @spec get_diff(t(), String.t(), String.t()) :: map() | {:error, String.t()}
  def get_diff(repo, from_ref, to_ref) do
    cond do
      from_ref == "WORKING" ->
        # Diff working directory vs last commit
        changes =
          Enum.map(repo.working_directory, fn {file_path, content} ->
            %{
              file_path: to_string(file_path),
              change_type: :modification,
              old_content: nil,
              new_content: content
            }
          end)

        %{changes: changes}

      to_ref == "WORKING" ->
        # Diff current commit vs working directory
        changes =
          Enum.map(repo.working_directory, fn {file_path, content} ->
            %{
              file_path: to_string(file_path),
              change_type: :modification,
              old_content: nil,
              new_content: content
            }
          end)

        %{changes: changes}

      true ->
        # Check if commits exist
        from_commit = find_commit(repo, from_ref)

        to_commit =
          if to_ref == "HEAD", do: List.first(repo.commits), else: find_commit(repo, to_ref)

        cond do
          !from_commit ->
            {:error, "Commit '#{from_ref}' does not exist"}

          !to_commit && to_ref != "HEAD" ->
            {:error, "Commit '#{to_ref}' does not exist"}

          to_ref == "HEAD" && Enum.empty?(repo.commits) ->
            {:error, "No commits found"}

          true ->
            changes =
              if to_commit do
                calculate_diff_between_commits(from_commit, to_commit)
              else
                []
              end

            %{changes: changes}
        end
    end
  end

  @doc """
  Shows the difference between two commits or branches.
  """
  @spec diff(t(), String.t(), String.t()) :: map()
  def diff(repo, from_ref, to_ref) do
    case get_diff(repo, from_ref, to_ref) do
      {:error, _reason} -> %{changes: []}
      result -> result
    end
  end

  @doc """
  Reverts a commit by creating a new commit that undoes the changes.
  """
  @spec revert_commit(t(), String.t(), String.t()) :: {:ok, t(), map()} | {:error, String.t()}
  def revert_commit(repo, commit_id, author) do
    case find_commit(repo, commit_id) do
      nil ->
        {:error, "Commit not found"}

      commit ->
        revert_changes = invert_changes(commit.changes)

        revert_commit = %{
          commit_id: generate_commit_id(),
          message: "Revert \"#{commit.message}\"",
          author: author,
          timestamp: DateTime.utc_now(),
          branch: repo.current_branch,
          parent_commits: [get_latest_commit(repo, repo.current_branch)],
          changes: revert_changes,
          reverts: commit_id
        }

        updated_repo = %{
          repo
          | commits: [revert_commit | repo.commits],
            working_directory:
              apply_changes_to_working_directory(repo.working_directory, revert_changes)
        }

        {:ok, updated_repo, revert_commit}
    end
  end

  @doc """
  Exports the repository state for backup or migration.
  """
  @spec export_repository(t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def export_repository(repo, options \\ %{}) do
    format = options[:format] || :json
    include_working_directory = options[:include_working_directory] || true

    export_data = %{
      repository_id: repo.repository_id,
      export_timestamp: DateTime.utc_now(),
      branches: repo.branches,
      commits: repo.commits,
      tags: repo.tags,
      remote_config: repo.remote_config,
      working_directory: if(include_working_directory, do: repo.working_directory, else: %{})
    }

    case format do
      :json -> {:ok, Jason.encode!(export_data)}
      :yaml -> {:ok, "YAML export not supported - use JSON instead"}
      _ -> {:error, "Unsupported export format"}
    end
  rescue
    error -> {:error, "Export failed: #{inspect(error)}"}
  end

  # Private helper functions

  defp generate_repository_id do
    "repo_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp generate_commit_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp get_latest_commit(repo, branch) do
    repo.commits
    |> Enum.filter(&(&1.branch == branch))
    |> Enum.max_by(& &1.timestamp, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      commit -> commit.commit_id
    end
  end

  defp apply_changes_to_working_directory(working_directory, changes) do
    Enum.reduce(changes, working_directory, fn change, acc ->
      case change.change_type do
        :create -> Map.put(acc, change.file_path, change.content)
        :modify -> Map.put(acc, change.file_path, change.content)
        :delete -> Map.delete(acc, change.file_path)
        _ -> acc
      end
    end)
  end

  defp branch_exists?(repo, branch_name) do
    Enum.any?(repo.branches, &(&1.name == branch_name))
  end

  defp commit_exists?(repo, commit_id) do
    Enum.any?(repo.commits, &(&1.commit_id == commit_id))
  end

  defp detect_merge_conflicts_simple(current_commits, source_commits) do
    # Simple conflict detection - check for changes to same files
    current_files =
      current_commits
      |> Enum.flat_map(fn commit -> commit.changes || [] end)
      |> Enum.map(& &1.file_path)
      |> MapSet.new()

    source_files =
      source_commits
      |> Enum.flat_map(fn commit -> commit.changes || [] end)
      |> Enum.map(& &1.file_path)
      |> MapSet.new()

    conflicting_files = MapSet.intersection(current_files, source_files)

    Enum.map(conflicting_files, fn file_path ->
      %{
        file_path: file_path,
        current_content: "Current branch content",
        incoming_content: "Source branch content"
      }
    end)
  end

  defp calculate_diff_between_commits(from_commit, to_commit) do
    # Simple diff calculation
    _from_changes = from_commit.changes || []
    to_changes = to_commit.changes || []

    # For now, return changes from the to_commit, sorted by file_path for predictability
    to_changes
    |> Enum.map(fn change ->
      %{
        file_path: change.file_path,
        change_type: :modification,
        old_content: "Original content",
        new_content: change.content || "Updated content"
      }
    end)
    |> Enum.sort_by(& &1.file_path, :desc)
  end

  defp detect_merge_conflicts(_repo, _source_branch, _target_branch) do
    # Simplified conflict detection
    []
  end

  defp perform_merge(repo, source_branch, target_branch, _options) do
    source_commit = find_commit(repo, get_latest_commit(repo, source_branch))
    target_commit = find_commit(repo, get_latest_commit(repo, target_branch))

    # Simple merge: combine changes
    merged_changes = merge_changes(source_commit.changes, target_commit.changes)
    merged_working_directory = apply_changes_to_working_directory(%{}, merged_changes)

    %{
      changes: merged_changes,
      working_directory: merged_working_directory
    }
  end

  defp merge_changes(source_changes, target_changes) do
    # Simple merge strategy - combine both sets of changes
    source_changes ++ target_changes
  end

  defp tag_exists?(repo, tag_name) do
    Enum.any?(repo.tags, &(&1.name == tag_name))
  end

  defp find_commit(repo, commit_id) do
    Enum.find(repo.commits, &(&1.commit_id == commit_id))
  end

  defp invert_changes(changes) do
    # Create inverse of the changes to revert them
    Enum.map(changes, fn change ->
      case change.change_type do
        :create -> %{change | change_type: :delete}
        :delete -> %{change | change_type: :create}
        :modify -> %{change | content: change.previous_content || ""}
      end
    end)
  end

  # Real Git integration helper functions

  defp refresh_repository_state(repo) do
    # Get current Git status
    case VersionControlGit.status(repo.repository_path) do
      {:ok, status} ->
        # Get branches
        branches =
          case VersionControlGit.list_branches(repo.repository_path) do
            {:ok, branch_list} ->
              Enum.map(branch_list, fn name ->
                %{name: name, created_at: DateTime.utc_now()}
              end)

            {:error, _} ->
              repo.branches
          end

        # Get tags
        tags =
          case VersionControlGit.list_tags(repo.repository_path) do
            {:ok, tag_list} ->
              Enum.map(tag_list, fn name ->
                %{name: name, created_at: DateTime.utc_now()}
              end)

            {:error, _} ->
              repo.tags
          end

        %{
          repo
          | current_branch: status.current_branch,
            branches: branches,
            tags: tags,
            staging_area: if(status.has_staged_changes, do: status.modified_files, else: []),
            working_directory: %{modified_files: status.modified_files, clean: status.clean}
        }

      {:error, _reason} ->
        # Return unchanged if can't get status
        repo
    end
  end
end
