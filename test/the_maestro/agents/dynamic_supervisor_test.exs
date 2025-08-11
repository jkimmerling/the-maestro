defmodule TheMaestro.Agents.DynamicSupervisorTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.Agents.DynamicSupervisor, as: AgentSupervisor
  
  describe "start_agent/2" do
    test "starts agent under supervision" do
      agent_id = "supervised_agent_#{System.unique_integer()}"
      
      assert {:ok, pid} = AgentSupervisor.start_agent(agent_id)
      assert is_pid(pid)
      
      # Verify it's supervised by checking the supervisor's children
      children = DynamicSupervisor.which_children(AgentSupervisor)
      assert length(children) >= 1
      
      child_pids = Enum.map(children, fn {_, pid, _, _} -> pid end)
      assert pid in child_pids
    end
    
    test "prevents starting duplicate agents" do
      agent_id = "duplicate_supervised_agent_#{System.unique_integer()}"
      
      assert {:ok, _pid1} = AgentSupervisor.start_agent(agent_id)
      assert {:error, {:already_started, _pid2}} = AgentSupervisor.start_agent(agent_id)
    end
  end
  
  describe "terminate_agent/1" do
    test "terminates agent process" do
      agent_id = "termination_agent_#{System.unique_integer()}"
      {:ok, pid} = AgentSupervisor.start_agent(agent_id)
      
      assert Process.alive?(pid)
      assert :ok = AgentSupervisor.terminate_agent(pid)
      
      # Give it a moment to terminate
      :timer.sleep(10)
      refute Process.alive?(pid)
    end
  end
  
  describe "supervision strategy" do
    test "supervisor can manage agent lifecycle" do
      agent_id = "lifecycle_agent_#{System.unique_integer()}"
      
      # Can start an agent
      {:ok, pid} = AgentSupervisor.start_agent(agent_id)
      assert Process.alive?(pid)
      
      # Agent is supervised
      children = DynamicSupervisor.which_children(AgentSupervisor)
      child_pids = Enum.map(children, fn {_, child_pid, _, _} -> child_pid end)
      assert pid in child_pids
      
      # Can terminate the agent
      :ok = AgentSupervisor.terminate_agent(pid)
      :timer.sleep(10)
      refute Process.alive?(pid)
      
      # Can start a new agent with different ID
      new_agent_id = "lifecycle_agent_new_#{System.unique_integer()}"
      {:ok, new_pid} = AgentSupervisor.start_agent(new_agent_id)
      assert Process.alive?(new_pid)
      assert new_pid != pid
    end
  end
end