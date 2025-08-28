# Coding Standards

## Overview

This document consolidates coding standards, development best practices, and quality requirements for the Cleanops CRM project. These standards ensure code consistency, maintainability, and quality across the development team.

## Quality Standards


### Automated Enforcement

All code changes must pass:

1. **Unit test coverage**: minimum 80%
2. **Integration test coverage**: minimum 70%
3. **Security scan**: zero critical vulnerabilities
4. **Code complexity**: maximum cyclomatic complexity of 10
5. **Performance**: response time < 200ms for API calls

### Sub-agent Validation

Required approvals before merge:
- `code-reviewer`: PASS (no critical issues)
- `test-automator`: PASS (comprehensive coverage)
- `qa-expert`: PASS (strategy validated)

### Exemption Process

Exemptions require:
- Technical justification in `decisions.md`
- Alternative mitigation strategies
- Time-bound remediation plan

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

## Development Best Practices

### CRITICAL: Git Workflow Requirements

**VERY IMPORTANT** - These practices are mandatory for all development work:

#### Branch Management
- Create a new git branch for each feature or story
- Branch naming format: `{story-number}-{short-descriptive-title}`
  - Example: `1.1-user-authentication` or `2.3-api-rate-limiting`
- Use kebab-case for branch names (lowercase with hyphens)

#### Commit Strategy
- Commit after every successful addition or change
- "Successful" means the change passes all tests
- Never commit broken or failing code

#### Commit Messages
- Write comprehensive commit messages within GitHub's length limits
- Messages should give developers a clear understanding of:
  - What was done
  - What changes were made
  - Why the change was necessary (if not obvious)
- Use present tense and imperative mood
- Example: `Add user authentication middleware with JWT validation and rate limiting`

#### 🚨 ZERO TOLERANCE: Git Hook Bypassing Policy

**ABSOLUTELY FORBIDDEN - IMMEDIATE DISCIPLINARY ACTION:**

- **NEVER use `--no-verify` flag on commits or pushes**
- **NEVER use `--force` or `--force-with-lease` to bypass checks**
- **NEVER disable or bypass pre-commit hooks**
- **NEVER skip CI/CD pipeline validation**

**These commands are COMPLETELY PROHIBITED:**
```bash
# ❌ FORBIDDEN - ZERO TOLERANCE
git commit --no-verify
git push --no-verify
git push --force
git push --force-with-lease
git commit -n  # shorthand for --no-verify
```

**CONSEQUENCES:**
- First violation: Immediate code review and retraining
- Second violation: Formal disciplinary action
- Third violation: Project removal

**WHY THIS MATTERS:**
- Hooks enforce critical security, quality, and compliance checks
- Bypassing hooks introduces vulnerabilities, bugs, and technical debt
- Team code quality depends on consistent enforcement
- Client deliverables require verified, validated code

**CORRECT APPROACH:**
```bash
# ✅ ALWAYS DO THIS
git commit -m "Your message"
git push

# ✅ IF HOOKS FAIL - FIX THE ISSUES, DON'T BYPASS
# 1. Read the hook failure message
# 2. Fix the identified issues
# 3. Run hooks locally: npm run lint, npm run test, etc.
# 4. Commit and push normally
```

### Core Principles

#### Keep It Simple
- Implement code in the fewest lines possible
- Avoid over-engineering solutions
- Choose straightforward approaches over clever ones

#### Optimize for Readability
- Prioritize code clarity over micro-optimizations
- Write self-documenting code with clear variable names
- Add comments for "why" not "what"

#### DRY (Don't Repeat Yourself)
- Extract repeated business logic to private methods
- Extract repeated UI markup to reusable components
- Create utility functions for common operations

#### File Structure
- Keep files focused on a single responsibility
- Group related functionality together
- Use consistent naming conventions

### Elixir-Specific Practices

#### Code Quality & Consistency
- Use `mix format` for automatic code formatting
- Integrate Credo for static analysis and code quality checks
- Follow snake_case for variables/functions, CamelCase for modules
- Use trailing `!` for functions that raise exceptions, `?` for boolean returns

#### Function Complexity Guidelines
- **One Function = One Task**: Each function should have a single, clear responsibility
- **Cyclomatic Complexity**: Keep complexity ≤9 (Credo default maximum)
- **Nesting Depth**: Limit function body nesting to ≤2 levels deep (Credo default)
- **Function Length**: Aim for functions under 20 lines when possible
- **Refactoring Strategy**: When functions become complex:
  - Extract helper functions for subtasks
  - Use early returns to reduce nesting
  - Break down conditional logic into separate functions
  - Consider using `with` statements for happy path flows

#### Documentation Standards
- Write `@moduledoc` and `@doc` as public API contracts
- Use `@spec` for type specifications on all public functions
- Include testable examples with doctests
- Reserve inline comments (#) for implementation details only

#### Domain Organization
- Structure applications using Phoenix Contexts for domain boundaries
- Keep web layer thin - delegate business logic to contexts
- Use service/operation layers for cross-context coordination
- Avoid direct database access from controllers/LiveViews

#### Process Guidelines
- Use processes (GenServer) only for runtime properties: state, resources, concurrency
- Prefer plain modules for organizing pure functions
- Always supervise long-running processes
- Send minimal data in process messages to reduce copying overhead

#### Common Anti-Patterns to Avoid
- Primitive obsession (overusing strings/integers for domain concepts)
- Exceptions for control flow (prefer tagged tuples)
- Fat controllers/LiveViews (business logic belongs in contexts)
- Unsupervised processes

### Dependencies

#### Choose Libraries Wisely

When adding third-party dependencies:
- Select the most popular and actively maintained option
- Check the library's GitHub repository for:
  - Recent commits (within last 6 months)
  - Active issue resolution
  - Number of stars/downloads
  - Clear documentation

## Testing Standards

### Test-Driven Development (TDD)

Follow the **Red-Green-Refactor** cycle:

1. **Red**: Write a failing test that describes desired behavior
2. **Green**: Write minimal code to make the test pass  
3. **Refactor**: Improve code quality while keeping tests green

### Testing Best Practices

#### Test Structure (Arrange-Act-Assert)

```elixir
test "security confirmation engine approves low-risk operations automatically" do
  # Arrange
  engine = start_supervised!({ConfirmationEngine, []})
  low_risk_request = build_confirmation_request(:low_risk)
  
  # Act
  {:ok, result} = ConfirmationEngine.request_confirmation(engine, low_risk_request)
  
  # Assert
  assert result.approved == true
  assert result.reason == "Auto-approved: low risk operation"
end
```

#### Test Organization

- Use `describe` blocks to group related tests
- Each test should be independent and run in isolation
- Use `async: true` for tests that don't share state
- Create test data builders for complex structures

#### Coverage Requirements

- **Unit Tests**: Minimum 80% coverage
- **Integration Tests**: Minimum 70% coverage
- Focus on testing behaviors, not implementation details
- Test error conditions and edge cases

### Testing Anti-Patterns to Avoid

- Don't test multiple things in one test
- Don't use `sleep` for timing - use proper synchronization
- Don't create overly complex test setup
- Don't ignore test performance

## Code Review Standards

### Review Checklist

All code reviews must verify:

1. **Functionality**: Code works as intended
2. **Standards Compliance**: Follows all style and naming conventions
3. **Test Coverage**: Adequate test coverage with meaningful tests
4. **Performance**: No obvious performance issues
5. **Security**: No security vulnerabilities introduced
6. **Documentation**: Code is properly documented
7. **Maintainability**: Code is readable and maintainable

### Review Process

1. **Author Self-Review**: Review your own code before submitting
2. **Automated Checks**: Ensure all CI checks pass
3. **Peer Review**: At least one peer code review required
4. **Architectural Review**: Complex changes require architect approval

## Quality Enforcement

### Automated Tools

- **Mix Format**: Automatic code formatting
- **Credo**: Static analysis and code quality
- **Dialyzer**: Type checking and bug detection
- **ExUnit**: Testing framework with coverage reporting
- **Security Scanning**: Automated vulnerability detection

### Continuous Integration

All pull requests must pass:
- Code formatting checks (`mix format --check-formatted`)
- Static analysis checks (`mix credo --strict`)
- All tests (`mix test`)
- Type checking (`mix dialyzer`)
- Security scanning

### Quality Gates

No code can be merged without:
- All automated checks passing
- Required code review approvals
- Test coverage meeting minimum thresholds
- Performance requirements met

## Implementation Guidelines

### New Features

1. **Plan**: Design the feature architecture
2. **Test**: Write tests first (TDD approach)
3. **Implement**: Write minimal code to pass tests
4. **Refactor**: Improve code quality while keeping tests green
5. **Document**: Update documentation as needed
6. **Review**: Submit for code review

### Bug Fixes

1. **Reproduce**: Create a failing test that demonstrates the bug
2. **Fix**: Implement the minimal fix to make the test pass
3. **Verify**: Ensure the fix doesn't break existing functionality
4. **Document**: Update documentation if needed

### Refactoring

1. **Test Coverage**: Ensure good test coverage before refactoring
2. **Small Steps**: Make small, incremental changes
3. **Verify**: Run tests after each change
4. **Document**: Update documentation to reflect changes

## Documentation Standards

### Code Documentation

- All public functions must have `@doc` and `@spec`
- Include examples that work as doctests
- Document complex business logic with inline comments
- Keep documentation up-to-date with code changes

### Project Documentation

- Update architecture docs for significant changes
- Maintain clear README files
- Document deployment and setup procedures
- Keep API documentation current

This document serves as the authoritative source for coding standards in the Cleanops CRM project. All developers must follow these standards, and violations should be addressed in code reviews.