defmodule TheMaestroWeb.SessionControllerPromptIntegrationTest do
  use TheMaestroWeb.ConnCase, async: true

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.SuppliedContext
  alias TheMaestro.SystemPrompts
  alias TheMaestro.SystemPrompts.Defaults

  setup do
    SystemPrompts.Seeder.seed!(now: DateTime.utc_now())
    :ok
  end

  test "creating a session via controller stores provider prompt stacks", %{conn: conn} do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "controller-prompt-test",
        credentials: %{"api_key" => "sk-controller"},
        expires_at: DateTime.utc_now()
      })

    openai_default =
      SuppliedContext.get_default_prompt!(:openai, "openai.codex_cli.base", include_shared: false)

    anthropic_identity =
      SuppliedContext.get_default_prompt!(
        :anthropic,
        "anthropic.claude_code.identity",
        include_shared: false
      )

    anthropic_guidance =
      SuppliedContext.get_default_prompt!(
        :anthropic,
        "anthropic.claude_code.guidance",
        include_shared: false
      )

    gemini_default =
      SuppliedContext.get_default_prompt!(:gemini, "gemini.code_assist.base",
        include_shared: false
      )

    params = %{
      "name" => "ConnCase prompt session",
      "auth_id" => saved_auth.id,
      "system_prompt_ids_by_provider" => %{
        "openai" => [%{"id" => openai_default.id}],
        "anthropic" => [
          %{"id" => anthropic_identity.id},
          %{"id" => anthropic_guidance.id, "enabled" => false}
        ],
        "gemini" => [%{"id" => gemini_default.id}]
      }
    }

    conn = post(conn, ~p"/the_maestro_web/sessions", %{"session" => params})
    assert redirected_to(conn) =~ "/the_maestro_web/sessions/"

    session_id =
      redirected_to(conn)
      |> String.split("/")
      |> List.last()

    session = Conversations.get_session!(session_id)

    {:ok, openai_stack} = SystemPrompts.resolve_for_session(session, :openai)
    assert SystemPrompts.render_for_provider(:openai, openai_stack) == Defaults.openai_segments()

    {:ok, anthropic_stack} = SystemPrompts.resolve_for_session(session, :anthropic)

    assert SystemPrompts.render_for_provider(:anthropic, anthropic_stack) ==
             Defaults.anthropic_default_blocks() |> Enum.take(1)

    {:ok, gemini_stack} = SystemPrompts.resolve_for_session(session, :gemini)

    assert SystemPrompts.render_for_provider(:gemini, gemini_stack) ==
             Defaults.gemini_system_instruction()
  end
end
