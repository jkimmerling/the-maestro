defmodule TheMaestro.Prompts.EngineeringTools.VersionControlTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.VersionControl

  describe "init_repository/1" do
    test "initializes a repository with default settings" do
      {:ok, repo} = VersionControl.init_repository()

      assert %VersionControl{} = repo
      assert is_binary(repo.repository_id)
      assert repo.current_branch == "main"
      assert is_list(repo.branches)
      assert length(repo.branches) == 1
      assert is_list(repo.commits)
      assert length(repo.commits) == 0
      assert is_list(repo.staging_area)
      assert is_map(repo.working_directory)
      assert is_list(repo.merge_conflicts)
      assert is_list(repo.tags)
    end

    test "initializes a repository with custom branch name" do
      {:ok, repo} = VersionControl.init_repository(%{initial_branch: "development"})

      assert repo.current_branch == "development"
      [branch] = repo.branches
      assert branch.name == "development"
    end

    test "initializes a repository with remote config" do
      remote_config = %{url: "https://github.com/example/prompts.git", name: "origin"}
      {:ok, repo} = VersionControl.init_repository(%{remote: remote_config})

      assert repo.remote_config == remote_config
    end
  end

  describe "create_branch/3" do
    setup do
      {:ok, repo} = VersionControl.init_repository()
      {:ok, repo: repo}
    end

    test "creates a new branch from current branch", %{repo: repo} do
      {:ok, updated_repo} = VersionControl.create_branch(repo, "feature-branch", %{})

      assert length(updated_repo.branches) == 2

      feature_branch = Enum.find(updated_repo.branches, &(&1.name == "feature-branch"))
      assert feature_branch != nil
      assert feature_branch.name == "feature-branch"
      assert feature_branch.source_branch == "main"
    end

    test "creates a branch from specific source branch", %{repo: repo} do
      {:ok, repo_with_dev} = VersionControl.create_branch(repo, "dev", %{})

      {:ok, updated_repo} =
        VersionControl.create_branch(repo_with_dev, "feature", %{source_branch: "dev"})

      feature_branch = Enum.find(updated_repo.branches, &(&1.name == "feature"))
      assert feature_branch.source_branch == "dev"
    end

    test "prevents creating duplicate branch names", %{repo: repo} do
      {:error, reason} = VersionControl.create_branch(repo, "main", %{})

      assert reason == "Branch 'main' already exists"
    end

    test "validates branch name format", %{repo: repo} do
      {:error, reason} = VersionControl.create_branch(repo, "", %{})

      assert reason == "Invalid branch name"
    end
  end

  describe "switch_branch/2" do
    setup do
      {:ok, repo} = VersionControl.init_repository()
      {:ok, repo_with_branch} = VersionControl.create_branch(repo, "development", %{})
      {:ok, repo: repo_with_branch}
    end

    test "switches to existing branch", %{repo: repo} do
      {:ok, updated_repo} = VersionControl.switch_branch(repo, "development")

      assert updated_repo.current_branch == "development"
    end

    test "fails when switching to non-existent branch", %{repo: repo} do
      {:error, reason} = VersionControl.switch_branch(repo, "nonexistent")

      assert reason == "Branch 'nonexistent' does not exist"
    end

    test "handles uncommitted changes warning", %{repo: repo} do
      # Add some changes to working directory
      repo_with_changes = %{repo | working_directory: %{prompt: "Uncommitted changes"}}

      {:ok, updated_repo} = VersionControl.switch_branch(repo_with_changes, "development")

      assert updated_repo.current_branch == "development"
      # Changes should be preserved in working directory
      assert updated_repo.working_directory == %{prompt: "Uncommitted changes"}
    end
  end

  describe "stage_changes/2" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      working_changes = %{
        prompt: "New prompt content",
        metadata: %{author: "test_user", version: "1.0"}
      }

      repo_with_changes = %{repo | working_directory: working_changes}
      {:ok, repo: repo_with_changes}
    end

    test "stages all working directory changes", %{repo: repo} do
      {:ok, updated_repo} = VersionControl.stage_changes(repo, :all)

      assert length(updated_repo.staging_area) > 0
      staged_change = List.first(updated_repo.staging_area)
      assert staged_change.change_type == :modification
      assert Map.has_key?(staged_change, :content)
    end

    test "stages specific files", %{repo: repo} do
      {:ok, updated_repo} = VersionControl.stage_changes(repo, ["prompt"])

      assert length(updated_repo.staging_area) == 1
      staged_change = List.first(updated_repo.staging_area)
      assert staged_change.file_path == "prompt"
    end

    test "handles empty working directory", %{repo: _repo} do
      {:ok, empty_repo} = VersionControl.init_repository()

      {:ok, updated_repo} = VersionControl.stage_changes(empty_repo, :all)

      assert length(updated_repo.staging_area) == 0
    end
  end

  describe "commit/3" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      # Add and stage some changes
      working_changes = %{prompt: "Test prompt content"}
      repo_with_changes = %{repo | working_directory: working_changes}
      {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)

      {:ok, repo: repo_with_staged}
    end

    test "creates a commit with staged changes", %{repo: repo} do
      commit_message = "Add initial prompt content"
      commit_author = "test_user"

      {:ok, updated_repo} = VersionControl.commit(repo, commit_message, commit_author)

      assert length(updated_repo.commits) == 1
      commit = List.first(updated_repo.commits)

      assert commit.message == commit_message
      assert commit.author == commit_author
      assert is_binary(commit.commit_id)
      assert %DateTime{} = commit.timestamp
      assert is_list(commit.changes)

      # Staging area should be cleared after commit
      assert length(updated_repo.staging_area) == 0
    end

    test "fails with empty staging area" do
      {:ok, empty_repo} = VersionControl.init_repository()

      {:error, reason} = VersionControl.commit(empty_repo, "Empty commit", "test_user")

      assert reason == "No staged changes to commit"
    end

    test "validates commit message", %{repo: repo} do
      {:error, reason} = VersionControl.commit(repo, "", "test_user")

      assert reason == "Commit message cannot be empty"
    end

    test "validates author", %{repo: repo} do
      {:error, reason} = VersionControl.commit(repo, "Valid message", "")

      assert reason == "Commit author cannot be empty"
    end
  end

  describe "merge_branch/3" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      # Create a feature branch and add a commit
      {:ok, repo_with_branch} = VersionControl.create_branch(repo, "feature", %{})
      {:ok, repo_on_feature} = VersionControl.switch_branch(repo_with_branch, "feature")

      # Add changes and commit on feature branch
      working_changes = %{prompt: "Feature content"}
      repo_with_changes = %{repo_on_feature | working_directory: working_changes}
      {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)

      {:ok, repo_with_commit} =
        VersionControl.commit(repo_with_staged, "Add feature", "test_user")

      # Switch back to main
      {:ok, repo_on_main} = VersionControl.switch_branch(repo_with_commit, "main")

      {:ok, repo: repo_on_main}
    end

    test "merges feature branch into current branch", %{repo: repo} do
      {:ok, merged_repo} = VersionControl.merge_branch(repo, "feature", %{strategy: :auto})

      # Should have commits from both branches
      assert length(merged_repo.commits) >= 1

      # Should have a merge commit
      merge_commit = Enum.find(merged_repo.commits, &(&1.message =~ "Merge"))
      assert merge_commit != nil
    end

    test "detects merge conflicts", %{repo: repo} do
      # Create conflicting changes on main branch
      main_changes = %{prompt: "Main branch content"}
      repo_with_main_changes = %{repo | working_directory: main_changes}
      {:ok, repo_with_main_staged} = VersionControl.stage_changes(repo_with_main_changes, :all)

      {:ok, repo_with_main_commit} =
        VersionControl.commit(repo_with_main_staged, "Main changes", "test_user")

      {:ok, result} =
        VersionControl.merge_branch(repo_with_main_commit, "feature", %{strategy: :auto})

      # Should detect conflicts
      assert length(result.merge_conflicts) > 0
      conflict = List.first(result.merge_conflicts)
      assert conflict.file_path == "prompt"
      assert Map.has_key?(conflict, :current_content)
      assert Map.has_key?(conflict, :incoming_content)
    end

    test "fails when merging non-existent branch", %{repo: repo} do
      {:error, reason} = VersionControl.merge_branch(repo, "nonexistent", %{})

      assert reason == "Branch 'nonexistent' does not exist"
    end
  end

  describe "create_tag/3" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      # Add a commit to tag
      working_changes = %{prompt: "Tagged content"}
      repo_with_changes = %{repo | working_directory: working_changes}
      {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)

      {:ok, repo_with_commit} =
        VersionControl.commit(repo_with_staged, "Initial commit", "test_user")

      {:ok, repo: repo_with_commit}
    end

    test "creates a tag on current commit", %{repo: repo} do
      [latest_commit] = repo.commits

      {:ok, updated_repo} = VersionControl.create_tag(repo, "v1.0.0", latest_commit.commit_id)

      assert length(updated_repo.tags) == 1
      tag = List.first(updated_repo.tags)

      assert tag.name == "v1.0.0"
      assert tag.commit_id == latest_commit.commit_id
      assert %DateTime{} = tag.created_at
    end

    test "prevents duplicate tag names", %{repo: repo} do
      [latest_commit] = repo.commits
      {:ok, repo_with_tag} = VersionControl.create_tag(repo, "v1.0.0", latest_commit.commit_id)

      {:error, reason} =
        VersionControl.create_tag(repo_with_tag, "v1.0.0", latest_commit.commit_id)

      assert reason == "Tag 'v1.0.0' already exists"
    end

    test "validates tag name format", %{repo: repo} do
      [latest_commit] = repo.commits

      {:error, reason} = VersionControl.create_tag(repo, "", latest_commit.commit_id)

      assert reason == "Invalid tag name"
    end

    test "validates commit exists", %{repo: repo} do
      {:error, reason} = VersionControl.create_tag(repo, "v1.0.0", "nonexistent_commit")

      assert reason == "Commit 'nonexistent_commit' does not exist"
    end
  end

  describe "get_commit_history/2" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      # Create multiple commits
      commits_data = [
        {"First commit", "Initial content"},
        {"Second commit", "Updated content"},
        {"Third commit", "Final content"}
      ]

      final_repo =
        Enum.reduce(commits_data, repo, fn {message, content}, acc_repo ->
          working_changes = %{prompt: content}
          repo_with_changes = %{acc_repo | working_directory: working_changes}
          {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)
          {:ok, repo_with_commit} = VersionControl.commit(repo_with_staged, message, "test_user")
          repo_with_commit
        end)

      {:ok, repo: final_repo}
    end

    test "returns commit history in chronological order", %{repo: repo} do
      history = VersionControl.get_commit_history(repo)

      assert length(history) == 3

      # Should be ordered by timestamp (most recent first)
      [latest, second, oldest] = history
      assert latest.message == "Third commit"
      assert second.message == "Second commit"
      assert oldest.message == "First commit"
    end

    test "limits history with count option", %{repo: repo} do
      history = VersionControl.get_commit_history(repo, %{limit: 2})

      assert length(history) == 2
      [latest, second] = history
      assert latest.message == "Third commit"
      assert second.message == "Second commit"
    end

    test "filters history by author", %{repo: repo} do
      # Add commit by different author
      working_changes = %{prompt: "Different author content"}
      repo_with_changes = %{repo | working_directory: working_changes}
      {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)

      {:ok, repo_with_commit} =
        VersionControl.commit(repo_with_staged, "Different author", "other_user")

      test_user_history =
        VersionControl.get_commit_history(repo_with_commit, %{author: "test_user"})

      other_user_history =
        VersionControl.get_commit_history(repo_with_commit, %{author: "other_user"})

      assert length(test_user_history) == 3
      assert length(other_user_history) == 1
      assert List.first(other_user_history).author == "other_user"
    end
  end

  describe "get_diff/3" do
    setup do
      {:ok, repo} = VersionControl.init_repository()

      # Create initial commit
      working_changes = %{prompt: "Original content", metadata: %{version: "1.0"}}
      repo_with_changes = %{repo | working_directory: working_changes}
      {:ok, repo_with_staged} = VersionControl.stage_changes(repo_with_changes, :all)

      {:ok, repo_with_first} =
        VersionControl.commit(repo_with_staged, "First commit", "test_user")

      # Create second commit
      updated_changes = %{prompt: "Updated content", metadata: %{version: "1.1"}}
      repo_with_updates = %{repo_with_first | working_directory: updated_changes}
      {:ok, repo_with_staged2} = VersionControl.stage_changes(repo_with_updates, :all)

      {:ok, repo_with_second} =
        VersionControl.commit(repo_with_staged2, "Second commit", "test_user")

      {:ok, repo: repo_with_second}
    end

    test "shows diff between two commits", %{repo: repo} do
      [second_commit, first_commit] = repo.commits

      diff = VersionControl.get_diff(repo, first_commit.commit_id, second_commit.commit_id)

      assert Map.has_key?(diff, :changes)
      assert is_list(diff.changes)
      assert length(diff.changes) > 0

      change = List.first(diff.changes)
      assert change.file_path == "prompt"
      assert change.change_type == :modification
      assert change.old_content == "Original content"
      assert change.new_content == "Updated content"
    end

    test "shows diff of working directory vs last commit", %{repo: repo} do
      # Add uncommitted changes
      working_changes = %{prompt: "Uncommitted content"}
      repo_with_changes = %{repo | working_directory: working_changes}

      diff = VersionControl.get_diff(repo_with_changes, "HEAD", "WORKING")

      assert Map.has_key?(diff, :changes)
      change = List.first(diff.changes)
      assert change.new_content == "Uncommitted content"
    end

    test "handles non-existent commit IDs", %{repo: repo} do
      {:error, reason} = VersionControl.get_diff(repo, "nonexistent", "HEAD")

      assert reason == "Commit 'nonexistent' does not exist"
    end
  end
end
