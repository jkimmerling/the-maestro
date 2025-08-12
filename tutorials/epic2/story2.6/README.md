# Tutorial: Epic 2 Demo Creation - Phoenix LiveView UI Showcase

This tutorial explains how to create comprehensive demos for Phoenix LiveView applications that showcase both authenticated and anonymous user modes. You'll learn best practices for demo documentation, configuration management, and user experience testing in Elixir/Phoenix applications.

## Overview

Creating effective demos is crucial for showcasing complex Phoenix LiveView applications. This tutorial covers the development of Epic 2's demo, which demonstrates the configurable authentication system and real-time web interface we built throughout the epic.

## Learning Objectives

By the end of this tutorial, you'll understand:

- **Demo Architecture**: How to structure comprehensive demos for Phoenix applications
- **Configuration Documentation**: Best practices for documenting multi-mode configurations
- **User Experience Design**: Creating clear step-by-step guides for different user workflows
- **Testing Scenarios**: Designing verification checklists and troubleshooting guides
- **Documentation Standards**: Writing maintainable demo documentation

## Key Concepts

### Demo Documentation Patterns

Phoenix LiveView applications often have complex configuration requirements and multiple operational modes. Effective demo documentation must address:

1. **Multi-Mode Support**: Authenticated vs Anonymous access patterns
2. **Environment Configuration**: Clear variable setup for different scenarios
3. **User Workflows**: Step-by-step guides for each operational mode
4. **Troubleshooting**: Common issues and their resolutions

### Configuration Management

```elixir
# Example: Configurable authentication
config :the_maestro,
  # This single setting changes the entire application behavior
  require_authentication: true  # or false for single-user mode
```

The power of configuration-driven applications lies in their flexibility, but this also creates documentation complexity.

## Implementation Walkthrough

### Step 1: Understanding the Application Modes

Before creating demo documentation, we need to understand how our application behaves in different modes:

#### Authenticated Mode (Multi-User)
```elixir
# config/config.exs
config :the_maestro,
  require_authentication: true

# Requires OAuth configuration
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {:system, "GOOGLE_CLIENT_ID"},
  client_secret: {:system, "GOOGLE_CLIENT_SECRET"}
```

In this mode:
- Users must log in via Google OAuth
- Each authenticated user gets their own agent process
- Routes are protected by authentication plugs
- Session management is tied to user identity

#### Anonymous Mode (Single-User)
```elixir
# config/config.exs
config :the_maestro,
  require_authentication: false
```

In this mode:
- No authentication required
- Agent processes are tied to browser sessions
- All routes are publicly accessible
- Simpler deployment and setup

### Step 2: Structuring Demo Documentation

Our demo documentation follows a hierarchical structure:

```markdown
# Epic 2 Demo: Phoenix LiveView UI & User Authentication

## What This Demo Demonstrates
### 🌐 Phoenix LiveView Interface
### 🔐 Configurable Authentication  
### 📱 User Experience Features
### 🏗️ Phoenix Architecture

## Prerequisites
## Running the Demo
### Mode 1: Authenticated Mode
### Mode 2: Anonymous Mode
## Configuration Details
## Testing the Demo
## Troubleshooting
## Understanding the Architecture
```

This structure addresses different reader needs:
- **What**: Clear overview of capabilities
- **How**: Step-by-step instructions
- **Why**: Architecture and design decisions
- **When**: Troubleshooting and verification

### Step 3: Environment Variable Documentation

One of the most critical aspects is clear environment variable documentation:

```markdown
| Variable | Purpose | Authenticated Mode | Anonymous Mode |
|----------|---------|-------------------|----------------|
| `GEMINI_API_KEY` | LLM API authentication | Required | Required |
| `GOOGLE_CLIENT_ID` | OAuth client ID | Required | Not needed |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret | Required | Not needed |
| `MAESTRO_REQUIRE_AUTH` | Override auth requirement | Optional | Set to `false` |
```

This table format makes it immediately clear what's needed for each mode.

### Step 4: Creating Step-by-Step Guides

For each operational mode, we provide detailed step-by-step instructions:

```markdown
#### Step-by-Step Usage

1. **Start the Server**
   ```bash
   mix phx.server
   ```
   You should see:
   ```
   [info] Running TheMaestroWeb.Endpoint with Bandit 1.0.0 at 127.0.0.1:4000 (http)
   ```

2. **Open Your Browser**
   ```
   http://localhost:4000
   ```

3. **Log In with Google**
   - Click the "Login" button on the home page
   - Grant permissions to the application
   - You'll be redirected back to the application
```

Notice how each step includes:
- **Action**: What to do
- **Command**: Exact commands to run
- **Expected Output**: What should happen
- **Visual Cues**: UI elements to look for

### Step 5: Verification and Testing

Every good demo includes verification steps:

```markdown
### Quick Verification Checklist

#### Authenticated Mode
- [ ] Server starts without errors
- [ ] Home page shows login button
- [ ] Google OAuth flow works correctly
- [ ] After login, agent interface is accessible
- [ ] Streaming responses work correctly
```

Checklists are powerful because they:
- Provide immediate feedback on success/failure
- Help identify exactly where issues occur
- Can be used for automated testing later

### Step 6: Troubleshooting Documentation

Comprehensive troubleshooting addresses common failure modes:

```markdown
#### Problem: OAuth redirect errors
```
Error: invalid_redirect_uri
```
**Solution**: Check OAuth configuration
```bash
# Ensure your OAuth app has the correct redirect URI:
# http://localhost:4000/auth/google/callback
```
```

Each troubleshooting entry follows the pattern:
1. **Problem**: Clear symptom description
2. **Error**: Exact error message (if applicable)
3. **Solution**: Step-by-step resolution
4. **Code**: Specific commands or configuration

## Advanced Techniques

### Configuration Testing

To ensure our documentation is accurate, we can create configuration test scripts:

```elixir
# test/demo_verification_test.exs
defmodule DemoVerificationTest do
  use ExUnit.Case
  
  test "authenticated mode configuration" do
    # Set test environment variables
    System.put_env("GOOGLE_CLIENT_ID", "test_id")
    System.put_env("GOOGLE_CLIENT_SECRET", "test_secret")
    
    # Verify configuration loads correctly
    config = Application.get_env(:the_maestro, :require_authentication)
    assert config == true
  end
  
  test "anonymous mode configuration" do
    # Test configuration override
    Application.put_env(:the_maestro, :require_authentication, false)
    
    config = Application.get_env(:the_maestro, :require_authentication)
    assert config == false
  end
end
```

### Documentation Generation

For complex applications, consider generating parts of your demo documentation:

```elixir
defmodule DemoDocGenerator do
  @moduledoc """
  Generates demo documentation from application configuration
  """
  
  def generate_env_vars_table do
    required_vars = get_required_env_vars()
    optional_vars = get_optional_env_vars()
    
    # Generate markdown table
    generate_table(required_vars ++ optional_vars)
  end
  
  defp get_required_env_vars do
    # Extract from configuration
    [
      %{name: "GEMINI_API_KEY", purpose: "LLM API authentication", required: true},
      # ...
    ]
  end
end
```

### User Experience Testing

Consider automating the user experience verification:

```elixir
# test/support/demo_helper.ex
defmodule TheMaestro.DemoHelper do
  @moduledoc """
  Helper functions for testing demo scenarios
  """
  
  def simulate_oauth_flow(conn) do
    # Simulate the OAuth callback flow
    conn
    |> get("/auth/google")
    |> follow_redirect()
    # Verify successful authentication
  end
  
  def verify_streaming_response(live_view) do
    # Test that streaming responses work
    live_view
    |> form("#message-form", message: %{content: "Hello"})
    |> render_submit()
    
    # Verify streaming behavior
  end
end
```

## Best Practices

### 1. **Audience-Specific Documentation**

Structure your demo for different audiences:

```markdown
## For Developers
- Architecture explanations
- Code examples
- Configuration options

## For Users
- Step-by-step instructions
- Screenshots
- Troubleshooting

## For DevOps
- Environment variables
- Deployment considerations
- Security notes
```

### 2. **Maintainable Documentation**

Keep documentation maintainable by:

- **Version Alignment**: Update documentation with code changes
- **Automated Testing**: Test documentation instructions programmatically
- **Template Patterns**: Reuse successful documentation structures
- **Clear Ownership**: Assign documentation maintenance responsibility

### 3. **Progressive Complexity**

Structure demos with increasing complexity:

1. **Basic Setup**: Get the application running
2. **Core Features**: Demonstrate main functionality
3. **Advanced Usage**: Show complex scenarios
4. **Customization**: How to modify and extend

### 4. **Error Anticipation**

Good demo documentation anticipates common errors:

```markdown
### Common Setup Issues

#### Database Connection
**Symptom**: `Postgrex.Error: connection refused`
**Cause**: Database not running
**Solution**: `brew services start postgresql`

#### Port Conflicts  
**Symptom**: `Address already in use`
**Cause**: Another process using port 4000
**Solution**: `lsof -i :4000` then kill the process
```

## Testing Your Demo

Always test your demo documentation by:

1. **Fresh Environment**: Test on a clean system
2. **Different Platforms**: Verify cross-platform compatibility
3. **Multiple Users**: Test with team members unfamiliar with the code
4. **Automated Verification**: Create scripts to verify demo steps

## Integration with Development Workflow

Integrate demo creation into your development process:

```elixir
# In your Epic completion checklist
- [ ] Core functionality implemented
- [ ] Tests passing
- [ ] Demo created and tested
- [ ] Tutorial written
- [ ] Documentation updated
```

## Conclusion

Creating comprehensive demos for Phoenix LiveView applications requires attention to:

- **Multi-modal configuration**: Supporting different operational modes
- **Clear instructions**: Step-by-step guides for each scenario
- **Thorough testing**: Verification checklists and troubleshooting
- **Maintainable structure**: Templates and patterns for consistency

The investment in quality demo documentation pays dividends in:
- **Reduced support burden**: Users can self-serve successfully
- **Better adoption**: Clear onboarding increases usage
- **Team efficiency**: New team members can understand the system quickly
- **Quality assurance**: Documentation testing catches configuration issues

## Key Takeaways

1. **Configuration-driven applications need configuration-aware documentation**
2. **Step-by-step instructions must include expected outputs**
3. **Troubleshooting sections should anticipate common failure modes**
4. **Verification checklists provide immediate feedback on success**
5. **Demo documentation is living documentation that needs maintenance**

## Next Steps

- Review the Epic 2 demo implementation in `demos/epic2/README.md`
- Try creating demos for your own Phoenix LiveView applications
- Experiment with automated documentation testing
- Explore Epic 3 for advanced agent capabilities

## Related Tutorials

- [Story 2.1: Phoenix Project Integration & Basic Layout](../story2.1/README.md)
- [Story 2.2: Configurable Web User Authentication](../story2.2/README.md)
- [Story 2.3: Main Agent LiveView Interface](../story2.3/README.md)
- [Story 2.4: Real-time Streaming & Status Updates](../story2.4/README.md)

---

*This tutorial is part of The Maestro project - demonstrating advanced Phoenix LiveView patterns and comprehensive documentation practices.*