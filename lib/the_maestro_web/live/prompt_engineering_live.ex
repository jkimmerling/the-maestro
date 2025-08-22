defmodule TheMaestroWeb.PromptEngineeringLive do
  @moduledoc """
  LiveView for Prompt Engineering Tools interface.
  
  Provides a web-based interface for managing prompts, templates, experiments,
  and all other prompt engineering functionality.
  """
  
  use TheMaestroWeb, :live_view
  
  # Mock modules - would be implemented in full system
  # alias TheMaestro.Prompts.EngineeringTools.{...}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Prompt Engineering")
     |> assign(:active_tab, "dashboard")
     |> assign(:prompts, [])
     |> assign(:templates, [])
     |> assign(:experiments, [])
     |> assign(:workspaces, [])
     |> assign(:loading, false)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)
     |> load_initial_data()}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(to: ~p"/prompt-engineering?tab=#{tab}")}
  end

  def handle_event("create_prompt", %{"prompt" => prompt_params}, socket) do
    {:ok, prompt} = create_prompt(prompt_params)
    {:noreply,
     socket
     |> assign(:success_message, "Prompt '#{prompt.name}' created successfully")
     |> assign(:prompts, [prompt | socket.assigns.prompts])
     |> clear_error()}
  end

  def handle_event("delete_prompt", %{"id" => prompt_id}, socket) do
    {:ok, _} = delete_prompt(prompt_id)
    updated_prompts = Enum.reject(socket.assigns.prompts, &(&1.id == prompt_id))
    {:noreply,
     socket
     |> assign(:success_message, "Prompt deleted successfully")
     |> assign(:prompts, updated_prompts)
     |> clear_error()}
  end

  def handle_event("run_experiment", %{"id" => experiment_id}, socket) do
    socket = assign(socket, :loading, true)
    {:ok, results} = run_experiment(experiment_id)
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:success_message, "Experiment completed. Score: #{results.score}")
     |> clear_error()}
  end

  def handle_event("generate_report", _params, socket) do
    socket = assign(socket, :loading, true)
    {:ok, report_path} = generate_documentation_report()
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:success_message, "Report generated: #{report_path}")
     |> clear_error()}
  end

  def handle_event("clear_message", _params, socket) do
    {:noreply,
     socket
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="prompt-engineering-dashboard">
      <.header>
        🛠️ Prompt Engineering Tools
        <:subtitle>Comprehensive prompt development and management interface</:subtitle>
        <:actions>
          <.button phx-click="generate_report" class="bg-blue-600 hover:bg-blue-700">
            📊 Generate Report
          </.button>
        </:actions>
      </.header>

      <!-- Status Messages -->
      <div :if={@error_message} class="alert alert-error mb-4">
        <div class="flex items-center justify-between">
          <span>❌ <%= @error_message %></span>
          <button phx-click="clear_message" class="text-red-800 hover:text-red-900">×</button>
        </div>
      </div>
      
      <div :if={@success_message} class="alert alert-success mb-4">
        <div class="flex items-center justify-between">
          <span>✅ <%= @success_message %></span>
          <button phx-click="clear_message" class="text-green-800 hover:text-green-900">×</button>
        </div>
      </div>

      <!-- Loading Indicator -->
      <div :if={@loading} class="loading-indicator mb-4">
        <div class="flex items-center space-x-2">
          <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
          <span>Processing...</span>
        </div>
      </div>

      <!-- Navigation Tabs -->
      <div class="tabs mb-6">
        <.tab_button active={@active_tab == "dashboard"} tab="dashboard">
          📊 Dashboard
        </.tab_button>
        <.tab_button active={@active_tab == "prompts"} tab="prompts">
          📝 Prompts
        </.tab_button>
        <.tab_button active={@active_tab == "templates"} tab="templates">
          📋 Templates
        </.tab_button>
        <.tab_button active={@active_tab == "experiments"} tab="experiments">
          🧪 Experiments
        </.tab_button>
        <.tab_button active={@active_tab == "workspaces"} tab="workspaces">
          🏗️ Workspaces
        </.tab_button>
        <.tab_button active={@active_tab == "analytics"} tab="analytics">
          📈 Analytics
        </.tab_button>
      </div>

      <!-- Tab Content -->
      <div class="tab-content">
        <div :if={@active_tab == "dashboard"}>
          <.dashboard_view assigns={assigns} />
        </div>
        
        <div :if={@active_tab == "prompts"}>
          <.prompts_view assigns={assigns} />
        </div>
        
        <div :if={@active_tab == "templates"}>
          <.templates_view assigns={assigns} />
        </div>
        
        <div :if={@active_tab == "experiments"}>
          <.experiments_view assigns={assigns} />
        </div>
        
        <div :if={@active_tab == "workspaces"}>
          <.workspaces_view assigns={assigns} />
        </div>
        
        <div :if={@active_tab == "analytics"}>
          <.analytics_view assigns={assigns} />
        </div>
      </div>
    </div>
    """
  end

  # Tab button component
  attr :active, :boolean, required: true
  attr :tab, :string, required: true
  slot :inner_block, required: true
  
  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "tab-button px-4 py-2 mr-2 rounded-lg transition-colors",
        @active && "bg-blue-600 text-white" || "bg-gray-200 hover:bg-gray-300"
      ]}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  # Dashboard view
  defp dashboard_view(assigns) do
    ~H"""
    <div class="dashboard-grid grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <.stats_card title="Total Prompts" value={length(@prompts)} icon="📝" />
      <.stats_card title="Templates" value={length(@templates)} icon="📋" />
      <.stats_card title="Experiments" value={length(@experiments)} icon="🧪" />
      <.stats_card title="Workspaces" value={length(@workspaces)} icon="🏗️" />
      <.stats_card title="Success Rate" value="94.2%" icon="📈" />
      <.stats_card title="Avg Performance" value="87.5%" icon="⚡" />
    </div>

    <div class="recent-activity mt-8">
      <h3 class="text-xl font-semibold mb-4">Recent Activity</h3>
      <div class="activity-list space-y-2">
        <.activity_item icon="📝" text="Created prompt 'Code Review Assistant'" time="2 minutes ago" />
        <.activity_item icon="🧪" text="Experiment 'A/B Test v2.1' completed" time="15 minutes ago" />
        <.activity_item icon="📋" text="Updated template 'Bug Analysis'" time="1 hour ago" />
        <.activity_item icon="🏗️" text="Workspace 'ML Project' synchronized" time="2 hours ago" />
      </div>
    </div>

    <div class="quick-actions mt-8">
      <h3 class="text-xl font-semibold mb-4">Quick Actions</h3>
      <div class="action-buttons flex flex-wrap gap-4">
        <.button class="bg-green-600 hover:bg-green-700">
          📝 New Prompt
        </.button>
        <.button class="bg-purple-600 hover:bg-purple-700">
          🧪 Run Experiment
        </.button>
        <.button class="bg-orange-600 hover:bg-orange-700">
          📋 Create Template
        </.button>
        <.button class="bg-blue-600 hover:bg-blue-700">
          🏗️ New Workspace
        </.button>
      </div>
    </div>
    """
  end

  # Prompts view
  defp prompts_view(assigns) do
    ~H"""
    <div class="prompts-section">
      <div class="section-header flex justify-between items-center mb-6">
        <h2 class="text-2xl font-semibold">Prompt Management</h2>
        <.button class="bg-green-600 hover:bg-green-700">
          📝 Create New Prompt
        </.button>
      </div>

      <div class="prompts-grid grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div :for={prompt <- @prompts} class="prompt-card bg-white rounded-lg shadow-md p-6">
          <div class="flex justify-between items-start mb-3">
            <h3 class="font-semibold text-lg"><%= prompt.name %></h3>
            <span class="text-sm text-gray-500"><%= prompt.category %></span>
          </div>
          
          <p class="text-gray-600 mb-4 line-clamp-3"><%= prompt.description || "No description" %></p>
          
          <div class="flex justify-between items-center">
            <span class="text-xs text-gray-500">
              Updated <%= format_date(prompt.updated_at) %>
            </span>
            <div class="flex space-x-2">
              <.button class="bg-blue-600 hover:bg-blue-700">Edit</.button>
              <.button 
                 
                class="bg-red-600 hover:bg-red-700"
                phx-click="delete_prompt"
                phx-value-id={prompt.id}
                data-confirm="Are you sure?"
              >
                Delete
              </.button>
            </div>
          </div>
        </div>
      </div>

      <div :if={Enum.empty?(@prompts)} class="empty-state text-center py-12">
        <div class="text-6xl mb-4">📝</div>
        <h3 class="text-xl font-semibold mb-2">No Prompts Yet</h3>
        <p class="text-gray-600 mb-4">Create your first prompt to get started with prompt engineering.</p>
        <.button class="bg-green-600 hover:bg-green-700">
          📝 Create Your First Prompt
        </.button>
      </div>
    </div>
    """
  end

  # Templates view
  defp templates_view(assigns) do
    ~H"""
    <div class="templates-section">
      <div class="section-header flex justify-between items-center mb-6">
        <h2 class="text-2xl font-semibold">Template Library</h2>
        <.button class="bg-purple-600 hover:bg-purple-700">
          📋 Create Template
        </.button>
      </div>

      <div class="templates-grid grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div class="template-card bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center mb-3">
            <span class="text-2xl mr-3">🔍</span>
            <h3 class="font-semibold text-lg">Code Review</h3>
          </div>
          <p class="text-gray-600 mb-4">Template for conducting thorough code reviews</p>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500">Software Engineering</span>
            <.button  class="bg-purple-600 hover:bg-purple-700">Use Template</.button>
          </div>
        </div>

        <div class="template-card bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center mb-3">
            <span class="text-2xl mr-3">🐛</span>
            <h3 class="font-semibold text-lg">Bug Analysis</h3>
          </div>
          <p class="text-gray-600 mb-4">Systematic approach to analyzing and fixing bugs</p>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500">Software Engineering</span>
            <.button  class="bg-purple-600 hover:bg-purple-700">Use Template</.button>
          </div>
        </div>

        <div class="template-card bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center mb-3">
            <span class="text-2xl mr-3">📊</span>
            <h3 class="font-semibold text-lg">Data Summary</h3>
          </div>
          <p class="text-gray-600 mb-4">Template for summarizing data analysis results</p>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500">Data Science</span>
            <.button  class="bg-purple-600 hover:bg-purple-700">Use Template</.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Experiments view
  defp experiments_view(assigns) do
    ~H"""
    <div class="experiments-section">
      <div class="section-header flex justify-between items-center mb-6">
        <h2 class="text-2xl font-semibold">Experiments</h2>
        <.button class="bg-orange-600 hover:bg-orange-700">
          🧪 New Experiment
        </.button>
      </div>

      <div class="experiments-list space-y-4">
        <div :for={experiment <- @experiments} class="experiment-card bg-white rounded-lg shadow-md p-6">
          <div class="flex justify-between items-start">
            <div>
              <h3 class="font-semibold text-lg mb-2"><%= experiment.name %></h3>
              <p class="text-gray-600 mb-3"><%= experiment.description %></p>
              <div class="flex items-center space-x-4">
                <span class="text-sm">Status: 
                  <span class={[
                    "px-2 py-1 rounded text-xs font-medium",
                    experiment.status == "running" && "bg-blue-100 text-blue-800" || 
                    experiment.status == "completed" && "bg-green-100 text-green-800" ||
                    "bg-gray-100 text-gray-800"
                  ]}>
                    <%= experiment.status %>
                  </span>
                </span>
                <span class="text-sm text-gray-500">Variants: <%= experiment.variants %></span>
              </div>
            </div>
            <div class="flex space-x-2">
              <.button 
                 
                class="bg-orange-600 hover:bg-orange-700"
                phx-click="run_experiment"
                phx-value-id={experiment.id}
              >
                🧪 Run
              </.button>
              <.button  class="bg-blue-600 hover:bg-blue-700">📊 Results</.button>
            </div>
          </div>
        </div>
      </div>

      <div :if={Enum.empty?(@experiments)} class="empty-state text-center py-12">
        <div class="text-6xl mb-4">🧪</div>
        <h3 class="text-xl font-semibold mb-2">No Experiments</h3>
        <p class="text-gray-600 mb-4">Start experimenting with different prompt variations to optimize performance.</p>
        <.button class="bg-orange-600 hover:bg-orange-700">
          🧪 Create First Experiment
        </.button>
      </div>
    </div>
    """
  end

  # Workspaces view
  defp workspaces_view(assigns) do
    ~H"""
    <div class="workspaces-section">
      <div class="section-header flex justify-between items-center mb-6">
        <h2 class="text-2xl font-semibold">Workspaces</h2>
        <.button class="bg-indigo-600 hover:bg-indigo-700">
          🏗️ New Workspace
        </.button>
      </div>

      <div class="workspaces-grid grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="workspace-card bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center mb-3">
            <span class="text-2xl mr-3">💻</span>
            <h3 class="font-semibold text-lg">Development</h3>
          </div>
          <p class="text-gray-600 mb-4">Main development workspace for prompt engineering</p>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500">5 prompts • 3 experiments</span>
            <.button  class="bg-indigo-600 hover:bg-indigo-700">Open</.button>
          </div>
        </div>

        <div class="workspace-card bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center mb-3">
            <span class="text-2xl mr-3">🤖</span>
            <h3 class="font-semibold text-lg">ML Project</h3>
          </div>
          <p class="text-gray-600 mb-4">Machine learning focused prompt development</p>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500">8 prompts • 2 experiments</span>
            <.button  class="bg-indigo-600 hover:bg-indigo-700">Open</.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Analytics view
  defp analytics_view(assigns) do
    ~H"""
    <div class="analytics-section">
      <h2 class="text-2xl font-semibold mb-6">Performance Analytics</h2>

      <div class="analytics-grid grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="chart-card bg-white rounded-lg shadow-md p-6">
          <h3 class="font-semibold mb-4">Performance Trends</h3>
          <div class="chart-placeholder bg-gray-100 h-64 flex items-center justify-center rounded">
            📈 Performance chart would go here
          </div>
        </div>

        <div class="chart-card bg-white rounded-lg shadow-md p-6">
          <h3 class="font-semibold mb-4">Success Rates</h3>
          <div class="chart-placeholder bg-gray-100 h-64 flex items-center justify-center rounded">
            📊 Success rate chart would go here
          </div>
        </div>

        <div class="metrics-card bg-white rounded-lg shadow-md p-6">
          <h3 class="font-semibold mb-4">Key Metrics</h3>
          <div class="metrics-list space-y-3">
            <div class="flex justify-between">
              <span>Average Response Time</span>
              <span class="font-medium">1.24s</span>
            </div>
            <div class="flex justify-between">
              <span>Success Rate</span>
              <span class="font-medium">94.2%</span>
            </div>
            <div class="flex justify-between">
              <span>Quality Score</span>
              <span class="font-medium">87.5%</span>
            </div>
            <div class="flex justify-between">
              <span>Total Experiments</span>
              <span class="font-medium">23</span>
            </div>
          </div>
        </div>

        <div class="insights-card bg-white rounded-lg shadow-md p-6">
          <h3 class="font-semibold mb-4">Insights</h3>
          <div class="insights-list space-y-3">
            <div class="insight-item">
              <span class="text-green-600">✅</span>
              <span class="ml-2">Templates improve consistency by 23%</span>
            </div>
            <div class="insight-item">
              <span class="text-blue-600">📊</span>
              <span class="ml-2">A/B testing shows 15% performance gain</span>
            </div>
            <div class="insight-item">
              <span class="text-orange-600">⚡</span>
              <span class="ml-2">Optimization reduced response time by 31%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper components
  defp stats_card(assigns) do
    ~H"""
    <div class="stats-card bg-white rounded-lg shadow-md p-6">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm text-gray-600 mb-1"><%= @title %></p>
          <p class="text-2xl font-bold"><%= @value %></p>
        </div>
        <div class="text-3xl"><%= @icon %></div>
      </div>
    </div>
    """
  end

  defp activity_item(assigns) do
    ~H"""
    <div class="activity-item flex items-center space-x-3 p-3 bg-white rounded-lg shadow-sm">
      <span class="text-2xl"><%= @icon %></span>
      <div class="flex-1">
        <p class="text-sm"><%= @text %></p>
      </div>
      <span class="text-xs text-gray-500"><%= @time %></span>
    </div>
    """
  end

  # Helper functions
  defp load_initial_data(socket) do
    # Load prompts, templates, experiments, etc.
    # For now, return mock data
    socket
    |> assign(:prompts, get_mock_prompts())
    |> assign(:templates, get_mock_templates())
    |> assign(:experiments, get_mock_experiments())
    |> assign(:workspaces, get_mock_workspaces())
  end

  defp clear_error(socket) do
    assign(socket, :error_message, nil)
  end

  defp create_prompt(_params) do
    # Mock implementation
    {:ok, %{
      id: "prompt_#{System.unique_integer()}",
      name: "New Prompt",
      description: "A newly created prompt",
      category: "general",
      updated_at: DateTime.utc_now()
    }}
  end

  defp delete_prompt(_id) do
    # Mock implementation
    {:ok, :deleted}
  end

  defp run_experiment(_id) do
    # Mock implementation
    {:ok, %{score: 0.87}}
  end

  defp generate_documentation_report do
    # Mock implementation
    {:ok, "/tmp/prompt_engineering_report.pdf"}
  end

  defp format_date(datetime) do
    case datetime do
      %DateTime{} -> Calendar.strftime(datetime, "%Y-%m-%d")
      _ -> "Unknown"
    end
  end

  # Mock data functions
  defp get_mock_prompts do
    [
      %{
        id: "prompt_1",
        name: "Code Review Assistant",
        description: "Helps with comprehensive code reviews",
        category: "software_engineering",
        updated_at: DateTime.utc_now()
      },
      %{
        id: "prompt_2", 
        name: "Bug Analysis Helper",
        description: "Systematic bug analysis and resolution",
        category: "software_engineering",
        updated_at: DateTime.add(DateTime.utc_now(), -3600)
      }
    ]
  end

  defp get_mock_templates do
    [
      %{id: "template_1", name: "Code Review", category: "software_engineering"},
      %{id: "template_2", name: "Bug Analysis", category: "software_engineering"},
      %{id: "template_3", name: "Data Summary", category: "data_science"}
    ]
  end

  defp get_mock_experiments do
    [
      %{
        id: "exp_1",
        name: "A/B Test v2.1",
        description: "Testing prompt variations for better accuracy",
        status: "completed",
        variants: 3
      },
      %{
        id: "exp_2",
        name: "Performance Optimization",
        description: "Optimizing response time vs quality trade-off",
        status: "running",
        variants: 2
      }
    ]
  end

  defp get_mock_workspaces do
    [
      %{id: "ws_1", name: "Development", prompts: 5, experiments: 3},
      %{id: "ws_2", name: "ML Project", prompts: 8, experiments: 2}
    ]
  end
end