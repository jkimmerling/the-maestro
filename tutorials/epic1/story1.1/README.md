# Tutorial: Integrating Code Quality Tooling (Epic 1, Story 1.1)

## Overview

In this tutorial, we'll learn how to integrate and configure standard code quality tools into an Elixir project. By the end of this tutorial, you'll understand how to set up automated code formatting with `mix format`, static analysis with Credo, and continuous integration with GitHub Actions.

## Learning Objectives

- Configure `mix format` for consistent code formatting
- Add and configure Credo for static analysis
- Set up GitHub Actions for automated quality checks
- Understand the importance of code quality tooling in Elixir projects

## Prerequisites

- Basic understanding of Elixir and Mix
- Familiarity with Git and GitHub
- Understanding of CI/CD concepts

## Step 1: Configuring mix format

Elixir's built-in formatter ensures consistent code style across your project. The formatter is configured via a `.formatter.exs` file in your project root.

### Understanding .formatter.exs

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```

Key configuration options:

- **import_deps**: Imports formatting rules from dependencies
- **subdirectories**: Additional directories to format
- **plugins**: Custom formatters for specific file types
- **inputs**: Glob patterns for files to format

### Why This Matters

Consistent formatting eliminates bikeshedding and makes code reviews focus on logic rather than style. It's especially important in team environments.

## Step 2: Adding Credo for Static Analysis

Credo is a static code analysis tool that helps identify code smells, potential bugs, and style violations.

### Adding Credo to mix.exs

Add Credo as a development dependency:

```elixir
{:credo, "~> 1.7", only: [:dev, :test], runtime: false}
```

The `runtime: false` option means Credo won't be included in production releases.

### Configuring Credo with .credo.exs

Create a `.credo.exs` file to customize Credo's behavior:

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        enabled: [
          # Consistency checks
          {Credo.Check.Consistency.ExceptionNames, []},
          # ... more checks
        ]
      }
    }
  ]
}
```

Key configuration aspects:

- **strict: true**: Enables strict mode for higher standards
- **files.included/excluded**: Control which files are analyzed
- **checks.enabled**: Specify which checks to run

### Understanding Check Categories

Credo organizes checks into categories:

- **Consistency**: Ensures consistent naming and style
- **Design**: Identifies design issues and code smells
- **Readability**: Improves code clarity and maintainability
- **Refactoring**: Suggests opportunities for improvement
- **Warnings**: Identifies potential bugs and issues

## Step 3: Setting Up GitHub Actions CI

Continuous Integration ensures code quality checks run automatically on every commit and pull request.

### Creating the Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [ main, dev ]
  pull_request:
    branches: [ main, dev ]

env:
  MIX_ENV: test

jobs:
  code-quality:
    name: Code Quality
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.17.3'
        otp-version: '26.2.5'
        
    - name: Check code formatting
      run: mix format --check-formatted
      
    - name: Run Credo
      run: mix credo --strict
```

### Workflow Components

- **Triggers**: Run on pushes and pull requests to main/dev branches
- **Environment**: Set `MIX_ENV: test` for consistent builds
- **Steps**: Checkout, setup Elixir/OTP, run quality checks

### Benefits of Automation

- **Consistent Standards**: Every contribution meets quality standards
- **Early Detection**: Issues are caught before they reach production
- **Reduced Review Time**: Maintainers focus on logic, not formatting
- **Team Discipline**: Automated enforcement prevents quality degradation

## Step 4: Running Quality Checks

### Local Development

Run quality checks locally during development:

```bash
# Format code
mix format

# Check formatting without changing files
mix format --check-formatted

# Run static analysis
mix credo

# Run strict analysis with all checks
mix credo --strict

# Get detailed explanations for issues
mix credo explain
```

### Integration with Development Workflow

1. **Before Committing**: Run `mix format && mix credo --strict`
2. **Pre-commit Hooks**: Consider adding git hooks for automatic checks
3. **Editor Integration**: Configure your editor to run formatting on save

## Best Practices

### Code Formatting

- **Consistency Over Personal Preference**: Accept the formatter's decisions
- **Team Agreement**: Document any custom formatting configurations
- **Regular Formatting**: Run `mix format` frequently during development

### Static Analysis

- **Gradual Adoption**: Start with basic checks, add more over time
- **Custom Configuration**: Tailor Credo rules to your project's needs
- **Address Issues Promptly**: Don't let code quality debt accumulate

### Continuous Integration

- **Fast Feedback**: Keep CI builds fast for rapid iteration
- **Clear Error Messages**: Ensure failed builds provide actionable information
- **Branch Protection**: Require CI to pass before merging

## Common Issues and Solutions

### Formatting Conflicts

**Issue**: Code changes after running `mix format`

**Solution**: Always run `mix format` before committing. Consider pre-commit hooks.

### Credo Warnings

**Issue**: Too many warnings make it hard to focus on important issues

**Solution**: Start with `mix credo --strict` and gradually enable more checks. Disable less important checks initially.

### CI Build Failures

**Issue**: Builds fail due to formatting or Credo issues

**Solution**: Run checks locally before pushing. Use `mix format --check-formatted` to verify formatting without changes.

## Next Steps

After completing this tutorial, you should:

1. Understand the importance of code quality tooling
2. Be able to configure and use `mix format` and Credo
3. Set up automated quality checks with GitHub Actions
4. Know how to integrate quality tools into your development workflow

## Key Takeaways

- **Code quality tooling** is essential for maintainable Elixir projects
- **Automation** ensures consistent application of quality standards
- **Early integration** of these tools prevents technical debt
- **Team adoption** of quality standards improves collaboration

## Resources

- [Elixir Format Documentation](https://hexdocs.pm/mix/Mix.Tasks.Format.html)
- [Credo Documentation](https://hexdocs.pm/credo/)
- [GitHub Actions for Elixir](https://github.com/erlef/setup-beam)
- [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)

---

*This tutorial is part of Epic 1: Foundation & Core Agent Engine in The Maestro project.*