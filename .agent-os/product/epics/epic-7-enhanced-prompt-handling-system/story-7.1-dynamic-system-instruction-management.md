# Story 7.1: Dynamic System Instruction Management

## User Story
**As an** Agent,  
**I want** dynamic system instructions that adapt based on my capabilities, context, and task requirements,  
**so that** I can provide optimal performance with clear operational guidelines for each interaction.

## Acceptance Criteria

### System Instruction Architecture
1. **Modular Instruction System**: Implement composable system instruction modules:
   ```elixir
   defmodule TheMaestro.Prompts.SystemInstructions do
     @instruction_modules [
       :core_mandates,          # Basic operational principles
       :tool_integration,       # Available tools and usage
       :security_guidelines,    # Security and safety protocols  
       :context_awareness,      # Environmental and session context
       :provider_optimization,  # Provider-specific optimizations
       :capability_description, # Current capabilities and limitations
       :workflow_guidance,      # Task-specific workflow instructions
       :error_handling,         # Error recovery and handling
       :output_formatting      # Response formatting requirements
     ]
   end
   ```

2. **Instruction Assembly Pipeline**: Dynamic instruction composition:
   ```elixir
   def assemble_system_instructions(context) do
     context
     |> determine_required_modules()
     |> load_instruction_modules()
     |> apply_context_specific_adaptations()
     |> optimize_for_provider()
     |> validate_instruction_completeness()
     |> format_for_delivery()
   end
   ```

3. **Context-Aware Instruction Selection**: Intelligent module selection based on:
   - Available tools and capabilities
   - Current session context
   - Task complexity and type
   - Provider-specific requirements
   - User preferences and settings
   - Security and trust levels

### Core Instruction Modules
4. **Core Mandates Module**: Foundation operational principles from API analysis:
   ```elixir
   @core_mandates """
   You are an interactive CLI agent specializing in software engineering tasks. Your primary goal is to help users safely and efficiently, adhering strictly to the following instructions and utilizing your available tools.

   # Core Mandates

   - **Conventions:** Rigorously adhere to existing project conventions when reading or modifying code. Analyze surrounding code, tests, and configuration first.
   - **Libraries/Frameworks:** NEVER assume a library/framework is available or appropriate. Verify its established usage within the project.
   - **Style & Structure:** Mimic the style, structure, framework choices, typing, and architectural patterns of existing code.
   - **Idiomatic Changes:** When editing, understand the local context to ensure your changes integrate naturally.
   - **Comments:** Add code comments sparingly. Focus on *why* something is done, especially for complex logic.
   - **Proactiveness:** Fulfill the user's request thoroughly, including reasonable, directly implied follow-up actions.
   - **Confirm Ambiguity/Expansion:** Do not take significant actions beyond the clear scope without confirming with the user.
   - **Path Construction:** Always use absolute paths when using file system tools.
   """
   ```

5. **Tool Integration Module**: Dynamic tool availability and usage instructions:
   ```elixir
   def generate_tool_instructions(available_tools) do
     tool_descriptions = Enum.map(available_tools, &format_tool_description/1)
     
     """
     ## Available Tools

     You have access to the following tools for completing tasks:
     
     #{Enum.join(tool_descriptions, "\n\n")}

     ## Tool Usage Guidelines

     - **Parallelism:** Execute multiple independent tool calls in parallel when feasible
     - **File Paths:** Always use absolute paths when referring to files
     - **Confirmation:** Some tools may require user confirmation based on trust settings
     - **Error Handling:** Handle tool errors gracefully and provide alternatives
     """
   end
   ```

6. **Security Guidelines Module**: Comprehensive security instructions:
   ```elixir
   @security_guidelines """
   ## Security and Safety Rules

   - **Explain Critical Commands:** Before executing commands that modify the file system, codebase, or system state, you *must* provide a brief explanation of the command's purpose and potential impact.
   - **Security First:** Always apply security best practices. Never introduce code that exposes, logs, or commits secrets, API keys, or other sensitive information.
   - **Sandboxing Awareness:** You are running #{get_sandbox_status()}. Consider the implications for file system access and external commands.
   - **Trust Verification:** Verify tool and server trust levels before execution. Request confirmation when appropriate.
   """
   ```

### Context Integration System
7. **Environmental Context Module**: Dynamic environment information:
   ```elixir
   def generate_environmental_context(context) do
     """
     # Current Environment

     - **Date:** #{context.current_date}
     - **Operating System:** #{context.operating_system}
     - **Working Directory:** #{context.working_directory}
     - **Project Type:** #{detect_project_type(context.working_directory)}
     - **Available Tools:** #{length(context.available_tools)} tools
     - **MCP Servers:** #{get_connected_mcp_servers()} connected
     - **Sandbox Mode:** #{context.sandbox_enabled}
     
     ## Project Structure
     
     #{generate_directory_listing(context.working_directory)}
     """
   end
   ```

8. **Capability Description Module**: Current agent capabilities:
   ```elixir
   def generate_capability_description(agent_state) do
     """
     ## Your Current Capabilities

     ### Core Functions
     - Software engineering task assistance
     - Code analysis and modification
     - File system operations (#{get_file_access_level()})
     - Command execution (#{get_command_execution_level()})
     
     ### Available Integrations
     - **LLM Provider:** #{agent_state.current_provider}
     - **Model:** #{agent_state.current_model}
     - **MCP Tools:** #{get_available_mcp_tools()}
     - **Authentication:** #{get_auth_status()}
     
     ### Current Limitations
     #{generate_current_limitations()}
     """
   end
   ```

### Workflow-Specific Instructions
9. **Workflow Guidance Module**: Task-specific operational instructions:
   ```elixir
   def generate_workflow_instructions(task_context) do
     case task_context.primary_task_type do
       :software_engineering ->
         """
         ## Software Engineering Tasks
         When requested to perform tasks like fixing bugs, adding features, refactoring, or explaining code, follow this sequence:
         1. **Understand:** Use search tools extensively to understand file structures, existing code patterns, and conventions
         2. **Plan:** Build a coherent plan based on understanding. Share concise plan with user if helpful
         3. **Implement:** Use available tools, strictly adhering to project conventions
         4. **Verify (Tests):** Verify changes using project's testing procedures
         5. **Verify (Standards):** Execute project-specific build, linting and type-checking commands
         """
         
       :new_application ->
         """
         ## New Application Development
         **Goal:** Autonomously implement and deliver a visually appealing, substantially complete, and functional prototype.
         1. **Understand Requirements:** Analyze user request for core features, UX, visual aesthetic, platform
         2. **Propose Plan:** Present clear, concise, high-level summary to user
         3. **User Approval:** Obtain user approval for the proposed plan
         4. **Implementation:** Autonomously implement each feature per approved plan
         5. **Verify:** Review work against original request and approved plan
         6. **Solicit Feedback:** Provide instructions on how to start the application
         """
         
       _ ->
         generate_generic_workflow_instructions()
     end
   end
   ```

10. **Provider Optimization Module**: Provider-specific instruction optimization:
    ```elixir
    def generate_provider_optimizations(provider, model) do
      case {provider, model} do
        {:anthropic, "claude-" <> _} ->
          """
          ## Claude-Specific Optimizations
          - Utilize Claude's strong reasoning capabilities for complex problem analysis
          - Leverage excellent code understanding for software engineering tasks
          - Take advantage of large context window for comprehensive code analysis
          - Use structured thinking for complex multi-step problems
          """
          
        {:google, "gemini-" <> _} ->
          """
          ## Gemini-Specific Optimizations
          - Leverage multimodal capabilities when images or visual content is involved
          - Utilize strong code generation and understanding capabilities
          - Take advantage of integrated search capabilities when appropriate
          - Use function calling effectively for tool integration
          """
          
        {:openai, "gpt-" <> _} ->
          """
          ## GPT-Specific Optimizations
          - Utilize strong general reasoning and problem-solving capabilities
          - Leverage excellent natural language understanding and generation
          - Take advantage of consistent API behavior for reliable operations
          - Use structured outputs when supported by the model version
          """
          
        _ ->
          ""
      end
    end
    ```

### Dynamic Assembly Logic
11. **Instruction Assembly Engine**: Intelligent instruction compilation:
    ```elixir
    defmodule TheMaestro.Prompts.InstructionAssembler do
      def assemble_instructions(context) do
        %AssemblyContext{
          base_instructions: load_core_mandates(),
          available_tools: context.available_tools,
          mcp_servers: context.connected_mcp_servers,
          environment: context.environment,
          task_context: analyze_task_context(context),
          provider_info: context.provider_info,
          security_context: context.security_context
        }
        |> add_tool_integration_instructions()
        |> add_security_guidelines()
        |> add_environmental_context()
        |> add_capability_descriptions()
        |> add_workflow_guidance()
        |> add_provider_optimizations()
        |> add_output_formatting_rules()
        |> finalize_assembly()
      end
    end
    ```

12. **Context Analysis**: Intelligent context understanding:
    ```elixir
    def analyze_task_context(context) do
      %TaskContext{
        primary_task_type: determine_primary_task_type(context),
        complexity_level: assess_complexity_level(context),
        required_capabilities: identify_required_capabilities(context),
        time_sensitivity: assess_time_sensitivity(context),
        risk_level: assess_risk_level(context),
        collaboration_mode: determine_collaboration_mode(context)
      }
    end
    ```

### Instruction Optimization
13. **Length Optimization**: Optimize instruction length based on context:
    - Token budget management
    - Critical instruction prioritization
    - Context-specific compression
    - Provider-specific length limits
    - Performance impact balancing

14. **Relevance Filtering**: Include only relevant instruction modules:
    - Task-specific filtering
    - Capability-based filtering
    - Environment-based filtering
    - Provider-specific filtering
    - Security-level filtering

15. **Performance Optimization**: Optimize for execution efficiency:
    ```elixir
    def optimize_instructions_for_performance(instructions, context) do
      instructions
      |> cache_static_components()
      |> compress_repetitive_sections()
      |> prioritize_critical_instructions()
      |> adapt_to_provider_constraints()
      |> validate_optimization_effectiveness()
    end
    ```

### Integration Points
16. **Agent System Integration**: Seamless integration with agent framework:
    - Real-time instruction updates
    - Agent state synchronization
    - Capability change notifications
    - Context update propagation

17. **Provider Integration**: Provider-specific instruction delivery:
    - System instruction formatting
    - Provider API compatibility
    - Model-specific optimizations
    - Context window management

18. **MCP Integration**: Dynamic MCP tool instruction integration:
    - Real-time tool availability updates
    - Tool description integration
    - Security context integration
    - Trust level integration

## Technical Implementation

### Module Architecture
```elixir
lib/the_maestro/prompts/system_instructions/
├── assembler.ex              # Main instruction assembly engine
├── modules/
│   ├── core_mandates.ex     # Core operational principles
│   ├── tool_integration.ex  # Tool availability and usage
│   ├── security_guidelines.ex # Security and safety protocols
│   ├── context_awareness.ex # Environmental context
│   ├── capability_description.ex # Agent capabilities
│   ├── workflow_guidance.ex # Task-specific workflows
│   └── provider_optimization.ex # Provider-specific optimizations
├── analyzers/
│   ├── task_analyzer.ex     # Task context analysis
│   ├── complexity_analyzer.ex # Complexity assessment
│   └── context_analyzer.ex  # Environmental analysis
├── optimizers/
│   ├── length_optimizer.ex  # Instruction length optimization
│   ├── relevance_filter.ex  # Relevance-based filtering
│   └── performance_optimizer.ex # Performance optimization
└── formatters/
    ├── anthropic_formatter.ex # Claude-specific formatting
    ├── google_formatter.ex   # Gemini-specific formatting
    └── openai_formatter.ex   # GPT-specific formatting
```

### Caching and Performance
19. **Instruction Caching**: Efficient caching strategies:
    - Static instruction component caching
    - Context-specific caching
    - Provider-specific caching
    - LRU cache management
    - Cache invalidation strategies

20. **Performance Monitoring**: Track instruction system performance:
    - Assembly time monitoring
    - Token usage optimization
    - Cache hit/miss rates
    - Provider response impact
    - Quality metric tracking

## Testing Strategy
21. **Assembly Testing**: Comprehensive assembly testing:
    - Module combination testing
    - Context-specific assembly
    - Provider compatibility testing
    - Performance benchmarking
    - Quality validation

22. **Integration Testing**: End-to-end integration testing:
    - Agent behavior validation
    - Provider interaction testing
    - Tool integration verification
    - Security compliance testing
    - Performance impact assessment

## Dependencies
- Core agent framework from Epic 1
- Provider system from Epic 5
- MCP integration from Epic 6
- Existing context and tooling systems

## Definition of Done
- [ ] Modular system instruction architecture implemented
- [ ] Dynamic instruction assembly engine operational
- [ ] Context-aware instruction selection working
- [ ] All core instruction modules implemented and tested
- [ ] Provider-specific optimization integrated
- [ ] Performance optimization and caching systems
- [ ] Integration with agent framework completed
- [ ] MCP tool instruction integration functional
- [ ] Comprehensive testing coverage achieved
- [ ] Performance benchmarks established
- [ ] Documentation and examples created
- [ ] Tutorial created in `tutorials/epic7/story7.1/`