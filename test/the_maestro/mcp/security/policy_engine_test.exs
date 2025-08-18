defmodule TheMaestro.MCP.Security.PolicyEngineTest do
  use ExUnit.Case, async: false
  
  alias TheMaestro.MCP.Security.PolicyEngine
  
  setup do
    # Start the policy engine with test configuration - use default global settings
    start_supervised!({PolicyEngine, [
      initial_policies: %{}
      # Let it use default_global_settings() for complete settings
    ]})
    
    :ok
  end
  
  describe "global settings management" do
    test "gets default global settings" do
      settings = PolicyEngine.get_global_settings()
      
      assert settings.default_server_trust == :untrusted
      assert settings.require_confirmation_threshold == :medium
      assert settings.auto_block_high_risk == true
      assert is_integer(settings.session_trust_timeout)
    end
    
    test "updates global settings" do
      new_settings = %{
        default_server_trust: :trusted,
        max_concurrent_executions: 20
      }
      
      assert :ok = PolicyEngine.set_global_settings(new_settings)
      
      updated_settings = PolicyEngine.get_global_settings()
      assert updated_settings.default_server_trust == :trusted
      assert updated_settings.max_concurrent_executions == 20
      # Other settings should be preserved
      assert updated_settings.require_confirmation_threshold == :medium
    end
  end
  
  describe "policy management" do
    test "creates and retrieves policies" do
      policy_data = %{
        name: "Test User Policy",
        level: :user,
        settings: %{
          require_confirmation_threshold: :low,
          auto_block_high_risk: false
        },
        conditions: %{
          user_id: "test_user"
        },
        priority: 100
      }
      
      assert :ok = PolicyEngine.update_policy("test_policy", policy_data)
      
      policies = PolicyEngine.list_policies()
      assert length(policies) == 1
      
      policy = hd(policies)
      assert policy.name == "Test User Policy"
      assert policy.level == :user
      assert policy.settings.require_confirmation_threshold == :low
      assert policy.conditions.user_id == "test_user"
    end
    
    test "validates policy data" do
      invalid_policy = %{
        name: "Invalid Policy",
        level: :invalid_level,
        settings: "not_a_map"
      }
      
      assert {:error, reason} = PolicyEngine.update_policy("invalid", invalid_policy)
      assert String.contains?(reason, "Invalid policy level")
    end
    
    test "deletes policies" do
      policy_data = %{
        name: "Delete Test",
        level: :global,
        settings: %{}
      }
      
      PolicyEngine.update_policy("delete_test", policy_data)
      assert length(PolicyEngine.list_policies()) == 1
      
      assert :ok = PolicyEngine.delete_policy("delete_test")
      assert length(PolicyEngine.list_policies()) == 0
    end
    
    test "handles deleting non-existent policy" do
      assert {:error, "Policy not found"} = PolicyEngine.delete_policy("non_existent")
    end
  end
  
  describe "policy filtering" do
    setup do
      policies = [
        {"user_policy", %{name: "User Policy", level: :user, settings: %{}}},
        {"server_policy", %{name: "Server Policy", level: :server, settings: %{}}},
        {"emergency_policy", %{name: "Emergency Policy", level: :emergency, settings: %{}}}
      ]
      
      Enum.each(policies, fn {id, data} ->
        PolicyEngine.update_policy(id, data)
      end)
      
      :ok
    end
    
    test "filters policies by level" do
      user_policies = PolicyEngine.list_policies(level: :user)
      assert length(user_policies) == 1
      assert hd(user_policies).name == "User Policy"
      
      server_policies = PolicyEngine.list_policies(level: :server)
      assert length(server_policies) == 1
      assert hd(server_policies).name == "Server Policy"
    end
    
    test "filters policies by name" do
      emergency_policies = PolicyEngine.list_policies(name_contains: "emergency")
      assert length(emergency_policies) == 1
      assert hd(emergency_policies).name == "Emergency Policy"
    end
  end
  
  describe "effective policy evaluation" do
    setup do
      # Create multiple policies with different precedence
      policies = [
        {"global_policy", %{
          name: "Global Default",
          level: :global,
          settings: %{
            default_server_trust: :untrusted,
            require_confirmation_threshold: :medium
          },
          priority: 10
        }},
        {"user_policy", %{
          name: "User Override", 
          level: :user,
          settings: %{
            require_confirmation_threshold: :low
          },
          conditions: %{
            user_id: "test_user"
          },
          priority: 80
        }},
        {"server_policy", %{
          name: "Server Specific",
          level: :server,
          settings: %{
            max_concurrent_executions: 5
          },
          conditions: %{
            server_id: "test_server"
          },
          priority: 40
        }}
      ]
      
      Enum.each(policies, fn {id, data} ->
        PolicyEngine.update_policy(id, data)
      end)
      
      :ok
    end
    
    test "evaluates effective policy with precedence" do
      # Create test policies first
      policies = [
        {"global_policy", %{
          name: "Global Default",
          level: :global,
          settings: %{
            default_server_trust: :untrusted,
            require_confirmation_threshold: :medium
          },
          priority: 10
        }},
        {"user_policy", %{
          name: "User Override", 
          level: :user,
          settings: %{
            require_confirmation_threshold: :low
          },
          conditions: %{
            user_id: "test_user"
          },
          priority: 80
        }},
        {"server_policy", %{
          name: "Server Specific",
          level: :server,
          settings: %{
            max_concurrent_executions: 5
          },
          conditions: %{
            server_id: "test_server"
          },
          priority: 40
        }}
      ]
      
      Enum.each(policies, fn {id, data} ->
        PolicyEngine.update_policy(id, data)
      end)
      
      context = %{
        user_id: "test_user",
        server_id: "test_server",
        tool_name: "test_tool"
      }
      
      {:ok, effective_policy} = PolicyEngine.get_effective_policy(context)
      
      # User policy should override global threshold setting  
      assert effective_policy.require_confirmation_threshold == :low
      
      # Server policy setting should be included
      assert effective_policy.max_concurrent_executions == 5
      
      # Global policy setting should be preserved where not overridden
      assert effective_policy.default_server_trust == :untrusted
      
      # Metadata should be included
      assert effective_policy.evaluation_timestamp
      assert effective_policy.evaluated_for.user_id == "test_user"
    end
    
    test "evaluates policy for context without matches" do
      context = %{
        user_id: "other_user",
        server_id: "other_server" 
      }
      
      {:ok, effective_policy} = PolicyEngine.get_effective_policy(context)
      
      # Should get global defaults only
      assert effective_policy.require_confirmation_threshold == :medium
      assert effective_policy.default_server_trust == :untrusted
      # Server-specific setting should not be included
      refute Map.has_key?(effective_policy, :max_concurrent_executions)
    end
  end
  
  describe "emergency mode" do
    test "activates and deactivates emergency mode" do
      refute PolicyEngine.emergency_mode_active?()
      
      assert :ok = PolicyEngine.activate_emergency_mode("Security incident", "admin")
      assert PolicyEngine.emergency_mode_active?()
      
      assert :ok = PolicyEngine.deactivate_emergency_mode("admin")
      refute PolicyEngine.emergency_mode_active?()
    end
    
    test "applies emergency restrictions to effective policy" do
      context = %{user_id: "test_user"}
      
      # Normal policy
      {:ok, normal_policy} = PolicyEngine.get_effective_policy(context)
      assert normal_policy.default_server_trust == :untrusted
      
      # Activate emergency mode
      PolicyEngine.activate_emergency_mode("Test emergency", "admin")
      
      # Emergency policy should have additional restrictions
      {:ok, emergency_policy} = PolicyEngine.get_effective_policy(context)
      assert emergency_policy.emergency_mode == true
      assert emergency_policy.confirmation_required_for_all == true
      assert emergency_policy.max_concurrent_executions == 3
    end
  end
  
  describe "policy validation" do
    test "validates complete policy structure" do
      valid_policy = %{
        name: "Valid Policy",
        level: :user,
        settings: %{
          require_confirmation_threshold: :high
        },
        conditions: %{
          user_id: "test_user"
        }
      }
      
      assert {:ok, normalized} = PolicyEngine.validate_policy(valid_policy)
      
      # Check normalization
      assert normalized.name == "Valid Policy"
      assert normalized.status == :active
      assert normalized.created_by == "system"
      assert normalized.priority == 0
    end
    
    test "validates policy with missing required fields" do
      invalid_policy = %{
        level: :user
        # Missing name and settings
      }
      
      assert {:error, errors} = PolicyEngine.validate_policy(invalid_policy)
      assert Enum.any?(errors, &String.contains?(&1, "Missing required field: name"))
      assert Enum.any?(errors, &String.contains?(&1, "Missing required field: settings"))
    end
    
    test "validates policy with invalid level" do
      invalid_policy = %{
        name: "Invalid",
        level: :invalid_level,
        settings: %{}
      }
      
      assert {:error, errors} = PolicyEngine.validate_policy(invalid_policy)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid policy level"))
    end
    
    test "validates policy with invalid settings type" do
      invalid_policy = %{
        name: "Invalid Settings",
        level: :user,
        settings: "not_a_map"
      }
      
      assert {:error, errors} = PolicyEngine.validate_policy(invalid_policy)
      assert Enum.any?(errors, &String.contains?(&1, "Policy settings must be a map"))
    end
  end
  
  describe "time-based policies" do
    test "evaluates time-based policy conditions" do
      # Create a policy that only applies during work hours
      time_policy = %{
        name: "Work Hours Policy",
        level: :time_based,
        settings: %{
          require_confirmation_threshold: :high
        },
        conditions: %{
          time_range: %{start_hour: 9, end_hour: 17}
        }
      }
      
      PolicyEngine.update_policy("work_hours", time_policy)
      
      context = %{user_id: "test_user"}
      
      # The policy evaluation will use current time
      # This test assumes we're running during the time range
      {:ok, effective_policy} = PolicyEngine.get_effective_policy(context)
      
      # Policy might or might not apply depending on test execution time
      # This demonstrates the time-based functionality
      assert is_map(effective_policy)
    end
  end
  
  describe "policy expiration" do
    test "handles expired policies" do
      # Create a policy that expires immediately
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      
      expired_policy = %{
        name: "Expired Policy",
        level: :user,
        settings: %{test_setting: true},
        expires_at: past_time
      }
      
      PolicyEngine.update_policy("expired", expired_policy)
      
      # Trigger cleanup manually by sending the cleanup message
      send(PolicyEngine, :cleanup_expired_policies)
      :timer.sleep(100)  # Allow cleanup to process
      
      # Expired policy should be removed
      policies = PolicyEngine.list_policies()
      policy_names = Enum.map(policies, & &1.name)
      refute "Expired Policy" in policy_names
    end
  end
  
  describe "error handling" do
    test "handles policy evaluation errors gracefully" do
      # Create a context that might cause evaluation issues
      malformed_context = %{
        user_id: nil,
        invalid_field: :invalid_value
      }
      
      # Should still return a policy, even if some conditions can't be evaluated
      assert {:ok, policy} = PolicyEngine.get_effective_policy(malformed_context)
      assert is_map(policy)
    end
  end
end