# Story 8.4: TUI Persona Management Flow

## User Story

**As a** user of TheMaestro's terminal interface
**I want** comprehensive persona management capabilities directly in my terminal
**so that** I can create, edit, organize, and apply personas without leaving my command-line workflow

## Acceptance Criteria

1. **Persona List Interface**: Interactive terminal interface displaying all user personas with filtering, sorting, and navigation
2. **In-Terminal Editor**: Full-featured persona editor with syntax highlighting, validation, and preview modes
3. **Template Integration**: Browse and apply persona templates directly from the terminal interface
4. **Real-time Application**: Apply personas to active agent sessions with immediate feedback and status updates
5. **Search and Discovery**: Full-text search capabilities with incremental filtering and highlighting
6. **Version Management**: View, compare, and rollback to previous persona versions through terminal interface
7. **Import/Export Commands**: Terminal-native file operations for persona import and export workflows
8. **Bulk Operations**: Multi-select and bulk operations for efficient persona management
9. **Performance Analytics**: Terminal-based performance metrics and usage statistics display
10. **Keyboard Navigation**: Comprehensive keyboard shortcuts and navigation for power-user efficiency
11. **Color-coded Status**: Visual indicators for persona state, application status, and validation results
12. **Interactive Wizards**: Guided workflows for common tasks like persona creation and configuration
13. **Contextual Help**: Integrated help system with command hints and usage examples
14. **Session Integration**: Real-time display of which personas are active in which agent sessions
15. **Tag Management**: Interactive tagging and categorization system with autocomplete
16. **Content Validation**: Real-time content validation with error highlighting and suggestions
17. **Diff Visualization**: Visual comparison tools for persona versions and changes
18. **Background Operations**: Non-blocking operations with progress indicators and status updates
19. **Configuration Management**: Terminal-based configuration of persona system settings and preferences
20. **Error Recovery**: Graceful error handling with clear messages and recovery options
21. **Offline Mode**: Limited functionality when network connectivity is unavailable
22. **Extensibility**: Plugin architecture for custom persona management commands and workflows
23. **Cross-platform Compatibility**: Consistent functionality across Linux, macOS, and Windows terminals
24. **Performance Optimization**: Efficient rendering and memory usage for large persona collections
25. **Integration Testing**: Comprehensive testing of all terminal workflows and edge cases

## Technical Implementation

### Main TUI Application Structure

```elixir
# lib/the_maestro/tui/persona_manager.ex
defmodule TheMaestro.TUI.PersonaManager do
  @moduledoc """
  Terminal User Interface for persona management.
  """
  
  use ExTUI.Application
  
  alias TheMaestro.Personas
  alias TheMaestro.Personas.ApplicationEngine
  alias TheMaestro.TUI.PersonaManager.{
    ListScreen,
    EditorScreen,
    TemplateScreen,
    AnalyticsScreen,
    HelpScreen
  }
  
  @default_config %{
    theme: :default,
    editor: :vim,
    auto_save: true,
    show_line_numbers: true,
    syntax_highlighting: true,
    preview_mode: false
  }
  
  def init(opts) do
    user = Keyword.get(opts, :user)
    config = load_user_config(user) |> Map.merge(@default_config)
    
    state = %{
      user: user,
      config: config,
      current_screen: :list,
      personas: [],
      filtered_personas: [],
      selected_persona: nil,
      search_query: "",
      sort_by: :updated_at,
      sort_direction: :desc,
      selected_indices: MapSet.new(),
      status_message: nil,
      error_message: nil,
      active_sessions: [],
      clipboard: nil,
      undo_stack: [],
      redo_stack: []
    }
    
    # Subscribe to persona events
    Phoenix.PubSub.subscribe(TheMaestro.PubSub, "personas:#{user.id}")
    Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agents:#{user.id}")
    
    # Load initial data
    state = 
      state
      |> load_personas()
      |> load_active_sessions()
    
    {:ok, state}
  end
  
  def render(%{current_screen: :list} = state) do
    ListScreen.render(state)
  end
  
  def render(%{current_screen: :editor} = state) do
    EditorScreen.render(state)
  end
  
  def render(%{current_screen: :templates} = state) do
    TemplateScreen.render(state)
  end
  
  def render(%{current_screen: :analytics} = state) do
    AnalyticsScreen.render(state)
  end
  
  def render(%{current_screen: :help} = state) do
    HelpScreen.render(state)
  end
  
  def handle_key_event(key, state) do
    case {state.current_screen, key} do
      # Global shortcuts
      {:any, {:key, :ctrl_q}} -> 
        {:stop, :normal, state}
        
      {:any, {:key, :ctrl_h}} -> 
        {:noreply, %{state | current_screen: :help}}
        
      {:any, {:key, :f1}} -> 
        {:noreply, %{state | current_screen: :help}}
        
      # Screen-specific shortcuts
      {screen, key} -> 
        case screen do
          :list -> handle_list_key(key, state)
          :editor -> handle_editor_key(key, state)
          :templates -> handle_template_key(key, state)
          :analytics -> handle_analytics_key(key, state)
          :help -> handle_help_key(key, state)
        end
    end
  end
  
  def handle_message({:persona_created, persona}, state) do
    if persona.user_id == state.user.id do
      new_state = 
        state
        |> set_status("Persona '#{persona.name}' created successfully")
        |> load_personas()
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_message({:persona_updated, persona}, state) do
    if persona.user_id == state.user.id do
      new_state = 
        state
        |> set_status("Persona '#{persona.name}' updated successfully")
        |> load_personas()
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_message({:persona_applied, agent_id, persona_id}, state) do
    persona = Enum.find(state.personas, &(&1.id == persona_id))
    
    new_state = set_status(state, "Applied persona '#{persona.name}' to agent #{agent_id}")
    {:noreply, new_state}
  end
  
  def handle_message(_message, state) do
    {:noreply, state}
  end
  
  # Private helper functions
  
  defp load_personas(state) do
    personas = Personas.list_personas(state.user.id)
    
    %{state |
      personas: personas,
      filtered_personas: filter_personas(personas, state.search_query)
    }
  end
  
  defp load_active_sessions(state) do
    # Load active agent sessions - placeholder implementation
    sessions = [] # TheMaestro.Agents.list_active_sessions(state.user.id)
    %{state | active_sessions: sessions}
  end
  
  defp filter_personas(personas, ""), do: personas
  defp filter_personas(personas, query) do
    query = String.downcase(query)
    
    Enum.filter(personas, fn persona ->
      String.contains?(String.downcase(persona.name), query) ||
      String.contains?(String.downcase(persona.description || ""), query) ||
      String.contains?(String.downcase(persona.content), query)
    end)
  end
  
  defp set_status(state, message) do
    %{state | status_message: message, error_message: nil}
  end
  
  defp set_error(state, message) do
    %{state | error_message: message, status_message: nil}
  end
  
  defp load_user_config(user) do
    # Load user-specific TUI configuration
    config_path = Path.join([System.user_home!(), ".maestro", "tui_config.json"])
    
    case File.read(config_path) do
      {:ok, content} ->
        Jason.decode!(content, keys: :atoms)
      {:error, _} ->
        %{}
    end
  rescue
    _ -> %{}
  end
  
  # List screen key handlers
  defp handle_list_key({:key, :j}, state), do: move_selection_down(state)
  defp handle_list_key({:key, :k}, state), do: move_selection_up(state)
  defp handle_list_key({:key, :enter}, state), do: edit_selected_persona(state)
  defp handle_list_key({:key, :n}, state), do: create_new_persona(state)
  defp handle_list_key({:key, :d}, state), do: delete_selected_persona(state)
  defp handle_list_key({:key, :a}, state), do: apply_persona_to_session(state)
  defp handle_list_key({:key, :r}, state), do: remove_persona_from_session(state)
  defp handle_list_key({:key, :t}, state), do: {:noreply, %{state | current_screen: :templates}}
  defp handle_list_key({:key, :s}, state), do: {:noreply, %{state | current_screen: :analytics}}
  defp handle_list_key({:key, :/}, state), do: start_search_mode(state)
  defp handle_list_key({:key, :space}, state), do: toggle_selection(state)
  defp handle_list_key({:key, :ctrl_a}, state), do: select_all_personas(state)
  defp handle_list_key({:key, :ctrl_d}, state), do: deselect_all_personas(state)
  defp handle_list_key({:key, :x}, state), do: bulk_delete_selected(state)
  defp handle_list_key({:key, :e}, state), do: export_selected_persona(state)
  defp handle_list_key({:key, :i}, state), do: import_persona(state)
  defp handle_list_key(_key, state), do: {:noreply, state}
  
  # Editor screen key handlers
  defp handle_editor_key({:key, :esc}, state), do: {:noreply, %{state | current_screen: :list}}
  defp handle_editor_key({:key, :ctrl_s}, state), do: save_current_persona(state)
  defp handle_editor_key({:key, :ctrl_p}, state), do: toggle_preview_mode(state)
  defp handle_editor_key({:key, :ctrl_z}, state), do: undo_last_change(state)
  defp handle_editor_key({:key, :ctrl_y}, state), do: redo_last_change(state)
  defp handle_editor_key(key, state), do: handle_editor_input(key, state)
  
  # Template screen key handlers
  defp handle_template_key({:key, :esc}, state), do: {:noreply, %{state | current_screen: :list}}
  defp handle_template_key({:key, :enter}, state), do: apply_selected_template(state)
  defp handle_template_key({:key, :j}, state), do: move_template_selection_down(state)
  defp handle_template_key({:key, :k}, state), do: move_template_selection_up(state)
  defp handle_template_key(_key, state), do: {:noreply, state}
  
  # Analytics screen key handlers
  defp handle_analytics_key({:key, :esc}, state), do: {:noreply, %{state | current_screen: :list}}
  defp handle_analytics_key({:key, :r}, state), do: refresh_analytics(state)
  defp handle_analytics_key(_key, state), do: {:noreply, state}
  
  # Help screen key handlers
  defp handle_help_key({:key, :esc}, state), do: {:noreply, %{state | current_screen: :list}}
  defp handle_help_key({:key, :q}, state), do: {:noreply, %{state | current_screen: :list}}
  defp handle_help_key(_key, state), do: {:noreply, state}
end
```

### List Screen Module

```elixir
# lib/the_maestro/tui/persona_manager/list_screen.ex
defmodule TheMaestro.TUI.PersonaManager.ListScreen do
  @moduledoc """
  Persona list screen for TUI interface.
  """
  
  use ExTUI.Screen
  import ExTUI.Elements
  
  def render(state) do
    screen([
      header(state),
      search_bar(state),
      persona_list(state),
      status_bar(state),
      help_footer()
    ])
  end
  
  defp header(state) do
    row([
      col([
        text("TheMaestro - Persona Manager", style: [bold: true, color: :blue]),
        text("User: #{state.user.email}", style: [color: :dim])
      ], width: 0.7),
      
      col([
        text("Total: #{length(state.personas)}", align: :right),
        text("Filtered: #{length(state.filtered_personas)}", align: :right, style: [color: :dim])
      ], width: 0.3)
    ])
  end
  
  defp search_bar(state) do
    search_text = if state.search_query == "", do: "Search personas... (press '/' to search)", else: state.search_query
    
    box([
      text("🔍 #{search_text}", style: [color: :yellow])
    ], title: "Search", border: :rounded)
  end
  
  defp persona_list(state) do
    headers = [
      {"Name", 25},
      {"Description", 40}, 
      {"Tags", 20},
      {"Size", 8},
      {"Used", 8},
      {"Status", 10}
    ]
    
    rows = Enum.with_index(state.filtered_personas)
    |> Enum.map(fn {persona, index} ->
      selected = MapSet.member?(state.selected_indices, index)
      cursor = (state.cursor_position == index)
      
      status = determine_persona_status(persona, state.active_sessions)
      
      [
        format_name(persona.name, selected, cursor),
        truncate_text(persona.description || "", 38),
        format_tags(persona.tags),
        format_size(persona.size_bytes),
        format_usage(persona.application_count),
        format_status(status)
      ]
    end)
    
    table(headers, rows, [
      title: "Personas (#{length(state.filtered_personas)})",
      border: :rounded,
      header_style: [bold: true, color: :cyan],
      highlight_row: state.cursor_position
    ])
  end
  
  defp status_bar(state) do
    message = cond do
      state.error_message -> 
        text("ERROR: #{state.error_message}", style: [color: :red, bold: true])
      
      state.status_message -> 
        text("INFO: #{state.status_message}", style: [color: :green])
      
      true -> 
        text("Ready", style: [color: :dim])
    end
    
    row([
      col([message], width: 0.8),
      col([
        text("Selected: #{MapSet.size(state.selected_indices)}", align: :right, style: [color: :dim])
      ], width: 0.2)
    ])
  end
  
  defp help_footer do
    help_items = [
      "j/k: Navigate",
      "Enter: Edit",
      "n: New",
      "d: Delete", 
      "a: Apply",
      "Space: Select",
      "/: Search",
      "t: Templates",
      "s: Stats",
      "q: Quit"
    ]
    
    help_text = Enum.join(help_items, " | ")
    
    box([
      text(help_text, style: [color: :dim])
    ], border: :single)
  end
  
  # Helper functions
  
  defp format_name(name, selected, cursor) do
    prefix = cond do
      selected && cursor -> "►● "
      selected -> " ● "
      cursor -> "► "
      true -> "   "
    end
    
    style = cond do
      cursor -> [bold: true, color: :yellow]
      selected -> [color: :cyan]
      true -> []
    end
    
    "#{prefix}#{name}" |> String.slice(0, 22) |> String.pad_trailing(25)
    |> text(style: style)
  end
  
  defp format_tags(tags) do
    tags
    |> Enum.take(2)
    |> Enum.join(", ")
    |> truncate_text(18)
    |> text(style: [color: :magenta])
  end
  
  defp format_size(bytes) do
    cond do
      bytes > 1024 * 1024 -> "#{div(bytes, 1024 * 1024)}MB"
      bytes > 1024 -> "#{div(bytes, 1024)}KB"
      true -> "#{bytes}B"
    end
    |> String.pad_leading(6)
    |> text(style: [color: :dim])
  end
  
  defp format_usage(count) do
    count
    |> to_string()
    |> String.pad_leading(6)
    |> text(style: [color: :blue])
  end
  
  defp format_status(status) do
    {text_val, color} = case status do
      :active -> {"ACTIVE", :green}
      :inactive -> {"READY", :dim}
      :error -> {"ERROR", :red}
    end
    
    text(text_val, style: [color: color])
  end
  
  defp determine_persona_status(persona, active_sessions) do
    if Enum.any?(active_sessions, &(&1.current_persona_id == persona.id)) do
      :active
    else
      :inactive
    end
  end
  
  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      String.pad_trailing(text, max_length)
    end
  end
end
```

### Editor Screen Module

```elixir
# lib/the_maestro/tui/persona_manager/editor_screen.ex
defmodule TheMaestro.TUI.PersonaManager.EditorScreen do
  @moduledoc """
  Persona editor screen for TUI interface.
  """
  
  use ExTUI.Screen
  import ExTUI.Elements
  
  def render(state) do
    persona = state.selected_persona || %TheMaestro.Personas.Persona{}
    
    if state.config.preview_mode do
      dual_pane_view(state, persona)
    else
      single_pane_view(state, persona)
    end
  end
  
  defp single_pane_view(state, persona) do
    screen([
      editor_header(persona, state.config.preview_mode),
      metadata_form(persona),
      content_editor(persona, state),
      editor_status_bar(persona, state),
      editor_help_footer()
    ])
  end
  
  defp dual_pane_view(state, persona) do
    screen([
      editor_header(persona, state.config.preview_mode),
      row([
        col([
          metadata_form(persona),
          content_editor(persona, state)
        ], width: 0.6),
        
        col([
          preview_panel(persona, state)
        ], width: 0.4)
      ]),
      editor_status_bar(persona, state),
      editor_help_footer()
    ])
  end
  
  defp editor_header(persona, preview_mode) do
    title = if persona.id do
      "Edit Persona: #{persona.name} (v#{persona.version})"
    else
      "Create New Persona"
    end
    
    preview_indicator = if preview_mode, do: " [PREVIEW ON]", else: ""
    
    row([
      col([
        text(title, style: [bold: true, color: :blue])
      ], width: 0.8),
      
      col([
        text("#{preview_indicator}", align: :right, style: [color: :yellow])
      ], width: 0.2)
    ])
  end
  
  defp metadata_form(persona) do
    box([
      form_field("Name", persona.name || "", required: true),
      form_field("Display Name", persona.display_name || ""),
      form_field("Description", persona.description || ""),
      form_field("Tags", format_tags_for_edit(persona.tags || [])),
      form_field("Version", persona.version || "1.0.0")
    ], title: "Persona Metadata", border: :rounded)
  end
  
  defp content_editor(persona, state) do
    content = persona.content || ""
    line_count = String.split(content, "\n") |> length()
    
    editor_features = []
    editor_features = if state.config.show_line_numbers, do: [:line_numbers | editor_features], else: editor_features
    editor_features = if state.config.syntax_highlighting, do: [:syntax_highlighting | editor_features], else: editor_features
    
    box([
      text_editor(content, [
        language: :markdown,
        features: editor_features,
        height: 15,
        cursor_position: {state.editor_cursor.line, state.editor_cursor.column}
      ])
    ], title: "Content (#{line_count} lines)", border: :rounded)
  end
  
  defp preview_panel(persona, _state) do
    rendered_content = case persona.content do
      nil -> "No content to preview"
      "" -> "No content to preview"
      content -> 
        try do
          # Simple markdown rendering for TUI
          content
          |> String.replace(~r/^# (.+)$/m, fn _, header -> 
            text(header, style: [bold: true, color: :blue]) |> elem(1)
          end)
          |> String.replace(~r/^## (.+)$/m, fn _, header ->
            text(header, style: [bold: true, color: :cyan]) |> elem(1)
          end)
          |> String.replace(~r/\*\*(.+?)\*\*/m, fn _, bold ->
            text(bold, style: [bold: true]) |> elem(1)
          end)
        rescue
          _ -> content
        end
    end
    
    validation_status = validate_persona_content(persona.content)
    
    box([
      scrollable_text(rendered_content, height: 12),
      validation_indicators(validation_status)
    ], title: "Live Preview", border: :rounded)
  end
  
  defp validation_indicators(status) do
    indicators = []
    
    indicators = if status.has_structure do
      [text("✓ Structure", style: [color: :green]) | indicators]
    else
      [text("⚠ Structure", style: [color: :yellow]) | indicators]
    end
    
    indicators = if status.has_instructions do
      [text("✓ Instructions", style: [color: :green]) | indicators]
    else
      [text("⚠ Instructions", style: [color: :yellow]) | indicators]
    end
    
    indicators = if status.token_count < 1000 do
      [text("✓ Token Count (#{status.token_count})", style: [color: :green]) | indicators]
    else
      [text("⚠ Token Count (#{status.token_count})", style: [color: :yellow]) | indicators]
    end
    
    row([
      col(indicators)
    ])
  end
  
  defp editor_status_bar(persona, state) do
    save_status = if persona.id && state.has_unsaved_changes do
      "MODIFIED"
    else
      "SAVED"
    end
    
    cursor_info = "Line #{state.editor_cursor.line}, Col #{state.editor_cursor.column}"
    mode_info = "Mode: #{state.editor_mode || :normal}"
    
    row([
      col([
        text("Status: #{save_status}", style: [color: save_status == "MODIFIED" && :yellow || :green])
      ], width: 0.3),
      
      col([
        text(cursor_info, align: :center, style: [color: :dim])
      ], width: 0.4),
      
      col([
        text(mode_info, align: :right, style: [color: :dim])
      ], width: 0.3)
    ])
  end
  
  defp editor_help_footer do
    help_items = [
      "Ctrl+S: Save",
      "Ctrl+P: Toggle Preview", 
      "Ctrl+Z: Undo",
      "Ctrl+Y: Redo",
      "Esc: Back",
      "Tab: Next Field"
    ]
    
    help_text = Enum.join(help_items, " | ")
    
    box([
      text(help_text, style: [color: :dim])
    ], border: :single)
  end
  
  # Helper functions
  
  defp form_field(label, value, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    label_text = if required, do: "#{label} *", else: label
    
    row([
      col([
        text("#{label_text}:", style: [bold: true])
      ], width: 0.2),
      
      col([
        input_field(value)
      ], width: 0.8)
    ])
  end
  
  defp format_tags_for_edit(tags) do
    Enum.join(tags, ", ")
  end
  
  defp validate_persona_content(nil), do: %{has_structure: false, has_instructions: false, token_count: 0}
  defp validate_persona_content(""), do: %{has_structure: false, has_instructions: false, token_count: 0}
  defp validate_persona_content(content) do
    %{
      has_structure: String.contains?(content, ["#", "##", "###"]),
      has_instructions: String.contains?(content, ["You are", "Your role", "Instructions"]),
      token_count: div(String.length(content), 4)  # Rough estimate
    }
  end
end
```

### Template Screen Module

```elixir
# lib/the_maestro/tui/persona_manager/template_screen.ex
defmodule TheMaestro.TUI.PersonaManager.TemplateScreen do
  @moduledoc """
  Template selection screen for TUI interface.
  """
  
  use ExTUI.Screen
  import ExTUI.Elements
  
  alias TheMaestro.Personas.PersonaTemplates
  
  def render(state) do
    templates = PersonaTemplates.default_templates()
    
    screen([
      template_header(),
      template_categories(templates),
      template_list(templates, state),
      template_preview(state),
      template_help_footer()
    ])
  end
  
  defp template_header do
    text("Persona Template Gallery", style: [bold: true, color: :magenta])
  end
  
  defp template_categories(templates) do
    categories = templates
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.sort()
    
    category_pills = Enum.map(categories, fn category ->
      text("[#{String.capitalize(category)}]", style: [color: :cyan])
    end)
    
    box([
      row(category_pills)
    ], title: "Categories", border: :rounded)
  end
  
  defp template_list(templates, state) do
    headers = [
      {"Name", 20},
      {"Description", 45},
      {"Category", 15},
      {"Tags", 20}
    ]
    
    rows = templates
    |> Enum.with_index()
    |> Enum.map(fn {template, index} ->
      cursor = (state.template_cursor == index)
      
      [
        format_template_name(template.name, cursor),
        truncate_text(template.description, 43),
        text(String.capitalize(template.category), style: [color: :blue]),
        format_template_tags(template.tags)
      ]
    end)
    
    table(headers, rows, [
      title: "Available Templates",
      border: :rounded,
      header_style: [bold: true, color: :cyan],
      highlight_row: state.template_cursor
    ])
  end
  
  defp template_preview(state) do
    template = get_selected_template(state)
    
    case template do
      nil ->
        box([
          text("No template selected", style: [color: :dim])
        ], title: "Preview", border: :rounded)
        
      template ->
        content_preview = String.split(template.content, "\n")
        |> Enum.take(10)
        |> Enum.join("\n")
        
        box([
          text("Name: #{template.display_name}", style: [bold: true]),
          text("Description: #{template.description}"),
          text("Category: #{String.capitalize(template.category)}", style: [color: :blue]),
          text("Tags: #{Enum.join(template.tags, ", ")}", style: [color: :magenta]),
          text(""),
          text("Content Preview:", style: [bold: true]),
          scrollable_text(content_preview, height: 8)
        ], title: "Template Preview", border: :rounded)
    end
  end
  
  defp template_help_footer do
    help_items = [
      "j/k: Navigate",
      "Enter: Use Template",
      "p: Preview",
      "Esc: Back"
    ]
    
    help_text = Enum.join(help_items, " | ")
    
    box([
      text(help_text, style: [color: :dim])
    ], border: :single)
  end
  
  # Helper functions
  
  defp format_template_name(name, cursor) do
    prefix = if cursor, do: "► ", else: "  "
    style = if cursor, do: [bold: true, color: :yellow], else: []
    
    "#{prefix}#{name}"
    |> String.slice(0, 18)
    |> String.pad_trailing(20)
    |> text(style: style)
  end
  
  defp format_template_tags(tags) do
    tags
    |> Enum.take(2)
    |> Enum.join(", ")
    |> truncate_text(18)
    |> text(style: [color: :magenta])
  end
  
  defp get_selected_template(state) do
    templates = PersonaTemplates.default_templates()
    Enum.at(templates, state.template_cursor)
  end
  
  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      String.pad_trailing(text, max_length)
    end
  end
end
```

### Analytics Screen Module

```elixir
# lib/the_maestro/tui/persona_manager/analytics_screen.ex
defmodule TheMaestro.TUI.PersonaManager.AnalyticsScreen do
  @moduledoc """
  Persona analytics and performance screen for TUI interface.
  """
  
  use ExTUI.Screen
  import ExTUI.Elements
  
  alias TheMaestro.Personas.PerformanceMonitor
  
  def render(state) do
    global_stats = PerformanceMonitor.get_global_stats()
    persona_stats = get_persona_statistics(state.personas)
    
    screen([
      analytics_header(),
      row([
        col([
          global_performance_panel(global_stats),
          usage_trends_panel(persona_stats)
        ], width: 0.5),
        
        col([
          top_personas_panel(persona_stats),
          recent_activity_panel(state.personas)
        ], width: 0.5)
      ]),
      analytics_help_footer()
    ])
  end
  
  defp analytics_header do
    text("Persona Performance Analytics", style: [bold: true, color: :green])
  end
  
  defp global_performance_panel(stats) do
    box([
      metric_row("Total Applications", stats.total_applications),
      metric_row("Avg Load Time", "#{Float.round(stats.avg_load_time, 2)}ms"),
      metric_row("Cache Hit Rate", "#{Float.round(stats.cache_hit_rate * 100, 1)}%"),
      text(""),
      performance_indicator("System Health", calculate_system_health(stats))
    ], title: "Global Performance", border: :rounded)
  end
  
  defp usage_trends_panel(persona_stats) do
    total_usage = persona_stats.total_applications
    avg_size = persona_stats.avg_size_bytes
    
    box([
      metric_row("Active Personas", persona_stats.active_count),
      metric_row("Total Usage", total_usage),
      metric_row("Avg Persona Size", "#{div(avg_size, 1024)}KB"),
      text(""),
      usage_chart(persona_stats.usage_history)
    ], title: "Usage Trends", border: :rounded)
  end
  
  defp top_personas_panel(persona_stats) do
    top_personas = persona_stats.top_used
    |> Enum.take(5)
    
    persona_rows = Enum.map(top_personas, fn {name, count} ->
      bar_length = min(div(count * 20, persona_stats.max_usage), 20)
      bar = String.duplicate("█", bar_length) <> String.duplicate("░", 20 - bar_length)
      
      row([
        col([text(truncate_string(name, 15))], width: 0.4),
        col([text(bar, style: [color: :blue])], width: 0.4),
        col([text("#{count}", align: :right, style: [color: :yellow])], width: 0.2)
      ])
    end)
    
    box([
      text("Most Used Personas", style: [bold: true]),
      text("") | persona_rows
    ], title: "Top Performers", border: :rounded)
  end
  
  defp recent_activity_panel(personas) do
    recent_personas = personas
    |> Enum.filter(& &1.last_applied_at)
    |> Enum.sort_by(& &1.last_applied_at, {:desc, NaiveDateTime})
    |> Enum.take(8)
    
    activity_rows = Enum.map(recent_personas, fn persona ->
      time_ago = format_time_ago(persona.last_applied_at)
      
      row([
        col([text(truncate_string(persona.name, 15))], width: 0.6),
        col([text(time_ago, align: :right, style: [color: :dim])], width: 0.4)
      ])
    end)
    
    box([
      text("Recent Activity", style: [bold: true]),
      text("") | activity_rows
    ], title: "Recent Usage", border: :rounded)
  end
  
  defp analytics_help_footer do
    help_items = [
      "r: Refresh",
      "e: Export Report", 
      "f: Filter Data",
      "Esc: Back"
    ]
    
    help_text = Enum.join(help_items, " | ")
    
    box([
      text(help_text, style: [color: :dim])
    ], border: :single)
  end
  
  # Helper functions
  
  defp metric_row(label, value) do
    row([
      col([text("#{label}:", style: [color: :dim])], width: 0.6),
      col([text("#{value}", style: [bold: true], align: :right)], width: 0.4)
    ])
  end
  
  defp performance_indicator(label, health_score) do
    {status, color} = cond do
      health_score >= 0.8 -> {"EXCELLENT", :green}
      health_score >= 0.6 -> {"GOOD", :blue}
      health_score >= 0.4 -> {"FAIR", :yellow}
      true -> {"POOR", :red}
    end
    
    row([
      col([text("#{label}:", style: [color: :dim])], width: 0.6),
      col([text(status, style: [bold: true, color: color], align: :right)], width: 0.4)
    ])
  end
  
  defp usage_chart(history) do
    # Simple ASCII chart for usage trends
    max_val = Enum.max(history ++ [1])
    
    chart_rows = history
    |> Enum.take(-10)  # Last 10 data points
    |> Enum.map(fn val ->
      height = div(val * 5, max_val)
      String.duplicate("▁", 5 - height) <> String.duplicate("█", height)
    end)
    |> Enum.join(" ")
    
    text(chart_rows, style: [color: :cyan])
  end
  
  defp get_persona_statistics(personas) do
    active_personas = Enum.filter(personas, & &1.is_active)
    total_applications = Enum.sum(Enum.map(personas, & &1.application_count))
    avg_size = if length(personas) > 0 do
      Enum.sum(Enum.map(personas, & &1.size_bytes)) / length(personas)
    else
      0
    end
    
    top_used = personas
    |> Enum.map(&{&1.name, &1.application_count})
    |> Enum.sort_by(&elem(&1, 1), :desc)
    
    max_usage = case top_used do
      [] -> 1
      [{_, count} | _] -> max(count, 1)
    end
    
    %{
      active_count: length(active_personas),
      total_applications: total_applications,
      avg_size_bytes: round(avg_size),
      top_used: top_used,
      max_usage: max_usage,
      usage_history: generate_usage_history()  # Mock data for now
    }
  end
  
  defp calculate_system_health(stats) do
    # Simple health calculation based on performance metrics
    cache_score = stats.cache_hit_rate
    load_score = if stats.avg_load_time < 50, do: 1.0, else: max(0.0, 1.0 - stats.avg_load_time / 200)
    
    (cache_score + load_score) / 2
  end
  
  defp generate_usage_history do
    # Generate mock usage history - in real implementation, this would come from analytics
    1..10 |> Enum.map(fn _ -> :rand.uniform(20) end)
  end
  
  defp format_time_ago(datetime) do
    case NaiveDateTime.diff(NaiveDateTime.utc_now(), datetime, :second) do
      seconds when seconds < 60 -> "#{seconds}s ago"
      seconds when seconds < 3600 -> "#{div(seconds, 60)}m ago" 
      seconds when seconds < 86400 -> "#{div(seconds, 3600)}h ago"
      seconds -> "#{div(seconds, 86400)}d ago"
    end
  end
  
  defp truncate_string(str, max_length) do
    if String.length(str) > max_length do
      String.slice(str, 0, max_length - 3) <> "..."
    else
      str
    end
  end
end
```

### Command Line Interface

```elixir
# lib/the_maestro/tui/cli.ex (additions for persona management)
defmodule TheMaestro.TUI.CLI do
  # ... existing code ...
  
  def personas(args \\ []) do
    case parse_persona_args(args) do
      {:ok, opts} ->
        user = get_authenticated_user()
        
        case Keyword.get(opts, :action, :manage) do
          :manage -> 
            TheMaestro.TUI.PersonaManager.start(user: user)
            
          :list ->
            list_personas(user, opts)
            
          :create ->
            create_persona_interactive(user, opts)
            
          :apply ->
            apply_persona_command(user, opts)
            
          :import ->
            import_persona_command(user, opts)
            
          :export ->
            export_persona_command(user, opts)
        end
        
      {:error, message} ->
        IO.puts("Error: #{message}")
        print_persona_help()
    end
  end
  
  defp parse_persona_args(args) do
    case OptionParser.parse(args, 
      strict: [
        action: :string,
        name: :string,
        file: :string,
        agent: :string,
        template: :string
      ],
      aliases: [
        a: :action,
        n: :name,
        f: :file,
        t: :template
      ]
    ) do
      {opts, [], []} ->
        {:ok, opts}
        
      {_, invalid_args, []} when invalid_args != [] ->
        {:error, "Unknown arguments: #{Enum.join(invalid_args, ", ")}"}
        
      {_, _, errors} ->
        {:error, "Invalid options: #{inspect(errors)}"}
    end
  end
  
  defp list_personas(user, opts) do
    personas = TheMaestro.Personas.list_personas(user.id)
    
    if personas == [] do
      IO.puts("No personas found. Create one with 'maestro personas --action create'")
    else
      print_persona_table(personas)
    end
  end
  
  defp create_persona_interactive(user, opts) do
    name = get_input("Persona name", Keyword.get(opts, :name))
    display_name = get_input("Display name (optional)", "")
    description = get_input("Description (optional)", "")
    
    template_name = Keyword.get(opts, :template)
    content = if template_name do
      case get_template_content(template_name) do
        {:ok, content} -> content
        {:error, _} ->
          IO.puts("Template '#{template_name}' not found. Using empty content.")
          ""
      end
    else
      get_multiline_input("Persona content (end with Ctrl+D)")
    end
    
    attrs = %{
      name: name,
      display_name: if(display_name == "", do: nil, else: display_name),
      description: if(description == "", do: nil, else: description),
      content: content,
      user_id: user.id
    }
    
    case TheMaestro.Personas.create_persona(attrs) do
      {:ok, persona} ->
        IO.puts("✓ Created persona '#{persona.name}' successfully!")
        
      {:error, changeset} ->
        IO.puts("✗ Failed to create persona:")
        print_changeset_errors(changeset)
    end
  end
  
  defp apply_persona_command(user, opts) do
    persona_name = Keyword.get(opts, :name)
    agent_name = Keyword.get(opts, :agent, "default")
    
    unless persona_name do
      IO.puts("Error: Persona name is required. Use --name option.")
      return
    end
    
    case TheMaestro.Personas.get_persona_by_name(user.id, persona_name) do
      nil ->
        IO.puts("Error: Persona '#{persona_name}' not found.")
        
      persona ->
        agent_pid = String.to_atom("agent_#{agent_name}")
        
        case TheMaestro.Personas.ApplicationEngine.apply_persona(agent_pid, persona.id) do
          {:ok, _} ->
            IO.puts("✓ Applied persona '#{persona_name}' to agent '#{agent_name}'")
            
          {:error, reason} ->
            IO.puts("✗ Failed to apply persona: #{reason}")
        end
    end
  end
  
  defp import_persona_command(user, opts) do
    file_path = Keyword.get(opts, :file)
    
    unless file_path do
      IO.puts("Error: File path is required. Use --file option.")
      return
    end
    
    case TheMaestro.Personas.import_from_markdown(user.id, file_path) do
      {:ok, persona} ->
        IO.puts("✓ Imported persona '#{persona.name}' from #{file_path}")
        
      {:error, reason} ->
        IO.puts("✗ Failed to import persona: #{reason}")
    end
  end
  
  defp export_persona_command(user, opts) do
    persona_name = Keyword.get(opts, :name)
    output_file = Keyword.get(opts, :file, "#{persona_name}.md")
    
    unless persona_name do
      IO.puts("Error: Persona name is required. Use --name option.")
      return
    end
    
    case TheMaestro.Personas.get_persona_by_name(user.id, persona_name) do
      nil ->
        IO.puts("Error: Persona '#{persona_name}' not found.")
        
      persona ->
        case TheMaestro.Personas.export_to_markdown(persona) do
          {:ok, content} ->
            File.write!(output_file, content)
            IO.puts("✓ Exported persona '#{persona_name}' to #{output_file}")
            
          {:error, reason} ->
            IO.puts("✗ Failed to export persona: #{reason}")
        end
    end
  end
  
  defp print_persona_table(personas) do
    headers = ["Name", "Description", "Tags", "Size", "Used", "Modified"]
    
    rows = Enum.map(personas, fn persona ->
      [
        persona.name,
        String.slice(persona.description || "", 0, 30),
        Enum.join(persona.tags, ", ") |> String.slice(0, 15),
        format_bytes(persona.size_bytes),
        to_string(persona.application_count),
        format_datetime(persona.updated_at)
      ]
    end)
    
    TableFormatter.print_table(headers, rows)
  end
  
  defp print_persona_help do
    IO.puts("""
    Persona Management Commands:
    
    maestro personas                    # Open interactive persona manager
    maestro personas --action list     # List all personas
    maestro personas --action create   # Create new persona interactively
    maestro personas --action apply --name PERSONA --agent AGENT
    maestro personas --action import --file FILE.md
    maestro personas --action export --name PERSONA --file OUTPUT.md
    
    Options:
      --name, -n    Persona name
      --file, -f    File path for import/export
      --agent       Agent name for persona application
      --template, -t Template name for creation
    
    Examples:
      maestro personas --action create --template developer_assistant
      maestro personas --action apply --name helpful-assistant --agent session-1
      maestro personas --action export --name my-persona --file backup.md
    """)
  end
  
  # Helper functions...
  
  defp get_input(prompt, default \\ nil) do
    prompt_text = if default, do: "#{prompt} [#{default}]", else: prompt
    
    case IO.gets("#{prompt_text}: ") |> String.trim() do
      "" when default != nil -> default
      "" -> get_input(prompt, default)
      input -> input
    end
  end
  
  defp get_multiline_input(prompt) do
    IO.puts("#{prompt}:")
    IO.puts("(Enter your content, press Ctrl+D when finished)")
    
    read_multiline_input([])
  end
  
  defp read_multiline_input(acc) do
    case IO.gets("") do
      :eof -> 
        acc |> Enum.reverse() |> Enum.join()
        
      {:error, _} -> 
        acc |> Enum.reverse() |> Enum.join()
        
      line -> 
        read_multiline_input([line | acc])
    end
  end
  
  defp get_template_content(template_name) do
    case TheMaestro.Personas.PersonaTemplates.get_template(template_name) do
      nil -> {:error, :not_found}
      template -> {:ok, template.content}
    end
  end
  
  defp format_bytes(bytes) do
    cond do
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)}KB"
      true -> "#{bytes}B"
    end
  end
  
  defp format_datetime(datetime) do
    datetime
    |> NaiveDateTime.to_date()
    |> Date.to_string()
  end
  
  defp print_changeset_errors(changeset) do
    Enum.each(changeset.errors, fn {field, {message, _}} ->
      IO.puts("  #{field}: #{message}")
    end)
  end
end
```

## Module Structure

```
lib/the_maestro/tui/persona_manager/
├── persona_manager.ex          # Main TUI application
├── list_screen.ex              # Persona list interface
├── editor_screen.ex            # Persona editor interface
├── template_screen.ex          # Template selection interface
├── analytics_screen.ex         # Performance analytics interface
├── help_screen.ex              # Help and documentation interface
├── search_handler.ex           # Search functionality
├── key_bindings.ex             # Keyboard shortcut management
└── config_manager.ex           # TUI configuration management
```

## Integration Points

1. **Persona API Integration**: Direct integration with Personas context for all CRUD operations
2. **ApplicationEngine Integration**: Real-time persona application and management
3. **CLI Integration**: Command-line interface for scripting and automation
4. **Configuration System**: User preferences and TUI customization
5. **Performance Monitoring**: Real-time metrics and analytics display

## Performance Considerations

- Efficient terminal rendering with minimal screen updates
- Lazy loading of persona content and metadata
- Background operations for non-blocking user experience
- Memory-efficient handling of large persona collections
- Optimized keyboard input handling

## Accessibility Features

- High contrast mode support
- Configurable color schemes
- Alternative key bindings for different terminal capabilities
- Screen reader compatibility through structured output
- Font size and rendering adjustments

## Dependencies

- Story 8.1: Persona Definition & Storage System for data operations
- Story 8.2: Dynamic Persona Loading & Application for real-time management
- ExTUI or similar terminal UI framework
- Terminal capability detection libraries
- Keyboard input handling libraries

## Definition of Done

- [ ] Interactive persona list interface with navigation, filtering, and sorting
- [ ] Full-featured in-terminal editor with syntax highlighting and validation
- [ ] Template gallery with preview and application functionality
- [ ] Real-time persona application with status updates
- [ ] Search and discovery capabilities with incremental filtering
- [ ] Version management interface with diff visualization
- [ ] Import/export commands with file system integration
- [ ] Bulk operations for efficient multi-persona management
- [ ] Performance analytics dashboard with visual metrics
- [ ] Comprehensive keyboard navigation and shortcuts
- [ ] Color-coded status indicators and validation feedback
- [ ] Interactive wizards for common workflows
- [ ] Contextual help system with command hints
- [ ] CLI integration for scripting and automation
- [ ] Configuration management for user preferences
- [ ] Cross-platform compatibility (Linux, macOS, Windows)
- [ ] Performance optimization for large collections
- [ ] Error handling with clear recovery options
- [ ] Integration tests for all TUI workflows
- [ ] User acceptance testing with terminal power users