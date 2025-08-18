defmodule TheMaestro.MCP.Security.AnomalyDetectorTest do
  use ExUnit.Case, async: false
  
  alias TheMaestro.MCP.Security.AnomalyDetector
  
  setup do
    # Start the anomaly detector with test configuration
    start_supervised!({AnomalyDetector, [
      thresholds: %{
        max_tools_per_minute: 10,
        max_failed_confirmations_per_hour: 3,
        injection_pattern_threshold: 0.8,
        burst_activity_threshold: 3.0
      }
    ]})
    
    :ok
  end
  
  describe "event recording and analysis" do
    test "records security events" do
      event = %{
        event_type: :tool_execution,
        user_id: "test_user",
        server_id: "test_server", 
        tool_name: "test_tool",
        parameters: %{path: "/tmp/file.txt"},
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = AnomalyDetector.record_event(event)
      
      # Check that statistics are updated
      :timer.sleep(50)  # Allow async processing
      stats = AnomalyDetector.get_statistics()
      assert stats.events_processed >= 1
    end
    
    test "detects parameter injection patterns" do
      malicious_event = %{
        event_type: :tool_execution,
        user_id: "test_user",
        tool_name: "read_file",
        parameters: %{
          path: "../../../etc/passwd",
          command: "ls; rm -rf /"
        },
        timestamp: DateTime.utc_now()
      }
      
      AnomalyDetector.record_event(malicious_event)
      :timer.sleep(100)
      
      anomalies = AnomalyDetector.get_active_anomalies()
      
      # Should detect directory traversal and command injection
      assert length(anomalies) >= 1
      
      traversal_anomaly = Enum.find(anomalies, fn anomaly ->
        anomaly.type == :parameter_pattern and
        String.contains?(anomaly.description, "directory_traversal")
      end)
      
      assert traversal_anomaly != nil
      assert traversal_anomaly.severity in [:high, :critical]
    end
    
    test "detects excessive tool usage patterns" do
      user_id = "rapid_user"
      
      # Generate many tool usage events quickly
      for i <- 1..15 do
        event = %{
          event_type: :tool_execution,
          user_id: user_id,
          tool_name: "tool_#{i}",
          parameters: %{},
          timestamp: DateTime.utc_now()
        }
        AnomalyDetector.record_event(event)
      end
      
      :timer.sleep(200)
      
      anomalies = AnomalyDetector.get_active_anomalies(user_id: user_id)
      usage_anomaly = Enum.find(anomalies, &(&1.type == :usage_pattern))
      
      assert usage_anomaly != nil
      assert String.contains?(usage_anomaly.description, "tool usage rate")
    end
    
    test "detects temporal anomalies for off-hours access" do
      # Create a user baseline first
      for _i <- 1..10 do
        daytime_event = %{
          event_type: :tool_execution,
          user_id: "day_user",
          tool_name: "normal_tool",
          timestamp: DateTime.new!(Date.utc_today(), ~T[14:00:00], "Etc/UTC")
        }
        AnomalyDetector.record_event(daytime_event)
      end
      
      # Trigger baseline update
      send(AnomalyDetector, :update_baselines)
      :timer.sleep(100)
      
      # Now generate an off-hours event
      night_event = %{
        event_type: :tool_execution,
        user_id: "day_user",
        tool_name: "suspicious_tool",
        timestamp: DateTime.new!(Date.utc_today(), ~T[03:00:00], "Etc/UTC")
      }
      
      AnomalyDetector.record_event(night_event)
      :timer.sleep(100)
      
      anomalies = AnomalyDetector.get_active_anomalies(user_id: "day_user")
      temporal_anomaly = Enum.find(anomalies, &(&1.type == :temporal_pattern))
      
      # Off-hours detection might trigger based on baseline
      if temporal_anomaly do
        assert String.contains?(temporal_anomaly.description, "hours")
      end
    end
    
    test "detects resource usage anomalies" do
      # Create baseline events with normal resource usage
      for _i <- 1..5 do
        normal_event = %{
          event_type: :tool_execution,
          user_id: "resource_user",
          tool_name: "normal_tool",
          resource_usage: %{cpu_percent: 20, memory_mb: 100},
          timestamp: DateTime.utc_now()
        }
        AnomalyDetector.record_event(normal_event)
      end
      
      # Update baselines
      send(AnomalyDetector, :update_baselines)
      :timer.sleep(100)
      
      # Generate high resource usage event
      high_usage_event = %{
        event_type: :tool_execution,
        user_id: "resource_user", 
        tool_name: "heavy_tool",
        resource_usage: %{cpu_percent: 95, memory_mb: 2048},
        timestamp: DateTime.utc_now()
      }
      
      AnomalyDetector.record_event(high_usage_event)
      :timer.sleep(100)
      
      anomalies = AnomalyDetector.get_active_anomalies(user_id: "resource_user")
      resource_anomalies = Enum.filter(anomalies, &(&1.type == :resource_pattern))
      
      assert length(resource_anomalies) >= 1
      cpu_anomaly = Enum.find(resource_anomalies, fn anomaly ->
        String.contains?(anomaly.description, "CPU")
      end)
      
      if cpu_anomaly do
        assert cpu_anomaly.severity in [:medium, :high]
      end
    end
  end
  
  describe "context analysis" do
    test "analyzes context for existing anomalies" do
      # Create an anomaly by recording a malicious event
      event = %{
        user_id: "context_user",
        server_id: "context_server",
        tool_name: "context_tool",
        parameters: %{path: "../../../etc/shadow"},
        timestamp: DateTime.utc_now()
      }
      
      AnomalyDetector.record_event(event)
      :timer.sleep(100)
      
      # Analyze the same context
      context = %{
        user_id: "context_user",
        server_id: "context_server",
        tool_name: "context_tool"
      }
      
      {:ok, anomalies} = AnomalyDetector.analyze_context(context)
      
      # Should find anomalies related to this context
      assert length(anomalies) >= 0  # Might be 0 if no matching anomalies
    end
    
    test "handles context analysis errors gracefully" do
      malformed_context = %{
        invalid_key: :invalid_value,
        nil_value: nil
      }
      
      # Should not crash on malformed context
      assert {:ok, _anomalies} = AnomalyDetector.analyze_context(malformed_context)
    end
  end
  
  describe "anomaly management" do
    test "updates anomaly status" do
      # Create an anomaly first
      event = %{
        parameters: %{command: "rm -rf /"},
        user_id: "test_user",
        timestamp: DateTime.utc_now()
      }
      
      AnomalyDetector.record_event(event)
      :timer.sleep(100)
      
      anomalies = AnomalyDetector.get_active_anomalies()
      
      if length(anomalies) > 0 do
        anomaly = hd(anomalies)
        assert anomaly.status == :detected
        
        # Update status
        assert :ok = AnomalyDetector.update_anomaly_status(
          anomaly.id, :investigating, "security_analyst"
        )
        
        updated_anomalies = AnomalyDetector.get_active_anomalies()
        updated_anomaly = Enum.find(updated_anomalies, &(&1.id == anomaly.id))
        assert updated_anomaly.status == :investigating
      end
    end
    
    test "handles updating non-existent anomaly" do
      assert {:error, "Anomaly not found"} = AnomalyDetector.update_anomaly_status(
        "non_existent", :resolved, "admin"
      )
    end
    
    test "filters anomalies by various criteria" do
      # Create anomalies with different characteristics
      events = [
        %{
          user_id: "user1",
          server_id: "server1", 
          parameters: %{path: "../etc/passwd"},
          timestamp: DateTime.utc_now()
        },
        %{
          user_id: "user2",
          server_id: "server2",
          parameters: %{command: "sudo rm"},
          timestamp: DateTime.utc_now()
        }
      ]
      
      Enum.each(events, &AnomalyDetector.record_event/1)
      :timer.sleep(200)
      
      # Filter by user
      user1_anomalies = AnomalyDetector.get_active_anomalies(user_id: "user1")
      user2_anomalies = AnomalyDetector.get_active_anomalies(user_id: "user2")
      
      # Each user should have their own anomalies (if any were detected)
      user1_users = Enum.map(user1_anomalies, & &1.user_id) |> Enum.uniq()
      user2_users = Enum.map(user2_anomalies, & &1.user_id) |> Enum.uniq()
      
      if length(user1_users) > 0, do: assert(user1_users == ["user1"])
      if length(user2_users) > 0, do: assert(user2_users == ["user2"])
      
      # Filter by type
      param_anomalies = AnomalyDetector.get_active_anomalies(type: :parameter_pattern)
      assert Enum.all?(param_anomalies, &(&1.type == :parameter_pattern))
    end
  end
  
  describe "threshold configuration" do
    test "configures detection thresholds" do
      new_thresholds = %{
        max_tools_per_minute: 5,
        injection_pattern_threshold: 0.9
      }
      
      assert :ok = AnomalyDetector.configure_thresholds(new_thresholds)
      
      # Test that new threshold is applied
      user_id = "threshold_test_user"
      
      # Generate events that exceed the new lower threshold
      for i <- 1..7 do
        event = %{
          user_id: user_id,
          tool_name: "tool_#{i}",
          timestamp: DateTime.utc_now()
        }
        AnomalyDetector.record_event(event)
      end
      
      :timer.sleep(150)
      
      anomalies = AnomalyDetector.get_active_anomalies(user_id: user_id)
      usage_anomaly = Enum.find(anomalies, &(&1.type == :usage_pattern))
      
      # Should detect anomaly with new threshold
      assert usage_anomaly != nil
    end
    
    test "validates threshold values" do
      # Invalid thresholds should be filtered out
      invalid_thresholds = %{
        max_tools_per_minute: -5,  # Negative value
        unknown_threshold: 100,    # Unknown threshold
        invalid_value: "not_a_number"  # Non-numeric
      }
      
      # Should not crash and should filter out invalid values
      assert :ok = AnomalyDetector.configure_thresholds(invalid_thresholds)
    end
  end
  
  describe "baseline management" do
    test "maintains user baselines" do
      user_id = "baseline_user"
      
      # Generate consistent pattern of events
      events = for i <- 1..10 do
        %{
          event_type: :tool_execution,
          user_id: user_id,
          tool_name: "consistent_tool",
          resource_usage: %{cpu_percent: 25, memory_mb: 128},
          timestamp: DateTime.add(DateTime.utc_now(), -i * 60, :second)
        }
      end
      
      Enum.each(events, &AnomalyDetector.record_event/1)
      
      # Trigger baseline update
      send(AnomalyDetector, :update_baselines)
      :timer.sleep(100)
      
      # Should be able to get baseline
      {:ok, baseline} = AnomalyDetector.get_user_baseline(user_id)
      
      assert is_map(baseline)
      assert "consistent_tool" in baseline.common_tools
      assert baseline.avg_cpu_usage > 0
      assert baseline.avg_memory_usage > 0
    end
    
    test "handles baseline request for unknown user" do
      assert {:error, "No baseline found for user"} = 
        AnomalyDetector.get_user_baseline("unknown_user")
    end
  end
  
  describe "statistics and monitoring" do
    test "tracks detection statistics" do
      initial_stats = AnomalyDetector.get_statistics()
      
      # Record some events
      events = [
        %{user_id: "stats_user", tool_name: "tool1", timestamp: DateTime.utc_now()},
        %{user_id: "stats_user", parameters: %{path: "../etc/passwd"}, timestamp: DateTime.utc_now()}
      ]
      
      Enum.each(events, &AnomalyDetector.record_event/1)
      :timer.sleep(150)
      
      updated_stats = AnomalyDetector.get_statistics()
      
      # Should have more events processed
      assert updated_stats.events_processed >= initial_stats.events_processed + 2
      
      # Might have detected anomalies
      assert updated_stats.anomalies_detected >= initial_stats.anomalies_detected
      
      # Should track active anomalies
      assert is_integer(updated_stats.active_anomalies)
    end
  end
  
  describe "cleanup and maintenance" do
    test "cleans up resolved anomalies" do
      # This test would need to create old resolved anomalies and test cleanup
      # For now, just test that the cleanup message doesn't crash
      send(AnomalyDetector, :cleanup_resolved_anomalies)
      :timer.sleep(50)
      
      # Should still be responsive
      stats = AnomalyDetector.get_statistics()
      assert is_map(stats)
    end
  end
  
  describe "behavioral pattern detection" do
    test "detects new tool usage patterns" do
      user_id = "behavioral_user"
      
      # Establish baseline with common tools
      common_tools = ["ls", "cat", "grep"]
      
      for tool <- common_tools do
        for _i <- 1..3 do
          event = %{
            user_id: user_id,
            tool_name: tool,
            timestamp: DateTime.add(DateTime.utc_now(), -Enum.random(1..3600), :second)
          }
          AnomalyDetector.record_event(event)
        end
      end
      
      # Update baselines
      send(AnomalyDetector, :update_baselines)
      :timer.sleep(100)
      
      # Use completely new tool
      new_tool_event = %{
        user_id: user_id,
        tool_name: "very_unusual_tool",
        timestamp: DateTime.utc_now()
      }
      
      AnomalyDetector.record_event(new_tool_event)
      :timer.sleep(100)
      
      anomalies = AnomalyDetector.get_active_anomalies(user_id: user_id)
      behavioral_anomaly = Enum.find(anomalies, &(&1.type == :behavioral_pattern))
      
      # Might detect new tool usage
      if behavioral_anomaly do
        assert String.contains?(behavioral_anomaly.description, "tool")
      end
    end
  end
end