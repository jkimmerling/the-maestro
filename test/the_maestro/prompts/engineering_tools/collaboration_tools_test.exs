defmodule TheMaestro.Prompts.EngineeringTools.CollaborationToolsTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.CollaborationTools

  describe "create_session/2" do
    test "creates a session with valid participants" do
      participants = ["user1", "user2", "user3"]
      
      {:ok, session} = CollaborationTools.create_session(participants)
      
      assert %CollaborationTools{} = session
      assert is_binary(session.session_id)
      assert session.participants == participants
      assert session.collaboration_mode == :asynchronous
      assert is_map(session.permissions)
      assert session.real_time_sync == false
      assert session.change_tracking == true
      assert session.comment_system == true
      assert session.approval_workflow == false
      assert session.conflict_resolution == :automatic
    end

    test "creates a session with custom options" do
      participants = ["user1", "user2"]
      options = %{
        mode: :real_time,
        real_time_sync: true,
        approval_workflow: true,
        conflict_resolution: :manual
      }
      
      {:ok, session} = CollaborationTools.create_session(participants, options)
      
      assert session.collaboration_mode == :real_time
      assert session.real_time_sync == true
      assert session.approval_workflow == true
      assert session.conflict_resolution == :manual
    end

    test "fails with empty participants list" do
      {:error, reason} = CollaborationTools.create_session([])
      
      assert reason == "At least one participant is required"
    end

    test "creates a single-user session" do
      participants = ["single_user"]
      
      {:ok, session} = CollaborationTools.create_session(participants)
      
      assert session.participants == ["single_user"]
    end
  end

  describe "add_participant/2" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1"])
      {:ok, session: session}
    end

    test "adds a new participant to session", %{session: session} do
      {:ok, updated_session} = CollaborationTools.add_participant(session, "user2")
      
      assert "user2" in updated_session.participants
      assert length(updated_session.participants) == 2
    end

    test "prevents duplicate participants", %{session: session} do
      {:error, reason} = CollaborationTools.add_participant(session, "user1")
      
      assert reason == "Participant already exists in session"
    end

    test "validates participant ID format", %{session: session} do
      {:error, reason} = CollaborationTools.add_participant(session, "")
      
      assert reason == "Invalid participant ID"
    end
  end

  describe "remove_participant/2" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2", "user3"])
      {:ok, session: session}
    end

    test "removes existing participant from session", %{session: session} do
      {:ok, updated_session} = CollaborationTools.remove_participant(session, "user2")
      
      refute "user2" in updated_session.participants
      assert length(updated_session.participants) == 2
    end

    test "fails when removing non-existent participant", %{session: session} do
      {:error, reason} = CollaborationTools.remove_participant(session, "nonexistent")
      
      assert reason == "Participant not found in session"
    end

    test "prevents removing last participant", %{session: _session} do
      {:ok, single_session} = CollaborationTools.create_session(["user1"])
      
      {:error, reason} = CollaborationTools.remove_participant(single_session, "user1")
      
      assert reason == "Cannot remove last participant from session"
    end
  end

  describe "start_real_time_sync/1" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      {:ok, session: session}
    end

    test "enables real-time synchronization", %{session: session} do
      {:ok, updated_session} = CollaborationTools.start_real_time_sync(session)
      
      assert updated_session.real_time_sync == true
      assert updated_session.collaboration_mode == :real_time
    end

    test "handles already enabled sync", %{session: session} do
      {:ok, synced_session} = CollaborationTools.start_real_time_sync(session)
      {:ok, double_synced} = CollaborationTools.start_real_time_sync(synced_session)
      
      assert double_synced.real_time_sync == true
    end
  end

  describe "stop_real_time_sync/1" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"], %{real_time_sync: true})
      {:ok, session: session}
    end

    test "disables real-time synchronization", %{session: session} do
      {:ok, updated_session} = CollaborationTools.stop_real_time_sync(session)
      
      assert updated_session.real_time_sync == false
      assert updated_session.collaboration_mode == :asynchronous
    end
  end

  describe "create_comment/4" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      {:ok, session: session}
    end

    test "creates a comment on prompt content", %{session: session} do
      comment_data = CollaborationTools.create_comment(
        session,
        "user1",
        "This could be more specific",
        %{line: 5, section: "task_description"}
      )
      
      assert Map.has_key?(comment_data, :comment_id)
      assert comment_data.author == "user1"
      assert comment_data.content == "This could be more specific"
      assert comment_data.position == %{line: 5, section: "task_description"}
      assert comment_data.status == :active
      assert %DateTime{} = comment_data.created_at
    end

    test "validates comment content", %{session: session} do
      {:error, reason} = CollaborationTools.create_comment(
        session,
        "user1",
        "",
        %{line: 1}
      )
      
      assert reason == "Comment content cannot be empty"
    end

    test "validates participant permissions", %{session: session} do
      {:error, reason} = CollaborationTools.create_comment(
        session,
        "unauthorized_user",
        "Some comment",
        %{line: 1}
      )
      
      assert reason == "User not authorized to comment in this session"
    end
  end

  describe "resolve_comment/3" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      comment = CollaborationTools.create_comment(
        session,
        "user1",
        "This needs work",
        %{line: 3}
      )
      {:ok, session: session, comment: comment}
    end

    test "resolves an active comment", %{session: session, comment: comment} do
      {:ok, resolved_comment} = CollaborationTools.resolve_comment(
        session,
        comment.comment_id,
        "user2"
      )
      
      assert resolved_comment.status == :resolved
      assert resolved_comment.resolved_by == "user2"
      assert %DateTime{} = resolved_comment.resolved_at
    end

    test "prevents unauthorized comment resolution", %{session: session, comment: comment} do
      {:error, reason} = CollaborationTools.resolve_comment(
        session,
        comment.comment_id,
        "unauthorized_user"
      )
      
      assert reason == "User not authorized to resolve comments in this session"
    end
  end

  describe "track_change/4" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      {:ok, session: session}
    end

    test "tracks prompt changes", %{session: session} do
      change = CollaborationTools.track_change(
        session,
        "user1",
        :content_update,
        %{
          before: "Original content",
          after: "Updated content",
          section: "task_description"
        }
      )
      
      assert Map.has_key?(change, :change_id)
      assert change.user_id == "user1"
      assert change.change_type == :content_update
      assert change.metadata.before == "Original content"
      assert change.metadata.after == "Updated content"
      assert %DateTime{} = change.timestamp
    end

    test "validates change metadata", %{session: session} do
      {:error, reason} = CollaborationTools.track_change(
        session,
        "user1",
        :content_update,
        %{}
      )
      
      assert reason == "Change metadata must include before and after content"
    end
  end

  describe "get_change_history/1" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      
      # Create some changes
      _change1 = CollaborationTools.track_change(
        session,
        "user1",
        :content_update,
        %{before: "Old", after: "New", section: "task"}
      )
      
      _change2 = CollaborationTools.track_change(
        session,
        "user2",
        :parameter_update,
        %{before: "param1", after: "param2", section: "parameters"}
      )
      
      {:ok, session: session}
    end

    test "returns chronological change history", %{session: session} do
      history = CollaborationTools.get_change_history(session)
      
      assert is_list(history)
      assert length(history) == 2
      
      # Should be ordered by timestamp (most recent first)
      [latest | _] = history
      assert latest.change_type in [:content_update, :parameter_update]
      assert latest.user_id in ["user1", "user2"]
    end

    test "filters history by user", %{session: session} do
      history = CollaborationTools.get_change_history(session, %{user_id: "user1"})
      
      assert length(history) == 1
      assert List.first(history).user_id == "user1"
    end

    test "filters history by change type", %{session: session} do
      history = CollaborationTools.get_change_history(session, %{change_type: :parameter_update})
      
      assert length(history) == 1
      assert List.first(history).change_type == :parameter_update
    end
  end

  describe "create_approval_request/3" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"], %{approval_workflow: true})
      {:ok, session: session}
    end

    test "creates approval request", %{session: session} do
      request = CollaborationTools.create_approval_request(
        session,
        "user1",
        %{
          title: "New prompt optimization",
          description: "Improved token efficiency",
          changes: ["Modified task description", "Added examples"]
        }
      )
      
      assert Map.has_key?(request, :request_id)
      assert request.requester == "user1"
      assert request.status == :pending
      assert request.metadata.title == "New prompt optimization"
      assert length(request.metadata.changes) == 2
      assert %DateTime{} = request.created_at
    end

    test "fails when approval workflow disabled" do
      {:ok, no_approval_session} = CollaborationTools.create_session(["user1", "user2"])
      
      {:error, reason} = CollaborationTools.create_approval_request(
        no_approval_session,
        "user1",
        %{title: "Test", description: "Test"}
      )
      
      assert reason == "Approval workflow is not enabled for this session"
    end
  end

  describe "approve_request/3" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"], %{approval_workflow: true})
      
      request = CollaborationTools.create_approval_request(
        session,
        "user1",
        %{title: "Test approval", description: "Test"}
      )
      
      {:ok, session: session, request: request}
    end

    test "approves pending request", %{session: session, request: request} do
      {:ok, approved_request} = CollaborationTools.approve_request(
        session,
        request.request_id,
        "user2"
      )
      
      assert approved_request.status == :approved
      assert approved_request.approved_by == "user2"
      assert %DateTime{} = approved_request.approved_at
    end

    test "prevents self-approval", %{session: session, request: request} do
      {:error, reason} = CollaborationTools.approve_request(
        session,
        request.request_id,
        "user1"
      )
      
      assert reason == "Users cannot approve their own requests"
    end
  end

  describe "handle_conflict/4" do
    setup do
      {:ok, session} = CollaborationTools.create_session(["user1", "user2"])
      {:ok, session: session}
    end

    test "resolves conflict automatically when configured", %{session: session} do
      conflict_data = %{
        section: "task_description",
        user1_change: "Version A",
        user2_change: "Version B",
        timestamp1: DateTime.utc_now() |> DateTime.add(-5, :second),
        timestamp2: DateTime.utc_now()
      }
      
      resolution = CollaborationTools.handle_conflict(
        session,
        :content_conflict,
        conflict_data,
        %{strategy: :latest_wins}
      )
      
      assert resolution.resolution_strategy == :latest_wins
      assert resolution.resolved_content == "Version B"  # Latest timestamp
      assert resolution.status == :resolved
    end

    test "creates manual conflict when automatic resolution disabled", %{session: session} do
      manual_session = %{session | conflict_resolution: :manual}
      
      conflict_data = %{
        section: "parameters",
        user1_change: "param=value1",
        user2_change: "param=value2"
      }
      
      resolution = CollaborationTools.handle_conflict(
        manual_session,
        :parameter_conflict,
        conflict_data,
        %{strategy: :manual}
      )
      
      assert resolution.resolution_strategy == :manual
      assert resolution.status == :pending
      assert Map.has_key?(resolution, :conflict_id)
    end
  end
end