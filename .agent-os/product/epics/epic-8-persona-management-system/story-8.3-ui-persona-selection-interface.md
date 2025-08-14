# Story 8.3: UI Persona Selection Interface

## User Story

**As a** user of TheMaestro's web interface
**I want** an intuitive and comprehensive persona management interface
**so that** I can easily create, edit, organize, and apply personas to my agent sessions through a visual interface

## Acceptance Criteria

1. **Persona Library Dashboard**: A comprehensive dashboard displaying all user personas with filtering, sorting, and search capabilities
2. **Visual Persona Cards**: Rich persona cards showing preview content, metadata, usage statistics, and quick action buttons
3. **Real-time Persona Creator**: An interactive editor for creating new personas with live preview and validation
4. **Advanced Persona Editor**: Full-featured editor with markdown support, syntax highlighting, and content validation
5. **Template Gallery**: Browse and instantiate personas from built-in and community templates
6. **Persona Application Controls**: One-click persona application to active agent sessions with visual feedback
7. **Hierarchical Organization**: Visual representation of persona inheritance with drag-and-drop organization
8. **Version Management Interface**: UI for viewing, comparing, and rolling back persona versions
9. **Import/Export Workflows**: Drag-and-drop file import and one-click export functionality
10. **Performance Analytics Dashboard**: Visual performance metrics and effectiveness analytics for each persona
11. **Tag and Category Management**: Interactive tagging system with autocomplete and category organization
12. **Collaboration Features**: Sharing personas with other users and community submission workflows
13. **Mobile-responsive Design**: Full functionality maintained across desktop, tablet, and mobile devices
14. **Accessibility Compliance**: WCAG 2.1 AA compliance with full keyboard navigation and screen reader support
15. **Real-time Updates**: Live updates when personas are modified, ensuring consistency across multiple sessions
16. **Bulk Operations**: Multi-select functionality for bulk delete, tag, and export operations
17. **Advanced Search**: Full-text search across persona content with highlighting and faceted filtering
18. **Usage Analytics**: Visual representations of persona application frequency and success rates
19. **Contextual Help**: Integrated help system with tutorials, tooltips, and guided workflows
20. **Integration Indicators**: Visual indicators showing which agent sessions are using which personas
21. **Backup and Restore**: UI for managing persona backups and restoration workflows
22. **Theme Customization**: User-customizable interface themes and layout preferences
23. **Keyboard Shortcuts**: Comprehensive keyboard shortcuts for power user efficiency
24. **Error Handling and Recovery**: Graceful error handling with user-friendly messages and recovery options
25. **Performance Optimization**: Lazy loading, virtual scrolling, and optimized rendering for large persona collections

## Technical Implementation

### Main Persona Management LiveView

```elixir
# lib/the_maestro_web/live/persona_live/index.ex
defmodule TheMaestroWeb.PersonaLive.Index do
  use TheMaestroWeb, :live_view
  
  alias TheMaestro.Personas
  alias TheMaestro.Personas.{Persona, ApplicationEngine}
  
  @items_per_page 12
  
  def mount(_params, session, socket) do
    user = get_current_user(session)
    
    if connected?(socket) do
      # Subscribe to persona events
      Phoenix.PubSub.subscribe(TheMaestro.PubSub, "personas:#{user.id}")
      Phoenix.PubSub.subscribe(TheMaestro.PubSub, "agents:#{user.id}")
    end
    
    socket = 
      socket
      |> assign(:user, user)
      |> assign(:personas, [])
      |> assign(:filtered_personas, [])
      |> assign(:selected_personas, MapSet.new())
      |> assign(:page_title, "Persona Management")
      |> assign(:search_query, "")
      |> assign(:selected_tags, [])
      |> assign(:sort_by, "updated_at")
      |> assign(:sort_direction, :desc)
      |> assign(:view_mode, "cards")
      |> assign(:show_template_gallery, false)
      |> assign(:show_create_modal, false)
      |> assign(:show_import_modal, false)
      |> assign(:active_agent_sessions, [])
      |> assign(:loading, true)
      |> load_personas()
      |> load_active_sessions()
    
    {:ok, socket}
  end
  
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end
  
  defp apply_action(socket, :index, _params) do
    socket
  end
  
  defp apply_action(socket, :new, _params) do
    assign(socket, :show_create_modal, true)
  end
  
  defp apply_action(socket, :edit, %{"id" => id}) do
    persona = Personas.get_persona!(id)
    
    if persona.user_id == socket.assigns.user.id do
      assign(socket, :editing_persona, persona)
    else
      socket
      |> put_flash(:error, "Unauthorized")
      |> push_navigate(to: ~p"/personas")
    end
  end
  
  def handle_event("search", %{"query" => query}, socket) do
    socket = 
      socket
      |> assign(:search_query, query)
      |> filter_personas()
    
    {:noreply, socket}
  end
  
  def handle_event("filter_by_tags", %{"tags" => tags}, socket) do
    socket = 
      socket
      |> assign(:selected_tags, tags)
      |> filter_personas()
    
    {:noreply, socket}
  end
  
  def handle_event("sort_personas", %{"sort_by" => sort_by, "direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)
    
    socket = 
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_direction, direction)
      |> sort_personas()
    
    {:noreply, socket}
  end
  
  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end
  
  def handle_event("select_persona", %{"id" => id}, socket) do
    selected = 
      if MapSet.member?(socket.assigns.selected_personas, id) do
        MapSet.delete(socket.assigns.selected_personas, id)
      else
        MapSet.put(socket.assigns.selected_personas, id)
      end
    
    {:noreply, assign(socket, :selected_personas, selected)}
  end
  
  def handle_event("select_all_personas", _params, socket) do
    all_ids = Enum.map(socket.assigns.filtered_personas, & &1.id) |> MapSet.new()
    {:noreply, assign(socket, :selected_personas, all_ids)}
  end
  
  def handle_event("deselect_all_personas", _params, socket) do
    {:noreply, assign(socket, :selected_personas, MapSet.new())}
  end
  
  def handle_event("apply_persona", %{"persona_id" => persona_id, "agent_id" => agent_id}, socket) do
    case ApplicationEngine.apply_persona(String.to_atom("agent_#{agent_id}"), persona_id) do
      {:ok, _} ->
        persona = Enum.find(socket.assigns.personas, &(&1.id == persona_id))
        
        socket = 
          socket
          |> put_flash(:info, "Applied persona '#{persona.name}' successfully")
          |> update_persona_stats(persona_id)
        
        {:noreply, socket}
        
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to apply persona: #{reason}")
        {:noreply, socket}
    end
  end
  
  def handle_event("remove_persona", %{"agent_id" => agent_id}, socket) do
    case ApplicationEngine.remove_persona(String.to_atom("agent_#{agent_id}")) do
      {:ok, _} ->
        socket = put_flash(socket, :info, "Removed persona from agent")
        {:noreply, socket}
        
      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to remove persona: #{reason}")
        {:noreply, socket}
    end
  end
  
  def handle_event("delete_persona", %{"id" => id}, socket) do
    persona = Personas.get_persona!(id)
    
    case Personas.delete_persona(persona) do
      {:ok, _} ->
        socket = 
          socket
          |> put_flash(:info, "Persona deleted successfully")
          |> load_personas()
        
        {:noreply, socket}
        
      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to delete persona")
        {:noreply, socket}
    end
  end
  
  def handle_event("bulk_delete", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_personas)
    
    {success_count, _} = 
      Enum.reduce(selected_ids, {0, []}, fn id, {success, errors} ->
        case Personas.get_persona(id) do
          nil -> {success, errors}
          persona ->
            case Personas.delete_persona(persona) do
              {:ok, _} -> {success + 1, errors}
              {:error, reason} -> {success, [reason | errors]}
            end
        end
      end)
    
    socket = 
      socket
      |> put_flash(:info, "Deleted #{success_count} personas")
      |> assign(:selected_personas, MapSet.new())
      |> load_personas()
    
    {:noreply, socket}
  end
  
  def handle_event("export_persona", %{"id" => id}, socket) do
    case Personas.get_persona(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Persona not found")}
        
      persona ->
        case Personas.export_to_markdown(persona) do
          {:ok, content} ->
            filename = "#{persona.name}.md"
            
            socket = 
              socket
              |> put_flash(:info, "Persona exported successfully")
              |> push_event("download-file", %{
                filename: filename,
                content: content,
                mime_type: "text/markdown"
              })
            
            {:noreply, socket}
            
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Export failed: #{reason}")}
        end
    end
  end
  
  def handle_event("show_template_gallery", _params, socket) do
    {:noreply, assign(socket, :show_template_gallery, true)}
  end
  
  def handle_event("hide_template_gallery", _params, socket) do
    {:noreply, assign(socket, :show_template_gallery, false)}
  end
  
  # PubSub event handlers
  def handle_info({:persona_created, persona}, socket) do
    if persona.user_id == socket.assigns.user.id do
      {:noreply, load_personas(socket)}
    else
      {:noreply, socket}
    end
  end
  
  def handle_info({:persona_updated, persona}, socket) do
    if persona.user_id == socket.assigns.user.id do
      {:noreply, load_personas(socket)}
    else
      {:noreply, socket}
    end
  end
  
  def handle_info({:persona_applied, agent_id, persona_id}, socket) do
    {:noreply, update_agent_session_status(socket, agent_id, persona_id)}
  end
  
  # Private helper functions
  
  defp load_personas(socket) do
    personas = Personas.list_personas(socket.assigns.user.id)
    
    socket
    |> assign(:personas, personas)
    |> assign(:filtered_personas, personas)
    |> assign(:loading, false)
  end
  
  defp load_active_sessions(socket) do
    # Load active agent sessions for the user
    # This would integrate with the agent system
    sessions = [] # TheMaestro.Agents.list_active_sessions(socket.assigns.user.id)
    assign(socket, :active_agent_sessions, sessions)
  end
  
  defp filter_personas(socket) do
    filtered = 
      socket.assigns.personas
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_tags(socket.assigns.selected_tags)
    
    assign(socket, :filtered_personas, filtered)
  end
  
  defp filter_by_search(personas, ""), do: personas
  defp filter_by_search(personas, query) do
    query = String.downcase(query)
    
    Enum.filter(personas, fn persona ->
      String.contains?(String.downcase(persona.name), query) ||
      String.contains?(String.downcase(persona.description || ""), query) ||
      String.contains?(String.downcase(persona.content), query)
    end)
  end
  
  defp filter_by_tags(personas, []), do: personas
  defp filter_by_tags(personas, selected_tags) do
    Enum.filter(personas, fn persona ->
      Enum.any?(selected_tags, &(&1 in persona.tags))
    end)
  end
  
  defp sort_personas(socket) do
    sorted = 
      Enum.sort_by(socket.assigns.filtered_personas, fn persona ->
        case socket.assigns.sort_by do
          "name" -> persona.name
          "updated_at" -> persona.updated_at
          "created_at" -> persona.inserted_at
          "usage_count" -> persona.application_count
          _ -> persona.updated_at
        end
      end, socket.assigns.sort_direction)
    
    assign(socket, :filtered_personas, sorted)
  end
  
  defp update_persona_stats(socket, persona_id) do
    # Update persona usage statistics
    updated_personas = 
      Enum.map(socket.assigns.personas, fn persona ->
        if persona.id == persona_id do
          %{persona | 
            application_count: persona.application_count + 1,
            last_applied_at: NaiveDateTime.utc_now()
          }
        else
          persona
        end
      end)
    
    assign(socket, :personas, updated_personas)
  end
  
  defp update_agent_session_status(socket, agent_id, persona_id) do
    # Update which personas are active in which sessions
    # Implementation depends on agent system integration
    socket
  end
end
```

### Persona Card Component

```elixir
# lib/the_maestro_web/live/persona_live/persona_card_component.ex
defmodule TheMaestroWeb.PersonaLive.PersonaCardComponent do
  use TheMaestroWeb, :live_component
  
  alias TheMaestro.Personas
  
  def render(assigns) do
    ~H"""
    <div class={[
      "persona-card bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700",
      "hover:shadow-md transition-shadow duration-200",
      @selected && "ring-2 ring-blue-500"
    ]}>
      <div class="p-4">
        <!-- Header with selection checkbox and actions -->
        <div class="flex items-start justify-between mb-3">
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              checked={@selected}
              phx-click="select_persona"
              phx-value-id={@persona.id}
              phx-target={@myself}
              class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
            />
            <div>
              <h3 class="font-semibold text-gray-900 dark:text-white">
                <%= @persona.display_name || @persona.name %>
              </h3>
              <p class="text-sm text-gray-500 dark:text-gray-400">
                v<%= @persona.version %>
              </p>
            </div>
          </div>
          
          <!-- Action dropdown -->
          <div class="relative" x-data="{ open: false }">
            <button
              @click="open = !open"
              class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700"
            >
              <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
            </button>
            
            <div
              x-show="open"
              @click.away="open = false"
              class="absolute right-0 mt-1 w-48 bg-white dark:bg-gray-700 rounded-md shadow-lg z-10"
            >
              <div class="py-1">
                <button
                  phx-click="edit_persona"
                  phx-value-id={@persona.id}
                  phx-target={@myself}
                  class="w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-600"
                >
                  <.icon name="hero-pencil" class="w-4 h-4 inline mr-2" />
                  Edit
                </button>
                
                <button
                  phx-click="duplicate_persona"
                  phx-value-id={@persona.id}
                  phx-target={@myself}
                  class="w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-600"
                >
                  <.icon name="hero-document-duplicate" class="w-4 h-4 inline mr-2" />
                  Duplicate
                </button>
                
                <button
                  phx-click="export_persona"
                  phx-value-id={@persona.id}
                  phx-target={@myself}
                  class="w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-600"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4 inline mr-2" />
                  Export
                </button>
                
                <button
                  phx-click="delete_persona"
                  phx-value-id={@persona.id}
                  phx-target={@myself}
                  class="w-full text-left px-4 py-2 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900"
                  data-confirm="Are you sure you want to delete this persona?"
                >
                  <.icon name="hero-trash" class="w-4 h-4 inline mr-2" />
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Description -->
        <div class="mb-3">
          <p class="text-sm text-gray-600 dark:text-gray-300 line-clamp-2">
            <%= @persona.description || "No description available" %>
          </p>
        </div>
        
        <!-- Content preview -->
        <div class="mb-3 p-2 bg-gray-50 dark:bg-gray-900 rounded text-xs">
          <code class="text-gray-700 dark:text-gray-300 line-clamp-3">
            <%= String.slice(@persona.content, 0, 120) %>...
          </code>
        </div>
        
        <!-- Tags -->
        <div class="mb-3 flex flex-wrap gap-1">
          <%= for tag <- Enum.take(@persona.tags, 3) do %>
            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
              <%= tag %>
            </span>
          <% end %>
          
          <%= if length(@persona.tags) > 3 do %>
            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300">
              +<%= length(@persona.tags) - 3 %> more
            </span>
          <% end %>
        </div>
        
        <!-- Stats -->
        <div class="mb-3 grid grid-cols-3 gap-2 text-center">
          <div class="p-2 bg-gray-50 dark:bg-gray-900 rounded">
            <div class="text-lg font-semibold text-gray-900 dark:text-white">
              <%= @persona.application_count %>
            </div>
            <div class="text-xs text-gray-500 dark:text-gray-400">Uses</div>
          </div>
          
          <div class="p-2 bg-gray-50 dark:bg-gray-900 rounded">
            <div class="text-lg font-semibold text-gray-900 dark:text-white">
              <%= @persona.size_bytes |> div(1024) %>KB
            </div>
            <div class="text-xs text-gray-500 dark:text-gray-400">Size</div>
          </div>
          
          <div class="p-2 bg-gray-50 dark:bg-gray-900 rounded">
            <div class="text-lg font-semibold text-gray-900 dark:text-white">
              <%= if @persona.last_applied_at do %>
                <%= relative_time(@persona.last_applied_at) %>
              <% else %>
                Never
              <% end %>
            </div>
            <div class="text-xs text-gray-500 dark:text-gray-400">Used</div>
          </div>
        </div>
        
        <!-- Apply to agent section -->
        <div class="border-t pt-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
              Apply to Agent:
            </span>
            
            <div class="flex space-x-1">
              <%= for session <- @active_sessions do %>
                <button
                  phx-click="apply_persona_to_session"
                  phx-value-persona-id={@persona.id}
                  phx-value-session-id={session.id}
                  phx-target={@myself}
                  class={[
                    "px-2 py-1 text-xs rounded transition-colors",
                    session.current_persona_id == @persona.id && "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
                    session.current_persona_id != @persona.id && "bg-gray-100 text-gray-700 hover:bg-blue-100 hover:text-blue-800 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-blue-800 dark:hover:text-blue-200"
                  ]}
                  title={session.name || "Agent Session"}
                >
                  <%= if session.current_persona_id == @persona.id do %>
                    <.icon name="hero-check" class="w-3 h-3" />
                  <% else %>
                    Session <%= session.id |> String.slice(0, 4) %>
                  <% end %>
                </button>
              <% end %>
              
              <%= if @active_sessions == [] do %>
                <span class="text-xs text-gray-500 dark:text-gray-400">
                  No active sessions
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  def handle_event("edit_persona", %{"id" => id}, socket) do
    send(self(), {:edit_persona, id})
    {:noreply, socket}
  end
  
  def handle_event("duplicate_persona", %{"id" => id}, socket) do
    send(self(), {:duplicate_persona, id})
    {:noreply, socket}
  end
  
  def handle_event("export_persona", %{"id" => id}, socket) do
    send(self(), {:export_persona, id})
    {:noreply, socket}
  end
  
  def handle_event("delete_persona", %{"id" => id}, socket) do
    send(self(), {:delete_persona, id})
    {:noreply, socket}
  end
  
  def handle_event("apply_persona_to_session", %{"persona_id" => persona_id, "session_id" => session_id}, socket) do
    send(self(), {:apply_persona, persona_id, session_id})
    {:noreply, socket}
  end
  
  defp relative_time(datetime) do
    case Timex.from_now(datetime) do
      time_str -> time_str
    end
  end
end
```

### Persona Editor Component

```elixir
# lib/the_maestro_web/live/persona_live/editor_component.ex
defmodule TheMaestroWeb.PersonaLive.EditorComponent do
  use TheMaestroWeb, :live_component
  
  alias TheMaestro.Personas
  alias TheMaestro.Personas.Persona
  
  def render(assigns) do
    ~H"""
    <div class="persona-editor h-full flex flex-col">
      <!-- Editor Header -->
      <div class="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700">
        <div class="flex items-center space-x-3">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            <%= if @persona.id, do: "Edit Persona", else: "Create Persona" %>
          </h2>
          
          <%= if @persona.id do %>
            <span class="px-2 py-1 text-xs bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300 rounded">
              v<%= @persona.version %>
            </span>
          <% end %>
        </div>
        
        <div class="flex items-center space-x-2">
          <!-- Live preview toggle -->
          <button
            type="button"
            phx-click="toggle_preview"
            phx-target={@myself}
            class={[
              "px-3 py-1 text-sm rounded transition-colors",
              @show_preview && "bg-blue-500 text-white",
              !@show_preview && "bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
            ]}
          >
            <.icon name="hero-eye" class="w-4 h-4 mr-1" />
            Preview
          </button>
          
          <!-- Save button -->
          <button
            form="persona-form"
            type="submit"
            disabled={!@changeset.valid?}
            class="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <.icon name="hero-check" class="w-4 h-4 mr-1" />
            <%= if @persona.id, do: "Save Changes", else: "Create Persona" %>
          </button>
        </div>
      </div>
      
      <!-- Editor Body -->
      <div class="flex-1 flex min-h-0">
        <!-- Left Panel: Form -->
        <div class={[
          "flex-shrink-0 border-r border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800",
          @show_preview && "w-1/2" || "w-full"
        ]}>
          <div class="h-full overflow-y-auto p-4">
            <.form
              for={@changeset}
              id="persona-form"
              phx-change="validate"
              phx-submit="save"
              phx-target={@myself}
              class="space-y-4"
            >
              <!-- Basic Information -->
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@changeset[:name]}
                  label="Name"
                  placeholder="e.g., helpful-assistant"
                  required
                />
                
                <.input
                  field={@changeset[:display_name]}
                  label="Display Name"
                  placeholder="e.g., Helpful Assistant"
                />
              </div>
              
              <.input
                field={@changeset[:description]}
                type="textarea"
                label="Description"
                placeholder="Brief description of this persona's characteristics and use case"
                rows="2"
              />
              
              <!-- Tags -->
              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Tags
                </label>
                <div class="flex flex-wrap gap-1 mb-2">
                  <%= for tag <- @changeset |> Ecto.Changeset.get_field(:tags, []) do %>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                      <%= tag %>
                      <button
                        type="button"
                        phx-click="remove_tag"
                        phx-value-tag={tag}
                        phx-target={@myself}
                        class="ml-1 text-blue-600 hover:text-blue-800"
                      >
                        ×
                      </button>
                    </span>
                  <% end %>
                </div>
                
                <div class="flex">
                  <input
                    type="text"
                    placeholder="Add tag and press Enter"
                    phx-keydown="add_tag"
                    phx-key="Enter"
                    phx-target={@myself}
                    class="flex-1 rounded-l-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                  />
                  <button
                    type="button"
                    phx-click="add_tag"
                    phx-target={@myself}
                    class="px-3 py-2 border border-l-0 border-gray-300 dark:border-gray-600 bg-gray-50 dark:bg-gray-700 text-gray-500 dark:text-gray-300 rounded-r-md hover:bg-gray-100 dark:hover:bg-gray-600"
                  >
                    Add
                  </button>
                </div>
              </div>
              
              <!-- Parent Persona (for inheritance) -->
              <%= if @available_parents != [] do %>
                <.input
                  field={@changeset[:parent_persona_id]}
                  type="select"
                  label="Parent Persona (Optional)"
                  prompt="Select a parent persona for inheritance"
                  options={@available_parents}
                />
              <% end %>
              
              <!-- Content Editor -->
              <div>
                <div class="flex items-center justify-between mb-2">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Persona Content *
                  </label>
                  
                  <div class="flex items-center space-x-2 text-xs text-gray-500">
                    <span>
                      <%= @content_stats.character_count %> chars
                    </span>
                    <span>
                      ~<%= @content_stats.estimated_tokens %> tokens
                    </span>
                    
                    <%= if @content_stats.estimated_tokens > 1000 do %>
                      <span class="text-amber-500">
                        <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                        High token usage
                      </span>
                    <% end %>
                  </div>
                </div>
                
                <div class="relative">
                  <.input
                    field={@changeset[:content]}
                    type="textarea"
                    rows="12"
                    class="font-mono text-sm"
                    placeholder="Enter your persona instructions in markdown format..."
                    phx-hook="MarkdownEditor"
                    phx-debounce="300"
                  />
                  
                  <!-- Content validation indicators -->
                  <div class="absolute top-2 right-2 flex space-x-1">
                    <%= if @content_validation.has_structure do %>
                      <span class="flex items-center text-green-500" title="Good structure detected">
                        <.icon name="hero-check-circle" class="w-4 h-4" />
                      </span>
                    <% else %>
                      <span class="flex items-center text-amber-500" title="Consider adding structure (headers, etc.)">
                        <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                      </span>
                    <% end %>
                    
                    <%= if @content_validation.has_instructions do %>
                      <span class="flex items-center text-green-500" title="Instructions detected">
                        <.icon name="hero-academic-cap" class="w-4 h-4" />
                      </span>
                    <% else %>
                      <span class="flex items-center text-amber-500" title="Consider adding clear instructions">
                        <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                      </span>
                    <% end %>
                  </div>
                </div>
                
                <!-- Content templates -->
                <div class="mt-2">
                  <details class="group">
                    <summary class="text-sm text-blue-600 dark:text-blue-400 cursor-pointer hover:text-blue-800">
                      Show content templates
                    </summary>
                    <div class="mt-2 p-3 bg-gray-50 dark:bg-gray-900 rounded text-xs space-y-2">
                      <%= for template <- @content_templates do %>
                        <button
                          type="button"
                          phx-click="insert_template"
                          phx-value-template={template.id}
                          phx-target={@myself}
                          class="block w-full text-left p-2 hover:bg-gray-100 dark:hover:bg-gray-800 rounded"
                        >
                          <div class="font-medium"><%= template.name %></div>
                          <div class="text-gray-500"><%= template.description %></div>
                        </button>
                      <% end %>
                    </div>
                  </details>
                </div>
              </div>
              
              <!-- Version and Change Summary (for updates) -->
              <%= if @persona.id do %>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@changeset[:version]}
                    label="Version"
                    placeholder="e.g., 1.0.1"
                  />
                  
                  <.input
                    field={@changeset[:changes_summary]}
                    label="Changes Summary"
                    placeholder="Brief summary of what changed"
                  />
                </div>
              <% end %>
            </.form>
          </div>
        </div>
        
        <!-- Right Panel: Preview -->
        <%= if @show_preview do %>
          <div class="w-1/2 bg-gray-50 dark:bg-gray-900">
            <div class="h-full overflow-y-auto p-4">
              <div class="space-y-4">
                <!-- Rendered preview -->
                <div class="prose prose-sm dark:prose-invert max-w-none">
                  <%= raw(Earmark.as_html!(@preview_content)) %>
                </div>
                
                <!-- Token usage visualization -->
                <div class="mt-6 p-4 bg-white dark:bg-gray-800 rounded border">
                  <h4 class="text-sm font-medium mb-2">Token Usage Analysis</h4>
                  
                  <div class="space-y-2">
                    <div class="flex justify-between text-xs">
                      <span>Estimated Tokens:</span>
                      <span class={[
                        @content_stats.estimated_tokens > 1000 && "text-red-500",
                        @content_stats.estimated_tokens > 500 && @content_stats.estimated_tokens <= 1000 && "text-amber-500",
                        @content_stats.estimated_tokens <= 500 && "text-green-500"
                      ]}>
                        <%= @content_stats.estimated_tokens %>
                      </span>
                    </div>
                    
                    <div class="w-full bg-gray-200 rounded-full h-2">
                      <div
                        class="bg-blue-600 h-2 rounded-full"
                        style={"width: #{min(@content_stats.estimated_tokens / 1500 * 100, 100)}%"}
                      >
                      </div>
                    </div>
                    
                    <p class="text-xs text-gray-500">
                      Recommended to keep under 500 tokens for optimal performance
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
  
  def mount(socket) do
    socket = 
      socket
      |> assign(:show_preview, false)
      |> assign(:content_stats, %{character_count: 0, estimated_tokens: 0})
      |> assign(:content_validation, %{has_structure: false, has_instructions: false})
      |> assign(:preview_content, "")
      |> assign(:available_parents, [])
      |> assign(:content_templates, default_content_templates())
    
    {:ok, socket}
  end
  
  def update(%{persona: persona} = assigns, socket) do
    changeset = Personas.change_persona(persona)
    available_parents = load_available_parents(assigns.user_id, persona.id)
    
    socket = 
      socket
      |> assign(assigns)
      |> assign(:changeset, changeset)
      |> assign(:available_parents, available_parents)
      |> update_content_analysis(persona.content)
    
    {:ok, socket}
  end
  
  def handle_event("validate", %{"persona" => params}, socket) do
    changeset = 
      socket.assigns.persona
      |> Personas.change_persona(params)
      |> Map.put(:action, :validate)
    
    socket = 
      socket
      |> assign(:changeset, changeset)
      |> update_content_analysis(params["content"] || "")
    
    {:noreply, socket}
  end
  
  def handle_event("save", %{"persona" => params}, socket) do
    save_persona(socket, socket.assigns.live_action, params)
  end
  
  def handle_event("toggle_preview", _params, socket) do
    {:noreply, assign(socket, :show_preview, !socket.assigns.show_preview)}
  end
  
  def handle_event("add_tag", %{"key" => "Enter", "value" => tag}, socket) when tag != "" do
    add_tag_to_changeset(socket, String.trim(tag))
  end
  
  def handle_event("add_tag", %{"value" => tag}, socket) when tag != "" do
    add_tag_to_changeset(socket, String.trim(tag))
  end
  
  def handle_event("add_tag", _params, socket) do
    {:noreply, socket}
  end
  
  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    current_tags = Ecto.Changeset.get_field(socket.assigns.changeset, :tags, [])
    new_tags = List.delete(current_tags, tag)
    
    changeset = Ecto.Changeset.put_change(socket.assigns.changeset, :tags, new_tags)
    {:noreply, assign(socket, :changeset, changeset)}
  end
  
  def handle_event("insert_template", %{"template" => template_id}, socket) do
    template = Enum.find(socket.assigns.content_templates, &(&1.id == template_id))
    
    if template do
      current_content = Ecto.Changeset.get_field(socket.assigns.changeset, :content, "")
      new_content = if current_content == "", do: template.content, else: "#{current_content}\n\n#{template.content}"
      
      changeset = Ecto.Changeset.put_change(socket.assigns.changeset, :content, new_content)
      
      socket = 
        socket
        |> assign(:changeset, changeset)
        |> update_content_analysis(new_content)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
  
  defp save_persona(socket, :edit, params) do
    case Personas.update_persona(socket.assigns.persona, params) do
      {:ok, persona} ->
        send(self(), {:persona_saved, persona})
        {:noreply, socket}
        
      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
  
  defp save_persona(socket, :new, params) do
    params = Map.put(params, "user_id", socket.assigns.user_id)
    
    case Personas.create_persona(params) do
      {:ok, persona} ->
        send(self(), {:persona_created, persona})
        {:noreply, socket}
        
      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
  
  defp add_tag_to_changeset(socket, tag) do
    current_tags = Ecto.Changeset.get_field(socket.assigns.changeset, :tags, [])
    
    if tag not in current_tags do
      new_tags = [tag | current_tags]
      changeset = Ecto.Changeset.put_change(socket.assigns.changeset, :tags, new_tags)
      {:noreply, assign(socket, :changeset, changeset)}
    else
      {:noreply, socket}
    end
  end
  
  defp update_content_analysis(socket, content) do
    stats = analyze_content(content)
    validation = validate_content_structure(content)
    preview_content = content || ""
    
    socket
    |> assign(:content_stats, stats)
    |> assign(:content_validation, validation)
    |> assign(:preview_content, preview_content)
  end
  
  defp analyze_content(content) when is_binary(content) do
    char_count = String.length(content)
    estimated_tokens = div(char_count, 4)  # Rough estimate
    
    %{
      character_count: char_count,
      estimated_tokens: estimated_tokens
    }
  end
  
  defp analyze_content(_), do: %{character_count: 0, estimated_tokens: 0}
  
  defp validate_content_structure(content) when is_binary(content) do
    has_structure = String.contains?(content, ["#", "##", "###"])
    has_instructions = String.contains?(content, ["You are", "Your role", "Instructions"])
    
    %{
      has_structure: has_structure,
      has_instructions: has_instructions
    }
  end
  
  defp validate_content_structure(_), do: %{has_structure: false, has_instructions: false}
  
  defp load_available_parents(user_id, exclude_id) do
    user_id
    |> Personas.list_personas()
    |> Enum.reject(&(&1.id == exclude_id))
    |> Enum.map(&{&1.display_name || &1.name, &1.id})
  end
  
  defp default_content_templates do
    [
      %{
        id: "basic_assistant",
        name: "Basic Assistant",
        description: "Simple helpful assistant template",
        content: """
        # Assistant Role

        You are a helpful AI assistant focused on providing accurate, helpful responses.

        ## Communication Style
        - Be clear and concise
        - Ask clarifying questions when needed
        - Provide examples when helpful
        """
      },
      
      %{
        id: "technical_expert",
        name: "Technical Expert",
        description: "Template for technical domain expertise",
        content: """
        # Technical Expert

        You are an expert technical advisor with deep knowledge in your domain.

        ## Core Principles
        - Provide accurate technical information
        - Explain complex concepts clearly
        - Consider best practices and standards
        - Highlight potential risks or limitations

        ## Communication Style
        - Use precise technical language
        - Provide concrete examples and code samples
        - Break down complex problems into steps
        """
      }
    ]
  end
end
```

### Template Gallery Component

```elixir
# lib/the_maestro_web/live/persona_live/template_gallery_component.ex
defmodule TheMaestroWeb.PersonaLive.TemplateGalleryComponent do
  use TheMaestroWeb, :live_component
  
  alias TheMaestro.Personas.PersonaTemplates
  
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 overflow-y-auto bg-black bg-opacity-50">
      <div class="flex min-h-screen items-center justify-center p-4">
        <div class="relative w-full max-w-4xl bg-white dark:bg-gray-800 rounded-lg shadow-xl">
          <!-- Header -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
            <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
              Persona Template Gallery
            </h2>
            
            <button
              phx-click="close_gallery"
              phx-target={@myself}
              class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
            >
              <.icon name="hero-x-mark" class="w-6 h-6" />
            </button>
          </div>
          
          <!-- Search and Filter -->
          <div class="p-6 border-b border-gray-200 dark:border-gray-700">
            <div class="flex space-x-4">
              <div class="flex-1">
                <input
                  type="text"
                  placeholder="Search templates..."
                  phx-keyup="search_templates"
                  phx-debounce="300"
                  phx-target={@myself}
                  class="w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
                />
              </div>
              
              <select
                phx-change="filter_by_category"
                phx-target={@myself}
                class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              >
                <option value="">All Categories</option>
                <%= for category <- @categories do %>
                  <option value={category} selected={category == @selected_category}>
                    <%= String.capitalize(category) %>
                  </option>
                <% end %>
              </select>
            </div>
          </div>
          
          <!-- Templates Grid -->
          <div class="p-6 max-h-96 overflow-y-auto">
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for template <- @filtered_templates do %>
                <div class="border border-gray-200 dark:border-gray-700 rounded-lg p-4 hover:shadow-md transition-shadow">
                  <div class="flex items-start justify-between mb-2">
                    <h3 class="font-medium text-gray-900 dark:text-white">
                      <%= template.display_name %>
                    </h3>
                    
                    <%= if template.is_system_template do %>
                      <span class="px-2 py-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 rounded">
                        Official
                      </span>
                    <% end %>
                  </div>
                  
                  <p class="text-sm text-gray-600 dark:text-gray-300 mb-3">
                    <%= template.description %>
                  </p>
                  
                  <div class="flex flex-wrap gap-1 mb-3">
                    <%= for tag <- Enum.take(template.tags, 2) do %>
                      <span class="px-2 py-1 text-xs bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300 rounded">
                        <%= tag %>
                      </span>
                    <% end %>
                  </div>
                  
                  <div class="flex space-x-2">
                    <button
                      phx-click="preview_template"
                      phx-value-id={template.id}
                      phx-target={@myself}
                      class="flex-1 px-3 py-1 text-sm text-blue-600 border border-blue-600 rounded hover:bg-blue-50 dark:text-blue-400 dark:border-blue-400 dark:hover:bg-blue-900"
                    >
                      Preview
                    </button>
                    
                    <button
                      phx-click="use_template"
                      phx-value-id={template.id}
                      phx-target={@myself}
                      class="flex-1 px-3 py-1 text-sm text-white bg-blue-600 rounded hover:bg-blue-700"
                    >
                      Use Template
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
            
            <%= if @filtered_templates == [] do %>
              <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                <.icon name="hero-document-text" class="w-12 h-12 mx-auto mb-2" />
                <p>No templates found matching your criteria</p>
              </div>
            <% end %>
          </div>
          
          <!-- Template Preview Modal -->
          <%= if @preview_template do %>
            <div class="absolute inset-0 bg-white dark:bg-gray-800 rounded-lg">
              <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
                <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                  <%= @preview_template.display_name %>
                </h3>
                
                <button
                  phx-click="close_preview"
                  phx-target={@myself}
                  class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
                >
                  <.icon name="hero-x-mark" class="w-6 h-6" />
                </button>
              </div>
              
              <div class="p-6 overflow-y-auto max-h-96">
                <div class="prose prose-sm dark:prose-invert max-w-none">
                  <%= raw(Earmark.as_html!(@preview_template.content)) %>
                </div>
              </div>
              
              <div class="p-6 border-t border-gray-200 dark:border-gray-700 flex justify-end space-x-3">
                <button
                  phx-click="close_preview"
                  phx-target={@myself}
                  class="px-4 py-2 text-gray-700 dark:text-gray-300 border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-50 dark:hover:bg-gray-700"
                >
                  Cancel
                </button>
                
                <button
                  phx-click="use_template"
                  phx-value-id={@preview_template.id}
                  phx-target={@myself}
                  class="px-4 py-2 text-white bg-blue-600 rounded hover:bg-blue-700"
                >
                  Use This Template
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
  
  def mount(socket) do
    templates = PersonaTemplates.list_all_templates()
    categories = PersonaTemplates.list_categories()
    
    socket = 
      socket
      |> assign(:templates, templates)
      |> assign(:filtered_templates, templates)
      |> assign(:categories, categories)
      |> assign(:selected_category, "")
      |> assign(:search_query, "")
      |> assign(:preview_template, nil)
    
    {:ok, socket}
  end
  
  def handle_event("search_templates", %{"value" => query}, socket) do
    socket = 
      socket
      |> assign(:search_query, query)
      |> filter_templates()
    
    {:noreply, socket}
  end
  
  def handle_event("filter_by_category", %{"value" => category}, socket) do
    socket = 
      socket
      |> assign(:selected_category, category)
      |> filter_templates()
    
    {:noreply, socket}
  end
  
  def handle_event("preview_template", %{"id" => id}, socket) do
    template = Enum.find(socket.assigns.templates, &(&1.id == id))
    {:noreply, assign(socket, :preview_template, template)}
  end
  
  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview_template, nil)}
  end
  
  def handle_event("use_template", %{"id" => id}, socket) do
    send(self(), {:use_template, id})
    send(self(), :close_template_gallery)
    {:noreply, socket}
  end
  
  def handle_event("close_gallery", _params, socket) do
    send(self(), :close_template_gallery)
    {:noreply, socket}
  end
  
  defp filter_templates(socket) do
    filtered = 
      socket.assigns.templates
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_category(socket.assigns.selected_category)
    
    assign(socket, :filtered_templates, filtered)
  end
  
  defp filter_by_search(templates, ""), do: templates
  defp filter_by_search(templates, query) do
    query = String.downcase(query)
    
    Enum.filter(templates, fn template ->
      String.contains?(String.downcase(template.name), query) ||
      String.contains?(String.downcase(template.display_name), query) ||
      String.contains?(String.downcase(template.description), query)
    end)
  end
  
  defp filter_by_category(templates, ""), do: templates
  defp filter_by_category(templates, category) do
    Enum.filter(templates, &(&1.category == category))
  end
end
```

## Module Structure

```
lib/the_maestro_web/live/persona_live/
├── index.ex                     # Main persona management interface
├── show.ex                      # Individual persona details view
├── persona_card_component.ex    # Persona card component
├── editor_component.ex          # Persona editor with live preview
├── template_gallery_component.ex # Template selection interface
├── import_modal_component.ex    # File import interface
├── analytics_component.ex       # Performance analytics display
└── bulk_operations_component.ex # Bulk operation interface
```

## Integration Points

1. **ApplicationEngine Integration**: Real-time persona application to agent sessions
2. **WebSocket Updates**: Live updates when personas are modified or applied
3. **File Upload System**: Drag-and-drop import functionality
4. **Analytics Integration**: Performance metrics and usage statistics
5. **Agent Session Integration**: Real-time agent session status and persona application

## Performance Considerations

- Virtual scrolling for large persona collections
- Lazy loading of persona content and previews
- Client-side search and filtering for responsiveness
- Optimized database queries with pagination
- Image and content caching

## Accessibility Features

- Full keyboard navigation support
- ARIA labels and descriptions
- High contrast mode support
- Screen reader compatibility
- Focus management for modals and dynamic content

## Dependencies

- Story 8.1: Persona Definition & Storage System for data operations
- Story 8.2: Dynamic Persona Loading & Application for real-time persona management
- Phoenix LiveView for real-time UI updates
- Alpine.js for client-side interactivity
- Tailwind CSS for responsive design

## Definition of Done

- [ ] Main persona management interface implemented with full CRUD operations
- [ ] Visual persona cards with rich metadata and quick actions
- [ ] Advanced persona editor with live preview and validation
- [ ] Template gallery with search, filter, and preview functionality
- [ ] Real-time persona application to agent sessions
- [ ] Import/export workflows with drag-and-drop support
- [ ] Bulk operations for managing multiple personas
- [ ] Performance analytics dashboard with visual metrics
- [ ] Mobile-responsive design working across all screen sizes
- [ ] WCAG 2.1 AA accessibility compliance verified
- [ ] Comprehensive keyboard navigation implemented
- [ ] Real-time updates and synchronization functional
- [ ] Error handling with user-friendly messages
- [ ] Integration tests passing for all user workflows
- [ ] Performance benchmarks meeting requirements (<2s page load)
- [ ] Cross-browser compatibility tested (Chrome, Firefox, Safari, Edge)
- [ ] User acceptance testing completed with positive feedback