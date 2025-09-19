defmodule TheMaestroWeb.DashboardLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestro.Provider
  alias TheMaestro.SuppliedContext
  alias TheMaestro.SystemPrompts
  alias TheMaestro.Tools.Inventory
  alias TheMaestroWeb.MCPServersLive.FormComponent

  @prompt_providers [:openai, :anthropic, :gemini]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TheMaestroWeb.Endpoint.subscribe("oauth:events")

    socket =
      socket
      |> assign(:auths, Auth.list_saved_authentications())
      |> assign(:sessions, Conversations.list_sessions_with_auth())
      |> assign(:show_session_modal, false)
      |> assign(:auth_options, build_auth_options())
      |> assign(:persona_options, build_persona_options())
      |> assign(:session_form, to_form(Conversations.change_session(%Conversations.Session{})))
      |> assign(:session_provider, "openai")
      |> assign(:session_auth_options, build_auth_options_for(:openai))
      |> assign(:session_model_options, [])
      |> assign(:show_session_dir_picker, false)
      |> assign(:mcp_server_options, MCP.server_options())
      |> assign(:session_mcp_selected_ids, [])
      |> assign(:tool_picker_allowed_map, %{})
      |> assign(:tool_inventory_by_provider, build_tool_inventory_for_servers([]))
      |> assign(:mcp_warming, false)
      |> assign(:show_mcp_modal, false)
      |> assign(:session_form_params, %{})
      |> assign(:prompt_picker_provider, :openai)
      |> assign(:prompt_picker_providers, @prompt_providers)
      |> assign(:session_prompt_builder, empty_builder())
      |> assign(:prompt_library, %{})
      |> assign(:prompt_catalog, %{})
      |> assign(:prompt_picker_selection, %{})
      |> assign(:page_title, "Dashboard")
      |> assign(:active_streams, %{})
      |> assign(:show_delete_session_modal, false)
      |> assign(:delete_session_id, nil)

    # When connected, subscribe to all session topics to track active streams
    socket =
      if connected?(socket) do
        Enum.each(socket.assigns.sessions, fn s -> TheMaestro.Chat.subscribe(s.id) end)
        socket
      else
        socket
      end

    socket = refresh_prompt_state(socket)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    sessions = Conversations.list_sessions_with_auth()

    if connected?(socket) do
      Enum.each(sessions, fn s -> TheMaestro.Chat.subscribe(s.id) end)
    end

    {:noreply,
     socket
     |> assign(:auths, Auth.list_saved_authentications())
     |> assign(:sessions, sessions)
     |> assign(:auth_options, build_auth_options())
     |> assign(:persona_options, build_persona_options())
     |> refresh_prompt_state()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case id do
      id when is_binary(id) ->
        sa = Auth.get_saved_authentication!(id)
        # Delete via Auth context (accepts atom or string provider) so UI doesn't depend
        # on Provider.validate_provider/1's atom-only contract.
        case Auth.delete_named_session(sa.provider, sa.auth_type, sa.name) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Auth deleted; refresh jobs canceled if any.")
             |> assign(:auths, Auth.list_saved_authentications())
             |> assign(:auth_options, build_auth_options())}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Auth not found; nothing deleted.")
             |> assign(:auths, Auth.list_saved_authentications())
             |> assign(:auth_options, build_auth_options())}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Delete failed: #{inspect(reason)}")
             |> assign(:auths, Auth.list_saved_authentications())
             |> assign(:auth_options, build_auth_options())}
        end

      :error ->
        {:noreply, socket}
    end
  end

  # Begin delete flow with confirmation modal
  def handle_event("delete_session", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_session_modal, true)
     |> assign(:delete_session_id, id)}
  end

  def handle_event("cancel_delete_session", _params, socket) do
    {:noreply,
     socket |> assign(:show_delete_session_modal, false) |> assign(:delete_session_id, nil)}
  end

  # Delete the session only; preserve chat history (session_id will be nilified by FK)
  def handle_event("confirm_delete_session_only", _params, socket) do
    id = socket.assigns.delete_session_id
    session = Conversations.get_session!(id)
    _ = Conversations.delete_session_only(session)

    {:noreply,
     socket
     |> put_flash(:info, "Session deleted; chat history preserved.")
     |> assign(:show_delete_session_modal, false)
     |> assign(:delete_session_id, nil)
     |> assign(:sessions, Conversations.list_sessions_with_auth())}
  end

  # Delete the session and its associated chat history rows
  def handle_event("confirm_delete_session_and_chat", _params, socket) do
    id = socket.assigns.delete_session_id
    session = Conversations.get_session!(id)
    _ = Conversations.delete_session_and_chat(session)

    {:noreply,
     socket
     |> put_flash(:info, "Session and chat history deleted.")
     |> assign(:show_delete_session_modal, false)
     |> assign(:delete_session_id, nil)
     |> assign(:sessions, Conversations.list_sessions_with_auth())}
  end

  def handle_event("open_session_modal", _params, socket) do
    cs = Conversations.change_session(%Conversations.Session{})
    builder = build_default_prompt_builder()

    socket =
      socket
      |> refresh_prompt_state()
      |> assign(:session_prompt_builder, builder)
      |> merge_builder_into_catalog(builder)
      |> assign(:prompt_picker_provider, :openai)
      |> assign(:prompt_picker_selection, %{})

    {:noreply,
     socket
     |> assign(:session_provider, "openai")
     |> assign(:session_auth_options, build_auth_options_for(:openai))
     |> assign(:session_model_options, [])
     |> assign(:auth_options, build_auth_options())
     |> assign(:orphan_threads, orphan_thread_options())
     |> assign(:session_form, to_form(cs))
     |> assign(:mcp_server_options, MCP.server_options())
     |> assign(:session_mcp_selected_ids, [])
     |> assign(:ui_sections, %{prompt: true, persona: true, memory: true})
     |> assign(:session_form_params, %{})
     |> assign(:show_mcp_modal, false)
     |> assign(:show_session_modal, true)}
  end

  def handle_event("cancel_session_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_session_modal, false)
     |> assign(:show_session_dir_picker, false)
     |> assign(:show_mcp_modal, false)}
  end

  # Target-aware validate to avoid clobbering model list when provider also present
  def handle_event(
        "session_validate",
        %{"_target" => ["session", target], "session" => params},
        socket
      ) do
    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    socket =
      socket
      |> assign(:session_form, to_form(cs, action: :validate))
      |> assign(:session_form_params, params)
      |> assign(:session_mcp_selected_ids, selected)

    case target do
      "provider" ->
        provider = to_provider_atom(params["provider"]) || :openai

        {:noreply,
         socket
         |> assign(:session_provider, params["provider"])
         |> assign(:session_auth_options, build_auth_options_for(provider))
         |> assign(:session_model_options, [])
         |> assign(:prompt_picker_provider, provider)
         |> ensure_prompt_builder()}

      "auth_id" ->
        models = build_model_options(%{"auth_id" => params["auth_id"]})
        {:noreply, assign(socket, :session_model_options, models)}

      "mcp_server_ids" ->
        _ =
          Task.start(fn ->
            warm_mcp_tools_cache(selected)
            send(self(), :refresh_mcp_inventory)
          end)

        {:noreply, assign(socket, :mcp_warming, true)}

      _ ->
        {:noreply, socket}
    end
  end

  # Fallback validate (no _target); preserve previous behavior
  def handle_event("session_validate", %{"session" => params}, socket) do
    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    {:noreply,
     socket
     |> assign(:session_form, to_form(cs, action: :validate))
     |> assign(:session_form_params, params)
     |> assign(:session_mcp_selected_ids, selected)
     |> ensure_prompt_builder()}
  end

  def handle_event("open_session_dir_picker", _params, socket) do
    {:noreply, assign(socket, :show_session_dir_picker, true)}
  end

  def handle_event("open_mcp_modal", _params, socket) do
    {:noreply, assign(socket, :show_mcp_modal, true)}
  end

  def handle_event("close_mcp_modal", _params, socket) do
    {:noreply, assign(socket, :show_mcp_modal, false)}
  end

  # All dynamic UI events handled inside SessionFormComponent to keep LiveView dry.

  def handle_event("session_use_root_dir", _params, socket) do
    wd = File.cwd!() |> Path.expand()

    params = merge_session_params(socket, %{"working_dir" => wd})
    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:session_form, to_form(cs, action: :validate))
     |> assign(:session_form_params, params)
     |> assign(:session_mcp_selected_ids, selected)
     |> assign(:tool_inventory_by_provider, build_tool_inventory_for_servers(selected))}

    _ =
      Task.start(fn ->
        warm_mcp_tools_cache(selected)
        send(self(), :refresh_mcp_inventory)
      end)

    {:noreply, assign(socket, :mcp_warming, true)}
  end

  def handle_event("session_save", %{"session" => params}, socket) do
    socket = ensure_prompt_builder(socket)

    with {:ok, params2} <- build_session_params(socket, params),
         {:ok, session} <- Conversations.create_session(params2) do
      case Map.get(params, "attach_thread_id") do
        tid when is_binary(tid) and tid != "" ->
          _ = Conversations.attach_thread_to_session(tid, session.id)
          :ok

        _ ->
          :ok
      end

      {:noreply,
       socket
       |> put_flash(:info, "Session created")
       |> assign(:show_session_modal, false)
       |> assign(:show_session_dir_picker, false)
       |> assign(:show_mcp_modal, false)
       |> assign(:sessions, Conversations.list_sessions_with_auth())
       |> assign(:session_form_params, %{})
       |> assign(:session_mcp_selected_ids, [])
       |> assign(:session_prompt_builder, build_default_prompt_builder())
       |> assign(:prompt_picker_selection, %{})
       |> assign(:prompt_picker_provider, :openai)}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

        {:noreply,
         socket
         |> assign(:session_form, to_form(cs))
         |> assign(:session_form_params, params)
         |> assign(:session_mcp_selected_ids, selected)}
    end
  end

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  @impl true
  def handle_event("prompt_picker:tab", %{"provider" => provider_param}, socket) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    {:noreply, assign(socket, :prompt_picker_provider, provider)}
  end

  def handle_event("prompt_picker:add", params, socket) do
    provider =
      to_provider_atom(Map.get(params, "provider")) || socket.assigns[:prompt_picker_provider] ||
        :openai

    prompt_id = Map.get(params, "prompt_id", "") |> to_string |> String.trim()

    selection = Map.put(socket.assigns[:prompt_picker_selection] || %{}, provider, "")

    {:noreply, do_add_prompt(socket, provider, prompt_id, selection)}
  end

  # moved below to keep handle_event/3 clauses contiguous

  # moved below to keep handle_event/3 clauses contiguous

  def handle_event(
        "prompt_picker:remove",
        %{"provider" => provider_param, "id" => prompt_id},
        socket
      ) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    list = Map.get(builder, provider, [])

    case Enum.split_with(list, &(&1.id == prompt_id)) do
      {[entry], rest} ->
        if entry.prompt.immutable do
          {:noreply,
           put_flash(socket, :error, "#{entry.prompt.name} is immutable and cannot be removed.")}
        else
          updated_builder = Map.put(builder, provider, rest)

          {:noreply,
           socket
           |> assign(:session_prompt_builder, updated_builder)
           |> merge_builder_into_catalog(updated_builder)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "prompt_picker:toggle",
        %{"provider" => provider_param, "id" => prompt_id},
        socket
      ) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    list = Map.get(builder, provider, [])

    case Enum.find(list, &(&1.id == prompt_id)) do
      nil ->
        {:noreply, socket}

      entry ->
        desired = !entry.enabled

        if entry.prompt.immutable and not desired do
          {:noreply,
           socket
           |> put_flash(:error, "#{entry.prompt.name} is immutable and must remain enabled.")}
        else
          {:noreply, apply_toggle(socket, builder, provider, list, prompt_id, desired)}
        end
    end
  end

  def handle_event(
        "prompt_picker:reorder",
        %{"provider" => provider_param, "ordered_ids" => ordered_ids},
        socket
      ) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    list = Map.get(builder, provider, [])
    ordered_ids = List.wrap(ordered_ids) |> Enum.map(&to_string/1)

    case reorder_entries(list, ordered_ids) do
      {:ok, reordered} ->
        updated_builder = Map.put(builder, provider, reordered)

        {:noreply,
         socket
         |> assign(:session_prompt_builder, updated_builder)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("prompt_picker:refresh", %{"provider" => provider_param}, socket) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    socket =
      socket
      |> refresh_prompt_state()
      |> merge_builder_into_catalog()
      |> assign(:prompt_picker_provider, provider)

    {:noreply, socket}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_session_modal, false)
     |> assign(:show_session_dir_picker, false)
     |> assign(:show_agent_modal, false)}
  end

  # Keep all handle_event/3 clauses grouped together to avoid warnings
  defp apply_toggle(socket, builder, provider, list, prompt_id, desired) do
    updated_list =
      Enum.map(list, fn
        %{id: ^prompt_id} = e -> %{e | enabled: desired}
        e -> e
      end)

    updated_builder = Map.put(builder, provider, updated_list)

    socket
    |> assign(:session_prompt_builder, updated_builder)
    |> merge_builder_into_catalog(updated_builder)
  end

  defp add_prompt_to_builder(socket, builder, provider, current, prompt, selection) do
    entry = %{
      id: prompt.id,
      prompt: prompt,
      enabled: true,
      overrides: %{},
      source: :manual
    }

    updated_builder = Map.put(builder, provider, current ++ [entry])

    socket
    |> assign(:session_prompt_builder, updated_builder)
    |> assign(:prompt_picker_selection, selection)
    |> assign(:prompt_picker_provider, provider)
    |> merge_builder_into_catalog(updated_builder)
  end

  defp do_add_prompt(socket, _provider, "", selection),
    do: assign(socket, :prompt_picker_selection, selection)

  defp do_add_prompt(socket, provider, prompt_id, selection) do
    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    current = Map.get(builder, provider, [])

    if Enum.any?(current, &(&1.id == prompt_id)) do
      socket
      |> assign(:prompt_picker_selection, selection)
      |> put_flash(:info, "Prompt already present for #{provider_label(provider)}")
    else
      handle_fetch_prompt(socket, builder, provider, current, prompt_id, selection)
    end
  end

  defp handle_fetch_prompt(socket, builder, provider, current, prompt_id, selection) do
    case fetch_prompt(socket, prompt_id) do
      {nil, updated_socket} ->
        updated_socket
        |> assign(:prompt_picker_selection, selection)
        |> put_flash(:error, "Prompt could not be loaded. Try refreshing.")

      {prompt, updated_socket} ->
        case prompt.provider do
          ^provider ->
            add_prompt_to_builder(updated_socket, builder, provider, current, prompt, selection)

          :shared ->
            add_prompt_to_builder(updated_socket, builder, provider, current, prompt, selection)

          _ ->
            provider_mismatch_flash(updated_socket, selection, prompt)
        end
    end
  end

  defp provider_mismatch_flash(socket, selection, prompt) do
    socket
    |> assign(:prompt_picker_selection, selection)
    |> put_flash(:error, "#{prompt.name} belongs to #{provider_label(prompt.provider)} prompts.")
  end

  defp build_session_params(socket, params) do
    with {:ok, p2} <- mirror_persona(params),
         {:ok, p3} <- decode_memory_json(p2) do
      prompt_map = prompt_specs_from_builder(socket.assigns[:session_prompt_builder] || %{})

      payload0 =
        if prompt_map == %{},
          do: Map.put_new(p3, "system_prompt_ids_by_provider", %{}),
          else: Map.put(p3, "system_prompt_ids_by_provider", prompt_map)

      # Persist MCP server ids chosen via checkboxes (component emits hidden fields into params)
      payload1 = Map.put(payload0, "mcp_server_ids", Map.get(params, "mcp_server_ids", []))

      # Prefer tools_json from hidden field emitted by SessionFormComponent
      payload =
        case Map.get(params, "tools_json") do
          s when is_binary(s) and byte_size(s) > 0 ->
            case Jason.decode(s) do
              {:ok, %{} = tools_map} -> Map.put(payload1, "tools", tools_map)
              _ -> payload1
            end

          _ ->
            payload1
        end

      {:ok, payload}
    end
  end

  defp mirror_persona(params) do
    case Map.get(params, "persona_id") do
      id when is_binary(id) and id != "" ->
        p = TheMaestro.SuppliedContext.get_item!(id)

        {:ok,
         Map.put(params, "persona", %{
           "name" => p.name,
           "version" => p.version || 1,
           "persona_text" => p.text
         })}

      _ ->
        {:ok, params}
    end
  end

  defp decode_memory_json(params) do
    case Map.get(params, "memory_json") do
      txt when is_binary(txt) and txt != "" ->
        case Jason.decode(txt) do
          {:ok, %{} = m} -> {:ok, Map.put(params, "memory", m)}
          _ -> {:ok, params}
        end

      _ ->
        {:ok, params}
    end
  end

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :selected, path, :new_session}, socket) do
    params = merge_session_params(socket, %{"working_dir" => path})
    selected = normalize_mcp_ids(Map.get(params, "mcp_server_ids"))

    cs =
      Conversations.change_session(%Conversations.Session{}, params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:session_form, to_form(cs, action: :validate))
     |> assign(:session_form_params, params)
     |> assign(:session_mcp_selected_ids, selected)
     |> assign(:show_session_dir_picker, false)}
  end

  @impl true
  def handle_info({TheMaestroWeb.DirectoryPicker, :cancel, :new_session}, socket) do
    {:noreply, assign(socket, :show_session_dir_picker, false)}
  end

  def handle_info({FormComponent, {:saved, server}}, socket) do
    selected = Enum.uniq([server.id | socket.assigns.session_mcp_selected_ids || []])

    params =
      socket.assigns[:session_form_params]
      |> Kernel.||(%{})
      |> Map.put("mcp_server_ids", selected)

    cs =
      socket.assigns.session_form.data
      |> Conversations.change_session(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:mcp_server_options, MCP.server_options(include_disabled?: true))
     |> assign(:session_mcp_selected_ids, selected)
     |> assign(:session_form_params, params)
     |> assign(:session_form, to_form(cs, action: :validate))
     |> assign(:show_mcp_modal, false)}
  end

  def handle_info({FormComponent, {:canceled, _}}, socket) do
    {:noreply, assign(socket, :show_mcp_modal, false)}
  end

  @impl true
  def handle_info(%{topic: "oauth:events", event: "completed", payload: payload}, socket) do
    # Refresh list when a new auth is persisted by the callback server
    {:noreply,
     socket
     |> put_flash(:info, "OAuth completed for #{payload["provider"]}: #{payload["session_name"]}")
     |> assign(:auths, Auth.list_saved_authentications())
     |> assign(:auth_options, build_auth_options())}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           event: %TheMaestro.Domain.StreamEvent{type: type}
         }},
        socket
      ) do
    {:noreply, put_active_stream(socket, sid, type)}
  end

  @impl true
  def handle_info(:refresh_mcp_inventory, socket) do
    selected = socket.assigns[:session_mcp_selected_ids] || []

    {:noreply,
     socket
     |> assign(:tool_inventory_by_provider, build_tool_inventory_for_servers(selected))
     |> assign(:mcp_warming, false)}
  end

  # Catch-all handle_info should be last among handle_info clauses
  def handle_info(_msg, socket), do: {:noreply, socket}

  # moved catch-all to end of module to avoid overshadowing specific clauses

  defp put_active_stream(socket, session_id, type) do
    active? = type in [:thinking, :content, :function_call, :usage]
    assign(socket, :active_streams, Map.put(socket.assigns.active_streams, session_id, active?))
  end

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")

  defp format_dt(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S") <> " UTC"

  defp build_auth_options do
    Auth.list_saved_authentications()
    |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
  end

  defp build_persona_options do
    TheMaestro.SuppliedContext.list_items(:persona) |> Enum.map(&{&1.name, &1.id})
  end

  defp orphan_thread_options do
    Conversations.list_orphan_threads()
    |> Enum.map(fn %{thread_id: tid, label: label} ->
      {label || "thread-" <> String.slice(tid, 0, 8), tid}
    end)
  end

  # agent options removed

  defp build_model_options(%{"auth_id" => auth_id}) when is_binary(auth_id) and auth_id != "" do
    with %{} = sa <- Auth.get_saved_authentication!(auth_id),
         provider <- to_provider_atom(sa.provider),
         {:ok, models} <- Provider.list_models(provider, sa.auth_type, sa.name),
         list when is_list(list) and list != [] <-
           Enum.map(models, fn m -> {m.name || m.id, m.id} end) do
      list
    else
      _ -> default_models_for(Auth.get_saved_authentication!(auth_id))
    end
  end

  # fallback clause grouped with the primary build_model_options/1
  defp build_model_options(_), do: []

  defp default_models_for(%{provider: provider}) do
    case to_provider_atom(provider) do
      :openai ->
        [{"gpt-5", "gpt-5"}, {"gpt-4o", "gpt-4o"}]

      :anthropic ->
        [{"claude-3-5-sonnet", "claude-3-5-sonnet"}, {"claude-3-opus", "claude-3-opus"}]

      :gemini ->
        [{"gemini-2.5-pro", "gemini-2.5-pro"}, {"gemini-1.5-pro-latest", "gemini-1.5-pro-latest"}]

      _ ->
        []
    end
  end

  defp default_models_for(_), do: []

  # helpers mirrored from SessionChatLive
  # removed: stringify_provider_keys (unused)

  # Convert provider strings/atoms to a safe allowed atom
  defp to_provider_atom(p) when is_atom(p) do
    providers = Provider.list_providers()
    if p in providers, do: p, else: nil
  end

  defp to_provider_atom(p) when is_binary(p) do
    providers = Provider.list_providers()
    Enum.find(providers, fn provider -> Atom.to_string(provider) == p end)
  end

  defp to_provider_atom(_), do: nil

  defp build_auth_options_for(provider) when is_atom(provider) do
    Auth.list_saved_authentications_by_provider(provider)
    |> Enum.map(fn sa -> {"#{sa.name} — #{sa.provider}/#{sa.auth_type}", sa.id} end)
  end

  # Merge new form values into the current session form params, preserving prior selections
  defp merge_session_params(socket, extra) when is_map(extra) do
    current = socket.assigns[:session_form_params] || %{}
    Map.merge(current, extra)
  end

  defp refresh_prompt_state(socket) do
    library =
      Enum.reduce(@prompt_providers, %{}, fn provider, acc ->
        prompts =
          SuppliedContext.list_system_prompts(provider,
            include_shared: true,
            only_defaults: false,
            group_by_family: false
          )

        Map.put(acc, provider, prompts)
      end)

    catalog =
      library
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(%{}, fn prompt, acc ->
        Map.put(acc, prompt.id, prompt)
      end)

    socket
    |> assign(:prompt_library, library)
    |> assign(:prompt_catalog, catalog)
    |> merge_builder_into_catalog()
  end

  defp empty_builder do
    Enum.into(@prompt_providers, %{}, &{&1, []})
  end

  defp build_default_prompt_builder do
    Enum.reduce(@prompt_providers, %{}, fn provider, acc ->
      stack = SystemPrompts.default_stack(provider)

      entries =
        stack.prompts
        |> Enum.map(fn %{prompt: prompt, overrides: overrides} ->
          %{
            id: prompt.id,
            prompt: prompt,
            enabled: true,
            overrides: overrides || %{},
            source: stack.source
          }
        end)

      Map.put(acc, provider, entries)
    end)
  end

  defp ensure_prompt_builder(socket) do
    builder = socket.assigns[:session_prompt_builder] || %{}

    complete? =
      builder != %{} and Enum.all?(@prompt_providers, &Map.has_key?(builder, &1))

    if complete? do
      socket
    else
      defaults = build_default_prompt_builder()

      merged =
        Enum.reduce(@prompt_providers, %{}, fn provider, acc ->
          Map.put(acc, provider, Map.get(builder, provider, Map.get(defaults, provider, [])))
        end)

      socket
      |> assign(:session_prompt_builder, merged)
      |> merge_builder_into_catalog(merged)
    end
  end

  defp merge_builder_into_catalog(socket, builder) do
    updated_catalog =
      builder
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(socket.assigns[:prompt_catalog] || %{}, fn entry, acc ->
        Map.put(acc, entry.id, entry.prompt)
      end)

    assign(socket, :prompt_catalog, updated_catalog)
  end

  defp merge_builder_into_catalog(socket) do
    builder = socket.assigns[:session_prompt_builder] || %{}
    merge_builder_into_catalog(socket, builder)
  end

  defp prompt_specs_from_builder(builder) do
    Enum.reduce(builder, %{}, fn {provider, entries}, acc ->
      specs = Enum.map(entries, &to_spec/1)
      if specs == [], do: acc, else: Map.put(acc, Atom.to_string(provider), specs)
    end)
  end

  defp to_spec(entry) do
    overrides = entry.overrides || %{}
    enabled = if entry.prompt.immutable, do: true, else: !!entry.enabled

    %{
      "id" => entry.id,
      "enabled" => enabled,
      "overrides" => overrides
    }
  end

  defp fetch_prompt(socket, prompt_id) do
    catalog = socket.assigns[:prompt_catalog] || %{}

    case Map.get(catalog, prompt_id) do
      %{} = prompt ->
        {prompt, socket}

      _ ->
        try do
          prompt = SuppliedContext.get_item!(prompt_id)
          new_catalog = Map.put(catalog, prompt_id, prompt)
          {prompt, assign(socket, :prompt_catalog, new_catalog)}
        rescue
          Ecto.NoResultsError -> {nil, socket}
        end
    end
  end

  defp provider_label(:openai), do: "OpenAI"
  defp provider_label(:anthropic), do: "Anthropic"
  defp provider_label(:gemini), do: "Gemini"
  defp provider_label(other), do: other |> to_string() |> String.capitalize()

  # removed: prompt error helpers (unused)

  defp reorder_entries(entries, ordered_ids) do
    current_ids = Enum.map(entries, & &1.id) |> MapSet.new()
    desired_ids = MapSet.new(ordered_ids)

    if current_ids == desired_ids do
      by_id = Map.new(entries, &{&1.id, &1})
      reordered = Enum.map(ordered_ids, &Map.fetch!(by_id, &1))
      {:ok, reordered}
    else
      :error
    end
  end

  defp normalize_mcp_ids(nil), do: []

  defp normalize_mcp_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_mcp_ids(id), do: normalize_mcp_ids([id])

  defp session_label(s) do
    cond do
      is_binary(s.name) and String.trim(s.name) != "" ->
        s.name

      s.saved_authentication && s.saved_authentication.name ->
        s.saved_authentication.name <> " · sess-" <> String.slice(s.id, 0, 8)

      true ->
        "sess-" <> String.slice(s.id, 0, 8)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      page_title={@page_title}
      main_class="px-6 py-8"
      container_class="mx-auto max-w-7xl"
    >
      <div
        id="dashboard-root"
        phx-hook="DashboardHotkeys"
      >
        <section class="mb-12">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-2xl font-bold text-green-400 glow">
              &gt; SAVED_AUTHENTICATIONS.DAT
            </h2>
            <.link
              navigate={~p"/auths/new"}
              class="px-4 py-2 rounded transition-all duration-200 btn-amber hover:glow-strong"
              data-hotkey="alt+a"
              data-hotkey-seq="g a"
              data-hotkey-label="New Auth"
            >
              <.icon name="hero-key" class="inline mr-2 h-4 w-4" /> NEW AUTH
            </.link>
          </div>
          <div class="terminal-card terminal-border-amber rounded-lg overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead class="bg-amber-600/20">
                  <tr>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">NAME</th>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">PROVIDER</th>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">AUTH_TYPE</th>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">EXPIRATION</th>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">CREATED</th>
                    <th class="px-4 py-3 text-left font-bold text-amber-300">ACTIONS</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for sa <- @auths do %>
                    <tr id={"auth-#{sa.id}"} class="border-t border-amber-800 hover:bg-amber-600/10">
                      <td class="px-4 py-3 text-amber-200">{sa.name}</td>
                      <td class="px-4 py-3 text-amber-200">{provider_label(sa.provider)}</td>
                      <td class="px-4 py-3 text-amber-200 uppercase">{sa.auth_type}</td>
                      <td class="px-4 py-3 text-amber-200">{format_dt(sa.expires_at)}</td>
                      <td class="px-4 py-3 text-amber-200">{format_dt(sa.inserted_at)}</td>
                      <td class="px-4 py-3">
                        <div class="flex space-x-2">
                          <.link
                            navigate={~p"/auths/#{sa.id}"}
                            class="text-green-400 hover:text-green-300"
                          >
                            <.icon name="hero-eye" class="h-4 w-4" />
                          </.link>
                          <.link
                            navigate={~p"/auths/#{sa.id}/edit"}
                            class="text-blue-400 hover:text-blue-300"
                          >
                            <.icon name="hero-pencil-square" class="h-4 w-4" />
                          </.link>
                          <button
                            phx-click="delete"
                            phx-value-id={sa.id}
                            data-confirm="Delete this auth?"
                            class="text-red-400 hover:text-red-300"
                          >
                            <.icon name="hero-trash" class="h-4 w-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section>
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-green-400 glow">&gt; SESSION_MANAGER.DAT</h2>
            <button
              class="px-4 py-2 rounded transition-all duration-200 btn-blue"
              phx-click="open_session_modal"
              data-hotkey="alt+n"
              data-hotkey-seq="g n"
              data-hotkey-label="New Session"
            >
              <.icon name="hero-plus" class="inline mr-2 h-4 w-4" /> NEW SESSION
            </button>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for s <- @sessions do %>
              <div
                class="terminal-card terminal-border-blue rounded-lg p-6 transition-colors"
                id={"session-" <> to_string(s.id)}
              >
                <h3 class="text-xl font-bold text-blue-300 mb-1 glow">{session_label(s)}</h3>
                <%= if Map.get(@active_streams || %{}, s.id) do %>
                  <div class="text-xs text-amber-400 glow mb-2" role="status" aria-live="polite">
                    ACTIVE
                  </div>
                <% end %>
                <div class="space-y-2 text-sm">
                  <p class="text-amber-300">
                    Auth: {s.saved_authentication && s.saved_authentication.name} ({s.saved_authentication &&
                      s.saved_authentication.provider}/ {s.saved_authentication &&
                      s.saved_authentication.auth_type})
                  </p>
                  <p class="text-amber-200">Model: {s.model_id || "(auto)"}</p>
                  <p class="text-amber-200">Last used: {format_dt(s.last_used_at)}</p>
                </div>
                <div class="flex justify-between mt-4 pt-3 border-t border-blue-800">
                  <div class="flex space-x-2">
                    <.link
                      class="px-3 py-1 rounded text-xs btn-green"
                      navigate={~p"/sessions/#{s.id}/chat"}
                    >
                      CHAT
                    </.link>
                    <.link
                      class="text-blue-400 hover:text-blue-300"
                      navigate={~p"/sessions/#{s.id}/edit"}
                    >
                      <.icon name="hero-pencil-square" class="h-4 w-4" />
                    </.link>
                  </div>
                  <button
                    class="text-red-400 hover:text-red-300"
                    phx-click="delete_session"
                    phx-value-id={s.id}
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <.modal :if={@show_session_modal} id="session-modal">
          <h3 class="text-2xl font-bold text-blue-400 mb-6 glow">CREATE NEW SESSION</h3>
          <.form
            for={@session_form}
            id="session-modal-form"
            phx-submit="session_save"
            phx-change="session_validate"
            class="flex flex-col max-h-[80vh]"
          >
            <div class="flex-1 overflow-y-auto pr-1">
              <.input field={@session_form[:name]} type="text" label="Session Name" />
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <label class="text-xs">Provider (filter)</label>
                  <select name="session[provider]" class="input">
                    <%= for p <- ["openai", "anthropic", "gemini"] do %>
                      <option value={p} selected={@session_provider == p}>{p}</option>
                    <% end %>
                  </select>
                </div>
                <.input
                  field={@session_form[:auth_id]}
                  type="select"
                  label="Saved Auth"
                  options={@session_auth_options}
                  prompt="Select auth"
                />
                <.input
                  field={@session_form[:model_id]}
                  type="select"
                  label="Model"
                  options={@session_model_options}
                  prompt="(auto)"
                />
                <div>
                  <.input field={@session_form[:working_dir]} type="text" label="Working Directory" />
                  <div class="mt-1 flex gap-2">
                    <button
                      type="button"
                      class="btn btn-xs btn-amber"
                      phx-click="session_use_root_dir"
                    >
                      ROOT
                    </button>
                    <button
                      type="button"
                      class="btn btn-xs btn-amber"
                      phx-click="open_session_dir_picker"
                    >
                      <.icon name="hero-folder" class="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>
              <div class="mt-2">
                <label class="text-xs">Chat History</label>
                <div class="text-sm opacity-80">Start New Chat or attach an existing thread</div>
              </div>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <.input
                  name="session[attach_thread_id]"
                  type="select"
                  label="Attach Existing Thread"
                  options={@orphan_threads}
                  prompt="(Start New Chat)"
                  value={nil}
                />
              </div>
              
    <!-- Shared sections: System Prompts, Persona, Memory, Tool pickers, MCPs -->
              <.live_component
                module={TheMaestroWeb.SessionFormComponent}
                id="session-modal-form-body"
                mode={:create}
                provider={@prompt_picker_provider}
                prompt_picker_provider={@prompt_picker_provider}
                session_prompt_builder={@session_prompt_builder}
                prompt_library={@prompt_library}
                prompt_picker_selection={@prompt_picker_selection}
                ui_sections={@ui_sections || %{prompt: true, persona: true, memory: true}}
                session_form={@session_form}
                persona_options={@persona_options}
                mcp_server_options={@mcp_server_options}
                session_mcp_selected_ids={@session_mcp_selected_ids}
                mcp_warming={@mcp_warming}
                tool_picker_allowed={@tool_picker_allowed_map}
                tool_inventory_by_provider={@tool_inventory_by_provider}
              />
            </div>
            <div class="sticky bottom-0 mt-3 border-t border-base-300 bg-base-100 pt-3">
              <div class="flex justify-end gap-2">
                <button type="submit" class="btn btn-blue">Save</button>
                <button type="button" class="btn" phx-click="cancel_session_modal">Cancel</button>
              </div>
            </div>
          </.form>
          <.modal :if={@show_session_dir_picker} id="dir-picker-session-new">
            <.live_component
              module={TheMaestroWeb.DirectoryPicker}
              id="dirpick-session-new"
              start_path={@session_form[:working_dir].value || Path.expand(".")}
              context={:new_session}
            />
          </.modal>
          <.modal :if={@show_mcp_modal} id="session-mcp-modal">
            <.live_component
              module={FormComponent}
              id="session-mcp-form"
              title="New MCP Server"
              server={%MCP.Servers{}}
              action={:new}
            />
          </.modal>
        </.modal>

        <.modal :if={@show_delete_session_modal} id="confirm-delete-session">
          <div class="space-y-3">
            <h3 class="text-lg font-semibold">Delete Session</h3>
            <p class="text-sm opacity-80">
              Choose what to delete. By default, chat history is preserved for RAG/learning.
            </p>
            <div class="flex flex-col sm:flex-row sm:space-x-2 space-y-2 sm:space-y-0">
              <button phx-click="confirm_delete_session_only" class="btn btn-warning flex-1">
                Delete Session Only (Keep Chat)
              </button>
              <button phx-click="confirm_delete_session_and_chat" class="btn btn-error flex-1">
                Delete Session AND Chat History
              </button>
              <button phx-click="cancel_delete_session" class="btn flex-1">Cancel</button>
            </div>
          </div>
        </.modal>

        <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />
      </div>
    </Layouts.app>
    """
  end

  # ===== Extracted components to reduce nesting =====
  attr :auths, :list, required: true

  defp auths_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th>Name</th>
            <th>Provider</th>
            <th>Auth Type</th>
            <th>Expiration</th>
            <th>Created</th>
            <th class="w-40">Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for sa <- @auths do %>
            <tr id={"auth-#{sa.id}"}>
              <td>{sa.name}</td>
              <td>{provider_label(sa.provider)}</td>
              <td class="uppercase">{sa.auth_type}</td>
              <td>{format_dt(sa.expires_at)}</td>
              <td>{format_dt(sa.inserted_at)}</td>
              <td class="space-x-2">
                <.link navigate={~p"/auths/#{sa.id}"} class="btn btn-xs">View</.link>
                <.link navigate={~p"/auths/#{sa.id}/edit"} class="btn btn-xs">Edit</.link>
                <button
                  phx-click="delete"
                  phx-value-id={sa.id}
                  data-confirm="Delete this auth?"
                  class="btn btn-xs btn-error"
                >
                  Delete
                </button>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  # Agents grid removed in session-centric cleanup

  attr :sessions, :list, required: true

  defp sessions_grid(assigns) do
    ~H"""
    <div class="mt-10">
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-lg font-semibold">Sessions</h2>
        <button class="btn" phx-click="open_session_modal">New Session</button>
      </div>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div class="card bg-base-200 p-4">
          <div class="font-semibold text-base">Chat Histories</div>
          <div class="text-xs opacity-70">Browse orphaned chats and reattach to sessions.</div>
          <div class="mt-2 space-x-2">
            <.link class="btn btn-xs" navigate={~p"/chat_history"}>Open Chat Histories</.link>
          </div>
        </div>
        <%= for s <- @sessions do %>
          <div class="card bg-base-200 p-4" id={"session-" <> to_string(s.id)}>
            <div class="font-semibold text-base">{session_label(s)}</div>
            <%= if Map.get(@active_streams || %{}, to_string(s.id)) do %>
              <div class="text-xs text-amber-400 glow">ACTIVE</div>
            <% end %>
            <div class="text-sm opacity-80">
              Auth: {s.saved_authentication && s.saved_authentication.name} ({s.saved_authentication &&
                s.saved_authentication.provider}/ {s.saved_authentication &&
                s.saved_authentication.auth_type})
            </div>
            <div class="text-xs opacity-70">Model: {s.model_id || "(auto)"}</div>
            <div class="text-xs opacity-70">Last used: {format_dt(s.last_used_at)}</div>
            <div class="mt-2 space-x-2">
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/chat"}>Go into chat</.link>
              <.link class="btn btn-xs" navigate={~p"/sessions/#{s.id}/chat"}>
                Open
              </.link>
              <button class="btn btn-xs btn-error" phx-click="delete_session" phx-value-id={s.id}>
                Delete
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # -- MCP inventory/warmup helpers and message handling --

  defp build_tool_inventory_for_servers(server_ids) do
    %{
      openai: Inventory.list_for_provider_with_servers(server_ids, :openai),
      anthropic: Inventory.list_for_provider_with_servers(server_ids, :anthropic),
      gemini: Inventory.list_for_provider_with_servers(server_ids, :gemini)
    }
  end

  defp warm_mcp_tools_cache(server_ids) do
    Enum.each(server_ids, &warm_single_server_cache/1)
  end

  defp warm_single_server_cache(sid) do
    case MCP.ToolsCache.get(sid, 60 * 60_000) do
      {:ok, _} -> :ok
      _ -> discover_and_cache_server_tools(sid)
    end
  end

  defp discover_and_cache_server_tools(sid) do
    server = MCP.get_server!(sid)

    case MCP.Client.discover_server(server) do
      {:ok, %{tools: tools}} -> cache_server_tools(sid, server, tools)
      _ -> :ok
    end
  end

  defp cache_server_tools(sid, server, tools) do
    ttl_ms = calculate_server_cache_ttl(server.metadata)
    _ = MCP.ToolsCache.put(sid, tools, ttl_ms)
    :ok
  end

  defp calculate_server_cache_ttl(%{} = metadata),
    do: to_int(metadata["tool_cache_ttl_minutes"] || 60) * 60_000

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60
end
