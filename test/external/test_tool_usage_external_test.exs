defmodule TheMaestro.External.ToolUsageExternalTest do
  require Logger
  use ExUnit.Case, async: false

  @moduletag :external

  alias TheMaestro.AgentLoop

  # No sandbox here: set USE_REAL_DB=1 to bypass Ecto sandbox entirely

  test "OpenAI OAuth via ChatGPTAgent clone: shell tool turn end-to-end" do
    if System.get_env("USE_REAL_DB") != "1" do
      IO.puts("\n⏭️  Skipping external DB test — set USE_REAL_DB=1 to run")
      assert true
    else
      # Find Agent row named ChatGPTAgent and load its SavedAuthentication
      import Ecto.Query
      alias TheMaestro.{Agents.Agent, Repo, SavedAuthentication}

      agent = Repo.one(from a in Agent, where: a.name == ^"ChatGPTAgent")

      # If ChatGPTAgent doesn't have an auth_id, try to find and link an OpenAI OAuth saved authentication
      base_sa =
        if agent && is_nil(agent.auth_id) do
          # Find any OpenAI OAuth saved authentication
          openai_sa =
            Repo.one(
              from sa in SavedAuthentication,
                where: sa.provider == ^:openai and sa.auth_type == ^:oauth,
                order_by: [desc: sa.id],
                limit: 1
            )

          if openai_sa do
            IO.puts(
              "\n🔧 Linking ChatGPTAgent to OpenAI OAuth authentication (id: #{openai_sa.id})"
            )

            {:ok, updated_agent} = TheMaestro.Agents.update_agent(agent, %{auth_id: openai_sa.id})
            openai_sa
          else
            nil
          end
        else
          # Load the saved authentication if agent already has auth_id
          agent && Repo.preload(agent, :saved_authentication).saved_authentication
        end

      if is_nil(base_sa) do
        IO.puts("\n⏭️  Skipping: Agent 'ChatGPTAgent' or its OAuth auth not found in DB")
        :ok
      else
        # Keep session name short (<= 50 chars)
        short = String.slice(Ecto.UUID.generate(), 0, 8)
        new_session = "e2e_" <> short
        # Clone base SA into a new SavedAuthentication session name
        {:ok, cloned} =
          SavedAuthentication.create_named_session(:openai, :oauth, new_session, %{
            credentials: base_sa.credentials,
            expires_at: base_sa.expires_at
          })

        # Reload agent to get current auth_id and tools
        agent = Repo.get!(Agent, agent.id)
        original_auth_id = agent.auth_id
        original_tools = agent.tools

        try do
          # Temporarily attach the cloned auth to ChatGPTAgent for this run
          case TheMaestro.Agents.update_agent(agent, %{auth_id: cloned.id}) do
            {:ok, _} -> :ok
            {:error, cs} -> raise "failed to attach cloned auth to agent: #{inspect(cs.errors)}"
          end

          model = "gpt-5"

          # First, update the agent to include shell tool
          IO.puts("\n🔧 Updating ChatGPTAgent to include shell tool...")

          updated_tools =
            Map.put(agent.tools, "enabled_tools", [
              "list_directory",
              "read_file",
              "google_web_search",
              "shell"
            ])

          {:ok, _} = TheMaestro.Agents.update_agent(agent, %{tools: updated_tools})

          messages = [
            %{
              "role" => "user",
              "content" =>
                "Use the shell tool to run ['bash','-lc','echo external-ok'] and then answer 'done'."
            }
          ]

          case AgentLoop.run_turn(:openai, new_session, model, messages) do
            {:ok, res} ->
              IO.puts("\n📊 Response from agent:")
              IO.puts("   Final text: #{inspect(res.final_text)}")
              IO.puts("   Tools used: #{inspect(res.tools)}")
              IO.puts("   Usage: #{inspect(res.usage)}")

              # Check if shell tool was used
              if not Enum.any?(res.tools || [], &(&1["name"] == "shell")) do
                IO.puts("\n⚠️  WARNING: Shell tool was not used as expected")
                IO.puts("   Response might have used a different approach")
              end

              assert Enum.any?(res.tools || [], &(&1["name"] == "shell")),
                     "Expected shell tool to be used"

              assert String.downcase(res.final_text || "") =~ "done",
                     "Expected 'done' in response"

            other ->
              flunk("unexpected: #{inspect(other)}")
          end
        after
          # Restore original agent auth, tools and delete the cloned session
          _ =
            if agent && agent.id,
              do:
                TheMaestro.Agents.update_agent(agent, %{
                  auth_id: original_auth_id,
                  tools: original_tools
                }),
              else: {:ok, agent}

          :ok = TheMaestro.SavedAuthentication.delete_named_session(:openai, :oauth, new_session)
        end
      end
    end
  end
end
