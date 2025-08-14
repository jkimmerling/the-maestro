# Story 9.2: Template Agent Storage & Retrieval System

## User Story

**As a** user of TheMaestro  
**I want** a high-performance template agent storage and retrieval system with advanced query capabilities, intelligent caching, and efficient data management  
**so that** I can quickly discover, filter, search, and access template agents with sub-second response times, even when working with large template libraries containing thousands of templates

## Acceptance Criteria

1. **High-Performance Database Operations**: Optimized database queries with proper indexing for template storage, retrieval, and complex filtering operations
2. **Advanced Search and Discovery**: Full-text search capabilities with relevance ranking, faceted filtering, and intelligent suggestions
3. **Intelligent Caching System**: Multi-layer caching strategy with automatic cache invalidation and preloading for frequently accessed templates
4. **Template Library Management**: Comprehensive system for organizing, categorizing, and curating template collections with metadata management
5. **Scalable Query Architecture**: Database query optimization supporting concurrent operations for 1000+ users with <500ms response times
6. **Template Versioning Storage**: Complete versioning system with storage optimization, migration tracking, and rollback capabilities
7. **Template Relationship Management**: Efficient storage and retrieval of template inheritance hierarchies and dependency relationships
8. **Batch Operations Support**: Bulk template operations for importing, exporting, and managing large template sets efficiently
9. **Template Analytics Storage**: Data collection and storage infrastructure for template usage analytics, performance metrics, and optimization insights
10. **Advanced Filtering Capabilities**: Multi-criteria filtering by category, tags, rating, usage patterns, author, organization, and custom attributes
11. **Template Recommendation Engine**: Data infrastructure supporting intelligent template recommendations based on user behavior and context
12. **Real-time Template Synchronization**: Live updates for template changes with real-time notifications and conflict resolution
13. **Template Backup and Recovery**: Automated backup system with point-in-time recovery and disaster recovery capabilities
14. **Permission-Aware Retrieval**: Security-integrated queries respecting user permissions, organization boundaries, and privacy settings
15. **Template Popularity Tracking**: Usage metrics, rating aggregation, and trend analysis for template discovery optimization
16. **Geographic Distribution Support**: Multi-region template storage with automatic failover and regional optimization
17. **Template Import/Export System**: Standardized format for template data exchange with validation and migration support
18. **Query Performance Optimization**: Database query analysis, optimization, and monitoring with performance alerting
19. **Template Content Indexing**: Advanced indexing for template configurations, metadata, and relationships for fast retrieval
20. **Collaborative Features Storage**: Data infrastructure for template sharing, collaboration, and team-based template management
21. **Template Audit Trail**: Complete audit logging with searchable history of template changes and access patterns
22. **Template Validation Pipeline**: Background validation processes ensuring template integrity and dependency resolution
23. **Storage Optimization**: Efficient storage patterns reducing redundancy while maintaining fast access times
24. **Template Migration Framework**: Database migration system for template schema evolution and data transformation
25. **Real-time Performance Monitoring**: Comprehensive monitoring of storage operations with alerting and performance analytics

## Technical Implementation

### Database Schema Implementation

```elixir
# priv/repo/migrations/20240315_create_agent_templates_system.exs
defmodule TheMaestro.Repo.Migrations.CreateAgentTemplatesSystem do
  use Ecto.Migration

  def up do
    # Create agent templates table with comprehensive indexing
    create table(:agent_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, size: 100
      add :display_name, :string, size: 200
      add :description, :text, null: false
      add :version, :string, null: false, default: "1.0.0"
      add :schema_version, :string, null: false, default: "1.0"
      add :category, :string, null: false
      add :tags, {:array, :string}, default: []
      add :is_public, :boolean, default: false, null: false
      add :is_featured, :boolean, default: false, null: false
      add :is_system_template, :boolean, default: false, null: false
      add :is_deprecated, :boolean, default: false, null: false
      
      # Configuration fields (JSONB for efficient querying)
      add :provider_config, :map, null: false, default: %{}
      add :persona_config, :map, null: false, default: %{}
      add :tool_config, :map, null: false, default: %{}
      add :prompt_config, :map, null: false, default: %{}
      add :deployment_config, :map, null: false, default: %{}
      add :configuration_hash, :string, null: false
      
      # Relationships
      add :author_id, references(:users, type: :binary_id), null: false
      add :parent_template_id, references(:agent_templates, type: :binary_id)
      add :organization_id, references(:organizations, type: :binary_id)
      
      # Analytics and metrics
      add :usage_count, :bigint, default: 0, null: false
      add :instantiation_count, :bigint, default: 0, null: false
      add :rating_average, :float, default: 0.0, null: false
      add :rating_count, :integer, default: 0, null: false
      add :last_used_at, :naive_datetime_usec
      add :performance_score, :float, default: 0.0
      
      # Template metadata
      add :size_estimate_kb, :integer, default: 0
      add :complexity_score, :float, default: 0.0
      add :compatibility_matrix, :map, default: %{}
      add :validation_status, :string, default: "pending"
      add :validation_errors, {:array, :map}, default: []
      add :last_validated_at, :naive_datetime_usec
      
      timestamps(type: :naive_datetime_usec)
    end

    # Create comprehensive indexes for performance
    create unique_index(:agent_templates, [:name, :author_id])
    create index(:agent_templates, [:author_id])
    create index(:agent_templates, [:parent_template_id])
    create index(:agent_templates, [:organization_id])
    create index(:agent_templates, [:category])
    create index(:agent_templates, [:is_public])
    create index(:agent_templates, [:is_featured])
    create index(:agent_templates, [:is_system_template])
    create index(:agent_templates, [:usage_count])
    create index(:agent_templates, [:rating_average])
    create index(:agent_templates, [:last_used_at])
    create index(:agent_templates, [:inserted_at])
    create index(:agent_templates, [:configuration_hash])
    create index(:agent_templates, [:validation_status])
    
    # GIN indexes for array and JSONB columns
    create index(:agent_templates, [:tags], using: :gin)
    create index(:agent_templates, [:provider_config], using: :gin)
    create index(:agent_templates, [:persona_config], using: :gin)
    create index(:agent_templates, [:tool_config], using: :gin)
    create index(:agent_templates, [:prompt_config], using: :gin)
    create index(:agent_templates, [:deployment_config], using: :gin)
    
    # Full-text search index
    execute """
    CREATE INDEX agent_templates_search_idx ON agent_templates 
    USING gin(to_tsvector('english', 
      coalesce(name, '') || ' ' || 
      coalesce(display_name, '') || ' ' || 
      coalesce(description, '') || ' ' || 
      array_to_string(tags, ' ')
    ))
    """

    # Template instantiations table
    create table(:template_instantiations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, references(:agent_templates, type: :binary_id), null: false
      add :agent_session_id, references(:conversation_sessions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id), null: false
      add :instantiation_config, :map, default: %{}
      add :instantiation_status, :string, default: "pending", null: false
      add :instantiation_time_ms, :integer
      add :performance_metrics, :map, default: %{}
      add :user_satisfaction_score, :float
      add :error_log, :text
      add :context_metadata, :map, default: %{}
      
      timestamps(type: :naive_datetime_usec)
    end

    create index(:template_instantiations, [:template_id])
    create index(:template_instantiations, [:user_id])
    create index(:template_instantiations, [:agent_session_id])
    create index(:template_instantiations, [:instantiation_status])
    create index(:template_instantiations, [:inserted_at])
    create index(:template_instantiations, [:user_satisfaction_score])

    # Template ratings table
    create table(:template_ratings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, references(:agent_templates, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :rating, :integer, null: false
      add :review, :text
      add :usage_context, :string
      add :helpful_votes, :integer, default: 0
      add :total_votes, :integer, default: 0
      add :verified_usage, :boolean, default: false
      
      timestamps(type: :naive_datetime_usec)
    end

    create unique_index(:template_ratings, [:template_id, :user_id])
    create index(:template_ratings, [:template_id])
    create index(:template_ratings, [:user_id])
    create index(:template_ratings, [:rating])
    create index(:template_ratings, [:verified_usage])

    # Template collections table
    create table(:template_collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, size: 100
      add :display_name, :string, size: 200
      add :description, :text
      add :owner_id, references(:users, type: :binary_id), null: false
      add :organization_id, references(:organizations, type: :binary_id)
      add :is_public, :boolean, default: false, null: false
      add :is_featured, :boolean, default: false, null: false
      add :template_ids, {:array, :binary_id}, default: []
      add :collection_type, :string, default: "user_created"
      add :sorting_criteria, :map, default: %{}
      add :access_permissions, :map, default: %{}
      
      timestamps(type: :naive_datetime_usec)
    end

    create unique_index(:template_collections, [:name, :owner_id])
    create index(:template_collections, [:owner_id])
    create index(:template_collections, [:organization_id])
    create index(:template_collections, [:is_public])
    create index(:template_collections, [:is_featured])
    create index(:template_collections, [:collection_type])
    create index(:template_collections, [:template_ids], using: :gin)

    # Template usage analytics table
    create table(:template_usage_analytics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, references(:agent_templates, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id)
      add :organization_id, references(:organizations, type: :binary_id)
      add :event_type, :string, null: false
      add :event_data, :map, default: %{}
      add :session_id, :string
      add :ip_address, :inet
      add :user_agent, :string
      add :performance_data, :map, default: %{}
      add :occurred_at, :naive_datetime_usec, null: false
      
      timestamps(type: :naive_datetime_usec)
    end

    create index(:template_usage_analytics, [:template_id])
    create index(:template_usage_analytics, [:user_id])
    create index(:template_usage_analytics, [:organization_id])
    create index(:template_usage_analytics, [:event_type])
    create index(:template_usage_analytics, [:occurred_at])
    create index(:template_usage_analytics, [:session_id])

    # Template cache entries table
    create table(:template_cache_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cache_key, :string, null: false, size: 255
      add :cache_data, :binary, null: false
      add :template_id, references(:agent_templates, type: :binary_id)
      add :cache_type, :string, null: false
      add :expires_at, :naive_datetime_usec, null: false
      add :hit_count, :bigint, default: 0
      add :last_accessed_at, :naive_datetime_usec, null: false
      add :size_bytes, :integer, null: false
      
      timestamps(type: :naive_datetime_usec)
    end

    create unique_index(:template_cache_entries, [:cache_key])
    create index(:template_cache_entries, [:template_id])
    create index(:template_cache_entries, [:cache_type])
    create index(:template_cache_entries, [:expires_at])
    create index(:template_cache_entries, [:last_accessed_at])

    # Template search suggestions table
    create table(:template_search_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :query_text, :string, null: false
      add :suggestion_text, :string, null: false
      add :suggestion_type, :string, null: false
      add :relevance_score, :float, default: 0.0
      add :usage_count, :bigint, default: 0
      add :template_ids, {:array, :binary_id}, default: []
      add :is_active, :boolean, default: true
      
      timestamps(type: :naive_datetime_usec)
    end

    create index(:template_search_suggestions, [:query_text])
    create index(:template_search_suggestions, [:suggestion_type])
    create index(:template_search_suggestions, [:relevance_score])
    create index(:template_search_suggestions, [:usage_count])
    create index(:template_search_suggestions, [:is_active])
  end

  def down do
    drop table(:template_search_suggestions)
    drop table(:template_cache_entries)
    drop table(:template_usage_analytics)
    drop table(:template_collections)
    drop table(:template_ratings)
    drop table(:template_instantiations)
    drop table(:agent_templates)
  end
end
```

### Template Storage Service

```elixir
# lib/the_maestro/agent_templates/storage_service.ex
defmodule TheMaestro.AgentTemplates.StorageService do
  @moduledoc """
  High-performance template storage and retrieval service with advanced caching and query optimization.
  """
  
  use GenServer
  import Ecto.Query
  alias TheMaestro.Repo
  alias TheMaestro.AgentTemplates.{Template, TemplateInstantiation, TemplateRating, TemplateCollection}
  alias TheMaestro.AgentTemplates.{CacheManager, QueryOptimizer, SearchEngine}

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store a new template with validation and indexing
  """
  def store_template(template_attrs, user_id) do
    GenServer.call(__MODULE__, {:store_template, template_attrs, user_id})
  end

  @doc """
  Retrieve template by ID with caching
  """
  def get_template(template_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_template, template_id, opts})
  end

  @doc """
  Update existing template with cache invalidation
  """
  def update_template(template_id, updates, user_id) do
    GenServer.call(__MODULE__, {:update_template, template_id, updates, user_id})
  end

  @doc """
  Delete template with cascade handling
  """
  def delete_template(template_id, user_id) do
    GenServer.call(__MODULE__, {:delete_template, template_id, user_id})
  end

  @doc """
  Search templates with advanced filtering and ranking
  """
  def search_templates(query, filters \\ %{}, opts \\ %{}) do
    GenServer.call(__MODULE__, {:search_templates, query, filters, opts})
  end

  @doc """
  Get templates for user with permission filtering
  """
  def get_user_templates(user_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:get_user_templates, user_id, opts})
  end

  @doc """
  Get featured templates with caching
  """
  def get_featured_templates(opts \\ %{}) do
    GenServer.call(__MODULE__, {:get_featured_templates, opts})
  end

  @doc """
  Get templates by category with filtering
  """
  def get_templates_by_category(category, opts \\ %{}) do
    GenServer.call(__MODULE__, {:get_templates_by_category, category, opts})
  end

  @doc """
  Get template recommendations based on user context
  """
  def get_template_recommendations(user_id, context \\ %{}) do
    GenServer.call(__MODULE__, {:get_template_recommendations, user_id, context})
  end

  @doc """
  Bulk operations for template management
  """
  def bulk_operation(operation, template_ids, user_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:bulk_operation, operation, template_ids, user_id, opts}, 30_000)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    state = %{
      cache_manager: CacheManager.new(),
      query_optimizer: QueryOptimizer.new(),
      search_engine: SearchEngine.new(),
      performance_metrics: %{},
      last_cleanup: DateTime.utc_now()
    }
    
    # Schedule periodic maintenance
    schedule_maintenance()
    
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:store_template, template_attrs, user_id}, _from, state) do
    result = with {:ok, validated_attrs} <- validate_template_attrs(template_attrs),
                  {:ok, template} <- create_template_with_transaction(validated_attrs, user_id),
                  :ok <- update_search_index(template),
                  :ok <- invalidate_related_caches(template) do
      {:ok, template}
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_template, template_id, opts}, _from, state) do
    cache_key = "template:#{template_id}:#{:erlang.phash2(opts)}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, template} -> 
        track_cache_hit(template_id)
        {:ok, template}
      
      :miss ->
        case fetch_template_from_db(template_id, opts) do
          {:ok, template} ->
            CacheManager.put(state.cache_manager, cache_key, template, ttl: 300)
            track_cache_miss(template_id)
            {:ok, template}
          
          error -> error
        end
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:update_template, template_id, updates, user_id}, _from, state) do
    result = with {:ok, template} <- get_template_for_update(template_id, user_id),
                  {:ok, validated_updates} <- validate_template_updates(updates),
                  {:ok, updated_template} <- update_template_with_transaction(template, validated_updates),
                  :ok <- update_search_index(updated_template),
                  :ok <- invalidate_template_caches(template_id) do
      {:ok, updated_template}
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete_template, template_id, user_id}, _from, state) do
    result = with {:ok, template} <- get_template_for_update(template_id, user_id),
                  :ok <- validate_template_deletion(template),
                  {:ok, _} <- delete_template_with_transaction(template),
                  :ok <- remove_from_search_index(template_id),
                  :ok <- invalidate_template_caches(template_id) do
      :ok
    else
      error -> error
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:search_templates, query, filters, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Check cache for search results
    cache_key = "search:#{:erlang.phash2({query, filters, opts})}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, results} -> {:ok, results}
      :miss ->
        case perform_template_search(query, filters, opts, state) do
          {:ok, results} ->
            CacheManager.put(state.cache_manager, cache_key, results, ttl: 60)
            {:ok, results}
          error -> error
        end
    end
    
    # Track search performance
    duration = System.monotonic_time(:millisecond) - start_time
    track_search_performance(query, duration)
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_user_templates, user_id, opts}, _from, state) do
    cache_key = "user_templates:#{user_id}:#{:erlang.phash2(opts)}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, templates} -> {:ok, templates}
      :miss ->
        case fetch_user_templates(user_id, opts) do
          {:ok, templates} ->
            CacheManager.put(state.cache_manager, cache_key, templates, ttl: 120)
            {:ok, templates}
          error -> error
        end
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_featured_templates, opts}, _from, state) do
    cache_key = "featured_templates:#{:erlang.phash2(opts)}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, templates} -> {:ok, templates}
      :miss ->
        case fetch_featured_templates(opts) do
          {:ok, templates} ->
            CacheManager.put(state.cache_manager, cache_key, templates, ttl: 600)
            {:ok, templates}
          error -> error
        end
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_templates_by_category, category, opts}, _from, state) do
    cache_key = "category_templates:#{category}:#{:erlang.phash2(opts)}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, templates} -> {:ok, templates}
      :miss ->
        case fetch_templates_by_category(category, opts) do
          {:ok, templates} ->
            CacheManager.put(state.cache_manager, cache_key, templates, ttl: 300)
            {:ok, templates}
          error -> error
        end
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_template_recommendations, user_id, context}, _from, state) do
    cache_key = "recommendations:#{user_id}:#{:erlang.phash2(context)}"
    
    result = case CacheManager.get(state.cache_manager, cache_key) do
      {:hit, recommendations} -> {:ok, recommendations}
      :miss ->
        case generate_template_recommendations(user_id, context, state) do
          {:ok, recommendations} ->
            CacheManager.put(state.cache_manager, cache_key, recommendations, ttl: 180)
            {:ok, recommendations}
          error -> error
        end
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:bulk_operation, operation, template_ids, user_id, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case operation do
      :export -> bulk_export_templates(template_ids, user_id, opts)
      :import -> bulk_import_templates(template_ids, user_id, opts)
      :update -> bulk_update_templates(template_ids, user_id, opts)
      :delete -> bulk_delete_templates(template_ids, user_id, opts)
      :validate -> bulk_validate_templates(template_ids, opts)
      _ -> {:error, "Unknown bulk operation: #{operation}"}
    end
    
    duration = System.monotonic_time(:millisecond) - start_time
    track_bulk_operation_performance(operation, length(template_ids), duration)
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:maintenance, state) do
    new_state = perform_maintenance(state)
    schedule_maintenance()
    {:noreply, new_state}
  end

  # Private Implementation Functions

  defp validate_template_attrs(attrs) do
    # Comprehensive validation using the schema validator
    case TheMaestro.AgentTemplates.SchemaValidator.validate_template(attrs) do
      {:ok, validated_attrs} ->
        {:ok, Map.put(validated_attrs, :configuration_hash, generate_config_hash(validated_attrs))}
      error -> error
    end
  end

  defp create_template_with_transaction(attrs, user_id) do
    Repo.transaction(fn ->
      attrs_with_user = Map.put(attrs, :author_id, user_id)
      
      case Repo.insert(Template.changeset(%Template{}, attrs_with_user)) do
        {:ok, template} ->
          # Update usage analytics
          track_template_creation(template.id, user_id)
          template
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp fetch_template_from_db(template_id, opts) do
    query = from t in Template,
      where: t.id == ^template_id,
      preload: [:author, :parent_template, :organization]
    
    query = apply_template_filters(query, opts)
    
    case Repo.one(query) do
      nil -> {:error, :not_found}
      template -> 
        track_template_access(template_id)
        {:ok, template}
    end
  end

  defp update_template_with_transaction(template, updates) do
    Repo.transaction(fn ->
      updates_with_hash = Map.put(updates, :configuration_hash, generate_config_hash(updates))
      
      case Repo.update(Template.changeset(template, updates_with_hash)) do
        {:ok, updated_template} ->
          track_template_update(template.id)
          updated_template
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp delete_template_with_transaction(template) do
    Repo.transaction(fn ->
      # Delete related records first
      delete_template_dependencies(template.id)
      
      case Repo.delete(template) do
        {:ok, deleted_template} ->
          track_template_deletion(template.id)
          deleted_template
        
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp perform_template_search(query_text, filters, opts, state) do
    base_query = from t in Template, 
      where: t.is_public == true or 
             (^Map.get(filters, :user_id) == t.author_id),
      preload: [:author, :organization]
    
    # Apply text search if query provided
    search_query = if query_text && String.trim(query_text) != "" do
      from t in base_query,
        where: fragment(
          "to_tsvector('english', ? || ' ' || ? || ' ' || ? || ' ' || array_to_string(?, ' ')) @@ plainto_tsquery('english', ?)",
          t.name, t.display_name, t.description, t.tags, ^query_text
        ),
        order_by: [
          desc: fragment(
            "ts_rank(to_tsvector('english', ? || ' ' || ? || ' ' || ? || ' ' || array_to_string(?, ' ')), plainto_tsquery('english', ?))",
            t.name, t.display_name, t.description, t.tags, ^query_text
          )
        ]
    else
      base_query
    end
    
    # Apply filters
    filtered_query = apply_search_filters(search_query, filters)
    
    # Apply pagination and limits
    paginated_query = apply_pagination(filtered_query, opts)
    
    case Repo.all(paginated_query) do
      templates -> 
        track_search_query(query_text, filters, length(templates))
        {:ok, %{
          templates: templates,
          total_count: get_total_count(filtered_query),
          filters_applied: filters,
          search_time_ms: 0  # Will be calculated by caller
        }}
      
      _ -> {:error, "Search failed"}
    end
  end

  defp fetch_user_templates(user_id, opts) do
    query = from t in Template,
      where: t.author_id == ^user_id,
      order_by: [desc: t.last_used_at, desc: t.inserted_at],
      preload: [:parent_template, :organization]
    
    query = apply_template_filters(query, opts)
    query = apply_pagination(query, opts)
    
    {:ok, Repo.all(query)}
  end

  defp fetch_featured_templates(opts) do
    query = from t in Template,
      where: t.is_featured == true and t.is_public == true,
      order_by: [desc: t.rating_average, desc: t.usage_count],
      preload: [:author, :organization]
    
    query = apply_template_filters(query, opts)
    query = apply_pagination(query, opts)
    
    {:ok, Repo.all(query)}
  end

  defp fetch_templates_by_category(category, opts) do
    query = from t in Template,
      where: t.category == ^category and t.is_public == true,
      order_by: [desc: t.rating_average, desc: t.usage_count],
      preload: [:author, :organization]
    
    query = apply_template_filters(query, opts)
    query = apply_pagination(query, opts)
    
    {:ok, Repo.all(query)}
  end

  defp generate_template_recommendations(user_id, context, _state) do
    # Implement recommendation algorithm based on:
    # 1. User's past template usage
    # 2. Similar users' preferences
    # 3. Template popularity and ratings
    # 4. Context-specific recommendations
    
    base_query = from t in Template,
      where: t.is_public == true,
      join: r in TemplateRating, on: r.template_id == t.id,
      group_by: t.id,
      having: count(r.id) >= 5,
      order_by: [desc: avg(r.rating), desc: t.usage_count],
      limit: 10,
      preload: [:author, :organization]
    
    {:ok, Repo.all(base_query)}
  end

  # Bulk Operations

  defp bulk_export_templates(template_ids, user_id, opts) do
    format = Map.get(opts, :format, "json")
    
    query = from t in Template,
      where: t.id in ^template_ids and
             (t.author_id == ^user_id or t.is_public == true),
      preload: [:author, :parent_template, :organization]
    
    case Repo.all(query) do
      templates -> 
        export_data = format_templates_for_export(templates, format)
        {:ok, export_data}
      
      _ -> {:error, "Export failed"}
    end
  end

  defp bulk_import_templates(template_data, user_id, opts) do
    validate_on_import = Map.get(opts, :validate, true)
    
    Repo.transaction(fn ->
      results = Enum.map(template_data, fn template_attrs ->
        attrs_with_user = Map.put(template_attrs, :author_id, user_id)
        
        if validate_on_import do
          case validate_template_attrs(attrs_with_user) do
            {:ok, validated_attrs} ->
              case Repo.insert(Template.changeset(%Template{}, validated_attrs)) do
                {:ok, template} -> {:ok, template}
                {:error, changeset} -> {:error, changeset}
              end
            error -> error
          end
        else
          case Repo.insert(Template.changeset(%Template{}, attrs_with_user)) do
            {:ok, template} -> {:ok, template}
            {:error, changeset} -> {:error, changeset}
          end
        end
      end)
      
      case Enum.find(results, fn {status, _} -> status == :error end) do
        nil -> 
          {:ok, Enum.map(results, fn {:ok, template} -> template end)}
        
        {:error, first_error} -> 
          Repo.rollback(first_error)
      end
    end)
  end

  defp bulk_update_templates(template_ids, user_id, opts) do
    updates = Map.get(opts, :updates, %{})
    
    Repo.transaction(fn ->
      query = from t in Template,
        where: t.id in ^template_ids and t.author_id == ^user_id
      
      case Repo.update_all(query, set: Map.to_list(updates)) do
        {count, _} when count > 0 ->
          # Invalidate caches for updated templates
          Enum.each(template_ids, &invalidate_template_caches/1)
          {:ok, count}
        
        _ -> Repo.rollback("No templates updated")
      end
    end)
  end

  defp bulk_delete_templates(template_ids, user_id, _opts) do
    Repo.transaction(fn ->
      query = from t in Template,
        where: t.id in ^template_ids and t.author_id == ^user_id
      
      # Delete dependencies first
      Enum.each(template_ids, &delete_template_dependencies/1)
      
      case Repo.delete_all(query) do
        {count, _} when count > 0 ->
          # Invalidate caches and update search index
          Enum.each(template_ids, fn template_id ->
            invalidate_template_caches(template_id)
            remove_from_search_index(template_id)
          end)
          {:ok, count}
        
        _ -> Repo.rollback("No templates deleted")
      end
    end)
  end

  defp bulk_validate_templates(template_ids, _opts) do
    query = from t in Template, where: t.id in ^template_ids
    
    results = Repo.all(query)
    |> Enum.map(fn template ->
      validation_result = validate_template_configuration(template)
      {template.id, validation_result}
    end)
    
    {:ok, results}
  end

  # Cache Management Functions

  defp invalidate_template_caches(template_id) do
    # Invalidate specific template caches
    CacheManager.delete_pattern("template:#{template_id}:*")
    
    # Invalidate search result caches
    CacheManager.delete_pattern("search:*")
    
    # Invalidate user template caches
    CacheManager.delete_pattern("user_templates:*")
    
    # Invalidate category and featured caches
    CacheManager.delete_pattern("category_templates:*")
    CacheManager.delete_pattern("featured_templates:*")
    
    :ok
  end

  defp invalidate_related_caches(template) do
    invalidate_template_caches(template.id)
    
    # Invalidate organization caches if applicable
    if template.organization_id do
      CacheManager.delete_pattern("org_templates:#{template.organization_id}:*")
    end
    
    :ok
  end

  # Helper Functions

  defp apply_template_filters(query, opts) do
    Enum.reduce(opts, query, fn {key, value}, acc ->
      case key do
        :limit -> from t in acc, limit: ^value
        :offset -> from t in acc, offset: ^value
        :order_by -> from t in acc, order_by: ^value
        :include_deprecated -> 
          if value, do: acc, else: from t in acc, where: t.is_deprecated == false
        :min_rating -> from t in acc, where: t.rating_average >= ^value
        :tags -> from t in acc, where: fragment("? && ?", t.tags, ^value)
        _ -> acc
      end
    end)
  end

  defp apply_search_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, acc ->
      case key do
        :category -> from t in acc, where: t.category == ^value
        :author_id -> from t in acc, where: t.author_id == ^value
        :organization_id -> from t in acc, where: t.organization_id == ^value
        :tags -> from t in acc, where: fragment("? && ?", t.tags, ^value)
        :min_rating -> from t in acc, where: t.rating_average >= ^value
        :max_rating -> from t in acc, where: t.rating_average <= ^value
        :is_featured -> from t in acc, where: t.is_featured == ^value
        :created_after -> from t in acc, where: t.inserted_at >= ^value
        :created_before -> from t in acc, where: t.inserted_at <= ^value
        _ -> acc
      end
    end)
  end

  defp apply_pagination(query, opts) do
    limit = Map.get(opts, :limit, 50)
    offset = Map.get(opts, :offset, 0)
    
    from t in query, limit: ^limit, offset: ^offset
  end

  defp get_total_count(query) do
    query
    |> exclude(:order_by)
    |> exclude(:preload)
    |> exclude(:limit)
    |> exclude(:offset)
    |> select([t], count(t.id))
    |> Repo.one()
  end

  defp generate_config_hash(attrs) do
    config_data = %{
      provider_config: Map.get(attrs, :provider_config, %{}),
      persona_config: Map.get(attrs, :persona_config, %{}),
      tool_config: Map.get(attrs, :tool_config, %{}),
      prompt_config: Map.get(attrs, :prompt_config, %{}),
      deployment_config: Map.get(attrs, :deployment_config, %{})
    }
    
    :crypto.hash(:sha256, Jason.encode!(config_data))
    |> Base.encode16(case: :lower)
  end

  defp format_templates_for_export(templates, format) do
    case format do
      "json" -> Jason.encode!(templates)
      "yaml" -> YamlElixir.encode!(templates)
      _ -> Jason.encode!(templates)  # Default to JSON
    end
  end

  # Search Index Management

  defp update_search_index(_template) do
    # Update external search index (if using Elasticsearch, etc.)
    :ok
  end

  defp remove_from_search_index(_template_id) do
    # Remove from external search index
    :ok
  end

  # Analytics and Tracking

  defp track_template_creation(template_id, user_id) do
    # Record template creation analytics
    :ok
  end

  defp track_template_access(template_id) do
    # Record template access analytics
    :ok
  end

  defp track_template_update(template_id) do
    # Record template update analytics
    :ok
  end

  defp track_template_deletion(template_id) do
    # Record template deletion analytics
    :ok
  end

  defp track_cache_hit(template_id) do
    # Track cache performance
    :ok
  end

  defp track_cache_miss(template_id) do
    # Track cache performance
    :ok
  end

  defp track_search_performance(query, duration) do
    # Track search performance metrics
    :ok
  end

  defp track_search_query(query, filters, result_count) do
    # Track search analytics
    :ok
  end

  defp track_bulk_operation_performance(operation, item_count, duration) do
    # Track bulk operation performance
    :ok
  end

  # Maintenance Functions

  defp schedule_maintenance do
    Process.send_after(__MODULE__, :maintenance, 3_600_000)  # 1 hour
  end

  defp perform_maintenance(state) do
    # Perform cache cleanup
    CacheManager.cleanup_expired(state.cache_manager)
    
    # Update performance metrics
    # Clean up analytics data
    # Optimize database queries
    
    %{state | last_cleanup: DateTime.utc_now()}
  end

  # Validation Functions

  defp get_template_for_update(template_id, user_id) do
    query = from t in Template,
      where: t.id == ^template_id and t.author_id == ^user_id
    
    case Repo.one(query) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  defp validate_template_updates(updates) do
    # Validate update attributes
    {:ok, updates}
  end

  defp validate_template_deletion(template) do
    # Check if template has dependencies
    child_count = from(t in Template, where: t.parent_template_id == ^template.id)
                  |> Repo.aggregate(:count, :id)
    
    if child_count > 0 do
      {:error, "Cannot delete template with child templates"}
    else
      :ok
    end
  end

  defp validate_template_configuration(template) do
    # Validate template configuration against current schema
    TheMaestro.AgentTemplates.SchemaValidator.validate_template(template)
  end

  defp delete_template_dependencies(template_id) do
    # Delete related records (ratings, instantiations, etc.)
    from(r in TemplateRating, where: r.template_id == ^template_id) |> Repo.delete_all()
    from(i in TemplateInstantiation, where: i.template_id == ^template_id) |> Repo.delete_all()
    # Remove from collections
    :ok
  end
end
```

## Module Structure

```
lib/the_maestro/agent_templates/storage/
├── storage_service.ex           # Main storage service GenServer
├── cache_manager.ex            # Multi-layer caching system
├── query_optimizer.ex          # Database query optimization
├── search_engine.ex            # Advanced search functionality
├── bulk_operations.ex          # Bulk operation handlers
├── analytics_collector.ex      # Usage analytics collection
├── performance_monitor.ex      # Performance monitoring
├── backup_manager.ex          # Backup and recovery
└── migration_helper.ex        # Schema migration utilities
```

## Integration Points

1. **Epic 5 Integration**: Provider configuration storage and validation
2. **Epic 6 Integration**: MCP tool configuration storage and validation
3. **Epic 7 Integration**: Prompt configuration storage and optimization
4. **Epic 8 Integration**: Persona configuration storage and relationships
5. **Authentication System**: User permission integration for template access
6. **Caching Layer**: Redis integration for distributed caching

## Performance Considerations

- Database indexing strategy for sub-500ms query response times
- Multi-layer caching with intelligent invalidation
- Query optimization with database connection pooling
- Background processing for analytics and maintenance
- Horizontal scaling support with database sharding

## Security Considerations

- Row-level security for multi-tenant template isolation
- Audit logging for all template operations
- Permission validation at the storage layer
- Data encryption for sensitive template configurations
- Rate limiting for API operations

## Dependencies

- Epic 5: Model Choice & Authentication System
- Epic 6: MCP Protocol Implementation  
- Epic 7: Enhanced Prompt Handling System
- Epic 8: Persona Management System
- Ecto for database operations
- Jason for JSON handling
- Oban for background job processing

## Definition of Done

- [ ] High-performance database schema with comprehensive indexing
- [ ] Advanced search and discovery system with full-text search
- [ ] Multi-layer caching system with intelligent invalidation
- [ ] Template library management with metadata handling
- [ ] Scalable query architecture supporting 1000+ concurrent users
- [ ] Complete template versioning storage system
- [ ] Template relationship management with inheritance support
- [ ] Bulk operations for template management efficiency
- [ ] Template analytics storage infrastructure
- [ ] Advanced filtering capabilities with performance optimization
- [ ] Template recommendation engine data infrastructure
- [ ] Real-time template synchronization system
- [ ] Automated backup and recovery system
- [ ] Permission-aware retrieval with security integration
- [ ] Template popularity tracking and trend analysis
- [ ] Geographic distribution support with failover
- [ ] Template import/export system with validation
- [ ] Query performance optimization with monitoring
- [ ] Template content indexing for fast retrieval
- [ ] Collaborative features storage infrastructure
- [ ] Complete audit trail with searchable history
- [ ] Template validation pipeline with background processing
- [ ] Storage optimization with redundancy reduction
- [ ] Database migration framework for schema evolution
- [ ] Real-time performance monitoring with alerting
- [ ] Comprehensive unit tests with >95% coverage
- [ ] Integration tests with all dependent systems
- [ ] Performance benchmarks meeting <500ms response requirements
- [ ] Load testing validation for 1000+ concurrent users
- [ ] Security audit with penetration testing
- [ ] Complete API documentation for storage operations
- [ ] Database optimization guide and runbooks