# Story 8.1: Persona Definition & Storage System

## User Story

**As a** user of TheMaestro
**I want** to define, create, and store AI agent personas with rich configuration options
**so that** I can customize my agents' behavior, tone, and response patterns to match specific use cases and contexts

## Acceptance Criteria

1. **Persona Schema Design**: A comprehensive Ecto schema is defined for personas with all required fields including name, content, version, metadata, and relationships
2. **Content Format Support**: Personas support markdown-based content similar to GEMINI.md files with system instruction formatting
3. **Hierarchical Structure**: Personas support parent-child relationships for inheritance and specialization
4. **Version Management**: Each persona maintains version history with the ability to rollback to previous versions
5. **User Ownership**: Personas are associated with specific users and respect authentication boundaries
6. **Metadata Framework**: Rich metadata support for categorization, tags, and configuration options
7. **Validation System**: Comprehensive validation ensures persona content integrity and prevents malformed definitions
8. **Database Migrations**: All necessary database tables and indexes are created with proper constraints
9. **Context API**: Core API functions for persona CRUD operations with proper error handling
10. **Content Parsing**: Persona content is parsed and validated for system instruction compatibility
11. **Template Support**: Built-in persona templates for common use cases (developer, writer, analyst, etc.)
12. **Import/Export**: Functionality to import personas from markdown files and export for sharing
13. **Search and Discovery**: Full-text search capabilities for finding personas by name, content, or metadata
14. **Audit Trail**: Complete audit logging for persona creation, modification, and deletion events
15. **Size Limitations**: Configurable limits on persona content size to prevent token overflow
16. **Sanitization**: Content sanitization to prevent injection attacks while preserving markdown formatting
17. **Backup and Recovery**: System for backing up persona definitions and recovering from corruption
18. **Performance Optimization**: Database indexes and query optimization for persona retrieval
19. **Caching Strategy**: Memory-based caching for frequently accessed personas
20. **Migration Tools**: Tools for migrating existing system instructions into the persona format
21. **Testing Suite**: Comprehensive unit tests for all persona operations and edge cases
22. **Documentation**: Complete API documentation and developer guides for persona definition
23. **Integration Hooks**: Event system for persona lifecycle notifications
24. **Concurrent Access**: Safe handling of concurrent persona modifications
25. **Compliance Framework**: GDPR-compliant data handling for persona content and metadata

## Technical Implementation

### Database Schema

```elixir
# Migration: create_personas_tables.exs
defmodule TheMaestro.Repo.Migrations.CreatePersonasTables do
  use Ecto.Migration

  def change do
    create table(:personas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :display_name, :string
      add :description, :text
      add :content, :text, null: false
      add :version, :string, default: "1.0.0", null: false
      add :is_active, :boolean, default: true, null: false
      add :parent_persona_id, references(:personas, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :content_hash, :string
      add :size_bytes, :integer
      add :last_applied_at, :naive_datetime_usec
      add :application_count, :integer, default: 0

      timestamps(type: :naive_datetime_usec)
    end

    create table(:persona_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :persona_id, references(:personas, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :content, :text, null: false
      add :content_hash, :string
      add :changes_summary, :text
      add :created_by_user_id, references(:users, type: :binary_id)
      add :metadata, :map, default: %{}

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec, updated_at: false)
    end

    create table(:persona_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :display_name, :string
      add :description, :text
      add :content, :text, null: false
      add :category, :string
      add :tags, {:array, :string}, default: []
      add :is_system_template, :boolean, default: false
      add :popularity_score, :float, default: 0.0
      add :metadata, :map, default: %{}

      timestamps(type: :naive_datetime_usec)
    end

    # Indexes for performance
    create unique_index(:personas, [:name, :user_id])
    create index(:personas, [:user_id])
    create index(:personas, [:parent_persona_id])
    create index(:personas, [:is_active])
    create index(:personas, [:tags])
    create index(:personas, [:last_applied_at])
    
    create unique_index(:persona_versions, [:persona_id, :version])
    create index(:persona_versions, [:persona_id])
    create index(:persona_versions, [:created_at])
    
    create unique_index(:persona_templates, [:name])
    create index(:persona_templates, [:category])
    create index(:persona_templates, [:is_system_template])

    # Full-text search index (PostgreSQL specific)
    execute("CREATE INDEX personas_content_search_idx ON personas USING gin(to_tsvector('english', content))")
    execute("CREATE INDEX personas_name_search_idx ON personas USING gin(to_tsvector('english', name || ' ' || coalesce(display_name, '') || ' ' || coalesce(description, '')))")
  end

  def down do
    drop_if_exists table(:persona_templates)
    drop_if_exists table(:persona_versions)
    drop_if_exists table(:personas)
  end
end
```

### Core Schema Module

```elixir
# lib/the_maestro/personas/persona.ex
defmodule TheMaestro.Personas.Persona do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "personas" do
    field :name, :string
    field :display_name, :string
    field :description, :string
    field :content, :string
    field :version, :string, default: "1.0.0"
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :content_hash, :string
    field :size_bytes, :integer
    field :last_applied_at, :naive_datetime_usec
    field :application_count, :integer, default: 0

    belongs_to :parent_persona, __MODULE__
    belongs_to :user, TheMaestro.Accounts.User
    has_many :child_personas, __MODULE__, foreign_key: :parent_persona_id
    has_many :versions, TheMaestro.Personas.PersonaVersion
    has_many :applications, TheMaestro.Personas.PersonaApplication

    timestamps(type: :naive_datetime_usec)
  end

  @doc false
  def changeset(persona, attrs) do
    persona
    |> cast(attrs, [:name, :display_name, :description, :content, :version, 
                   :is_active, :metadata, :tags, :parent_persona_id, :user_id])
    |> validate_required([:name, :content, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:display_name, max: 200)
    |> validate_length(:description, max: 1000)
    |> validate_content_size()
    |> validate_content_format()
    |> generate_content_hash()
    |> calculate_size_bytes()
    |> unique_constraint([:name, :user_id])
    |> foreign_key_constraint(:parent_persona_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_content_size(changeset) do
    case get_field(changeset, :content) do
      nil -> changeset
      content when is_binary(content) ->
        max_size = Application.get_env(:the_maestro, :persona_max_size, 50_000)
        if byte_size(content) > max_size do
          add_error(changeset, :content, "Content size exceeds maximum limit of #{max_size} bytes")
        else
          changeset
        end
    end
  end

  defp validate_content_format(changeset) do
    case get_field(changeset, :content) do
      nil -> changeset
      content when is_binary(content) ->
        if String.valid?(content) and validate_markdown_structure(content) do
          changeset
        else
          add_error(changeset, :content, "Content must be valid markdown with proper structure")
        end
    end
  end

  defp validate_markdown_structure(content) do
    # Basic validation for system instruction format
    has_instruction_markers = String.contains?(content, ["# ", "## ", "You are", "Your role"])
    not String.contains?(content, ["<script", "javascript:", "eval("])
  end

  defp generate_content_hash(changeset) do
    case get_field(changeset, :content) do
      nil -> changeset
      content -> put_change(changeset, :content_hash, hash_content(content))
    end
  end

  defp calculate_size_bytes(changeset) do
    case get_field(changeset, :content) do
      nil -> changeset
      content -> put_change(changeset, :size_bytes, byte_size(content))
    end
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  # Query helpers
  def active_query(query \\ __MODULE__) do
    from p in query, where: p.is_active == true
  end

  def for_user_query(query \\ __MODULE__, user_id) do
    from p in query, where: p.user_id == ^user_id
  end

  def search_query(query \\ __MODULE__, search_term) do
    from p in query,
      where: fragment("to_tsvector('english', ?) @@ plainto_tsquery('english', ?)", 
                     p.name || " " || coalesce(p.display_name, "") || " " || coalesce(p.description, ""), 
                     ^search_term) or
             fragment("to_tsvector('english', ?) @@ plainto_tsquery('english', ?)", 
                     p.content, ^search_term)
  end

  def with_tags_query(query \\ __MODULE__, tags) when is_list(tags) do
    from p in query, where: fragment("? && ?", p.tags, ^tags)
  end
end
```

### Persona Version Schema

```elixir
# lib/the_maestro/personas/persona_version.ex
defmodule TheMaestro.Personas.PersonaVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "persona_versions" do
    field :version, :string
    field :content, :string
    field :content_hash, :string
    field :changes_summary, :string
    field :metadata, :map, default: %{}

    belongs_to :persona, TheMaestro.Personas.Persona
    belongs_to :created_by_user, TheMaestro.Accounts.User

    timestamps(inserted_at: :created_at, type: :naive_datetime_usec, updated_at: false)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:version, :content, :changes_summary, :metadata, 
                   :persona_id, :created_by_user_id])
    |> validate_required([:version, :content, :persona_id])
    |> generate_content_hash()
    |> unique_constraint([:persona_id, :version])
    |> foreign_key_constraint(:persona_id)
    |> foreign_key_constraint(:created_by_user_id)
  end

  defp generate_content_hash(changeset) do
    case get_field(changeset, :content) do
      nil -> changeset
      content -> 
        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        put_change(changeset, :content_hash, hash)
    end
  end
end
```

### Core API Context

```elixir
# lib/the_maestro/personas.ex
defmodule TheMaestro.Personas do
  @moduledoc """
  The Personas context for managing AI agent personas.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo
  alias TheMaestro.Personas.{Persona, PersonaVersion, PersonaTemplate}

  require Logger

  @doc """
  Gets a single persona by id.
  """
  def get_persona(id) do
    Repo.get(Persona, id)
  end

  @doc """
  Gets a single persona by id, raising if not found.
  """
  def get_persona!(id) do
    Repo.get!(Persona, id)
  end

  @doc """
  Gets a persona by name for a specific user.
  """
  def get_persona_by_name(user_id, name) do
    Persona
    |> Persona.for_user_query(user_id)
    |> Persona.active_query()
    |> where([p], p.name == ^name)
    |> Repo.one()
  end

  @doc """
  Lists all personas for a user.
  """
  def list_personas(user_id, opts \\ []) do
    query = 
      Persona
      |> Persona.for_user_query(user_id)
      |> Persona.active_query()
    
    query = 
      case Keyword.get(opts, :search) do
        nil -> query
        term -> Persona.search_query(query, term)
      end

    query =
      case Keyword.get(opts, :tags) do
        nil -> query
        tags -> Persona.with_tags_query(query, tags)
      end

    query = 
      case Keyword.get(opts, :parent_id) do
        nil -> query
        parent_id -> where(query, [p], p.parent_persona_id == ^parent_id)
      end

    query
    |> order_by([p], [desc: p.last_applied_at, desc: p.updated_at])
    |> limit(Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  @doc """
  Creates a persona.
  """
  def create_persona(attrs \\ %{}) do
    with {:ok, persona} <- %Persona{}
                          |> Persona.changeset(attrs)
                          |> Repo.insert() do
      
      # Create initial version
      create_version(persona, %{
        version: persona.version,
        content: persona.content,
        changes_summary: "Initial version",
        created_by_user_id: persona.user_id
      })

      # Log creation event
      log_persona_event(persona, :created)
      
      {:ok, reload_persona(persona)}
    end
  end

  @doc """
  Updates a persona, creating a new version.
  """
  def update_persona(%Persona{} = persona, attrs) do
    old_version = persona.version
    old_content = persona.content

    with {:ok, updated_persona} <- persona
                                  |> Persona.changeset(attrs)
                                  |> Repo.update() do

      # Create version record if content changed
      if updated_persona.content != old_content do
        create_version(updated_persona, %{
          version: updated_persona.version,
          content: updated_persona.content,
          changes_summary: Map.get(attrs, :changes_summary, "Updated content"),
          created_by_user_id: updated_persona.user_id
        })
      end

      # Log update event
      log_persona_event(updated_persona, :updated)

      {:ok, reload_persona(updated_persona)}
    end
  end

  @doc """
  Deletes a persona (soft delete by setting is_active to false).
  """
  def delete_persona(%Persona{} = persona) do
    with {:ok, persona} <- persona
                          |> Persona.changeset(%{is_active: false})
                          |> Repo.update() do
      log_persona_event(persona, :deleted)
      {:ok, persona}
    end
  end

  @doc """
  Creates a persona version.
  """
  def create_version(%Persona{} = persona, attrs) do
    %PersonaVersion{}
    |> PersonaVersion.changeset(Map.put(attrs, :persona_id, persona.id))
    |> Repo.insert()
  end

  @doc """
  Lists versions for a persona.
  """
  def list_versions(%Persona{} = persona) do
    PersonaVersion
    |> where([v], v.persona_id == ^persona.id)
    |> order_by([v], desc: v.created_at)
    |> Repo.all()
  end

  @doc """
  Rollback persona to a specific version.
  """
  def rollback_to_version(%Persona{} = persona, version_id) do
    with %PersonaVersion{} = version <- Repo.get(PersonaVersion, version_id),
         true <- version.persona_id == persona.id do
      
      new_version = next_version(persona.version)
      
      update_persona(persona, %{
        content: version.content,
        version: new_version,
        changes_summary: "Rollback to version #{version.version}"
      })
    else
      nil -> {:error, :version_not_found}
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Import persona from markdown file.
  """
  def import_from_markdown(user_id, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path),
         {:ok, parsed} <- parse_markdown_persona(content) do
      
      attrs = Map.merge(parsed, %{
        user_id: user_id,
        name: Keyword.get(opts, :name, Path.basename(file_path, ".md")),
        tags: Keyword.get(opts, :tags, [])
      })
      
      create_persona(attrs)
    end
  end

  @doc """
  Export persona to markdown format.
  """
  def export_to_markdown(%Persona{} = persona) do
    template = """
    # #{persona.display_name || persona.name}
    
    #{if persona.description, do: "#{persona.description}\n", else: ""}
    #{persona.content}
    """
    
    {:ok, template}
  end

  @doc """
  Search personas with full-text search.
  """
  def search_personas(user_id, search_term, opts \\ []) do
    list_personas(user_id, [search: search_term] ++ opts)
  end

  # Private helper functions

  defp reload_persona(persona) do
    Repo.preload(persona, [:versions, :applications, :child_personas])
  end

  defp log_persona_event(persona, action) do
    Logger.info("Persona #{action}: #{persona.name} (#{persona.id}) by user #{persona.user_id}")
  end

  defp next_version(current_version) do
    case String.split(current_version, ".") do
      [major, minor, patch] ->
        {patch_int, _} = Integer.parse(patch)
        "#{major}.#{minor}.#{patch_int + 1}"
      _ ->
        "1.0.1"
    end
  end

  defp parse_markdown_persona(content) do
    # Parse markdown headers and content for persona metadata
    lines = String.split(content, "\n")
    
    {metadata, content_start} = extract_frontmatter(lines)
    actual_content = Enum.drop(lines, content_start) |> Enum.join("\n")
    
    persona_data = Map.merge(metadata, %{
      content: String.trim(actual_content)
    })
    
    {:ok, persona_data}
  end

  defp extract_frontmatter(lines) do
    case lines do
      ["---" | rest] ->
        case Enum.find_index(rest, &(&1 == "---")) do
          nil -> {%{}, 0}
          end_idx ->
            frontmatter = Enum.take(rest, end_idx)
            metadata = parse_yaml_frontmatter(frontmatter)
            {metadata, end_idx + 2}
        end
      _ -> {%{}, 0}
    end
  end

  defp parse_yaml_frontmatter(lines) do
    # Simple YAML parser for basic key-value pairs
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value) |> String.trim("\"'")
          Map.put(acc, String.to_atom(key), value)
        _ -> acc
      end
    end)
  end
end
```

### Built-in Persona Templates

```elixir
# lib/the_maestro/personas/persona_templates.ex
defmodule TheMaestro.Personas.PersonaTemplates do
  @moduledoc """
  Built-in persona templates for common use cases.
  """

  def default_templates do
    [
      %{
        name: "developer_assistant",
        display_name: "Developer Assistant",
        description: "A technical assistant focused on software development, code review, and architecture",
        category: "development",
        tags: ["coding", "technical", "development"],
        content: """
        # Developer Assistant Persona

        You are an expert software developer and technical advisor with deep knowledge across multiple programming languages, frameworks, and architectural patterns.

        ## Core Principles
        - Write clean, maintainable, and well-documented code
        - Follow established conventions and best practices
        - Prioritize security and performance considerations
        - Provide clear explanations for technical decisions

        ## Communication Style
        - Be precise and technical when discussing code
        - Provide concrete examples and code snippets
        - Explain trade-offs and alternatives
        - Ask clarifying questions for ambiguous requirements

        ## Expertise Areas
        - Full-stack web development
        - Database design and optimization
        - System architecture and scaling
        - DevOps and deployment strategies
        - Code review and refactoring
        - Testing strategies and implementation
        """
      },
      
      %{
        name: "creative_writer",
        display_name: "Creative Writer",
        description: "A creative writing assistant for storytelling, content creation, and narrative development",
        category: "writing",
        tags: ["creative", "writing", "storytelling"],
        content: """
        # Creative Writer Persona

        You are a skilled creative writer with expertise in storytelling, narrative structure, and engaging content creation.

        ## Core Principles
        - Craft compelling narratives with strong character development
        - Use vivid, descriptive language that engages the reader
        - Maintain consistent tone and voice throughout content
        - Adapt writing style to match the intended audience and purpose

        ## Communication Style
        - Use rich, descriptive language
        - Employ literary techniques like metaphor and imagery
        - Vary sentence structure for rhythm and flow
        - Show rather than tell when crafting narratives

        ## Expertise Areas
        - Fiction and non-fiction storytelling
        - Character development and dialogue
        - Plot structure and pacing
        - Content marketing and copywriting
        - Blog posts and articles
        - Script and screenplay writing
        """
      },

      %{
        name: "business_analyst",
        display_name: "Business Analyst",
        description: "A strategic business advisor focused on analysis, planning, and operational improvement",
        category: "business",
        tags: ["business", "strategy", "analysis"],
        content: """
        # Business Analyst Persona

        You are an experienced business analyst with expertise in strategic planning, process optimization, and data-driven decision making.

        ## Core Principles
        - Base recommendations on data and evidence
        - Consider multiple stakeholder perspectives
        - Focus on measurable outcomes and ROI
        - Think strategically about long-term implications

        ## Communication Style
        - Present information clearly with supporting data
        - Use frameworks and structured approaches
        - Provide actionable recommendations
        - Anticipate questions and objections

        ## Expertise Areas
        - Market analysis and competitive intelligence
        - Process improvement and optimization
        - Financial analysis and budgeting
        - Project management and planning
        - Stakeholder management
        - Risk assessment and mitigation
        """
      },

      %{
        name: "research_assistant",
        display_name: "Research Assistant",
        description: "An academic research assistant focused on thorough analysis and evidence-based insights",
        category: "research",
        tags: ["research", "academic", "analysis"],
        content: """
        # Research Assistant Persona

        You are a meticulous research assistant with strong analytical skills and commitment to academic rigor.

        ## Core Principles
        - Provide well-sourced and evidence-based information
        - Present multiple perspectives on complex topics
        - Distinguish between correlation and causation
        - Acknowledge limitations and uncertainties

        ## Communication Style
        - Use precise, academic language
        - Cite sources and provide references
        - Present information objectively
        - Organize findings logically and systematically

        ## Expertise Areas
        - Literature reviews and synthesis
        - Data collection and analysis
        - Methodology design and evaluation
        - Citation and reference management
        - Statistical analysis and interpretation
        - Report writing and documentation
        """
      }
    ]
  end

  def seed_templates do
    for template <- default_templates() do
      case TheMaestro.Repo.get_by(TheMaestro.Personas.PersonaTemplate, name: template.name) do
        nil ->
          %TheMaestro.Personas.PersonaTemplate{}
          |> TheMaestro.Personas.PersonaTemplate.changeset(Map.put(template, :is_system_template, true))
          |> TheMaestro.Repo.insert!()
        existing ->
          existing
          |> TheMaestro.Personas.PersonaTemplate.changeset(template)
          |> TheMaestro.Repo.update!()
      end
    end
  end
end
```

### Module Structure

```
lib/the_maestro/personas/
├── persona.ex                    # Main persona schema
├── persona_version.ex           # Version tracking schema
├── persona_template.ex          # Template schema
├── persona_application.ex       # Application tracking schema
├── persona_templates.ex         # Built-in templates
├── content_validator.ex         # Content validation logic
├── import_export.ex             # Import/export functionality
└── cache.ex                     # Caching layer
```

### Integration Points

1. **Authentication Integration**: Personas linked to user accounts from Epic 5
2. **Prompt System Integration**: Persona content applied through Epic 7's prompt handling
3. **Agent System Integration**: Active personas influence agent behavior and responses
4. **Template Agent Preparation**: Foundation for Epic 9's template agent system

### Performance Considerations

- Database indexes on frequently queried fields
- Content size limits to prevent token overflow
- Caching layer for frequently accessed personas
- Lazy loading of persona content and versions

### Testing Strategy

```elixir
# test/the_maestro/personas_test.exs
defmodule TheMaestro.PersonasTest do
  use TheMaestro.DataCase
  alias TheMaestro.Personas

  describe "personas" do
    test "create_persona/1 with valid data creates a persona" do
      user = insert(:user)
      valid_attrs = %{
        name: "test_persona",
        display_name: "Test Persona",
        content: "You are a helpful assistant.",
        user_id: user.id
      }

      assert {:ok, persona} = Personas.create_persona(valid_attrs)
      assert persona.name == "test_persona"
      assert persona.content_hash != nil
      assert persona.size_bytes > 0
    end

    test "create_persona/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Personas.create_persona(%{})
    end

    test "update_persona/2 creates version and updates persona" do
      user = insert(:user)
      persona = insert(:persona, user: user)
      
      update_attrs = %{
        content: "Updated content",
        version: "1.0.1",
        changes_summary: "Updated instructions"
      }

      assert {:ok, updated_persona} = Personas.update_persona(persona, update_attrs)
      assert updated_persona.content == "Updated content"
      assert updated_persona.version == "1.0.1"
      
      versions = Personas.list_versions(updated_persona)
      assert length(versions) == 2  # Initial + update
    end

    test "search_personas/2 finds personas by content" do
      user = insert(:user)
      persona1 = insert(:persona, user: user, content: "You are a developer assistant")
      persona2 = insert(:persona, user: user, content: "You are a creative writer")

      results = Personas.search_personas(user.id, "developer")
      assert length(results) == 1
      assert hd(results).id == persona1.id
    end

    test "import_from_markdown/3 creates persona from file" do
      user = insert(:user)
      markdown_content = """
      ---
      display_name: "Imported Persona"
      description: "A persona imported from markdown"
      ---
      # Test Persona

      You are a test assistant.
      """
      
      file_path = "/tmp/test_persona.md"
      File.write!(file_path, markdown_content)
      
      assert {:ok, persona} = Personas.import_from_markdown(user.id, file_path)
      assert persona.name == "test_persona"
      assert persona.display_name == "Imported Persona"
      assert String.contains?(persona.content, "You are a test assistant")
      
      File.rm!(file_path)
    end
  end
end
```

## Dependencies

- Epic 5: User authentication system for persona ownership
- Epic 7: Enhanced prompt handling for persona content application
- Phoenix framework with Ecto for database operations
- PostgreSQL for full-text search capabilities

## Definition of Done

- [ ] Database migration created and successfully applied
- [ ] Persona, PersonaVersion, and PersonaTemplate schemas implemented with comprehensive validation
- [ ] Core API functions for CRUD operations implemented and tested
- [ ] Content validation and sanitization implemented
- [ ] Version management system operational
- [ ] Import/export functionality implemented
- [ ] Full-text search capability operational
- [ ] Built-in persona templates seeded
- [ ] Comprehensive unit test suite passing (>90% coverage)
- [ ] Integration tests for all persona operations passing
- [ ] Performance benchmarks meet established criteria (<100ms for persona retrieval)
- [ ] Caching layer implemented and functional
- [ ] Security audit completed with no high-severity issues
- [ ] Documentation completed for all public APIs
- [ ] Database indexes optimized for query performance
- [ ] Error handling and logging implemented
- [ ] GDPR compliance verified for persona data handling