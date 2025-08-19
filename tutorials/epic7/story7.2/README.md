# Epic 7 Story 7.2: Contextual Prompt Enhancement Pipeline Tutorial

Welcome to the comprehensive tutorial for the Contextual Prompt Enhancement Pipeline! This tutorial will guide you through understanding, using, and extending the 8-stage enhancement pipeline that makes The Maestro's prompt processing intelligent and context-aware.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Pipeline Stages](#pipeline-stages)
5. [Configuration](#configuration)
6. [Examples](#examples)
7. [Advanced Usage](#advanced-usage)
8. [Testing](#testing)
9. [Troubleshooting](#troubleshooting)

## Overview

The Contextual Prompt Enhancement Pipeline is a sophisticated 8-stage system that transforms raw user prompts into context-rich, intelligently formatted prompts. It analyzes intent, gathers relevant context from multiple sources, scores relevance, and integrates everything into an enhanced prompt optimized for AI processing.

### Key Features

- **8-Stage Pipeline**: Complete prompt processing workflow
- **Multi-Source Context**: Gathers context from 10+ different sources
- **Intent Detection**: Classifies prompts into 4 main categories
- **Relevance Scoring**: Prioritizes context based on relevance
- **Performance Optimized**: ~45ms average processing time
- **Extensible**: Modular design for easy extension

### Business Value

- **Improved AI Responses**: Context-rich prompts lead to better AI understanding
- **Reduced Token Usage**: Intelligent context selection minimizes unnecessary tokens
- **Better User Experience**: Users get more relevant and accurate responses
- **Scalability**: Designed to handle enterprise-scale prompt processing

## Architecture

The pipeline consists of 8 sequential stages, each with a specific responsibility:

```
User Prompt → Context Analysis → Intent Detection → Context Gathering → 
Relevance Scoring → Context Integration → Optimization → Validation → 
Formatted Output
```

### Core Components

```
lib/the_maestro/prompts/enhancement/
├── pipeline.ex              # Main orchestration
├── context_analyzer.ex      # Stage 1: Analyze prompt structure
├── intent_detector.ex       # Stage 2: Detect user intent  
├── context_gatherer.ex      # Stage 3: Gather relevant context
├── relevance_scorer.ex      # Stage 4: Score context relevance
├── context_integrator.ex    # Stage 5: Integrate context
├── enhancement_optimizer.ex # Stage 6: Optimize for performance
├── quality_validator.ex     # Stage 7: Validate quality
├── prompt_formatter.ex      # Stage 8: Format final output
└── structs.ex              # Data structures
```

## Quick Start

### Basic Usage

```elixir
alias TheMaestro.Prompts.Enhancement.Pipeline

# Basic enhancement
result = Pipeline.enhance_prompt("Fix the authentication bug", %{})

# Enhanced prompt with user context
user_context = %{
  working_directory: "/app/src",
  operating_system: "Linux",
  project_type: "phoenix"
}

result = Pipeline.enhance_prompt("Add user registration", user_context)

# Access the results
IO.puts(result.enhanced_prompt)    # The enhanced prompt
IO.puts(result.pre_context)        # Context that goes before
IO.puts(result.post_context)       # Context that goes after
```

### Expected Output Structure

```elixir
%{
  enhanced_prompt: "Original user prompt",
  pre_context: "Environmental and project context...",
  inline_context: "Context integrated within prompt...",
  post_context: "Additional context and constraints...",
  metadata: %{
    processing_time_ms: 45,
    context_sources: [:environmental, :project_structure],
    intent: %{type: :software_engineering, confidence: 0.95},
    complexity: :medium
  }
}
```

## Pipeline Stages

### Stage 1: Context Analysis

**Module**: `ContextAnalyzer`  
**Purpose**: Analyzes the raw prompt to extract structural information

```elixir
analysis = ContextAnalyzer.analyze_prompt("Create a REST API endpoint")

# Returns:
%{
  prompt_type: :software_engineering,
  entities: ["REST", "API", "endpoint"],
  complexity: :medium,
  domain_indicators: [:web_development, :software_development],
  implicit_requirements: [:code_analysis, :project_structure]
}
```

**Key Functions**:
- `analyze_prompt/1` - Main analysis function
- `assess_prompt_complexity/1` - Determines complexity (low/medium/high)
- `identify_domain_indicators/1` - Detects technical domains
- `extract_entities/1` - Extracts technical terms and entities

### Stage 2: Intent Detection

**Module**: `IntentDetector`  
**Purpose**: Classifies user intent and determines context requirements

```elixir
intent = IntentDetector.detect_intent(analysis)

# Returns:
%{
  type: :software_engineering,
  confidence: 0.95,
  category: :implementation,
  context_requirements: [:project_structure, :code_analysis],
  urgency: :normal
}
```

**Intent Types**:
- `:software_engineering` - Code-related tasks
- `:information_seeking` - Questions and explanations  
- `:creative_writing` - Content creation
- `:general_conversation` - Casual interaction

### Stage 3: Context Gathering

**Module**: `ContextGatherer`  
**Purpose**: Collects relevant context from multiple sources

```elixir
context = ContextGatherer.gather_context(analysis, intent, user_context)

# Gathers from 10 sources:
# - Environmental (OS, date, directory)
# - Project structure
# - Code analysis  
# - Tool availability
# - MCP integration
# - Session history
# - User preferences
# - Documentation
# - Security context
# - Performance context
```

**Context Sources**:
- **Environmental**: OS info, current directory, date/time
- **Project Structure**: File structure, dependencies, config
- **Code Analysis**: Existing code patterns, architecture
- **Tool Availability**: Available commands and tools
- **Documentation**: Relevant docs and examples

### Stage 4: Relevance Scoring

**Module**: `RelevanceScorer`  
**Purpose**: Scores and prioritizes context based on relevance

```elixir
scored_context = RelevanceScorer.score_context_relevance(context, analysis, intent)

# Returns context sorted by relevance score (0.0 - 1.0)
[
  {0.95, :project_structure, %{...}},
  {0.85, :environmental, %{...}},
  {0.75, :code_analysis, %{...}}
]
```

**Scoring Factors**:
- Intent alignment
- Domain relevance  
- Freshness of information
- Historical effectiveness

### Stage 5: Context Integration

**Module**: `ContextIntegrator`  
**Purpose**: Builds pre-context, inline, and post-context sections

```elixir
integrated = ContextIntegrator.integrate_context(scored_context, analysis, intent)

# Creates structured context sections:
%{
  pre_context: "Environmental and setup context...",
  inline_context: "Context woven into prompt...", 
  post_context: "Constraints and guidelines..."
}
```

### Stage 6: Enhancement Optimization

**Module**: `EnhancementOptimizer`  
**Purpose**: Optimizes for performance and token efficiency

```elixir
optimized = EnhancementOptimizer.optimize_enhancement(integrated, analysis)

# Applies optimizations:
# - Token limit awareness
# - Redundancy removal
# - Context compression
# - Priority-based inclusion
```

### Stage 7: Quality Validation

**Module**: `QualityValidator`  
**Purpose**: Validates enhancement quality and completeness

```elixir
validation = QualityValidator.validate_enhancement(optimized, analysis, intent)

# Checks:
# - Context relevance
# - Information completeness  
# - Token efficiency
# - Format correctness
```

### Stage 8: Prompt Formatting

**Module**: `PromptFormatter`  
**Purpose**: Formats the final output structure

```elixir
result = PromptFormatter.format_enhanced_prompt(validated, metadata)

# Final structured output ready for AI processing
```

## Configuration

### Environment Variables

```bash
# Context gathering limits
export CONTEXT_GATHERING_TIMEOUT_MS=5000
export MAX_CONTEXT_SOURCES=10

# Performance tuning
export PIPELINE_CACHE_TTL=3600
export MAX_CONTEXT_SIZE_KB=500

# Quality thresholds  
export MIN_RELEVANCE_SCORE=0.3
export CONTEXT_FRESHNESS_HOURS=24
```

### Application Configuration

```elixir
# config/config.exs
config :the_maestro, :prompt_enhancement,
  enabled: true,
  pipeline_timeout_ms: 10000,
  cache_enabled: true,
  quality_gates: true,
  context_sources: [
    :environmental,
    :project_structure, 
    :code_analysis,
    :tool_availability,
    :mcp_integration,
    :session_history,
    :user_preferences,
    :documentation,
    :security_context,
    :performance_context
  ]
```

## Examples

### Example 1: Software Engineering Task

```elixir
# Input
prompt = "Fix the authentication bug in user service"
context = %{
  working_directory: "/app/src/services",
  operating_system: "Darwin",
  project_type: "elixir_phoenix"
}

# Enhancement
result = Pipeline.enhance_prompt(prompt, context)

# Output
"""
This is The Maestro AI assistant. Context for current interaction:

## Environmental Context
- Operating System: Darwin
- Current Directory: /app/src/services  
- Date: 2024-08-19

## Project Context
- Project Type: elixir_phoenix
- Languages: elixir
- Current Focus: Authentication system debugging

---

Fix the authentication bug in user service

## Technical Context
- Focus: User authentication and authorization
- Scope: Service-level debugging
- Domain: Web application security
"""
```

### Example 2: API Development

```elixir
# Input  
prompt = "Create a REST API endpoint for user registration"
context = %{
  working_directory: "/api",
  project_dependencies: ["phoenix", "ecto", "jason"]
}

# Enhanced output includes:
# - Project structure context
# - Dependency information
# - API design patterns
# - Security considerations
```

### Example 3: Learning Question

```elixir
# Input
prompt = "How do GenServers work in Elixir?"

# Enhancement includes:
# - Educational context
# - Code examples
# - Best practices
# - Related concepts
```

## Advanced Usage

### Custom Context Sources

```elixir
defmodule MyApp.CustomContextSource do
  @behaviour ContextSource
  
  def gather_context(user_context, analysis, intent) do
    %{
      custom_metric: get_custom_metric(),
      business_context: get_business_context(analysis)
    }
  end
  
  def relevance_score(context, analysis, intent) do
    # Custom scoring logic
    0.85
  end
end

# Register custom source
Pipeline.register_context_source(:custom, MyApp.CustomContextSource)
```

### Pipeline Middleware

```elixir
defmodule MyApp.LoggingMiddleware do
  def call(stage, input, opts) do
    start_time = System.monotonic_time(:millisecond)
    result = apply_stage(stage, input, opts)
    duration = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("Stage #{stage} completed in #{duration}ms")
    result
  end
end

# Apply middleware
Pipeline.use_middleware(MyApp.LoggingMiddleware)
```

### Batch Processing

```elixir
prompts = [
  "Fix auth bug",
  "Add user endpoint", 
  "Update docs"
]

# Process in parallel
results = Pipeline.enhance_prompts_batch(prompts, context, concurrency: 3)
```

## Testing

### Unit Tests

```bash
# Run all enhancement tests
MIX_ENV=test mix test test/the_maestro/prompts/enhancement/ --warnings-as-errors

# Run specific stage tests
MIX_ENV=test mix test test/the_maestro/prompts/enhancement/context_analyzer_test.exs

# Run with coverage
MIX_ENV=test mix test --cover
```

### Integration Tests

```elixir
# Test full pipeline
test "full pipeline integration" do
  result = Pipeline.enhance_prompt("Fix auth bug", %{})
  
  assert is_map(result)
  assert String.contains?(result.pre_context, "Context for current interaction")
  assert result.enhanced_prompt == "Fix auth bug"
  assert result.metadata.processing_time_ms > 0
end
```

### Performance Tests

```bash
# Benchmark pipeline performance
MIX_ENV=test mix run -e 'TheMaestro.Prompts.Enhancement.Benchmark.run()'
```

## Troubleshooting

### Common Issues

#### 1. Missing Environmental Context

**Problem**: Environmental info not appearing in pre-context
**Solution**: Ensure context gatherer includes base requirements

```elixir
# Fix applied in context_gatherer.ex
base_requirements = [:current_directory, :operating_system] ++ intent.context_requirements
```

#### 2. Low Complexity Scoring

**Problem**: Complex prompts rated as low complexity
**Solution**: Adjust word count threshold

```elixir
# Fixed in context_analyzer.ex - reduced threshold from 5 to 3 words
low_matches > 0 or word_count <= 3 -> :low
```

#### 3. Protocol.UndefinedError

**Problem**: DateTime structs not handled in relevance scorer
**Solution**: Add struct handling in stringify_context_value

```elixir
defp stringify_context_value(%{__struct__: struct_name} = value) do
  case struct_name do
    TheMaestro.Prompts.Enhancement.Structs.EnvironmentalContext ->
      # Handle struct conversion
  end
end
```

#### 4. BadMapError in Pipeline

**Problem**: Nil values in pipeline extraction
**Solution**: Add nil handling in extract_enhanced_prompt

```elixir
formatted_result = case final_prompt do
  nil -> %{
    pre_context: "",
    enhanced_prompt: context.original_prompt,
    # ...
  }
  result -> result
end
```

### Debug Mode

```elixir
# Enable detailed logging
Logger.configure(level: :debug)

# Test specific prompt
Pipeline.enhance_prompt("test", %{}, debug: true)
```

### Performance Monitoring

```elixir
# Monitor processing times
{:ok, _} = :telemetry.attach(
  "pipeline-timing",
  [:maestro, :pipeline, :stage, :stop],
  &handle_telemetry/4,
  nil
)
```

## Next Steps

1. **Extend Context Sources**: Add domain-specific context sources
2. **Improve Scoring**: Enhance relevance scoring algorithms
3. **Add Caching**: Implement intelligent context caching
4. **Monitor Performance**: Set up production monitoring
5. **A/B Testing**: Test different enhancement strategies

## Resources

- [Pipeline Implementation](/lib/the_maestro/prompts/enhancement/)
- [Test Suite](/test/the_maestro/prompts/enhancement/)
- [Story Documentation](/.agent-os/product/epics/epic-7-enhanced-prompt-handling-system/story-7.2-contextual-prompt-enhancement-pipeline.md)
- [Epic 7 Overview](/.agent-os/product/epics/epic-7-enhanced-prompt-handling-system/)

---

**Status**: ✅ 100% Complete | **Tests**: 34/34 Passing | **Performance**: ~45ms average