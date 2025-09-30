defmodule TheMaestroWeb.Api.SessionsController do
  use TheMaestroWeb, :controller
  alias TheMaestro.Chat
  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestro.SystemPrompts
  alias TheMaestro.Tools.Inventory

  def index(conn, params) do
    case Map.get(params, "tool_runtime") do
      runtime when runtime in ["local", "remote"] ->
        list =
          Conversations.list_sessions_by_tool_runtime(runtime)
          |> Enum.sort_by(
            fn s ->
              s.last_used_at || s.updated_at || s.inserted_at || ~U[1970-01-01 00:00:00Z]
            end,
            {:desc, DateTime}
          )
          |> Enum.map(fn s ->
            %{
              id: to_string(s.id),
              name: s.name,
              working_dir: s.working_dir,
              last_used_at: s.last_used_at,
              updated_at: s.updated_at,
              inserted_at: s.inserted_at
            }
          end)

        json(conn, %{sessions: list})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "tool_runtime parameter required"})
    end
  end

  def show(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)
    session = Conversations.preload_session_mcp(session)

    prov = Chat.provider_for_session(session)
    {auth_type, auth_name} = Chat.auth_meta_for_session(session)

    prompts_by_provider =
      [:openai, :anthropic, :gemini]
      |> Enum.reduce(%{}, fn provider, acc ->
        list =
          SystemPrompts.list_session_prompts(session, provider)
          |> Enum.map(fn spi ->
            %{
              id: spi.supplied_context_item_id,
              enabled: !!spi.enabled,
              overrides: spi.overrides || %{}
            }
          end)

        if list == [], do: acc, else: Map.put(acc, Atom.to_string(provider), list)
      end)

    mcp_server_ids = Enum.map(MCP.list_session_servers(session), & &1.mcp_server_id)

    json(conn, %{
      id: to_string(session.id),
      name: session.name,
      working_dir: session.working_dir,
      tool_runtime: session.tool_runtime,
      provider: Atom.to_string(prov),
      auth: %{type: auth_type, name: auth_name},
      model_id: session.model_id,
      persona: session.persona || %{},
      memory: session.memory || %{},
      tools: session.tools || %{},
      mcp_server_ids: mcp_server_ids,
      system_prompt_ids_by_provider: prompts_by_provider
    })
  end

  def create(conn, params) do
    attrs =
      %{
        "auth_id" => params["auth_id"],
        "model_id" => params["model_id"] || params["model"],
        "working_dir" => params["working_dir"],
        "tool_runtime" => params["tool_runtime"] || "remote",
        "persona" => params["persona"] || %{},
        "memory" => params["memory"] || %{},
        "tools" => params["tools"] || %{},
        "mcps" => params["mcps"] || %{}
      }
      |> maybe_put(params, "mcp_server_ids")
      |> maybe_put(params, "system_prompt_ids_by_provider")

    case Conversations.create_session(attrs) do
      {:ok, session} ->
        json(conn, %{session_id: to_string(session.id)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    session = Conversations.get_session!(id)
    attrs = build_update_attrs(params)

    case Conversations.update_session(session, attrs) do
      {:ok, updated} ->
        _ = MCP.Registry.bump_revision(updated.id)
        apply_behavior = Map.get(params, "apply", "now")
        respond_after_apply(conn, updated, apply_behavior)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def delete(conn, %{"id" => id}) do
    session = Conversations.get_session!(id)

    case Conversations.delete_session(session) do
      {:ok, _session} ->
        conn
        |> put_status(:no_content)
        |> json(%{})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def inventory(conn, %{"id" => id}) do
    _ = Conversations.get_session!(id)

    json(conn, %{
      openai: Inventory.list_for_provider(id, :openai),
      anthropic: Inventory.list_for_provider(id, :anthropic),
      gemini: Inventory.list_for_provider(id, :gemini)
    })
  end

  def prompts(conn, %{"id" => id}) do
    _ = Conversations.get_session!(id)

    providers = [:openai, :anthropic, :gemini]

    by_provider =
      Enum.reduce(providers, %{}, fn provider, acc ->
        list =
          SystemPrompts.list_session_prompts(id, provider)
          |> Enum.map(fn spi ->
            %{
              id: spi.supplied_context_item_id,
              enabled: !!spi.enabled,
              overrides: spi.overrides || %{}
            }
          end)

        Map.put(acc, Atom.to_string(provider), list)
      end)

    json(conn, %{builder: by_provider})
  end

  defp maybe_put(map, params, key) do
    if Map.has_key?(params, key), do: Map.put(map, key, Map.get(params, key)), else: map
  end

  defp build_update_attrs(params) do
    %{}
    |> maybe_put(params, "auth_id")
    |> maybe_put(params, "model_id")
    |> maybe_put(params, "working_dir")
    |> maybe_put(params, "persona")
    |> maybe_put(params, "memory")
    |> maybe_put(params, "tools")
    |> maybe_put(params, "mcps")
    |> maybe_put(params, "mcp_server_ids")
    |> maybe_put(params, "system_prompt_ids_by_provider")
  end

  defp respond_after_apply(conn, updated, "now") do
    _ = Chat.cancel_turn(updated.id)
    prov = Chat.provider_for_session(updated)
    {_, session_name} = Chat.auth_meta_for_session(updated)

    canon =
      case Conversations.latest_snapshot(updated.id) do
        %Conversations.ChatEntry{} = entry -> Map.get(entry, :combined_chat) || %{"messages" => []}
        _ -> %{"messages" => []}
      end

    {:ok, provider_msgs} = Conversations.Translator.to_provider(canon, prov)
    model = Chat.resolve_model_for_session(updated, prov)

    opts =
      if Code.ensure_loaded?(TheMaestro.TestStreamingAdapter) and Mix.env() == :test do
        [streaming_adapter: TheMaestro.TestStreamingAdapter]
      else
        []
      end

    {:ok, stream_id} = Chat.start_stream(updated.id, prov, session_name, provider_msgs, model, opts)

    json(conn, %{
      session_id: to_string(updated.id),
      auth_id: updated.auth_id,
      model_id: updated.model_id,
      apply: "now",
      provider: Atom.to_string(prov),
      stream_id: stream_id,
      thread_id: Conversations.latest_thread_id(updated.id)
    })
  end

  defp respond_after_apply(conn, updated, _defer) do
    json(conn, %{
      session_id: to_string(updated.id),
      auth_id: updated.auth_id,
      model_id: updated.model_id,
      apply: "defer"
    })
  end
end
