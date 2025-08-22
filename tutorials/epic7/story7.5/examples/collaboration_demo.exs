# Collaboration Tools Demo
#
# This example demonstrates team collaboration features including session management,
# conflict resolution, and multi-user workflows
# Run in IEx with: Code.eval_file("tutorials/epic7/story7.5/examples/collaboration_demo.exs")

alias TheMaestro.Prompts.EngineeringTools
alias TheMaestro.Prompts.EngineeringTools.CollaborationTools

IO.puts("=== Collaboration Tools Demo ===")

# Step 1: Set up a collaborative workspace
IO.puts("\n1. Setting up collaborative workspace...")

{:ok, env} = EngineeringTools.initialize_engineering_environment(%{
  user_id: "team_lead",
  skill_level: :advanced
})

{:ok, workspace} = EngineeringTools.create_workspace(env, %{
  name: "team_collaboration_demo",
  domain: :general,
  user_id: "team_lead"
})

IO.puts("✅ Workspace created: team_collaboration_demo")

# Step 2: Create a small team collaboration session (≤5 people)
IO.puts("\n2. Creating small team collaboration session...")

small_team_config = %{
  workspace_id: workspace.name,
  participants: ["team_lead", "developer1", "developer2", "reviewer1"],
  permissions: %{
    edit: ["team_lead", "developer1", "developer2"],
    review: ["reviewer1"],
    admin: ["team_lead"]
  },
  collaboration_settings: %{
    max_concurrent_editors: 2,
    auto_save_interval: 30,  # seconds
    conflict_resolution: :manual,  # Manual for teams ≤ 5
    notification_level: :standard
  }
}

{:ok, small_session} = CollaborationTools.create_session(small_team_config)

IO.puts("✅ Small team session created (#{length(small_team_config.participants)} participants)")
IO.puts("   Session ID: #{small_session.id}")
IO.puts("   Conflict resolution: #{small_team_config.collaboration_settings.conflict_resolution}")
IO.puts("   Notification level: #{small_team_config.collaboration_settings.notification_level}")

# Demonstrate participants joining
IO.puts("\n3. Team members joining session...")

participants_to_join = ["developer1", "developer2", "reviewer1"]

Enum.each(participants_to_join, fn participant ->
  {:ok, _} = CollaborationTools.join_session(small_session.id, participant)
  IO.puts("   ✅ #{participant} joined the session")
end)

{:ok, active_participants} = CollaborationTools.list_active_participants(small_session.id)
IO.puts("\nActive participants: #{Enum.join(active_participants, ", ")}")

# Step 4: Simulate collaborative editing with conflict scenarios
IO.puts("\n4. Simulating collaborative editing...")

# Developer1 makes an edit
developer1_changes = %{
  section: "introduction",
  content: "Welcome to our customer service portal. We're here to help you with all your needs.",
  timestamp: DateTime.utc_now(),
  user: "developer1"
}

{:ok, edit1} = CollaborationTools.submit_edit(small_session.id, "developer1", developer1_changes)
IO.puts("✅ Developer1 submitted edit to introduction")

# Developer2 makes a conflicting edit to the same section
developer2_changes = %{
  section: "introduction", 
  content: "Hello! Welcome to our help center. Let us assist you with your questions today.",
  timestamp: DateTime.add(DateTime.utc_now(), 5, :second),
  user: "developer2"
}

{:ok, edit2} = CollaborationTools.submit_edit(small_session.id, "developer2", developer2_changes)
IO.puts("✅ Developer2 submitted conflicting edit to introduction")

# Detect and handle conflicts (manual resolution for small teams)
{:ok, conflicts} = CollaborationTools.detect_conflicts(small_session.id)
IO.puts("\n⚠️  Conflicts detected: #{length(conflicts)} conflicts found")

Enum.each(conflicts, fn conflict ->
  IO.puts("   Conflict in section: #{conflict.section}")
  IO.puts("   Between users: #{Enum.join(conflict.users, " and ")}")
  IO.puts("   Resolution needed: #{conflict.resolution_strategy}")
end)

# Manual conflict resolution process
IO.puts("\n5. Resolving conflicts manually (small team process)...")

resolution_choice = %{
  conflict_id: List.first(conflicts).id,
  resolution: :merge,  # Could be :merge, :take_first, :take_second, :custom
  final_content: "Welcome to our customer service help center. We're here to assist you with all your needs and questions.",
  resolved_by: "team_lead"
}

{:ok, _} = CollaborationTools.resolve_conflict(small_session.id, resolution_choice)
IO.puts("✅ Conflict resolved by team_lead using merge strategy")

# Step 6: Demonstrate large team collaboration (>5 people)
IO.puts("\n6. Creating large team collaboration session...")

large_team_config = %{
  workspace_id: workspace.name,
  participants: Enum.map(1..8, fn i -> "user#{i}" end),
  permissions: %{
    edit: Enum.map(1..6, fn i -> "user#{i}" end),
    review: ["user7", "user8"],
    admin: ["user1"]
  },
  collaboration_settings: %{
    max_concurrent_editors: 3,
    auto_save_interval: 15,
    conflict_resolution: :automatic,  # Automatic for teams > 5
    notification_level: :detailed,     # Detailed for teams > 10 (we have 8, so standard)
    team_size_optimizations: true
  }
}

{:ok, large_session} = CollaborationTools.create_session(large_team_config)

IO.puts("✅ Large team session created (#{length(large_team_config.participants)} participants)")
IO.puts("   Session ID: #{large_session.id}")
IO.puts("   Conflict resolution: #{large_team_config.collaboration_settings.conflict_resolution} (auto-enabled for teams > 5)")
IO.puts("   Notification level: standard (would be detailed for teams > 10)")

# Demonstrate automatic conflict resolution
IO.puts("\n7. Simulating automatic conflict resolution...")

# Multiple users make overlapping changes
user_changes = [
  %{user: "user1", section: "header", content: "Company Services - Version 1", timestamp: DateTime.utc_now()},
  %{user: "user2", section: "header", content: "Our Services - Version 2", timestamp: DateTime.add(DateTime.utc_now(), 2, :second)},
  %{user: "user3", section: "header", content: "Professional Services - Version 3", timestamp: DateTime.add(DateTime.utc_now(), 4, :second)}
]

Enum.each(user_changes, fn change ->
  {:ok, _} = CollaborationTools.submit_edit(large_session.id, change.user, change)
  IO.puts("   📝 #{change.user} submitted edit: '#{change.content}'")
end)

# Automatic conflict resolution kicks in
{:ok, auto_conflicts} = CollaborationTools.detect_conflicts(large_session.id)
IO.puts("\n🤖 Automatic conflict resolution processing #{length(auto_conflicts)} conflicts...")

# Simulate automatic resolution
{:ok, auto_resolution} = CollaborationTools.auto_resolve_conflicts(large_session.id, %{
  strategy: :intelligent_merge,
  preserve_intent: true,
  notify_users: true
})

IO.puts("✅ Automatic resolution complete")
IO.puts("   Resolution strategy: #{auto_resolution.strategy}")
IO.puts("   Final content: '#{auto_resolution.final_content}'")
IO.puts("   Users notified: #{Enum.join(auto_resolution.notified_users, ", ")}")

# Step 8: Collaboration analytics and insights
IO.puts("\n8. Gathering collaboration analytics...")

{:ok, small_team_analytics} = CollaborationTools.get_collaboration_analytics(small_session.id)
{:ok, large_team_analytics} = CollaborationTools.get_collaboration_analytics(large_session.id)

IO.puts("\nSmall Team Analytics:")
IO.puts("   Total edits: #{small_team_analytics.total_edits}")
IO.puts("   Conflicts: #{small_team_analytics.total_conflicts}")
IO.puts("   Resolution time: #{small_team_analytics.avg_resolution_time_minutes} minutes")
IO.puts("   Active users: #{small_team_analytics.active_user_count}")

IO.puts("\nLarge Team Analytics:")
IO.puts("   Total edits: #{large_team_analytics.total_edits}")
IO.puts("   Conflicts: #{large_team_analytics.total_conflicts}")
IO.puts("   Auto-resolutions: #{large_team_analytics.auto_resolutions}")
IO.puts("   Avg resolution time: #{large_team_analytics.avg_resolution_time_minutes} minutes")
IO.puts("   Concurrent edit efficiency: #{large_team_analytics.concurrent_edit_efficiency}%")

# Step 9: Best practices demonstration
IO.puts("\n9. Collaboration best practices...")

best_practices = %{
  small_teams: [
    "Use manual conflict resolution for better control",
    "Enable detailed discussions for complex changes",
    "Assign clear roles and responsibilities",
    "Regular check-ins and communication"
  ],
  large_teams: [
    "Enable automatic conflict resolution to maintain flow",
    "Use concurrent editor limits to prevent chaos",
    "Implement detailed notifications for awareness",
    "Set up clear approval workflows"
  ]
}

IO.puts("\nSmall Team Best Practices (≤5 people):")
Enum.each(best_practices.small_teams, fn practice ->
  IO.puts("   • #{practice}")
end)

IO.puts("\nLarge Team Best Practices (>5 people):")
Enum.each(best_practices.large_teams, fn practice ->
  IO.puts("   • #{practice}")
end)

# Step 10: Clean up sessions
IO.puts("\n10. Cleaning up collaboration sessions...")

{:ok, _} = CollaborationTools.close_session(small_session.id, "team_lead")
{:ok, _} = CollaborationTools.close_session(large_session.id, "user1")

IO.puts("✅ Sessions closed successfully")

IO.puts("\n=== Collaboration Demo Complete ===")
IO.puts("This example demonstrated:")
IO.puts("1. Small team collaboration (≤5 people) with manual conflict resolution")
IO.puts("2. Large team collaboration (>5 people) with automatic conflict resolution")
IO.puts("3. Real-time editing and conflict detection")
IO.puts("4. Different conflict resolution strategies")
IO.puts("5. Collaboration analytics and insights")
IO.puts("6. Best practices for different team sizes")

IO.puts("\nKey features showcased:")
IO.puts("• 🔧 Adaptive conflict resolution (manual ≤5, automatic >5)")
IO.puts("• 📊 Real-time collaboration analytics")
IO.puts("• 👥 Permission-based access control")
IO.puts("• ⚡ Concurrent editing with limits")
IO.puts("• 🔔 Intelligent notification systems")

IO.puts("\nConfiguration highlights:")
IO.puts("• Teams ≤5: Manual conflict resolution, standard notifications")
IO.puts("• Teams >5: Automatic conflict resolution, detailed notifications")
IO.puts("• Teams >10: Enhanced notification levels and analytics")
IO.puts("• Concurrent editor limits scale with team size")

IO.puts("\nNext steps:")
IO.puts("- Try the ab_testing_example.exs for A/B testing workflows")
IO.puts("- Check advanced-features.md for enterprise collaboration")
IO.puts("- Review troubleshooting.md for common collaboration issues")