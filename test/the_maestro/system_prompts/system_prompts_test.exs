defmodule TheMaestro.SystemPromptsTest do
  use TheMaestro.DataCase

  alias TheMaestro.{Repo, SystemPrompts}
  alias TheMaestro.SuppliedContext.SuppliedContextItem

  import Ecto.Query
  import TheMaestro.SuppliedContextFixtures
  import TheMaestro.ConversationsFixtures, only: [session_fixture: 0]

  describe "versioning" do
    test "create_version adds new revision and can mark default" do
      base =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          render_format: :text,
          version: 1,
          text: "v1",
          is_default: true,
          editor: "original"
        })

      {:ok, v2} =
        SystemPrompts.create_version(base, %{
          text: "v2",
          editor: "alice",
          change_note: "refresh",
          is_default: true
        })

      assert v2.family_id == base.family_id
      assert v2.version == 2
      assert v2.text == "v2"
      assert v2.editor == "alice"
      assert v2.is_default

      reloaded_base = Repo.get!(SuppliedContextItem, base.id)
      refute reloaded_base.is_default

      assert Enum.map(SystemPrompts.list_versions(base), & &1.version) == [2, 1]
    end

    test "fork_version creates new family starting at version 1" do
      base =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :anthropic,
          render_format: :anthropic_blocks,
          version: 3,
          text: "anthropic v3"
        })

      {:ok, forked} =
        SystemPrompts.fork_version(base, %{
          name: base.name <> " fork",
          editor: "bob"
        })

      refute forked.family_id == base.family_id
      assert forked.version == 1
      assert forked.editor == "bob"
      assert forked.is_default
    end

    test "delete_version prevents removing default but deletes non-default" do
      base =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :gemini,
          render_format: :gemini_parts,
          version: 1,
          is_default: true
        })

      {:ok, v2} = SystemPrompts.create_version(base, %{version: 2, is_default: false})

      assert {:error, :cannot_delete_default} = SystemPrompts.delete_version(base)

      :ok = SystemPrompts.delete_version(Repo.get!(SuppliedContextItem, v2.id))

      assert Enum.map(SystemPrompts.list_versions(base.family_id), & &1.version) == [1]
    end

    test "set_default_version swaps the default flag" do
      base =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          render_format: :text,
          version: 1,
          is_default: true
        })

      {:ok, v2} = SystemPrompts.create_version(base, %{version: 2, is_default: false})

      :ok = SystemPrompts.set_default_version(v2)

      assert Repo.get!(SuppliedContextItem, v2.id).is_default
      refute Repo.get!(SuppliedContextItem, base.id).is_default
    end
  end

  describe "render_for_provider/2 openai" do
    test "returns segment list preserving metadata order" do
      prompt_a =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          render_format: :text,
          version: 1,
          metadata: %{"segments" => ["alpha", %{"type" => "text", "text" => "beta"}]},
          text: "ignored"
        })

      prompt_b =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          render_format: :text,
          version: 1,
          text: "gamma"
        })

      stack = %{
        source: :default,
        prompts: [
          %{prompt: prompt_a, overrides: %{}, session_prompt_item: nil},
          %{prompt: prompt_b, overrides: %{}, session_prompt_item: nil}
        ]
      }

      segments = SystemPrompts.render_for_provider(:openai, stack)

      assert segments == [
               %{"type" => "text", "text" => "alpha"},
               %{"type" => "text", "text" => "beta"},
               %{"type" => "text", "text" => "gamma"}
             ]
    end

    test "applies override segments when provided" do
      prompt =
        supplied_context_item_fixture(%{
          type: :system_prompt,
          provider: :openai,
          render_format: :text,
          version: 1,
          text: "base"
        })

      stack = %{
        source: :session,
        prompts: [
          %{
            prompt: prompt,
            overrides: %{"segments" => [%{"type" => "text", "text" => "override"}]},
            session_prompt_item: nil
          }
        ]
      }

      assert SystemPrompts.render_for_provider(:openai, stack) == [
               %{"type" => "text", "text" => "override"}
             ]
    end
  end

  test "render_for_provider/2 anthropic respects overrides" do
    prompt =
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: :anthropic,
        render_format: :anthropic_blocks,
        version: 1,
        metadata: %{"blocks" => [%{"type" => "text", "text" => "default"}]}
      })

    stack = %{
      source: :default,
      prompts: [
        %{
          prompt: prompt,
          overrides: %{"blocks" => [%{"type" => "text", "text" => "override"}]},
          session_prompt_item: nil
        }
      ]
    }

    assert SystemPrompts.render_for_provider(:anthropic, stack) == [
             %{"type" => "text", "text" => "override"}
           ]
  end

  test "render_for_provider/2 gemini merges metadata and overrides" do
    prompt =
      supplied_context_item_fixture(%{
        type: :system_prompt,
        provider: :gemini,
        render_format: :gemini_parts,
        version: 1,
        metadata: %{"parts" => [%{"text" => "default"}]}
      })

    stack = %{
      source: :default,
      prompts: [
        %{
          prompt: prompt,
          overrides: %{"parts" => [%{"text" => "override"}]},
          session_prompt_item: nil
        }
      ]
    }

    assert SystemPrompts.render_for_provider(:gemini, stack) == %{
             "role" => "user",
             "parts" => [%{"text" => "override"}]
           }
  end

  describe "resolve_for_session telemetry" do
    setup do
      handler_id =
        "system-prompts-telemetry-" <> Integer.to_string(:erlang.unique_integer([:positive]))

      :ok =
        :telemetry.attach(
          handler_id,
          [:system_prompts, :resolved],
          fn event, measurements, metadata, pid ->
            send(pid, {:telemetry_event, event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      %{handler_id: handler_id}
    end

    test "emits telemetry with prompt counts and metadata for session prompts" do
      session = session_fixture()

      {:ok, result} = SystemPrompts.resolve_for_session(session, :openai)

      assert_receive {
        :telemetry_event,
        [:system_prompts, :resolved],
        %{prompt_count: count, overrides_count: overrides_count} = measurements,
        %{provider: :openai, session_id: session_id} = metadata
      }

      assert count == length(result.prompts)
      assert overrides_count == Enum.count(result.prompts, &(map_size(&1.overrides) > 0))
      assert session_id == session.id
      assert metadata.source == result.source
      assert is_integer(measurements.duration)
      assert measurements.missing_defaults == 0
    end

    test "missing defaults increments counter" do
      Repo.delete_all(
        from i in SuppliedContextItem, where: i.type == :system_prompt and i.provider == :gemini
      )

      {:ok, result} = SystemPrompts.resolve_for_session(Ecto.UUID.generate(), :gemini)

      assert result.prompts == []

      assert_receive {
        :telemetry_event,
        [:system_prompts, :resolved],
        %{missing_defaults: 1},
        %{provider: :gemini, source: :default}
      }
    end
  end
end
