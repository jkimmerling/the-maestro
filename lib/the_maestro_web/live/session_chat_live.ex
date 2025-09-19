defmodule TheMaestroWeb.SessionChatLive do
  use TheMaestroWeb, :live_view

  alias TheMaestro.Auth
  alias TheMaestro.Conversations
  alias TheMaestro.MCP
  alias TheMaestro.SuppliedContext
  alias TheMaestro.Tools.Inventory
  require Logger
  alias TheMaestroWeb.MCPServersLive.FormComponent

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session =
      id
      |> Conversations.get_session_with_auth!()
      |> Conversations.preload_session_mcp()

    {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)
    TheMaestro.Chat.subscribe(session.id)

    # Determine current thread (latest) for display
    tid = Conversations.latest_thread_id(session.id)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:session, session)
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, (tid && Conversations.thread_label(tid)) || nil)
     |> assign(:message, "")
     |> assign(:messages, current_messages_for(session.id, tid))
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_id, nil)
     |> assign(:stream_task, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:followup_history, [])
     |> assign(:summary, compute_summary(current_messages_for(session.id, tid)))
     |> assign(:editing_latest, false)
     |> assign(:latest_json, nil)
     |> assign(:show_config, false)
     |> assign(:config_form, %{})
     |> assign(:config_models, [])
     |> assign(:config_persona_options, [])
     |> assign(:show_clear_confirm, false)
     |> assign(:show_persona_modal, false)
     |> assign(:persona_form, %{})
     |> assign(:show_memory_modal, false)
     |> assign(:memory_editor_text, nil)}
  end

  @impl true
  def handle_event("change", %{"message" => msg}, socket) do
    {:noreply, assign(socket, :message, msg)}
  end

  # handle_params moved after handle_event clauses to avoid grouping warnings

  @impl true
  def handle_event("send", _params, socket) do
    msg = String.trim(socket.assigns.message || "")

    if msg == "" do
      {:noreply, socket}
    else
      {:noreply, start_streaming_turn(socket, msg)}
    end
  end

  @impl true
  def handle_event("start_edit_latest", _params, socket) do
    case Conversations.latest_snapshot(socket.assigns.session.id) do
      nil ->
        {:noreply, socket}

      entry ->
        {:noreply,
         socket
         |> assign(:editing_latest, true)
         |> assign(:latest_json, Jason.encode!(entry.combined_chat, pretty: true))}
    end
  end

  @impl true
  def handle_event("cancel_edit_latest", _params, socket) do
    {:noreply, assign(socket, editing_latest: false, latest_json: nil)}
  end

  @impl true
  def handle_event("save_edit_latest", %{"json" => json}, socket) do
    with {:ok, map} <-
           Jason.decode(json),
         latest when not is_nil(latest) <-
           Conversations.latest_snapshot(socket.assigns.session.id),
         {:ok, _} <-
           Conversations.update_chat_entry(latest, %{
             combined_chat: map,
             edit_version: latest.edit_version + 1
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Latest snapshot updated")
       |> assign(:editing_latest, false)
       |> assign(:latest_json, nil)
       |> assign(:history, Conversations.list_chat_entries(socket.assigns.session.id))}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{inspect(e)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not save latest snapshot")}
    end
  end

  # ==== Toolbar events ====
  @impl true
  def handle_event("new_thread", _params, socket) do
    {:ok, tid} = Conversations.new_thread(socket.assigns.session)

    msgs = current_messages_for(socket.assigns.session.id, tid)

    {:noreply,
     socket
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, Conversations.thread_label(tid))
     |> assign(:messages, msgs)
     |> assign(:summary, compute_summary(msgs))
     |> put_flash(:info, "Started new chat thread")}
  end

  @impl true
  def handle_event("confirm_clear_chat", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, true)}
  end

  @impl true
  def handle_event("cancel_clear_chat", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, false)}
  end

  @impl true
  def handle_event("do_clear_chat", _params, socket) do
    case socket.assigns.current_thread_id do
      tid when is_binary(tid) ->
        {:ok, _} = Conversations.delete_thread_entries(tid)

        {:noreply,
         socket
         |> assign(:show_clear_confirm, false)
         |> assign(:messages, [])
         |> assign(:summary, nil)
         |> put_flash(:info, "Cleared current chat thread")}

      _ ->
        {:noreply, assign(socket, :show_clear_confirm, false)}
    end
  end

  @impl true
  def handle_event("rename_thread", %{"label" => label}, socket) do
    case socket.assigns.current_thread_id do
      tid when is_binary(tid) and label != "" ->
        {:ok, _} = Conversations.set_thread_label(tid, label)
        {:noreply, assign(socket, :current_thread_label, label)}

      _ ->
        {:noreply, socket}
    end
  end

  # ==== Config modal events ====
  @impl true
  def handle_event("open_config", _params, socket) do
    form0 = %{
      "provider" => default_provider(socket.assigns.session),
      "auth_id" => socket.assigns.session.auth_id,
      "model_id" => socket.assigns.session.model_id,
      "working_dir" => socket.assigns.session.working_dir
    }

    socket =
      socket
      |> assign(:config_form, form0)
      |> assign(:config_models, [])
      |> load_auth_options(form0)
      |> load_persona_options()
      |> assign(:mcp_server_options, TheMaestro.MCP.server_options(include_disabled?: true))
      |> assign(:tool_picker_allowed, load_allowed(socket.assigns.session))
      |> assign(:tool_inventory_by_provider, build_tool_inventory(socket.assigns.session.id))
      |> assign(:ui_sections, %{prompt: true, persona: true, memory: true})
      |> assign(
        :session_mcp_selected_ids,
        Enum.map(
          TheMaestro.MCP.list_session_servers(socket.assigns.session.id),
          & &1.mcp_server_id
        )
      )
      |> refresh_prompt_state()
      |> ensure_prompt_builder()
      |> assign(:prompt_picker_provider, to_provider_atom(form0["provider"]) || :openai)
      |> assign(:prompt_picker_selection, %{})
      |> assign(:show_mcp_modal, false)
      |> assign(:mcp_warming, false)

    {:noreply, assign(socket, :show_config, true)}
  end

  @impl true
  def handle_event("close_config", _params, socket) do
    {:noreply, assign(socket, :show_config, false)}
  end

  @impl true
  def handle_event("validate_config", params, socket) do
    form = Map.merge(socket.assigns.config_form || %{}, params)
    socket = assign(socket, :config_form, form)
    socket = maybe_reload_auth_options(socket, params, form)
    socket = maybe_reload_models(socket, params)
    socket = maybe_prompt_builder_for_provider(socket, params)
    socket = maybe_mirror_persona(socket, params, form)
    socket = maybe_update_mcp_selection(socket, params)
    {:noreply, socket}
  end

  # Collapsible sections toggle — robust when keys are missing
  def handle_event("toggle_section", %{"name" => name}, socket) do
    sections = socket.assigns[:ui_sections] || %{}

    updated =
      case name do
        "prompt" -> Map.put(sections, :prompt, !Map.get(sections, :prompt, true))
        "persona" -> Map.put(sections, :persona, !Map.get(sections, :persona, true))
        "memory" -> Map.put(sections, :memory, !Map.get(sections, :memory, true))
        _ -> sections
      end

    {:noreply, assign(socket, :ui_sections, updated)}
  end

  # ===== Prompt picker events within the Session Config modal =====
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
          updated_list = update_prompt_enabled_status(list, prompt_id, desired)

          updated_builder = Map.put(builder, provider, updated_list)

          {:noreply,
           socket
           |> assign(:session_prompt_builder, updated_builder)
           |> merge_builder_into_catalog(updated_builder)}
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
        {:noreply, socket |> assign(:session_prompt_builder, updated_builder)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "prompt_picker:move_up",
        %{"provider" => provider_param, "id" => prompt_id},
        socket
      ) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    list = Map.get(builder, provider, [])
    {new_list, changed?} = move_up_guarded(list, prompt_id)

    if changed? do
      updated_builder = Map.put(builder, provider, new_list)

      {:noreply,
       socket
       |> assign(:session_prompt_builder, updated_builder)
       |> merge_builder_into_catalog(updated_builder)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "prompt_picker:move_down",
        %{"provider" => provider_param, "id" => prompt_id},
        socket
      ) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    list = Map.get(builder, provider, [])
    {new_list, changed?} = move_down_guarded(list, prompt_id)

    if changed? do
      updated_builder = Map.put(builder, provider, new_list)

      {:noreply,
       socket
       |> assign(:session_prompt_builder, updated_builder)
       |> merge_builder_into_catalog(updated_builder)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prompt_picker:refresh", %{"provider" => provider_param}, socket) do
    provider =
      to_provider_atom(provider_param) || socket.assigns[:prompt_picker_provider] || :openai

    socket = socket |> refresh_prompt_state() |> merge_builder_into_catalog()
    {:noreply, assign(socket, :prompt_picker_provider, provider)}
  end

  # ==== Persona modal ====
  @impl true
  def handle_event("open_persona_modal", _params, socket) do
    {:noreply, socket |> assign(:show_persona_modal, true) |> assign(:persona_form, %{})}
  end

  @impl true
  def handle_event("cancel_persona_modal", _params, socket) do
    {:noreply, assign(socket, :show_persona_modal, false)}
  end

  @impl true
  def handle_event("save_persona", %{"name" => name, "prompt_text" => text}, socket) do
    case SuppliedContext.create_item(%{type: :persona, name: name, text: text, version: 1}) do
      {:ok, persona} ->
        pj =
          Jason.encode!(%{
            "name" => persona.name,
            "version" => persona.version || 1,
            "persona_text" => persona.text
          })

        socket =
          socket
          |> load_persona_options()
          |> assign(
            :config_form,
            (socket.assigns.config_form || %{})
            |> Map.put("persona_id", persona.id)
            |> Map.put("persona_json", pj)
          )

        {:noreply,
         socket |> assign(:show_persona_modal, false) |> put_flash(:info, "Persona created")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create persona: #{inspect(changeset.errors)}")}
    end
  end

  # ==== Memory modal ====
  @impl true
  def handle_event("open_memory_modal", _params, socket) do
    mem =
      socket.assigns.config_form["memory_json"] ||
        Jason.encode!(socket.assigns.session.memory || %{})

    {:noreply, socket |> assign(:show_memory_modal, true) |> assign(:memory_editor_text, mem)}
  end

  @impl true
  def handle_event("cancel_memory_modal", _params, socket) do
    {:noreply, assign(socket, :show_memory_modal, false)}
  end

  @impl true
  def handle_event("save_memory_modal", %{"memory_json" => txt}, socket) do
    case Jason.decode(txt) do
      {:ok, %{} = _map} ->
        socket =
          assign(socket, :config_form, Map.put(socket.assigns.config_form, "memory_json", txt))

        {:noreply,
         socket |> assign(:show_memory_modal, false) |> put_flash(:info, "Memory updated")}

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "Memory JSON must be an object")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{inspect(reason)}")}
    end
  end

  # MCP modal show/hide
  def handle_event("open_mcp_modal", _params, socket) do
    {:noreply, assign(socket, :show_mcp_modal, true)}
  end

  def handle_event("close_mcp_modal", _params, socket) do
    {:noreply, assign(socket, :show_mcp_modal, false)}
  end

  # MCP server toggling handled in SessionFormComponent

  @impl true
  def handle_event("save_config", params, socket) do
    case build_session_update_attrs(socket, params) do
      {:ok, attrs} ->
        case Conversations.update_session(socket.assigns.session, attrs) do
          {:ok, updated} ->
            socket = assign(socket, :session, updated)
            _ = TheMaestro.MCP.Registry.bump_revision(updated.id)
            apply_behavior = params["apply"] || "now"
            socket = maybe_restart_stream(socket, updated, apply_behavior)

            {:noreply,
             socket
             |> assign(:show_config, false)
             |> put_flash(
               :info,
               if(apply_behavior == "now",
                 do: "Config applied and stream restarted",
                 else: "Config saved; applied next turn"
               )
             )}

          {:error, changeset} ->
            {:noreply,
             put_flash(socket, :error, "Failed to save config: #{inspect(changeset.errors)}")}
        end

      {:error, {:decode, field, reason}} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON for #{field}: #{inspect(reason)}")}
    end
  end

  defp provider_mismatch_flash(socket, selection, prompt) do
    socket
    |> assign(:prompt_picker_selection, selection)
    |> put_flash(:error, "#{prompt.name} belongs to #{prompt.provider} prompts.")
  end

  defp do_add_prompt(socket, _provider, "", selection),
    do: assign(socket, :prompt_picker_selection, selection)

  defp do_add_prompt(socket, provider, prompt_id, selection) do
    builder = socket.assigns[:session_prompt_builder] || empty_builder()
    current = Map.get(builder, provider, [])

    if Enum.any?(current, &(&1.id == prompt_id)) do
      socket
      |> assign(:prompt_picker_selection, selection)
      |> put_flash(:info, "Prompt already present for #{provider}")
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

  defp add_prompt_to_builder(socket, builder, provider, current, prompt, selection) do
    entry = %{id: prompt.id, prompt: prompt, enabled: true, overrides: %{}, source: :manual}
    updated_builder = Map.put(builder, provider, current ++ [entry])

    socket
    |> assign(:session_prompt_builder, updated_builder)
    |> assign(:prompt_picker_selection, selection)
    |> assign(:prompt_picker_provider, provider)
    |> merge_builder_into_catalog(updated_builder)
  end

  defp build_session_update_attrs(socket, params) do
    with {:ok, persona} <- decode_persona(socket, params),
         {:ok, memory} <- decode_memory(socket, params),
         {:ok, tools} <- decode_tools(socket, params),
         {:ok, mcps} <- decode_mcps(socket, params) do
      specs_map = prompt_specs_from_builder(socket.assigns[:session_prompt_builder] || %{})

      tools2 = merge_allowed(tools, socket.assigns[:tool_picker_allowed] || %{})

      {:ok,
       %{
         "auth_id" => params["auth_id"] || socket.assigns.session.auth_id,
         "model_id" => params["model_id"] || socket.assigns.session.model_id,
         "working_dir" => params["working_dir"] || socket.assigns.session.working_dir,
         "persona" => persona,
         "memory" => memory,
         "tools" => tools2,
         "mcps" => mcps,
         "mcp_server_ids" =>
           Map.get(params, "mcp_server_ids", socket.assigns[:session_mcp_selected_ids] || []),
         "system_prompt_ids_by_provider" => specs_map
       }}
    end
  end

  # --- JSON decode helpers split out to reduce complexity ---
  defp decode_persona(socket, params) do
    default = Jason.encode!(socket.assigns.session.persona || %{})
    safe_decode(params["persona_json"] || default)
  end

  defp decode_memory(socket, params) do
    default = Jason.encode!(socket.assigns.session.memory || %{})
    safe_decode(params["memory_json"] || default)
  end

  defp decode_tools(socket, params) do
    default = Jason.encode!(socket.assigns.session.tools || %{})
    safe_decode(params["tools_json"] || default)
  end

  defp decode_mcps(socket, params) do
    default = Jason.encode!(legacy_session_mcps(socket.assigns.session))
    safe_decode(params["mcps_json"] || default)
  end

  defp legacy_session_mcps(session) do
    MCP.session_connector_map(session)
  end

  # Tool picker events handled in SessionFormComponent

  defp load_allowed(%{tools: %{"allowed" => m}}), do: stringify_provider_keys(m)
  defp load_allowed(_), do: %{}

  defp stringify_provider_keys(%{} = m) do
    Enum.into(m, %{}, fn {k, v} ->
      {to_provider_atom(k) || :openai, List.wrap(v) |> Enum.map(&to_string/1)}
    end)
  end

  defp build_tool_inventory(session_id) do
    %{
      openai: Inventory.list_for_provider(session_id, :openai),
      anthropic: Inventory.list_for_provider(session_id, :anthropic),
      gemini: Inventory.list_for_provider(session_id, :gemini)
    }
  end

  defp merge_allowed(%{} = tools, %{} = allowed_by_provider) do
    allowed_str =
      allowed_by_provider
      |> Enum.map(fn {prov, list} ->
        {Atom.to_string(prov), Enum.map(List.wrap(list), &to_string/1)}
      end)
      |> Enum.into(%{})

    if map_size(allowed_str) == 0 do
      tools
    else
      Map.update(tools, "allowed", allowed_str, fn existing ->
        Map.merge(existing || %{}, allowed_str)
      end)
    end
  end

  # ----- System Prompt Picker wiring (reuse Dashboard patterns) -----
  defp refresh_prompt_state(socket) do
    providers = [:openai, :anthropic, :gemini]

    library =
      Enum.reduce(providers, %{}, fn provider, acc ->
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
      |> Enum.reduce(%{}, fn prompt, acc -> Map.put(acc, prompt.id, prompt) end)

    socket
    |> assign(:prompt_library, library)
    |> assign(:prompt_catalog, catalog)
  end

  defp ensure_prompt_builder(socket) do
    builder = socket.assigns[:session_prompt_builder] || %{}
    providers = [:openai, :anthropic, :gemini]

    complete? = builder != %{} and Enum.all?(providers, &Map.has_key?(builder, &1))

    if complete? do
      socket
    else
      session_id = socket.assigns.session.id

      built =
        Enum.reduce(providers, %{}, fn provider, acc ->
          entries = build_provider_entries(session_id, provider)
          Map.put(acc, provider, entries)
        end)

      assign(socket, :session_prompt_builder, built)
      |> merge_builder_into_catalog(built)
    end
  end

  defp maybe_prompt_builder_for_provider(socket, params) do
    if Map.has_key?(params, "provider") do
      prov = to_provider_atom(params["provider"]) || :openai

      assign(socket, :prompt_picker_provider, prov)
      |> ensure_prompt_builder()
    else
      socket
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

    %{"id" => entry.id, "enabled" => enabled, "overrides" => overrides}
  end

  defp maybe_restart_stream(socket, updated, apply_behavior) do
    if apply_behavior == "now" and socket.assigns.streaming? do
      _ = TheMaestro.Chat.cancel_turn(updated.id)
      provider = TheMaestro.Chat.provider_for_session(updated)

      canon =
        socket.assigns.pending_canonical ||
          (Conversations.latest_snapshot(updated.id) || %{combined_chat: %{"messages" => []}})
          |> Map.get(:combined_chat, %{"messages" => []})

      {:ok, provider_msgs} = Conversations.Translator.to_provider(canon, provider)
      model = TheMaestro.Chat.resolve_model_for_session(updated, provider)

      {:ok, stream_id} =
        TheMaestro.Chat.start_stream(
          updated.id,
          provider,
          elem(TheMaestro.Chat.auth_meta_for_session(updated), 1),
          provider_msgs,
          model
        )

      socket
      |> assign(:stream_id, stream_id)
      |> assign(:used_provider, provider)
      |> assign(:used_model, model)
      |> assign(:used_usage, nil)
      |> assign(:thinking?, true)
    else
      socket
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, %{assigns: %{session: %{id: current_id}}} = socket)
      when is_binary(id) and id != current_id do
    _ = TheMaestro.Chat.unsubscribe(current_id)
    session = Conversations.get_session_with_auth!(id)
    {:ok, {session, _snap}} = Conversations.ensure_seeded_snapshot(session)
    :ok = TheMaestro.Chat.subscribe(session.id)

    tid = Conversations.latest_thread_id(session.id)
    msgs = current_messages_for(session.id, tid)

    {:noreply,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:session, session)
     |> assign(:current_thread_id, tid)
     |> assign(:current_thread_label, (tid && Conversations.thread_label(tid)) || nil)
     |> assign(:message, "")
     |> assign(:messages, msgs)
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_id, nil)
     |> assign(:stream_task, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:thinking?, false)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:followup_history, [])
     |> assign(:summary, compute_summary(msgs))
     |> assign(:editing_latest, false)
     |> assign(:latest_json, nil)
     |> assign(:show_config, false)
     |> assign(:config_form, %{})
     |> assign(:config_models, [])
     |> assign(:config_persona_options, [])
     |> assign(:show_clear_confirm, false)
     |> assign(:show_persona_modal, false)
     |> assign(:persona_form, %{})
     |> assign(:show_memory_modal, false)
     |> assign(:memory_editor_text, nil)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ===== Streaming turn handling =====
  defp start_streaming_turn(socket, user_text) do
    session = socket.assigns.session
    latest = Conversations.latest_snapshot(session.id)

    canonical = (latest && latest.combined_chat) || %{"messages" => []}

    _updated =
      put_in(canonical, ["messages"], (canonical["messages"] || []) ++ [user_msg(user_text)])

    # Ensure we have a thread to attach this turn to
    {tid, socket} =
      case socket.assigns[:current_thread_id] do
        id when is_binary(id) ->
          {id, socket}

        _ ->
          {:ok, new_tid} = TheMaestro.Chat.ensure_thread(session.id)
          {new_tid, assign(socket, :current_thread_id, new_tid)}
      end

    t0 = System.monotonic_time(:millisecond)

    case TheMaestro.Chat.start_turn(session.id, tid, user_text, t0_ms: t0) do
      {:ok, result} ->
        ui_messages =
          (socket.assigns.messages || []) ++
            [%{"role" => "user", "content" => [%{"type" => "text", "text" => user_text}]}]

        socket
        |> assign(:message, "")
        |> assign(:messages, ui_messages)
        |> assign(:streaming?, true)
        |> assign(:partial_answer, "")
        |> assign(:stream_id, result.stream_id)
        |> assign(:stream_task, nil)
        |> assign(:pending_canonical, result.pending_canonical)
        |> assign(:followup_history, [])
        |> assign(:used_provider, result.provider)
        |> assign(:used_model, result.model)
        |> assign(:used_auth_type, result.auth_type)
        |> assign(:used_auth_name, result.auth_name)
        |> assign(:used_usage, nil)
        |> assign(:tool_calls, [])
        |> assign(:used_t0_ms, t0)
        |> assign(:event_buffer, [])
        |> assign(:retry_attempts, 0)

      {:error, :duplicate_turn} ->
        # Ignore duplicate submits of identical user text at tail
        socket
        |> put_flash(:info, "Ignored duplicate message")
        |> assign(:message, "")
    end
  end

  defp user_msg(text), do: %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}

  # assistant message helpers moved to orchestrator

  # model resolution moved to Chat facade

  # Provider calls moved to TheMaestro.Sessions.Manager

  require Logger

  # Reuse provider atom helper locally (single definition kept)

  defp fetch_prompt(socket, prompt_id) do
    catalog = socket.assigns[:prompt_catalog] || %{}

    case Map.get(catalog, prompt_id) do
      %{} = prompt ->
        {prompt, socket}

      _ ->
        try do
          prompt = TheMaestro.SuppliedContext.get_item!(prompt_id)
          new_catalog = Map.put(catalog, prompt_id, prompt)
          {prompt, assign(socket, :prompt_catalog, new_catalog)}
        rescue
          Ecto.NoResultsError -> {nil, socket}
        end
    end
  end

  defp reorder_entries(entries, ordered_ids) do
    current_ids = Enum.map(entries, & &1.id) |> MapSet.new()
    desired_ids = MapSet.new(ordered_ids)

    if current_ids == desired_ids do
      by_id = Map.new(entries, &{&1.id, &1})
      {:ok, Enum.map(ordered_ids, &Map.fetch!(by_id, &1))}
    else
      :error
    end
  end

  defp move_up_guarded(entries, prompt_id) do
    idx = Enum.find_index(entries, &(&1.id == prompt_id))

    cond do
      is_nil(idx) or idx == 0 -> {entries, false}
      Enum.at(entries, idx).prompt.immutable -> {entries, false}
      idx <= Enum.take_while(entries, & &1.prompt.immutable) |> length() -> {entries, false}
      true -> swap(entries, idx, idx - 1)
    end
  end

  defp move_down_guarded(entries, prompt_id) do
    idx = Enum.find_index(entries, &(&1.id == prompt_id))
    last = length(entries) - 1

    if is_nil(idx) or idx == last do
      {entries, false}
    else
      entry = Enum.at(entries, idx)
      if entry.prompt.immutable, do: {entries, false}, else: swap(entries, idx, idx + 1)
    end
  end

  defp swap(list, i, j) when i == j, do: {list, false}

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)
    new = list |> List.replace_at(i, b) |> List.replace_at(j, a)
    {new, true}
  end

  @impl true
  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :thinking}
         } = envelope},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    handle_thinking_event(envelope, socket)
  end

  # moved below to keep handle_info/2 clauses contiguous

  # Handle MCP server create/cancel from modal
  @impl true
  def handle_info({FormComponent, {:saved, server}}, socket) do
    selected = Enum.uniq([server.id | socket.assigns[:session_mcp_selected_ids] || []])

    {:noreply,
     socket
     |> assign(:mcp_server_options, TheMaestro.MCP.server_options(include_disabled?: true))
     |> assign(:session_mcp_selected_ids, selected)
     |> assign(:show_mcp_modal, false)}
  end

  @impl true
  def handle_info({FormComponent, {:canceled, _}}, socket) do
    {:noreply, assign(socket, :show_mcp_modal, false)}
  end

  @impl true
  def handle_info({:session_mcp_selected_ids, ids}, socket) when is_list(ids) do
    {:noreply, assign(socket, :session_mcp_selected_ids, Enum.map(ids, &to_string/1))}
  end

  @impl true
  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :content, content: chunk}
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    current = socket.assigns.partial_answer || ""
    delta = dedup_delta(current, chunk)
    new_partial = current <> delta

    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "content", delta: delta, at: now_ms()})
     |> assign(partial_answer: new_partial, thinking?: false)}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :function_call, tool_calls: calls}
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      )
      when is_list(calls) do
    new =
      Enum.map(calls, fn
        %TheMaestro.Domain.ToolCall{id: cid, name: name, arguments: args} ->
          %{"id" => cid, "name" => name, "arguments" => args || ""}

        %{id: cid, name: name, arguments: args} ->
          %{"id" => cid, "name" => name, "arguments" => args || ""}
      end)

    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "function_call", calls: new, at: now_ms()})
     |> assign(:tool_calls, (socket.assigns.tool_calls || []) ++ new)
     |> assign(:pending_tool_calls, (socket.assigns.pending_tool_calls || []) ++ new)}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :error, error: err}
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    Logger.error("stream error: #{inspect(err)}")

    # Handle Anthropic overloads with bounded backoff retries
    attempts = socket.assigns[:retry_attempts] || 0

    if socket.assigns[:used_provider] == :anthropic and anth_overloaded?(err) and attempts < 2 do
      # Cancel current stream task if running
      if task = socket.assigns.stream_task do
        Process.exit(task, :kill)
      end

      next = attempts + 1
      delay_ms = next * 750
      Process.send_after(self(), {:retry_stream, next}, delay_ms)

      {:noreply,
       socket
       |> push_event(%{
         kind: "ai",
         type: "error",
         error: "Anthropic overloaded — retrying (attempt #{next}/2) in #{delay_ms}ms",
         at: now_ms()
       })
       |> put_flash(:info, "Anthropic overloaded — retrying (#{next}/2) in #{delay_ms}ms")
       |> assign(thinking?: false)
       |> assign(:retry_attempts, next)}
    else
      {:noreply,
       socket
       |> push_event(%{kind: "ai", type: "error", error: err, at: now_ms()})
       |> put_flash(:error, "Provider error: #{err}")
       |> assign(thinking?: false)}
    end
  end

  @impl true
  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :usage, usage: usage}
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    usage = if is_struct(usage), do: Map.from_struct(usage), else: usage

    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "usage", usage: usage, at: now_ms()})
     |> assign(:used_usage, usage)
     |> assign(
       :summary,
       (fn ->
          msgs = socket.assigns.messages || []
          # Keep summary updated to reflect latest token totals
          compute_summary(msgs)
        end).()
     )}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{
             type: :finalized,
             content: final_text,
             usage: usage,
             raw: raw
           }
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    usage_map = if is_struct(usage), do: Map.from_struct(usage), else: usage || %{}
    req_meta = (raw && Map.get(raw, :meta)) || %{}
    meta = Map.put(req_meta, "usage", usage_map)
    messages = append_assistant_message(socket.assigns.messages || [], final_text || "", meta)

    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> assign(:partial_answer, "")
     |> assign(:stream_task, nil)
     |> assign(:stream_id, nil)
     |> assign(:pending_canonical, nil)
     |> assign(:followup_history, [])
     |> assign(:thinking?, false)
     |> assign(:used_usage, nil)
     |> assign(:tool_calls, [])
     |> assign(:pending_tool_calls, [])
     |> assign(:summary, compute_summary(messages))
     |> assign(:messages, messages)}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :done}
         }},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      ) do
    # Manager now owns finalization and tool follow-ups; we only mark UI state
    {:noreply, push_event(socket, %{kind: "ai", type: "done", at: now_ms()})}
  end

  def handle_info(
        {:session_stream,
         %TheMaestro.Domain.StreamEnvelope{session_id: sid, stream_id: other_id}},
        %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
      )
      when other_id != id do
    {:noreply, socket}
  end

  def handle_info({:session_stream, %TheMaestro.Domain.StreamEnvelope{}}, socket),
    do: {:noreply, socket}

  # Internal: retry the current provider call after a backoff
  def handle_info({:retry_stream, _attempt}, socket), do: {:noreply, do_retry_stream(socket)}

  # Internal tool signals (defensive: accept with or without ref wrapper)
  def handle_info({:__shell_done__, {out, status}}, socket) do
    {:noreply,
     push_event(socket, %{
       kind: "internal",
       type: "shell_done",
       exit_code: status,
       out: out,
       at: now_ms()
     })}
  end

  def handle_info({ref, {:__shell_done__, {out, status}}}, socket) when is_reference(ref) do
    {:noreply,
     push_event(socket, %{
       kind: "internal",
       type: "shell_done",
       exit_code: status,
       out: out,
       at: now_ms()
     })}
  end

  @impl true
  def handle_info(:refresh_mcp_inventory, socket) do
    selected = socket.assigns[:session_mcp_selected_ids] || []

    {:noreply,
     socket
     |> assign(:tool_inventory_by_provider, build_tool_inventory_for_servers(selected))
     |> assign(:mcp_warming, false)}
  end

  defp handle_thinking_event(
         %TheMaestro.Domain.StreamEnvelope{
           session_id: sid,
           stream_id: id,
           event: %TheMaestro.Domain.StreamEvent{type: :thinking}
         },
         %{assigns: %{session: %{id: sid}, stream_id: id}} = socket
       ) do
    {:noreply,
     socket
     |> push_event(%{kind: "ai", type: "thinking", at: now_ms()})
     |> assign(thinking?: true)}
  end

  defp handle_thinking_event(_envelope, socket) do
    {:noreply, socket}
  end

  # ===== Event logging helpers =====
  defp now_ms, do: System.system_time(:millisecond)

  defp push_event(%{assigns: assigns} = socket, ev) when is_map(ev) do
    buf = assigns[:event_buffer] || []
    assign(socket, :event_buffer, buf ++ [ev])
  end

  defp do_retry_stream(socket) do
    case socket.assigns do
      %{pending_canonical: canon, used_provider: provider}
      when is_map(canon) and not is_nil(provider) ->
        model =
          socket.assigns.used_model ||
            TheMaestro.Chat.resolve_model_for_session(socket.assigns.session, provider)

        {:ok, provider_msgs} = Conversations.Translator.to_provider(canon, provider)

        {:ok, stream_id} =
          TheMaestro.Chat.start_stream(
            socket.assigns.session.id,
            provider,
            socket.assigns.used_auth_name,
            provider_msgs,
            model
          )

        socket
        |> assign(:stream_id, stream_id)
        |> assign(:stream_task, nil)
        |> assign(:used_provider, provider)
        |> assign(:used_model, model)
        |> assign(:used_usage, nil)
        |> assign(:thinking?, false)

      _ ->
        socket
    end
  end

  # Detect Anthropic overloaded errors from error strings
  defp anth_overloaded?(err) when is_binary(err) do
    down = String.downcase(err)
    if has_overloaded?(down), do: true, else: parse_overload_json(err) == :overloaded
  end

  defp has_overloaded?(down) when is_binary(down) do
    String.contains?(down, "overloaded_error") or String.contains?(down, "\"overloaded\"")
  end

  defp parse_overload_json(err) when is_binary(err) do
    with {idx, _len} <- :binary.match(err, "{"),
         {:ok, map} <- Jason.decode(String.slice(err, idx..-1)),
         t when is_binary(t) <- get_in(map, ["error", "type"]) || map["type"] do
      if String.contains?(String.downcase(t), "overloaded"), do: :overloaded, else: :no
    else
      _ -> :no
    end
  end

  # ---- Session helpers (derive provider/auth from SavedAuth) ----
  # provider/auth helpers moved to Chat facade

  defp default_provider(session) do
    session
    |> TheMaestro.Chat.provider_for_session()
    |> Atom.to_string()
  end

  defp load_auth_options(socket, form) do
    provider_value = form["provider"] || default_provider(socket.assigns.session)

    # Accept provider as string for Auth context (it normalizes input)
    opts =
      Auth.list_saved_authentications_by_provider(provider_value)
      |> Enum.map(fn sa ->
        label = "#{sa.name} (#{Atom.to_string(sa.auth_type)})"
        {label, sa.id}
      end)

    assign(socket, :config_form, Map.put(form, "auth_options", opts))
  end

  defp load_persona_options(socket) do
    opts =
      SuppliedContext.list_items(:persona)
      |> Enum.map(fn p -> {p.name, p.id} end)

    socket
    |> assign(:config_persona_options, opts)
  end

  defp get_persona_for_form(form) do
    case form["persona_id"] do
      nil ->
        nil

      "" ->
        nil

      id ->
        try do
          SuppliedContext.get_item!(to_string(id))
        rescue
          _ -> nil
        end
    end
  end

  defp list_models_for_form(form) do
    with p when is_binary(p) <- form["provider"],
         a when a not in [nil, ""] <- form["auth_id"] do
      provider = to_provider_atom(p)
      auth = Auth.get_saved_authentication!(a)

      case TheMaestro.Provider.list_models(provider, auth.auth_type, auth.name) do
        {:ok, models} -> Enum.map(models, & &1.id)
        {:error, _} -> []
      end
    else
      _ -> []
    end
  end

  # Convert a provider string to a known atom safely; default to :openai
  defp to_provider_atom(p) when is_binary(p) do
    allowed = TheMaestro.Provider.list_providers()
    allowed_strings = Enum.map(allowed, &Atom.to_string/1)

    if p in allowed_strings do
      String.to_existing_atom(p)
    else
      :openai
    end
  end

  defp safe_decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      {:ok, _} -> {:error, {:decode, :json, :must_be_object}}
      {:error, reason} -> {:error, {:decode, :json, reason}}
    end
  end

  # ==== Config helpers (kept at bottom to keep handle_event/handle_info clauses contiguous) ====
  defp maybe_reload_auth_options(socket, params, form) do
    if Map.has_key?(params, "provider") do
      socket = socket |> load_auth_options(form) |> assign(:config_models, [])
      new_form = socket.assigns.config_form
      opts = new_form["auth_options"] || []

      new_auth_id =
        case opts do
          [{_l, id} | _] -> id
          _ -> nil
        end

      assign(socket, :config_form, Map.put(new_form, "auth_id", new_auth_id))
    else
      socket
    end
  end

  defp maybe_reload_models(socket, params) do
    if Map.has_key?(params, "auth_id") do
      models = list_models_for_form(socket.assigns.config_form)
      assign(socket, :config_models, models)
    else
      socket
    end
  end

  # Provide an empty builder map keyed by providers
  defp empty_builder do
    %{openai: [], anthropic: [], gemini: []}
  end

  defp maybe_mirror_persona(socket, params, form) do
    if Map.has_key?(params, "persona_id") do
      case get_persona_for_form(form) do
        nil ->
          socket

        %TheMaestro.SuppliedContext.SuppliedContextItem{} = p ->
          pj =
            Jason.encode!(%{
              "name" => p.name,
              "version" => p.version || 1,
              "persona_text" => p.text
            })

          assign(socket, :config_form, Map.put(socket.assigns.config_form, "persona_json", pj))
      end
    else
      socket
    end
  end

  defp maybe_update_mcp_selection(socket, params) do
    # Component owns MCP selection state; ignore change echo from form params
    socket
  end

  defp normalize_mcp_ids(nil), do: []

  defp normalize_mcp_ids(ids) when is_list(ids),
    do: ids |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

  defp normalize_mcp_ids(id), do: normalize_mcp_ids([id])

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
      {:ok, _} ->
        :ok

      _ ->
        server = MCP.get_server!(sid)

        case MCP.Client.discover_server(server) do
          {:ok, %{tools: tools}} ->
            ttl_ms = compute_tools_cache_ttl(server.metadata)
            _ = MCP.ToolsCache.put(sid, tools, ttl_ms)
            :ok

          _ ->
            :ok
        end
    end
  end

  defp compute_tools_cache_ttl(%{} = metadata),
    do: to_int(metadata["tool_cache_ttl_minutes"] || 60) * 60_000

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 60
    end
  end

  defp to_int(_), do: 60

  defp append_assistant_message(messages, final_text, meta) do
    assistant_msg = build_assistant_message(final_text, meta)
    messages ++ [assistant_msg]
  end

  defp build_assistant_message(text, meta) do
    %{
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => text}],
      "_meta" => meta
    }
  end

  defp dedup_delta(current, chunk) when is_binary(current) and is_binary(chunk) do
    cond do
      chunk == "" ->
        ""

      String.starts_with?(chunk, current) ->
        binary_part(chunk, byte_size(current), byte_size(chunk) - byte_size(current))

      # snapshot smaller than what we have
      String.starts_with?(current, chunk) ->
        ""

      true ->
        chunk
    end
  end

  defp current_messages_for(session_id, nil) do
    case Conversations.latest_snapshot(session_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  defp current_messages_for(_session_id, thread_id) when is_binary(thread_id) do
    case Conversations.latest_snapshot_for_thread(thread_id) do
      %{combined_chat: %{"messages" => msgs}} -> msgs
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} show_header={false} main_class="p-0" container_class="p-0">
      <div class="min-h-screen bg-black text-amber-400 font-mono relative overflow-hidden">
        <div class="container mx-auto px-6 py-8">
          <div class="flex justify-between items-center mb-6 border-b border-amber-600 pb-4">
            <h1 class="text-3xl md:text-4xl font-bold text-amber-400 glow tracking-wider">
              &gt;&gt;&gt; SESSION CHAT: {@session.name || "Session"} &lt;&lt;&lt;
            </h1>
            <div class="flex items-center gap-2">
              <%= if @current_thread_label do %>
                <form phx-submit="rename_thread" class="flex items-center gap-2">
                  <input
                    type="text"
                    name="label"
                    value={@current_thread_label}
                    class="input input-xs"
                  />
                  <button class="btn btn-xs" type="submit">Rename</button>
                </form>
              <% end %>
              <button class="btn btn-amber btn-xs" phx-click="new_thread">Start New Chat</button>
              <button class="btn btn-red btn-xs" phx-click="confirm_clear_chat">Clear Chat</button>
              <button class="btn btn-blue btn-xs" phx-click="open_config">Config</button>
            </div>
            <.link
              navigate={~p"/dashboard"}
              class="px-4 py-2 rounded transition-all duration-200 btn-amber"
              data-hotkey="alt+b"
              data-hotkey-seq="g d"
              data-hotkey-label="Go to Dashboard"
            >
              <.icon name="hero-arrow-left" class="inline mr-2 w-4 h-4" /> BACK
            </.link>
          </div>

          <div class="sticky top-0 z-10 bg-black/90 border-b border-amber-600 -mt-2 mb-4 py-2 px-2 text-xs text-amber-300">
            <%= if s = @summary do %>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
                <div class="glow">
                  last: {s.provider}, {s.model}, {s.auth_type}{if s.auth_name,
                    do: "(" <> s.auth_name <> ")"}
                </div>
                <div>avg latency: {s.avg_latency_ms} ms</div>
                <%= if s[:total_tokens] do %>
                  <div>last turn tokens: {compact_int(s.total_tokens)}</div>
                <% end %>
              </div>
            <% else %>
              <div class="opacity-70">No summary yet</div>
            <% end %>
          </div>

          <div class="space-y-3">
            <%= for msg <- @messages do %>
              <div class={"terminal-card p-3 " <> if msg["role"] == "user", do: "terminal-border-amber", else: "terminal-border-blue"}>
                <div class="text-xs opacity-80">
                  {msg["role"]}
                  <%= if m = msg["_meta"] do %>
                    ( {m["provider"]}, {m["model"]}, {m["auth_type"]}
                    <%= if u = m["usage"] do %>
                      , total {compact_int(token_total(u))}
                    <% end %>
                    <%= if m["latency_ms"] do %>
                      , {m["latency_ms"]}ms
                    <% end %>
                    )
                  <% end %>
                </div>
                <div class="whitespace-pre-wrap text-sm text-amber-200">
                  <.render_text chat={%{"messages" => [msg]}} />
                </div>
                <%= if m = msg["_meta"] do %>
                  <details class="mt-1 opacity-80 text-xs">
                    <summary>details</summary>
                    <div>provider: {m["provider"]}</div>
                    <div>model: {m["model"]}</div>
                    <div>auth: {m["auth_type"]} ({m["auth_name"]})</div>
                    <%= if u = m["usage"] do %>
                      <div>
                        tokens: prompt {compact_int(u["prompt_tokens"] || u[:prompt_tokens] || 0)}, completion {compact_int(
                          u["completion_tokens"] || u[:completion_tokens] || 0
                        )}, total {compact_int(token_total(u))}
                      </div>
                    <% end %>
                    <%= if is_list(m["tools"]) and m["tools"] != [] do %>
                      <div class="mt-1">tools:</div>
                      <ul class="list-disc ml-4">
                        <%= for t <- m["tools"] do %>
                          <li>
                            <code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 120)}
                          </li>
                        <% end %>
                      </ul>
                    <% end %>
                    <%= if m["latency_ms"] do %>
                      <div>latency: {m["latency_ms"]} ms</div>
                    <% end %>
                  </details>
                <% end %>
              </div>
            <% end %>

            <%= if @streaming? and is_list(@tool_calls) and @tool_calls != [] do %>
              <div class="terminal-card terminal-border-amber p-3">
                <div class="text-xs opacity-80">tool activity</div>
                <ul class="list-disc ml-4 text-sm text-amber-200">
                  <%= for t <- @tool_calls do %>
                    <li><code>{t["name"]}</code> {String.slice(t["arguments"] || "", 0, 160)}</li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%= if @streaming? and @partial_answer == "" and @thinking? do %>
              <div class="terminal-card terminal-border-blue p-3">
                <div class="text-xs opacity-80">assistant</div>
                <div class="opacity-80 italic text-sm text-amber-200">thinking…</div>
              </div>
            <% end %>

            <%= if @streaming? and @partial_answer != "" do %>
              <div class="terminal-card terminal-border-blue p-3">
                <div class="text-xs opacity-80">
                  assistant
                  <%= if @used_provider do %>
                    ( {Atom.to_string(@used_provider)}, {@used_model}, {to_string(
                      @used_auth_type || ""
                    )}
                    <%= if u = @used_usage do %>
                      , total {compact_int(token_total(u))}
                    <% end %>
                    )
                  <% end %>
                </div>
                <div class="whitespace-pre-wrap text-sm text-amber-200">{@partial_answer}</div>
                <%= if u = @used_usage do %>
                  <details class="mt-1 opacity-80 text-xs">
                    <summary>details</summary>
                    <div>provider: {Atom.to_string(@used_provider)}</div>
                    <div>model: {@used_model}</div>
                    <div>auth: {to_string(@used_auth_type || "")} ({@used_auth_name})</div>
                    <div>
                      tokens: prompt {compact_int(u[:prompt_tokens] || u["prompt_tokens"] || 0)}, completion {compact_int(
                        u[:completion_tokens] || u["completion_tokens"] || 0
                      )}, total {compact_int(token_total(u))}
                    </div>
                  </details>
                <% end %>
              </div>
            <% end %>
          </div>

          <.form for={%{}} phx-submit="send" class="mt-6">
            <textarea
              id="chat-input"
              name="message"
              class="textarea-terminal"
              rows="4"
              value={@message}
              phx-change="change"
              phx-hook="ChatInput"
            ></textarea>
            <div class="mt-2">
              <button type="submit" class="px-4 py-2 rounded transition-all duration-200 btn-blue">
                Send
              </button>
            </div>
          </.form>

          <div class="mt-8">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-lg font-bold text-green-400 glow">LATEST_SNAPSHOT.JSON</h3>
              <%= if @editing_latest do %>
                <button class="px-2 py-1 rounded text-xs btn-amber" phx-click="cancel_edit_latest">
                  CANCEL
                </button>
              <% else %>
                <button class="px-2 py-1 rounded text-xs btn-amber" phx-click="start_edit_latest">
                  EDIT
                </button>
              <% end %>
            </div>
            <%= if @editing_latest do %>
              <.form for={%{}} phx-submit="save_edit_latest">
                <textarea
                  name="json"
                  class="textarea-terminal font-mono text-xs"
                  rows="10"
                ><%= @latest_json %></textarea>
                <div class="mt-2">
                  <button type="submit" class="px-3 py-1 rounded btn-blue text-sm">
                    Save Snapshot
                  </button>
                </div>
              </.form>
            <% else %>
              <div class="text-xs opacity-80 text-amber-300">
                Editing allows trimming or correcting the current context (full copy). Changes bump edit_version.
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <.live_component module={TheMaestroWeb.ShortcutsOverlay} id="shortcuts-overlay" />

      <.modal :if={@show_clear_confirm} id="clear-chat-confirm">
        <div class="p-4">
          <h3 class="text-lg font-bold mb-2">Clear Current Chat?</h3>
          <p class="mb-4">
            This will permanently delete the current thread history. This cannot be undone.
          </p>
          <div class="flex gap-2">
            <button class="btn btn-red" phx-click="do_clear_chat">Delete</button>
            <button class="btn" phx-click="cancel_clear_chat">Cancel</button>
          </div>
        </div>
      </.modal>

      <.modal :if={@show_config} id="session-config-modal">
        <div class="flex flex-col max-h-[80vh]">
          <.form
            for={%{}}
            phx-change="validate_config"
            phx-submit="save_config"
            id="session-config-form"
            class="flex flex-col max-h-[80vh] min-h-0"
          >
            <h3 class="text-lg font-bold mb-2">Session Config</h3>
            <div class="flex-1 overflow-y-auto min-h-0 pr-1">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <label class="text-xs">Provider (filter)</label>
                  <select name="provider" class="input">
                    <%= for p <- ["openai", "anthropic", "gemini"] do %>
                      <option value={p} selected={@config_form["provider"] == p}>{p}</option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="text-xs">Saved Auth</label>
                  <select name="auth_id" class="input">
                    <%= for {label, id} <- (@config_form["auth_options"] || []) do %>
                      <option
                        value={id}
                        selected={to_string(id) == to_string(@config_form["auth_id"])}
                      >
                        {label}
                      </option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="text-xs">Model</label>
                  <select name="model_id" class="input">
                    <%= for m <- (@config_models || []) do %>
                      <option value={m} selected={m == @config_form["model_id"]}>{m}</option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="text-xs">Working Dir</label>
                  <input
                    type="text"
                    name="working_dir"
                    value={@config_form["working_dir"] || @session.working_dir}
                    class="input"
                  />
                </div>
                <!-- Shared sections via component to keep parity with Create modal -->
                <.live_component
                  module={TheMaestroWeb.SessionFormComponent}
                  id="session-config-form-body"
                  mode={:edit}
                  provider={@prompt_picker_provider || :openai}
                  prompt_picker_provider={@prompt_picker_provider || :openai}
                  session_prompt_builder={@session_prompt_builder || %{}}
                  prompt_library={@prompt_library || %{}}
                  prompt_picker_selection={@prompt_picker_selection || %{}}
                  ui_sections={@ui_sections || %{prompt: true, persona: true, memory: true}}
                  config_persona_options={@config_persona_options || []}
                  config_form={Map.put(@config_form || %{}, "session_id", @session.id)}
                  mcp_server_options={@mcp_server_options || []}
                  session_mcp_selected_ids={@session_mcp_selected_ids || []}
                  tool_picker_allowed={@tool_picker_allowed || %{}}
                />
              </div>
              <div class="mt-3">
                <label class="text-xs">When saving while streaming</label>
                <div class="flex gap-3 text-sm">
                  <label>
                    <input type="radio" name="apply" value="now" checked /> Apply now (restart stream)
                  </label>
                  <label><input type="radio" name="apply" value="defer" /> Apply on next turn</label>
                </div>
              </div>
            </div>
            <div class="sticky bottom-0 z-30 mt-3 border-t border-base-300 bg-base-100 pt-3">
              <div class="flex justify-end gap-2">
                <button
                  class="btn btn-blue"
                  type="button"
                  phx-click={JS.dispatch("submit", to: "#session-config-form")}
                >
                  Save
                </button>
                <button class="btn" type="button" phx-click="close_config">Cancel</button>
              </div>
            </div>
          </.form>
          <.modal :if={@show_mcp_modal} id="session-mcp-modal">
            <.live_component
              module={TheMaestroWeb.MCPServersLive.FormComponent}
              id="session-mcp-form"
              title="New MCP Server"
              server={%TheMaestro.MCP.Servers{}}
              action={:new}
            />
          </.modal>
        </div>
      </.modal>

      <.modal :if={@show_persona_modal} id="persona-modal">
        <.form for={%{}} phx-submit="save_persona" id="persona-form">
          <h3 class="text-lg font-bold mb-2">Add Persona</h3>
          <div class="grid grid-cols-1 gap-2">
            <div>
              <label class="text-xs">Name</label>
              <input type="text" name="name" class="input" />
            </div>
            <div>
              <label class="text-xs">Prompt Text</label>
              <textarea name="prompt_text" rows="6" class="textarea-terminal"></textarea>
            </div>
          </div>
          <div class="mt-3 flex gap-2">
            <button class="btn btn-blue" type="submit">Save</button>
            <button class="btn" type="button" phx-click="cancel_persona_modal">Cancel</button>
          </div>
        </.form>
      </.modal>

      <.modal :if={@show_memory_modal} id="memory-modal">
        <.form for={%{}} phx-submit="save_memory_modal" id="memory-form">
          <h3 class="text-lg font-bold mb-2">Memory — Advanced JSON Editor</h3>
          <textarea name="memory_json" rows="12" class="textarea-terminal"><%= @memory_editor_text %></textarea>
          <div class="mt-3 flex gap-2">
            <button class="btn btn-blue" type="submit">Save</button>
            <button class="btn" type="button" phx-click="cancel_memory_modal">Cancel</button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  attr :chat, :map, required: true

  defp render_text(assigns) do
    messages = Map.get(assigns.chat, "messages", [])

    text =
      messages
      |> Enum.map(fn %{"role" => role, "content" => parts} ->
        role <>
          ": " <>
          (parts
           |> Enum.map(fn
             %{"type" => "text", "text" => t} -> t
             %{"text" => t} -> t
             t when is_binary(t) -> t
             _ -> ""
           end)
           |> Enum.join("\n"))
      end)
      |> Enum.join("\n\n")

    assigns = assign(assigns, :text, text)

    ~H"""
    {@text}
    """
  end

  # ===== Helpers for summary/formatting =====
  defp token_total(u) do
    u["total_tokens"] || u[:total_tokens] ||
      (u["prompt_tokens"] || u[:prompt_tokens] || 0) +
        (u["completion_tokens"] || u[:completion_tokens] || 0)
  end

  defp compact_int(n) when is_integer(n) and n >= 1000 do
    :erlang.float_to_binary(n / 1000, [:compact, {:decimals, 1}]) <> "k"
  end

  defp compact_int(n) when is_integer(n), do: Integer.to_string(n)
  defp compact_int(_), do: "0"

  defp compute_summary(messages) when is_list(messages) do
    assistants =
      messages
      |> Enum.filter(&(&1["role"] == "assistant"))

    last = assistants |> List.last()

    latencies =
      assistants
      |> Enum.map(fn m -> get_in(m, ["_meta", "latency_ms"]) end)
      |> Enum.filter(&is_integer/1)

    avg =
      case latencies do
        [] -> nil
        list -> div(Enum.sum(list), length(list))
      end

    if last && last["_meta"] do
      m = last["_meta"]

      %{
        provider: m["provider"],
        model: m["model"],
        auth_type: m["auth_type"],
        auth_name: m["auth_name"],
        avg_latency_ms: avg || 0,
        total_tokens: token_total(m["usage"] || %{})
      }
    else
      nil
    end
  end

  defp compute_summary(_), do: nil

  defp update_prompt_enabled_status(list, prompt_id, desired) do
    Enum.map(list, fn
      %{id: ^prompt_id} = e -> %{e | enabled: desired}
      e -> e
    end)
  end

  defp build_provider_entries(session_id, provider) do
    case TheMaestro.SystemPrompts.list_session_prompts(session_id, provider) do
      [] -> build_default_entries(provider)
      items when is_list(items) -> build_session_entries(items)
    end
  end

  defp build_default_entries(provider) do
    stack = TheMaestro.SystemPrompts.default_stack(provider)

    Enum.map(stack.prompts, fn %{prompt: p, overrides: ov} ->
      %{
        id: p.id,
        prompt: p,
        enabled: true,
        overrides: ov || %{},
        source: stack.source
      }
    end)
  end

  defp build_session_entries(items) do
    Enum.map(items, fn spi ->
      %{
        id: spi.supplied_context_item_id,
        prompt: spi.prompt,
        enabled: spi.enabled,
        overrides: spi.overrides || %{},
        source: :session
      }
    end)
  end
end
