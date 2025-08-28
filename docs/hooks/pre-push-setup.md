# Pre-Push Hook Setup Documentation

## Overview

A comprehensive pre-push git hook has been installed that automatically runs quality checks before allowing any `git push` operations. This ensures that code quality standards are maintained across the project.

## What the Hook Does

The pre-push hook runs **6 sequential quality checks** that must all pass before allowing a push:

### 1. **Dependency Installation** (`mix deps.get`)
- Ensures all required dependencies are installed
- Prevents issues from missing dependencies

### 2. **Compilation Check** (`mix compile --warnings-as-errors`)
- Compiles the project treating warnings as errors
- Prevents pushing code with compilation warnings or errors

### 3. **Code Formatting** (`mix format --check-formatted`)
- Verifies all code follows proper Elixir formatting standards
- Requires running `mix format` to fix any formatting issues

### 4. **Test Suite** (`mix test`)
- Runs the complete test suite
- All tests must pass before push is allowed

### 5. **Code Quality Analysis** (`mix credo --strict --only readability,refactor,warning,consistency`)
- Runs Credo static code analysis
- Focuses on critical issues: readability, refactor, warning, and consistency
- Allows design suggestions but blocks on critical quality issues

### 6. **Type Checking** (`mix dialyzer`)
- Runs Dialyzer static type analysis
- Ensures type safety and catches potential runtime errors
- First-time setup includes automatic PLT (Persistent Lookup Table) generation

## Hook Installation Details

### File Location
- **Hook File**: `.git/hooks/pre-push`
- **Permissions**: Executable (`chmod +x`)

### Dependencies Added
The following dependencies were added to `mix.exs`:

```elixir
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

### Mix Alias Updated
The `precommit` alias was updated to include the new tools:

```elixir
precommit: [
  "compile --warning-as-errors",
  "deps.unlock --unused", 
  "format",
  "test",
  "credo --strict",
  "dialyzer"
]
```

## Hook Behavior

### ✅ **Success Scenario**
When all checks pass:
```
🚀 Running Cleanops pre-push quality checks...
==> Step 1/6: Installing dependencies...
✅ Dependencies installed
==> Step 2/6: Compiling project (warnings as errors)...
✅ Compilation successful  
==> Step 3/6: Checking code formatting...
✅ Code formatting is correct
==> Step 4/6: Running test suite...
✅ All tests passed
==> Step 5/6: Running Credo code analysis...
✅ Credo analysis passed (design suggestions allowed)
==> Step 6/6: Running Dialyzer type checking...
✅ Dialyzer analysis passed

✅ 🎉 All quality checks passed! Push proceeding...
```

### ❌ **Failure Scenario**
When any check fails, the push is **blocked** and you'll see:
```
❌ [Check name] failed
⚠️  [Helpful guidance on how to fix]
```

The hook exits immediately on the first failure to provide fast feedback.

## Common Fixes

### Code Formatting Issues
```bash
# Fix formatting issues
mix format

# Then retry push
git push
```

### Credo Issues
```bash
# See detailed credo issues
mix credo --strict

# Fix issues manually or run
mix credo explain [issue_id]
```

### Test Failures
```bash
# Run tests to see failures
mix test

# Run specific test file
mix test test/path/to/failing_test.exs

# Run tests with more details
mix test --trace
```

### Dialyzer Issues
```bash
# See dialyzer issues
mix dialyzer

# For detailed explanations
mix dialyzer --explain warning_type
```

## Performance Considerations

### First Run
- **Dialyzer PLT Generation**: The first run may take several minutes as Dialyzer builds its PLT
- **Subsequent runs**: Much faster (typically < 30 seconds for the full suite)

### Optimization Tips
- Keep dependencies up to date for faster analysis
- The PLT is cached between runs for performance
- Hook provides clear progress indicators for long-running steps

## Bypassing the Hook (Emergency Only)

⚠️ **Not recommended for normal development**

```bash
# Emergency bypass (use sparingly)
git push --no-verify

# Or temporarily disable
mv .git/hooks/pre-push .git/hooks/pre-push.disabled
git push
mv .git/hooks/pre-push.disabled .git/hooks/pre-push
```

## Integration with Development Workflow

### Recommended Workflow
1. **Develop** your feature/fix
2. **Test locally** with `mix test`
3. **Format code** with `mix format`
4. **Run quality checks** with `mix precommit` (optional, but recommended)
5. **Commit** your changes with `git commit`
6. **Push** with `git push` (hook runs automatically)

### CI/CD Integration
This hook complements CI/CD pipelines by:
- **Catching issues early** (before they reach CI)
- **Reducing CI failures** and associated costs
- **Providing faster feedback** to developers
- **Maintaining consistent quality** standards

## Maintenance

### Updating Dependencies
The hook automatically installs dependencies but you may need to update:

```bash
# Update credo
mix deps.update credo

# Update dialyxir  
mix deps.update dialyxir

# Rebuild dialyzer PLT after major updates
rm -rf _build/dev/dialyxir_*
```

### Modifying Hook Behavior
Edit `.git/hooks/pre-push` to:
- Add additional checks
- Modify severity levels
- Adjust timeout values
- Customize output formatting

## Troubleshooting

### Hook Not Running
```bash
# Verify hook is executable
ls -la .git/hooks/pre-push

# Make executable if needed
chmod +x .git/hooks/pre-push
```

### Performance Issues
```bash
# Clean and rebuild if dialyzer is slow
mix clean
mix deps.compile
rm -rf _build/dev/dialyxir_*
mix dialyzer --plt
```

### Environment Issues
```bash
# Verify Elixir/OTP versions are compatible
elixir --version
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
```

## Quality Standards Enforced

This hook ensures:
- **Zero compilation warnings**
- **100% test pass rate** 
- **Consistent code formatting**
- **High code quality standards** (via Credo)
- **Type safety** (via Dialyzer)
- **Dependency integrity**

By implementing this pre-push hook, the Cleanops Elixir project maintains high quality standards and reduces the likelihood of bugs reaching production.