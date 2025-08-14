# Story 9.4: TUI Template Agent Creation & Selection

## User Story

**As a** developer using TheMaestro terminal interface  
**I want** a comprehensive and efficient TUI for template agent creation and selection with advanced navigation, creation wizards, and management features  
**so that** I can quickly create, customize, browse, and select template agents through an intuitive terminal interface that supports my entire template workflow without leaving the command line

## Acceptance Criteria

1. **Interactive Template Creation Wizard**: Step-by-step terminal wizard with form validation, configuration assistance, and real-time preview
2. **Advanced Template Browser**: Rich terminal interface with tree navigation, filtering, sorting, and detailed template information
3. **Template Search and Discovery**: Powerful search functionality with fuzzy matching, filtering, and intelligent suggestions
4. **Template Selection Interface**: Efficient template selection with preview, comparison, and quick instantiation options
5. **Template Management Operations**: Full CRUD operations through terminal interface with confirmation dialogs and progress indicators
6. **Real-time Template Validation**: Live validation feedback during creation and editing with error highlighting and suggestions
7. **Template Import/Export TUI**: Terminal interface for importing and exporting templates with progress tracking and format selection
8. **Template Collection Management**: TUI for creating, managing, and organizing template collections with drag-and-drop style interfaces
9. **Template Analytics Dashboard**: Terminal dashboard showing usage statistics, performance metrics, and optimization recommendations
10. **Template Inheritance Visualization**: ASCII-based hierarchy display with navigation and relationship management
11. **Keyboard Navigation Optimization**: Comprehensive keyboard shortcuts, vi-style navigation, and accessibility support
12. **Template Configuration Editor**: Full-featured terminal editor with syntax highlighting, auto-completion, and validation
13. **Template Rating and Review Interface**: Terminal interface for rating templates, writing reviews, and viewing community feedback
14. **Template Sharing and Collaboration**: TUI for sharing templates, managing permissions, and collaborative editing
15. **Template Version Management**: Version control interface with diff viewing, rollback capabilities, and merge assistance
16. **Template Testing and Preview**: Terminal-based template testing with execution simulation and result validation
17. **Template Marketplace Integration**: Browse and install community templates through terminal marketplace interface
18. **Batch Operations Support**: Bulk template operations with progress bars, confirmation prompts, and operation logging
19. **Template Documentation Viewer**: Integrated documentation browser with markdown rendering and help system
20. **Configuration Wizards**: Specialized wizards for provider setup, persona assignment, tool configuration, and deployment settings
21. **Template Performance Monitoring**: Real-time performance metrics display with alerting and optimization suggestions
22. **Template Security Auditing**: Security scanning interface with vulnerability reporting and remediation guidance
23. **Template Backup and Recovery**: TUI for backup management, restoration, and disaster recovery operations
24. **Cross-platform Compatibility**: Consistent experience across Windows, macOS, and Linux terminal environments
25. **Integration with External Tools**: Support for external editors, version control systems, and development workflows

## Technical Implementation

### Main TUI Application Structure

```elixir
# lib/the_maestro/tui/template_manager.ex
defmodule TheMaestro.TUI.TemplateManager do
  @moduledoc """
  Main TUI application for template agent management with comprehensive
  navigation, creation, and management capabilities.
  """
  
  use Ratatouille.App
  
  import Ratatouille.View
  import Ratatouille.Constants, only: [key: 1]
  
  alias TheMaestro.AgentTemplates
  alias TheMaestro.TUI.Components.{
    TemplateList,
    TemplateCreationWizard,
    TemplateEditor,
    TemplatePreview,
    SearchInterface,
    FilterPanel,
    HelpSystem
  }

  @app_title "TheMaestro Template Manager"
  @version "1.0.0"

  # Application state structure
  defstruct [
    :user,
    :mode,                    # :browse, :create, :edit, :search, :help
    :templates,
    :selected_template,
    :current_screen,
    :search_query,
    :filters,
    :cursor_position,
    :scroll_offset,
    :wizard_state,
    :editor_state,
    :preview_state,
    :loading,
    :error_message,
    :success_message,
    :keyboard_shortcuts,
    :show_help,
    :analytics_data,
    :collections
  ]

  @impl Ratatouille.App
  def init(%{user: user}) do
    state = %__MODULE__{
      user: user,
      mode: :browse,
      templates: [],
      selected_template: nil,
      current_screen: :template_list,
      search_query: "",
      filters: %{},
      cursor_position: 0,
      scroll_offset: 0,
      wizard_state: nil,
      editor_state: nil,
      preview_state: nil,
      loading: true,
      error_message: nil,
      success_message: nil,
      keyboard_shortcuts: load_keyboard_shortcuts(),
      show_help: false,
      analytics_data: %{},
      collections: []
    }
    
    # Load initial data
    {state, Ratatouille.Runtime.subscribe(self(), :template_updates)}
  end

  @impl Ratatouille.App
  def update(model, msg) do
    case msg do
      {:event, %{ch: ?q}} when model.mode == :browse ->
        # Quit application
        Ratatouille.Runtime.stop()
        model
      
      {:event, %{ch: ?h}} ->
        toggle_help(model)
      
      {:event, %{ch: ?c}} when model.mode == :browse ->
        start_template_creation(model)
      
      {:event, %{ch: ?s}} when model.mode == :browse ->
        start_template_search(model)
      
      {:event, %{ch: ?f}} when model.mode == :browse ->
        toggle_filter_panel(model)
      
      {:event, %{key: key(:enter)}} when model.mode == :browse ->
        select_current_template(model)
      
      {:event, %{key: key(:arrow_up)}} ->
        move_cursor_up(model)
      
      {:event, %{key: key(:arrow_down)}} ->
        move_cursor_down(model)
      
      {:event, %{key: key(:arrow_left)}} ->
        navigate_left(model)
      
      {:event, %{key: key(:arrow_right)}} ->
        navigate_right(model)
      
      {:event, %{key: key(:esc)}} ->
        handle_escape(model)
      
      {:event, %{ch: ch}} when model.mode == :search ->
        update_search_query(model, ch)
      
      {:event, %{key: key(:backspace)}} when model.mode == :search ->
        backspace_search_query(model)
      
      {:template_created, template} ->
        add_new_template(model, template)
      
      {:template_updated, template} ->
        update_template_in_list(model, template)
      
      {:template_deleted, template_id} ->
        remove_template_from_list(model, template_id)
      
      {:templates_loaded, templates} ->
        %{model | templates: templates, loading: false}
      
      {:error, message} ->
        %{model | error_message: message, loading: false}
      
      {:success, message} ->
        %{model | success_message: message}
      
      _ ->
        model
    end
  end

  @impl Ratatouille.App
  def render(model) do
    view top_bar: render_top_bar(model) do
      case model.current_screen do
        :template_list ->
          render_template_list_screen(model)
        
        :template_creation ->
          render_template_creation_screen(model)
        
        :template_editor ->
          render_template_editor_screen(model)
        
        :template_preview ->
          render_template_preview_screen(model)
        
        :search_results ->
          render_search_results_screen(model)
        
        :analytics_dashboard ->
          render_analytics_dashboard_screen(model)
        
        :help ->
          render_help_screen(model)
        
        _ ->
          render_template_list_screen(model)
      end
    end
  end

  # Screen rendering functions

  defp render_top_bar(model) do
    bar do
      label(content: @app_title, color: :white, background: :blue)
      
      label(content: " | ")
      
      label(content: "Mode: #{mode_display_name(model.mode)}", color: :cyan)
      
      label(content: " | ")
      
      if model.loading do
        label(content: "Loading...", color: :yellow)
      else
        label(content: "Templates: #{length(model.templates)}", color: :green)
      end
      
      label(content: " | ")
      
      label(content: "Press 'h' for help", color: :white, background: :magenta)
    end
  end

  defp render_template_list_screen(model) do
    row do
      # Left panel: Template list
      column(size: 8) do
        panel(title: "Templates", height: :fill) do
          if model.loading do
            label(content: "Loading templates...", color: :yellow)
          else
            render_template_list(model)
          end
        end
      end
      
      # Right panel: Template details
      column(size: 4) do
        panel(title: "Details", height: :fill) do
          case model.selected_template do
            nil ->
              label(content: "Select a template to view details", color: :gray)
            
            template ->
              render_template_details(template)
          end
        end
      end
    end
  end

  defp render_template_creation_screen(model) do
    case model.wizard_state do
      nil ->
        start_creation_wizard(model)
      
      wizard_state ->
        TemplateCreationWizard.render(wizard_state)
    end
  end

  defp render_template_editor_screen(model) do
    case model.editor_state do
      nil ->
        label(content: "No template selected for editing", color: :red)
      
      editor_state ->
        TemplateEditor.render(editor_state)
    end
  end

  defp render_template_preview_screen(model) do
    case model.preview_state do
      nil ->
        label(content: "No template selected for preview", color: :red)
      
      preview_state ->
        TemplatePreview.render(preview_state)
    end
  end

  defp render_search_results_screen(model) do
    row do
      column(size: 12) do
        panel(title: "Search Results: '#{model.search_query}'", height: :fill) do
          render_search_results(model)
        end
      end
    end
  end

  defp render_analytics_dashboard_screen(model) do
    row do
      # Analytics panels
      column(size: 6) do
        panel(title: "Usage Statistics", height: 12) do
          render_usage_statistics(model.analytics_data)
        end
      end
      
      column(size: 6) do
        panel(title: "Performance Metrics", height: 12) do
          render_performance_metrics(model.analytics_data)
        end
      end
    end
    
    row do
      column(size: 12) do
        panel(title: "Popular Templates", height: 8) do
          render_popular_templates(model.analytics_data)
        end
      end
    end
  end

  defp render_help_screen(model) do
    HelpSystem.render(model.keyboard_shortcuts)
  end

  # Template list rendering
  
  defp render_template_list(model) do
    templates = filter_and_sort_templates(model.templates, model.search_query, model.filters)
    
    templates
    |> Enum.with_index()
    |> Enum.map(fn {template, index} ->
      is_selected = index == model.cursor_position
      render_template_row(template, is_selected)
    end)
  end

  defp render_template_row(template, is_selected) do
    background_color = if is_selected, do: :blue, else: :default
    text_color = if is_selected, do: :white, else: :default
    
    row do
      column(size: 1) do
        if is_selected do
          label(content: ">", color: :yellow, background: background_color)
        else
          label(content: " ", background: background_color)
        end
      end
      
      column(size: 3) do
        label(
          content: truncate_string(template.name, 20),
          color: text_color,
          background: background_color
        )
      end
      
      column(size: 4) do
        label(
          content: truncate_string(template.description, 30),
          color: text_color,
          background: background_color
        )
      end
      
      column(size: 2) do
        label(
          content: template.category,
          color: :cyan,
          background: background_color
        )
      end
      
      column(size: 1) do
        rating_stars = render_rating_stars(template.rating_average)
        label(
          content: rating_stars,
          color: :yellow,
          background: background_color
        )
      end
      
      column(size: 1) do
        usage_indicator = if template.usage_count > 100, do: "🔥", else: " "
        label(
          content: usage_indicator,
          color: text_color,
          background: background_color
        )
      end
    end
  end

  defp render_template_details(template) do
    [
      label(content: "Name: #{template.display_name || template.name}", color: :white),
      label(content: "Category: #{template.category}", color: :cyan),
      label(content: "Version: #{template.version}", color: :green),
      label(content: "Author: #{template.author.name}", color: :yellow),
      label(content: ""),
      label(content: "Description:", color: :white),
      label(content: word_wrap(template.description, 35), color: :gray),
      label(content: ""),
      label(content: "Tags:", color: :white),
      label(content: Enum.join(template.tags, ", "), color: :magenta),
      label(content: ""),
      label(content: "Rating: #{Float.round(template.rating_average, 1)}/5.0", color: :yellow),
      label(content: "Usage: #{template.usage_count} times", color: :cyan),
      label(content: ""),
      label(content: "Provider: #{template.provider_config["default_provider"]}", color: :green),
      label(content: "Persona: #{template.persona_config["primary_persona_id"]}", color: :blue),
      label(content: ""),
      label(content: "Actions:", color: :white),
      label(content: "[Enter] Select  [e] Edit  [p] Preview", color: :gray),
      label(content: "[d] Delete  [x] Export  [r] Rate", color: :gray)
    ]
  end

  # Navigation and interaction functions

  defp move_cursor_up(model) do
    new_position = max(0, model.cursor_position - 1)
    update_cursor_position(model, new_position)
  end

  defp move_cursor_down(model) do
    max_position = length(model.templates) - 1
    new_position = min(max_position, model.cursor_position + 1)
    update_cursor_position(model, new_position)
  end

  defp update_cursor_position(model, new_position) do
    selected_template = Enum.at(model.templates, new_position)
    
    %{model | 
      cursor_position: new_position,
      selected_template: selected_template
    }
  end

  defp select_current_template(model) do
    case Enum.at(model.templates, model.cursor_position) do
      nil ->
        model
      
      template ->
        # Load full template details
        case AgentTemplates.get_template(template.id, user_id: model.user.id) do
          {:ok, full_template} ->
            %{model |
              selected_template: full_template,
              current_screen: :template_preview,
              preview_state: TemplatePreview.init(full_template)
            }
          
          {:error, _} ->
            %{model | error_message: "Failed to load template details"}
        end
    end
  end

  defp start_template_creation(model) do
    wizard_state = TemplateCreationWizard.init(model.user)
    
    %{model |
      mode: :create,
      current_screen: :template_creation,
      wizard_state: wizard_state
    }
  end

  defp start_template_search(model) do
    %{model |
      mode: :search,
      current_screen: :search_results,
      search_query: ""
    }
  end

  defp toggle_help(model) do
    if model.show_help do
      %{model | show_help: false, current_screen: :template_list}
    else
      %{model | show_help: true, current_screen: :help}
    end
  end

  defp handle_escape(model) do
    case model.mode do
      :search ->
        %{model | mode: :browse, current_screen: :template_list, search_query: ""}
      
      :create ->
        %{model | mode: :browse, current_screen: :template_list, wizard_state: nil}
      
      :edit ->
        %{model | mode: :browse, current_screen: :template_list, editor_state: nil}
      
      _ ->
        model
    end
  end

  # Search functionality
  
  defp update_search_query(model, char) do
    new_query = model.search_query <> List.to_string([char])
    perform_search(model, new_query)
  end

  defp backspace_search_query(model) do
    new_query = String.slice(model.search_query, 0..-2)
    perform_search(model, new_query)
  end

  defp perform_search(model, query) do
    # Perform real-time search
    Task.start(fn ->
      case AgentTemplates.search_templates(query, model.filters, %{user_id: model.user.id}) do
        {:ok, results} ->
          send(self(), {:search_results, results.templates})
        
        {:error, _} ->
          send(self(), {:error, "Search failed"})
      end
    end)
    
    %{model | search_query: query}
  end

  defp filter_and_sort_templates(templates, search_query, filters) do
    templates
    |> filter_by_search(search_query)
    |> apply_filters(filters)
    |> sort_templates()
  end

  defp filter_by_search(templates, "") do
    templates
  end

  defp filter_by_search(templates, query) do
    query = String.downcase(query)
    
    Enum.filter(templates, fn template ->
      String.contains?(String.downcase(template.name), query) or
      String.contains?(String.downcase(template.description), query) or
      Enum.any?(template.tags, fn tag -> String.contains?(String.downcase(tag), query) end)
    end)
  end

  defp apply_filters(templates, filters) do
    Enum.reduce(filters, templates, fn {key, value}, acc ->
      case key do
        :category -> Enum.filter(acc, fn t -> t.category == value end)
        :author -> Enum.filter(acc, fn t -> t.author.name == value end)
        :min_rating -> Enum.filter(acc, fn t -> t.rating_average >= value end)
        :tags -> Enum.filter(acc, fn t -> Enum.any?(t.tags, fn tag -> tag in value end) end)
        _ -> acc
      end
    end)
  end

  defp sort_templates(templates) do
    Enum.sort_by(templates, &{-&1.usage_count, -&1.rating_average, &1.name})
  end

  # Utility functions

  defp mode_display_name(:browse), do: "Browse"
  defp mode_display_name(:create), do: "Create"
  defp mode_display_name(:edit), do: "Edit"
  defp mode_display_name(:search), do: "Search"

  defp truncate_string(string, max_length) when byte_size(string) <= max_length do
    string
  end

  defp truncate_string(string, max_length) do
    String.slice(string, 0, max_length - 3) <> "..."
  end

  defp word_wrap(text, width) do
    text
    |> String.split(" ")
    |> Enum.reduce({[], 0, ""}, fn word, {lines, current_length, current_line} ->
      word_length = String.length(word)
      
      if current_length + word_length + 1 <= width do
        new_line = if current_line == "", do: word, else: current_line <> " " <> word
        {lines, current_length + word_length + 1, new_line}
      else
        {lines ++ [current_line], word_length, word}
      end
    end)
    |> case do
      {lines, _, last_line} -> Enum.join(lines ++ [last_line], "\n")
    end
  end

  defp render_rating_stars(rating) do
    full_stars = trunc(rating)
    half_star = if rating - full_stars >= 0.5, do: 1, else: 0
    empty_stars = 5 - full_stars - half_star
    
    String.duplicate("★", full_stars) <>
    String.duplicate("☆", half_star) <>
    String.duplicate("☆", empty_stars)
  end

  defp load_keyboard_shortcuts do
    %{
      global: [
        {"q", "Quit application"},
        {"h", "Toggle help"},
        {"↑/↓", "Navigate list"},
        {"←/→", "Navigate panels"},
        {"Esc", "Go back/Cancel"}
      ],
      browse_mode: [
        {"c", "Create new template"},
        {"s", "Search templates"},
        {"f", "Toggle filters"},
        {"Enter", "Select template"},
        {"e", "Edit template"},
        {"p", "Preview template"},
        {"d", "Delete template"},
        {"x", "Export template"},
        {"r", "Rate template"}
      ],
      create_mode: [
        {"Tab", "Next field"},
        {"Shift+Tab", "Previous field"},
        {"Ctrl+S", "Save template"},
        {"Ctrl+P", "Preview template"}
      ],
      search_mode: [
        {"Any key", "Add to search"},
        {"Backspace", "Remove character"},
        {"Enter", "Apply search"},
        {"Tab", "Toggle filters"}
      ]
    }
  end

  # Template management operations
  
  defp add_new_template(model, template) do
    %{model | 
      templates: [template | model.templates],
      success_message: "Template created successfully"
    }
  end

  defp update_template_in_list(model, updated_template) do
    updated_templates = Enum.map(model.templates, fn template ->
      if template.id == updated_template.id do
        updated_template
      else
        template
      end
    end)
    
    %{model | 
      templates: updated_templates,
      selected_template: if(model.selected_template && model.selected_template.id == updated_template.id, do: updated_template, else: model.selected_template),
      success_message: "Template updated successfully"
    }
  end

  defp remove_template_from_list(model, template_id) do
    updated_templates = Enum.reject(model.templates, fn template ->
      template.id == template_id
    end)
    
    selected_template = if model.selected_template && model.selected_template.id == template_id do
      nil
    else
      model.selected_template
    end
    
    %{model | 
      templates: updated_templates,
      selected_template: selected_template,
      success_message: "Template deleted successfully"
    }
  end
end
```

### Template Creation Wizard Component

```elixir
# lib/the_maestro/tui/components/template_creation_wizard.ex
defmodule TheMaestro.TUI.Components.TemplateCreationWizard do
  @moduledoc """
  Interactive terminal wizard for creating new template agents with
  step-by-step guidance and validation.
  """
  
  import Ratatouille.View
  import Ratatouille.Constants, only: [key: 1]
  
  alias TheMaestro.AgentTemplates
  alias TheMaestro.AgentTemplates.SchemaValidator

  defstruct [
    :user,
    :current_step,
    :max_steps,
    :template_data,
    :validation_errors,
    :field_focus,
    :available_providers,
    :available_personas,
    :available_tools,
    :step_validation
  ]

  @steps [
    %{
      name: :basic_info,
      title: "Basic Information",
      fields: [:name, :display_name, :description, :category, :tags],
      required_fields: [:name, :description, :category]
    },
    %{
      name: :provider_config,
      title: "Provider Configuration", 
      fields: [:default_provider, :fallback_providers, :model_preferences],
      required_fields: [:default_provider]
    },
    %{
      name: :persona_config,
      title: "Persona Assignment",
      fields: [:primary_persona_id, :persona_hierarchy, :context_specific_personas],
      required_fields: [:primary_persona_id]
    },
    %{
      name: :tool_config,
      title: "Tool Configuration",
      fields: [:required_tools, :optional_tools, :mcp_servers],
      required_fields: []
    },
    %{
      name: :prompt_config,
      title: "Prompt Setup",
      fields: [:system_instruction_template, :prompt_templates, :context_enhancement],
      required_fields: []
    },
    %{
      name: :deployment_config,
      title: "Deployment Settings",
      fields: [:auto_start, :session_timeout, :resource_limits],
      required_fields: []
    },
    %{
      name: :review,
      title: "Review & Create",
      fields: [],
      required_fields: []
    }
  ]

  def init(user) do
    %__MODULE__{
      user: user,
      current_step: 0,
      max_steps: length(@steps),
      template_data: initialize_template_data(),
      validation_errors: %{},
      field_focus: 0,
      available_providers: load_available_providers(),
      available_personas: load_available_personas(user),
      available_tools: load_available_tools(),
      step_validation: %{}
    }
  end

  def render(state) do
    current_step_info = Enum.at(@steps, state.current_step)
    
    column do
      # Wizard header
      panel(title: "Create Template - Step #{state.current_step + 1}/#{state.max_steps}: #{current_step_info.title}") do
        render_progress_bar(state)
      end
      
      # Step content
      panel(title: "Configuration", height: 20) do
        case current_step_info.name do
          :basic_info -> render_basic_info_step(state)
          :provider_config -> render_provider_config_step(state)
          :persona_config -> render_persona_config_step(state)
          :tool_config -> render_tool_config_step(state)
          :prompt_config -> render_prompt_config_step(state)
          :deployment_config -> render_deployment_config_step(state)
          :review -> render_review_step(state)
        end
      end
      
      # Validation errors
      if map_size(state.validation_errors) > 0 do
        panel(title: "Validation Errors", height: 5) do
          render_validation_errors(state.validation_errors)
        end
      end
      
      # Navigation instructions
      panel(title: "Navigation", height: 3) do
        render_navigation_instructions(state)
      end
    end
  end

  defp render_progress_bar(state) do
    progress = (state.current_step / (state.max_steps - 1)) * 100
    filled_chars = trunc(progress / 2)
    empty_chars = 50 - filled_chars
    
    progress_bar = String.duplicate("█", filled_chars) <> String.duplicate("░", empty_chars)
    
    label(content: "Progress: [#{progress_bar}] #{trunc(progress)}%", color: :cyan)
  end

  defp render_basic_info_step(state) do
    template_data = state.template_data
    field_focus = state.field_focus
    
    [
      render_input_field("Name:", template_data.name, field_focus == 0, state.validation_errors[:name]),
      render_input_field("Display Name:", template_data.display_name, field_focus == 1, state.validation_errors[:display_name]),
      render_textarea_field("Description:", template_data.description, field_focus == 2, state.validation_errors[:description]),
      render_select_field("Category:", template_data.category, get_available_categories(), field_focus == 3, state.validation_errors[:category]),
      render_tags_field("Tags:", template_data.tags, field_focus == 4, state.validation_errors[:tags])
    ]
  end

  defp render_provider_config_step(state) do
    provider_config = state.template_data.provider_config
    field_focus = state.field_focus
    
    [
      render_select_field("Default Provider:", provider_config["default_provider"], 
                         get_provider_names(state.available_providers), field_focus == 0, 
                         state.validation_errors[:default_provider]),
      
      render_multiselect_field("Fallback Providers:", provider_config["fallback_providers"],
                              get_provider_names(state.available_providers), field_focus == 1,
                              state.validation_errors[:fallback_providers]),
      
      render_model_preferences_field("Model Preferences:", provider_config["model_preferences"],
                                   state.available_providers, field_focus == 2,
                                   state.validation_errors[:model_preferences])
    ]
  end

  defp render_persona_config_step(state) do
    persona_config = state.template_data.persona_config
    field_focus = state.field_focus
    
    [
      render_select_field("Primary Persona:", persona_config["primary_persona_id"],
                         get_persona_names(state.available_personas), field_focus == 0,
                         state.validation_errors[:primary_persona_id]),
      
      render_multiselect_field("Persona Hierarchy:", persona_config["persona_hierarchy"],
                              get_persona_names(state.available_personas), field_focus == 1,
                              state.validation_errors[:persona_hierarchy]),
      
      render_context_personas_field("Context-Specific Personas:", persona_config["context_specific_personas"],
                                   state.available_personas, field_focus == 2,
                                   state.validation_errors[:context_specific_personas])
    ]
  end

  defp render_tool_config_step(state) do
    tool_config = state.template_data.tool_config
    field_focus = state.field_focus
    
    [
      render_multiselect_field("Required Tools:", tool_config["required_tools"],
                              get_tool_names(state.available_tools), field_focus == 0,
                              state.validation_errors[:required_tools]),
      
      render_multiselect_field("Optional Tools:", tool_config["optional_tools"],
                              get_tool_names(state.available_tools), field_focus == 1,
                              state.validation_errors[:optional_tools]),
      
      render_mcp_servers_field("MCP Servers:", tool_config["mcp_servers"],
                              state.available_tools, field_focus == 2,
                              state.validation_errors[:mcp_servers])
    ]
  end

  defp render_prompt_config_step(state) do
    prompt_config = state.template_data.prompt_config
    field_focus = state.field_focus
    
    [
      render_input_field("System Instruction Template:", prompt_config["system_instruction_template"],
                        field_focus == 0, state.validation_errors[:system_instruction_template]),
      
      render_boolean_field("Context Enhancement:", prompt_config["context_enhancement"],
                          field_focus == 1, state.validation_errors[:context_enhancement]),
      
      render_boolean_field("Provider Optimization:", prompt_config["provider_optimization"],
                          field_focus == 2, state.validation_errors[:provider_optimization]),
      
      render_prompt_templates_field("Prompt Templates:", prompt_config["prompt_templates"],
                                   field_focus == 3, state.validation_errors[:prompt_templates])
    ]
  end

  defp render_deployment_config_step(state) do
    deployment_config = state.template_data.deployment_config
    field_focus = state.field_focus
    
    [
      render_boolean_field("Auto Start:", deployment_config["auto_start"],
                          field_focus == 0, state.validation_errors[:auto_start]),
      
      render_number_field("Session Timeout (seconds):", deployment_config["session_timeout"],
                         field_focus == 1, state.validation_errors[:session_timeout]),
      
      render_boolean_field("Conversation Persistence:", deployment_config["conversation_persistence"],
                          field_focus == 2, state.validation_errors[:conversation_persistence]),
      
      render_resource_limits_field("Resource Limits:", deployment_config["resource_limits"],
                                  field_focus == 3, state.validation_errors[:resource_limits])
    ]
  end

  defp render_review_step(state) do
    template_data = state.template_data
    
    [
      label(content: "Template Review", color: :white),
      label(content: ""),
      label(content: "Name: #{template_data.name}", color: :cyan),
      label(content: "Description: #{template_data.description}", color: :gray),
      label(content: "Category: #{template_data.category}", color: :yellow),
      label(content: "Provider: #{template_data.provider_config["default_provider"]}", color: :green),
      label(content: "Persona: #{template_data.persona_config["primary_persona_id"]}", color: :blue),
      label(content: ""),
      render_final_validation_status(state),
      label(content: ""),
      label(content: "Press Enter to create template or Esc to cancel", color: :white, background: :magenta)
    ]
  end

  # Input field rendering functions

  defp render_input_field(label_text, value, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    [
      label(content: label_text, color: :white),
      label(content: "[#{value || ""}]", color: color, background: background),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_textarea_field(label_text, value, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    wrapped_value = word_wrap(value || "", 60)
    
    [
      label(content: label_text, color: :white),
      label(content: "┌─────────────────────────────────────────────────────────────┐", color: color),
      label(content: "│ #{String.pad_trailing(wrapped_value, 59)} │", color: color, background: background),
      label(content: "└─────────────────────────────────────────────────────────────┘", color: color),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_select_field(label_text, value, options, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    options_display = if is_focused do
      Enum.join(options, " | ")
    else
      ""
    end
    
    [
      label(content: label_text, color: :white),
      label(content: "Selected: [#{value || "None"}]", color: color, background: background),
      if is_focused, do: label(content: "Options: #{options_display}", color: :gray), else: nil,
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_multiselect_field(label_text, values, options, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    selected_display = case values do
      nil -> "None"
      [] -> "None"
      list -> Enum.join(list, ", ")
    end
    
    [
      label(content: label_text, color: :white),
      label(content: "Selected: [#{selected_display}]", color: color, background: background),
      if is_focused, do: label(content: "Available: #{Enum.join(options, " | ")}", color: :gray), else: nil,
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_boolean_field(label_text, value, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    display_value = case value do
      true -> "Yes"
      false -> "No"
      nil -> "No"
    end
    
    [
      label(content: label_text, color: :white),
      label(content: "[#{display_value}]", color: color, background: background),
      if is_focused, do: label(content: "Press space to toggle", color: :gray), else: nil,
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_number_field(label_text, value, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    [
      label(content: label_text, color: :white),
      label(content: "[#{value || 0}]", color: color, background: background),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_tags_field(label_text, tags, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    background = if is_focused, do: :blue, else: :default
    
    tags_display = case tags do
      nil -> ""
      [] -> ""
      list -> Enum.join(list, ", ")
    end
    
    [
      label(content: label_text, color: :white),
      label(content: "[#{tags_display}]", color: color, background: background),
      if is_focused, do: label(content: "Separate tags with commas", color: :gray), else: nil,
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  # Specialized field renderers

  defp render_model_preferences_field(label_text, preferences, providers, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    
    [
      label(content: label_text, color: :white),
      label(content: "Configure model preferences for each provider", color: :gray),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_context_personas_field(label_text, personas, available_personas, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    
    [
      label(content: label_text, color: :white),
      label(content: "Map contexts to specific personas", color: :gray),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_mcp_servers_field(label_text, servers, available_tools, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    
    [
      label(content: label_text, color: :white),
      label(content: "Configure MCP server connections", color: :gray),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_prompt_templates_field(label_text, templates, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    
    [
      label(content: label_text, color: :white),
      label(content: "Define context-specific prompt templates", color: :gray),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_resource_limits_field(label_text, limits, is_focused, error) do
    color = if is_focused, do: :yellow, else: :white
    
    [
      label(content: label_text, color: :white),
      label(content: "Set resource usage limits", color: :gray),
      if error, do: label(content: "Error: #{error}", color: :red), else: nil
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_final_validation_status(state) do
    case validate_complete_template(state.template_data) do
      {:ok, _} ->
        label(content: "✓ Template validation passed", color: :green)
      
      {:error, errors} ->
        [
          label(content: "✗ Template validation failed:", color: :red),
          Enum.map(errors, fn {field, message} ->
            label(content: "  • #{field}: #{message}", color: :red)
          end)
        ]
    end
  end

  defp render_validation_errors(errors) do
    Enum.map(errors, fn {field, message} ->
      label(content: "#{field}: #{message}", color: :red)
    end)
  end

  defp render_navigation_instructions(state) do
    current_step_info = Enum.at(@steps, state.current_step)
    
    base_instructions = [
      "Tab/↑↓: Navigate fields",
      "←→: Previous/Next step", 
      "Esc: Cancel"
    ]
    
    step_instructions = case current_step_info.name do
      :review -> ["Enter: Create template"]
      _ -> ["Space: Toggle boolean", "Enter: Edit field"]
    end
    
    all_instructions = base_instructions ++ step_instructions
    
    label(content: Enum.join(all_instructions, " | "), color: :cyan)
  end

  # Data initialization and loading functions

  defp initialize_template_data do
    %{
      name: "",
      display_name: "",
      description: "",
      category: "general",
      tags: [],
      provider_config: %{
        "default_provider" => nil,
        "fallback_providers" => [],
        "model_preferences" => %{}
      },
      persona_config: %{
        "primary_persona_id" => nil,
        "persona_hierarchy" => [],
        "context_specific_personas" => %{}
      },
      tool_config: %{
        "required_tools" => [],
        "optional_tools" => [],
        "mcp_servers" => []
      },
      prompt_config: %{
        "system_instruction_template" => "",
        "context_enhancement" => true,
        "provider_optimization" => true,
        "prompt_templates" => %{}
      },
      deployment_config: %{
        "auto_start" => false,
        "session_timeout" => 3600,
        "conversation_persistence" => true,
        "resource_limits" => %{
          "max_memory_mb" => 512,
          "max_cpu_percent" => 25
        }
      }
    }
  end

  defp load_available_providers do
    [
      %{name: "anthropic", display_name: "Anthropic Claude", models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]},
      %{name: "openai", display_name: "OpenAI GPT", models: ["gpt-4", "gpt-3.5-turbo"]},
      %{name: "gemini", display_name: "Google Gemini", models: ["gemini-pro", "gemini-1.5-pro"]}
    ]
  end

  defp load_available_personas(user) do
    # Load from Epic 8 persona system
    case TheMaestro.Personas.list_personas_for_user(user.id) do
      {:ok, personas} -> personas
      _ -> []
    end
  end

  defp load_available_tools do
    # Load from Epic 6 MCP system
    case TheMaestro.MCP.list_available_tools() do
      {:ok, tools} -> tools
      _ -> []
    end
  end

  defp get_available_categories do
    ["development", "writing", "analysis", "research", "support", "education", "business", "creative", "technical", "general"]
  end

  defp get_provider_names(providers) do
    Enum.map(providers, & &1.name)
  end

  defp get_persona_names(personas) do
    Enum.map(personas, & &1.name)
  end

  defp get_tool_names(tools) do
    Enum.map(tools, & &1.name)
  end

  defp validate_complete_template(template_data) do
    SchemaValidator.validate_template(template_data)
  end

  defp word_wrap(text, width) do
    text
    |> String.split(" ")
    |> Enum.reduce({[], 0, ""}, fn word, {lines, current_length, current_line} ->
      word_length = String.length(word)
      
      if current_length + word_length + 1 <= width do
        new_line = if current_line == "", do: word, else: current_line <> " " <> word
        {lines, current_length + word_length + 1, new_line}
      else
        {lines ++ [current_line], word_length, word}
      end
    end)
    |> case do
      {lines, _, last_line} -> Enum.join(lines ++ [last_line], "\n")
    end
  end
end
```

## Module Structure

```
lib/the_maestro/tui/template_management/
├── template_manager.ex              # Main TUI application
├── components/
│   ├── template_creation_wizard.ex  # Creation wizard component
│   ├── template_list.ex            # Template list display
│   ├── template_editor.ex          # Template editor interface
│   ├── template_preview.ex         # Template preview component
│   ├── search_interface.ex         # Search and filter UI
│   ├── analytics_dashboard.ex      # Analytics display
│   ├── help_system.ex             # Help and shortcuts
│   └── bulk_operations.ex         # Bulk operation handlers
├── keyboard/
│   ├── navigation_handler.ex       # Keyboard navigation logic
│   ├── input_handler.ex           # Text input handling
│   └── shortcut_manager.ex        # Keyboard shortcut management
└── utils/
    ├── text_formatter.ex          # Text formatting utilities
    ├── validation_display.ex      # Validation error display
    └── ascii_art.ex              # ASCII art and graphics
```

## Integration Points

1. **Epic 5 Integration**: Provider selection interfaces and authentication
2. **Epic 6 Integration**: MCP server configuration and tool selection
3. **Epic 7 Integration**: Prompt configuration and template editing
4. **Epic 8 Integration**: Persona selection and assignment interfaces
5. **Storage System**: Integration with Epic 9.2 storage and retrieval
6. **Real-time Updates**: Live template synchronization and notifications

## Performance Considerations

- Lazy loading of template lists for large collections
- Debounced search with intelligent caching
- Efficient terminal rendering with minimal screen updates
- Background loading of template metadata
- Memory-efficient handling of large template configurations

## Security Considerations

- Input validation for all template fields
- Permission checking before template operations
- Secure handling of sensitive configuration data
- Audit logging for template management operations
- Protection against terminal injection attacks

## Dependencies

- Epic 5: Model Choice & Authentication System
- Epic 6: MCP Protocol Implementation
- Epic 7: Enhanced Prompt Handling System
- Epic 8: Persona Management System
- Epic 9.2: Template Agent Storage & Retrieval System
- Ratatouille for terminal UI framework
- ExTermbox for low-level terminal handling

## Definition of Done

- [ ] Interactive template creation wizard with step-by-step guidance
- [ ] Advanced template browser with tree navigation and filtering
- [ ] Powerful search and discovery with fuzzy matching
- [ ] Efficient template selection interface with preview capabilities
- [ ] Complete template management operations through TUI
- [ ] Real-time template validation with error highlighting
- [ ] Template import/export interface with progress tracking
- [ ] Template collection management with organization features
- [ ] Analytics dashboard showing usage statistics and metrics
- [ ] Template inheritance visualization with ASCII hierarchy display
- [ ] Comprehensive keyboard navigation with vi-style shortcuts
- [ ] Full-featured terminal configuration editor with syntax highlighting
- [ ] Rating and review interface for community templates
- [ ] Template sharing and collaboration through terminal interface
- [ ] Version management with diff viewing and rollback capabilities
- [ ] Template testing and preview with execution simulation
- [ ] Marketplace integration for community template discovery
- [ ] Batch operations with progress bars and confirmation prompts
- [ ] Integrated documentation browser with markdown rendering
- [ ] Specialized configuration wizards for all template components
- [ ] Real-time performance monitoring with terminal dashboard
- [ ] Security auditing interface with vulnerability reporting
- [ ] Backup and recovery management through terminal interface
- [ ] Cross-platform compatibility (Windows, macOS, Linux)
- [ ] Integration with external development tools and editors
- [ ] Comprehensive unit tests with >95% coverage
- [ ] Integration tests with all dependent Epic systems
- [ ] Performance testing with large template collections (1000+ templates)
- [ ] Accessibility testing for screen readers and keyboard-only navigation
- [ ] Terminal compatibility testing across different terminal emulators
- [ ] User acceptance testing with developer workflow validation
- [ ] Complete TUI documentation with keyboard shortcut reference
- [ ] Performance benchmarks meeting <1-second response requirements