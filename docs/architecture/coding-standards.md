# Coding Standards

## Overview

This document establishes coding standards and conventions for The Maestro project, ensuring consistency, maintainability, and quality across the entire codebase.

**CRITICAL**: This document references and builds upon the comprehensive development guidelines in `CLAUDE.md`. All developers MUST read and follow both documents.

## Core Principles

### Zero Tolerance Policies

**Git Hook Compliance**: Never bypass git hooks with `--no-verify`, `--force`, or similar flags. Always fix issues identified by hooks rather than bypassing them.

As stated in `CLAUDE.md`:
- **IMMEDIATE PROJECT REMOVAL** for any use of bypass commands
- **Zero tolerance**: No exceptions, no warnings, no second chances
- **Professional developers solve problems, never bypass protections**

**Quality Standards**: All code must pass:
- Compilation without warnings (`mix compile --warnings-as-errors`)
- Code formatting (`mix format`)
- Static analysis (`mix credo`)
- All tests (`mix test`)

### Development Philosophy

Referenced from `CLAUDE.md` core principles:

1. **Brutal Honesty**: No mocks, placeholders, or theater - verify real implementations exist
2. **Evidence-Based**: All decisions supported by testing, metrics, or documentation  
3. **Quality Over Speed**: Prioritize correctness and maintainability over development velocity
4. **Professional Standards**: Fix problems, never bypass protections

### Mandatory Process Requirements

As detailed in `CLAUDE.md`, ALL development must follow:

1. **Research First**: Use Archon MCP server for documentation research before coding
2. **Multi-Option Analysis**: Evaluate 2-3 distinct approaches for non-trivial tasks
3. **Critical Evaluation**: Analyze pros/cons, integration plans, potential pitfalls
4. **Justify Recommendations**: Explain reasoning with evidence-based analysis
5. **Acknowledge Uncertainty**: State gaps explicitly, propose research steps
6. **Complete Definition**: All requirements satisfied, code functional, warnings resolved

## Language-Specific Standards

### Elixir/Phoenix Standards

**IMPORTANT**: This section summarizes key standards from `CLAUDE.md`. For complete guidelines including Phoenix v1.8 specifics, LiveView patterns, Ecto guidelines, and HEEx template rules, refer to the comprehensive documentation in `CLAUDE.md`.

#### Core Language Guidelines (from CLAUDE.md)

**Lists and Data Access:**
- Elixir lists do NOT support index access (`list[i]` is invalid)
- Use `Enum.at/2`, pattern matching, or `List` functions
- Never use map access syntax on structs (`changeset[:field]` invalid)

**Variable Binding:**
- Variables immutable but can be rebound
- Must bind block expression results (`if`, `case`, `cond`) to variables
- Cannot rebind inside block expressions

**Module Organization:**
- Never nest multiple modules in same file
- One module per file, names match file paths
- Follow Phoenix namespace conventions

#### Phoenix Framework Specifics (from CLAUDE.md)

**Router Scopes:**
- Scope blocks include optional alias prefixed for all routes
- Never create own alias for route definitions within scopes

**LiveView Guidelines:**
- Never use deprecated `live_redirect`/`live_patch` functions
- Use `<.link navigate={href}>` and `<.link patch={href}>`
- Avoid LiveComponents unless strong specific need
- Always use streams for collections

**Template Standards:**
- Phoenix templates always use `~H` or .html.heex files
- Always use `Phoenix.Component.form/1` and `to_form/2`
- Elixir does NOT support `if/else if` - use `cond` or `case`
- Use `{...}` for attribute interpolation, `<%= %>` for block constructs

#### HTTP Client Standards 

**Primary HTTP Client (ADR-002):**
- Use `:tesla` with `:finch` adapter for multi-provider API communication
- Tesla provides precise header control and middleware flexibility required for AI provider APIs
- Finch provides efficient HTTP/2 connection pooling for performance

**Secondary HTTP Client:**
- Use included `:req` (Req) library for simple HTTP requests and internal services
- Prefer existing dependencies over adding new ones (avoid `:httpoison` since `:req` already included)
- **AVOID** `:httpc` (limited functionality)

**Decision Context:**
- Tesla + Finch: Multi-provider API communication requiring exact header fidelity (Anthropic, OpenAI, Google)
- Req: General-purpose HTTP requests, file downloads, simple API calls
- HTTPoison: Not needed since Req covers the same use cases with modern API

#### Testing Standards (from CLAUDE.md)

**LiveView Testing:**
- Use `Phoenix.LiveViewTest` and `LazyHTML` for assertions
- Never test raw HTML, always use `element/2`, `has_element/2`
- Reference DOM IDs added in templates for element selection
- Focus on outcomes rather than implementation details

## Code Quality Standards

### Static Analysis

**Credo Configuration:**
- All code must pass Credo checks  
- Address warnings, don't disable rules without justification
- Maintain consistent code complexity metrics

**Dialyzer:**
- Use type specifications (`@spec`) for public functions
- Address Dialyzer warnings promptly
- Maintain PLT files for efficient analysis

### Documentation Standards

**Module Documentation:**
- Every public module needs `@moduledoc`
- Document module purpose and main responsibilities
- Include usage examples for complex modules

**Function Documentation:**
- Use `@doc` for all public functions
- Include examples using `iex>` format
- Document expected inputs and outputs

## Tool Configuration

### Mix Project (from CLAUDE.md)

**Dependencies:**
- Use exact version numbers for production dependencies
- Keep development/test dependencies up to date
- Use `:tesla` + `:finch` for multi-provider API communication (per ADR-002)
- Use `:req` for general-purpose HTTP requests (avoid `:httpoison`, `:httpc`)

**Required Aliases:**
- Use `mix precommit` alias to run all quality checks
- Maintain consistent build and test commands

### Development Workflow (from CLAUDE.md)

**Pre-commit Checks:**
1. `mix compile --warnings-as-errors`
2. `mix format`  
3. `mix credo`
4. `mix test`

**Archon Research Requirements:**
- Use Archon MCP server for documentation research before implementation
- Query for best practices and code examples 
- Cross-reference multiple sources for validation
- Adapt examples to project-specific patterns and conventions

## BMad Method Integration

### Research Integration (from CLAUDE.md)

**Mandatory Archon Queries:**

For Elixir/Phoenix development:
- `archon:search_code_examples(query="Elixir Enum.reduce examples", match_count=3)`
- `archon:search_code_examples(query="GenServer handle_call patterns", match_count=3)` 
- `archon:search_code_examples(query="Phoenix LiveView form handling examples", match_count=3)`
- `archon:search_code_examples(query="Ecto changeset validation examples", match_count=3)`
- `archon:search_code_examples(query="Tesla HTTP client middleware examples", match_count=3)`
- `archon:search_code_examples(query="Finch connection pooling configuration examples", match_count=3)`

### Quality Gates

**Development Process:**
- Research using Archon before implementation
- Plan with multi-option analysis
- Code following CLAUDE.md guidelines  
- Test with proper assertions
- Document as you go

## Reference Documents

This document works in conjunction with:
- **CLAUDE.md**: Complete Phoenix/Elixir development guidelines (MANDATORY reading)
- **docs/architecture/tech-stack.md**: Technology decisions and rationale
- **docs/architecture/source-tree.md**: Repository structure and organization

All developers must read CLAUDE.md for complete coding guidelines. This document provides project-specific standards and references to the comprehensive guidelines.