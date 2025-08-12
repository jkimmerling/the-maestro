# Code Style Guide

## Context

Global code style rules for Agent OS projects.

<conditional-block context-check="general-formatting">
IF this General Formatting section already read in current context:
  SKIP: Re-reading this section
  NOTE: "Using General Formatting rules already in context"
ELSE:
  READ: The following formatting rules

## General Formatting

### Indentation
- Use 2 spaces for indentation (never tabs)
- Maintain consistent indentation throughout files
- Align nested structures for readability

### Naming Conventions
- **Methods and Variables**: Use snake_case (e.g., `user_profile`, `calculate_total`)
- **Classes and Modules**: Use PascalCase (e.g., `UserProfile`, `PaymentProcessor`)
- **Constants**: Use UPPER_SNAKE_CASE (e.g., `MAX_RETRY_COUNT`)

### String Formatting
- Use single quotes for strings: `'Hello World'`
- Use double quotes only when interpolation is needed
- Use template literals for multi-line strings or complex interpolation

### Code Comments
- Add brief comments above non-obvious business logic
- Document complex algorithms or calculations
- Explain the "why" behind implementation choices
- Never remove existing comments unless removing the associated code
- Update comments when modifying code to maintain accuracy
- Keep comments concise and relevant
</conditional-block>

<conditional-block task-condition="html-css-tailwind" context-check="html-css-style">
IF current task involves writing or updating HTML, CSS, or TailwindCSS:
  IF html-style.md AND css-style.md already in context:
    SKIP: Re-reading these files
    NOTE: "Using HTML/CSS style guides already in context"
  ELSE:
    <context_fetcher_strategy>
      IF current agent is Claude Code AND context-fetcher agent exists:
        USE: @agent:context-fetcher
        REQUEST: "Get HTML formatting rules from code-style/html-style.md"
        REQUEST: "Get CSS and TailwindCSS rules from code-style/css-style.md"
        PROCESS: Returned style rules
      ELSE:
        READ the following style guides (only if not already in context):
        - @~/.agent-os/standards/code-style/html-style.md (if not in context)
        - @~/.agent-os/standards/code-style/css-style.md (if not in context)
    </context_fetcher_strategy>
ELSE:
  SKIP: HTML/CSS style guides not relevant to current task
</conditional-block>

<conditional-block task-condition="javascript" context-check="javascript-style">
IF current task involves writing or updating JavaScript:
  IF javascript-style.md already in context:
    SKIP: Re-reading this file
    NOTE: "Using JavaScript style guide already in context"
  ELSE:
    <context_fetcher_strategy>
      IF current agent is Claude Code AND context-fetcher agent exists:
        USE: @agent:context-fetcher
        REQUEST: "Get JavaScript style rules from code-style/javascript-style.md"
        PROCESS: Returned style rules
      ELSE:
        READ: @~/.agent-os/standards/code-style/javascript-style.md
    </context_fetcher_strategy>
ELSE:
  SKIP: JavaScript style guide not relevant to current task
</conditional-block>

<conditional-block task-condition="elixir" context-check="elixir-style">
IF current task involves writing or updating Elixir:
  IF Elixir style rules already read in current context:
    SKIP: Re-reading this section
    NOTE: "Using Elixir style guide already in context"
  ELSE:
    READ: The following Elixir style rules
ELSE:
  SKIP: Elixir style guide not relevant to current task

## Elixir Style Guide

### Automatic Formatting
- **MANDATORY**: Use `mix format` for all Elixir files
- Configure `.formatter.exs` in project root
- Integrate format-on-save in your editor
- Run `mix format --check-formatted` in CI/CD

### Naming Conventions
- **Functions and Variables**: snake_case (`user_name`, `calculate_total`)
- **Modules**: CamelCase (`MyApp.UserService`, `HTTPClient`)
- **Atoms**: snake_case (`:user_name`, `:ok`, `:error`)
- **Boolean Functions**: 
  - Suffix with `?` for general booleans (`valid?`, `empty?`)
  - Prefix with `is_` for guard-safe functions (`is_list`, `is_atom`)
- **Exception Functions**: Suffix with `!` (`File.read!`, `String.to_integer!`)

### String Formatting
- **Prefer double quotes** for strings: `"Hello World"`
- Use single quotes only for charlists when needed
- Use sigils for special string types (`~s`, `~r`, etc.)
- Use interpolation with `#{}`: `"Hello #{name}"`

### Function Definitions
- Always use parentheses when functions have arguments: `def hello(name)`
- Omit parentheses only for zero-argument functions: `def hello`
- Use `do:` syntax for single-line functions: `def add(a, b), do: a + b`

### Pipe Operator (|>)
- Use for chaining 2 or more functions
- Start pipeline with a variable, not a function call
- Avoid for single function calls
```elixir
# Good
data
|> String.trim()
|> String.downcase()
|> String.split()

# Avoid
data |> String.trim()  # single call
String.trim(data) |> String.downcase()  # starts with function
```

### Module Structure (in order)
1. `@moduledoc`
2. `@behaviour`
3. `use`
4. `import`
5. `alias`
6. `require`
7. `@module_attribute`
8. `defstruct`
9. `@type` / `@spec`
10. Public functions (`def`)
11. Private functions (`defp`)

### Comments and Documentation
- Use `@moduledoc` and `@doc` for public API documentation
- Use `#` comments only for implementation details
- Write `@spec` for all public functions
- Include examples in `@doc` that work as doctests
</conditional-block>
