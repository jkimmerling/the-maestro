Development Best Practices

## CRITIAL IMPORTANT MUST DO

If you think "simpler" - do not do it, fixit/do it the right way

## Context

Global development guidelines for Agent OS projects.

## CRITICAL: Git Workflow Requirements

**VERY IMPORTANT** - These practices are mandatory for all development work:

### Branch Management
- Create a new git branch for each feature or story
- Branch naming format: `{story-number}-{short-descriptive-title}`
  - Example: `1.1-user-authentication` or `2.3-api-rate-limiting`
- Use kebab-case for branch names (lowercase with hyphens)

### Commit Strategy
- Commit after every successful addition or change
- "Successful" means the change passes all tests
- Never commit broken or failing code

### Commit Messages
- Write comprehensive commit messages within GitHub's length limits
- Messages should give developers a clear understanding of:
  - What was done
  - What changes were made
  - Why the change was necessary (if not obvious)
- Use present tense and imperative mood
- Example: `Add user authentication middleware with JWT validation and rate limiting`

### Epic Demonstrations
- Each completed epic must produce (if possible) a runnable, self-contained demo located in the demos/[epic_name]/ directory
- The demo must include a README.md guide explaining its purpose and how to run it

### Iterative Tutorials
- Each completed story must produce a corresponding educational tutorial in Markdown format
- The tutorial should teach an intermediate Elixir developer how the story's features were built, styled like a blog post with code snippets and explanations
- Tutorials must be located in tutorials/[epic_name]/[story_name]/
- A main tutorials/index.md file must be updated with a link to the new tutorial

<conditional-block context-check="core-principles">
IF this Core Principles section already read in current context:
  SKIP: Re-reading this section
  NOTE: "Using Core Principles already in context"
ELSE:
  READ: The following principles

## Core Principles

### Keep It Simple
- Implement code in the fewest lines possible
- Avoid over-engineering solutions
- Choose straightforward approaches over clever ones

### Optimize for Readability
- Prioritize code clarity over micro-optimizations
- Write self-documenting code with clear variable names
- Add comments for "why" not "what"

### DRY (Don't Repeat Yourself)
- Extract repeated business logic to private methods
- Extract repeated UI markup to reusable components
- Create utility functions for common operations

### File Structure
- Keep files focused on a single responsibility
- Group related functionality together
- Use consistent naming conventions
</conditional-block>

<conditional-block context-check="dependencies" task-condition="choosing-external-library">
IF current task involves choosing an external library:
  IF Dependencies section already read in current context:
    SKIP: Re-reading this section
    NOTE: "Using Dependencies guidelines already in context"
  ELSE:
    READ: The following guidelines
ELSE:
  SKIP: Dependencies section not relevant to current task

## Dependencies

### Choose Libraries Wisely
When adding third-party dependencies:
- Select the most popular and actively maintained option
- Check the library's GitHub repository for:
  - Recent commits (within last 6 months)
  - Active issue resolution
  - Number of stars/downloads
  - Clear documentation
</conditional-block>

<conditional-block context-check="elixir-specifics" task-condition="elixir-development">
IF current task involves Elixir development:
  IF Elixir Best Practices section already read in current context:
    SKIP: Re-reading this section
    NOTE: "Using Elixir practices already in context"
  ELSE:
    READ: The following Elixir-specific practices
ELSE:
  SKIP: Elixir practices not relevant to current task

## Elixir-Specific Practices

### Code Quality & Consistency
- Use `mix format` for automatic code formatting
- Integrate Credo for static analysis and code quality checks
- Follow snake_case for variables/functions, CamelCase for modules
- Use trailing `!` for functions that raise exceptions, `?` for boolean returns

### Function Complexity Guidelines
- **One Function = One Task**: Each function should have a single, clear responsibility
- **Cyclomatic Complexity**: Keep complexity ≤9 (Credo default maximum)
- **Nesting Depth**: Limit function body nesting to ≤2 levels deep (Credo default)
- **Function Length**: Aim for functions under 20 lines when possible
- **Refactoring Strategy**: When functions become complex:
  - Extract helper functions for subtasks
  - Use early returns to reduce nesting
  - Break down conditional logic into separate functions
  - Consider using `with` statements for happy path flows

### Documentation Standards
- Write `@moduledoc` and `@doc` as public API contracts
- Use `@spec` for type specifications on all public functions
- Include testable examples with doctests
- Reserve inline comments (#) for implementation details only

### Domain Organization
- Structure applications using Phoenix Contexts for domain boundaries
- Keep web layer thin - delegate business logic to contexts
- Use service/operation layers for cross-context coordination
- Avoid direct database access from controllers/LiveViews

### Process Guidelines
- Use processes (GenServer) only for runtime properties: state, resources, concurrency
- Prefer plain modules for organizing pure functions
- Always supervise long-running processes
- Send minimal data in process messages to reduce copying overhead

### Common Anti-Patterns to Avoid
- Primitive obsession (overusing strings/integers for domain concepts)
- Exceptions for control flow (prefer tagged tuples)
- Fat controllers/LiveViews (business logic belongs in contexts)
- Unsupervised processes
</conditional-block>
