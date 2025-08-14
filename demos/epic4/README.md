# Epic 4 Demo: Terminal User Interface (TUI)

This demo showcases The Maestro's Terminal User Interface (TUI), providing a complete CLI experience for interacting with the AI agent. The TUI offers the same powerful features as the web interface but optimized for developers who prefer working in the terminal.

## Overview

Epic 4 delivers a feature-complete terminal interface that:
- **Runs completely standalone** - no external Phoenix server required!
- **Built-in OAuth server** - includes embedded web server for device authorization
- Supports both authenticated and anonymous modes based on configuration
- Provides real-time streaming responses from the AI agent
- Displays visual tool usage indicators and results
- Offers a clean, responsive terminal UI with ANSI colors
- Maintains conversation history and state management

## Prerequisites

1. **Elixir and Mix**: Ensure you have Elixir 1.14+ installed
2. **Dependencies**: Install project dependencies with `mix deps.get`
3. **Database**: Ensure the database is set up with `mix ecto.setup`
4. **API Keys**: Configure at least one LLM provider (see Configuration section)

**Note**: The TUI is completely self-contained and does not require the Phoenix web server to be running!

## Quick Start

The TUI runs completely standalone with its own embedded OAuth server!

### Option 1: Build and Run the Escript (Recommended)

```bash
# Build the escript executable
MIX_ENV=prod mix escript.build

# Run the TUI (completely standalone!)
./maestro_tui
```

### Authentication Modes

#### Authenticated Mode (Default)
The TUI includes its own embedded web server for OAuth device authorization:

1. **Run the TUI**: `./maestro_tui`
2. **Follow the prompts**: The TUI will display a URL to visit in your browser
3. **Authorize**: Visit the URL (e.g., `http://localhost:4001/auth/device?user_code=ABCD-1234`)
4. **Complete**: Return to the terminal to continue

#### Anonymous Mode (No Authentication)
For development or single-user setups:

```bash
# 1. Edit config/config.exs to disable authentication:
# config :the_maestro, require_authentication: false

# 2. Build and run the TUI
MIX_ENV=prod mix escript.build
./maestro_tui
```

### Option 2: Run via Mix Task

You can also run the TUI directly through Mix:

```bash
# Run in development mode
mix run -e "TheMaestro.TUI.CLI.main([])"
```

## Configuration

### Authentication Modes

The TUI supports two authentication modes, configured in `config/config.exs`:

#### Authenticated Mode (Default)
```elixir
config :the_maestro, require_authentication: true
```

In this mode:
- TUI will initiate a device authorization flow
- You'll be prompted to visit a URL in your browser
- Enter the provided user code to authorize the device
- Credentials are stored securely in `~/.maestro/tui_credentials.json`

#### Anonymous Mode
```elixir
config :the_maestro, require_authentication: false
```

In this mode:
- No authentication required
- Direct access to the agent interface
- Ideal for single-user setups or development

### LLM Provider Configuration

Configure at least one LLM provider by setting the appropriate environment variable:

#### Gemini (Default)
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

#### OpenAI
```bash
export OPENAI_API_KEY="your-openai-api-key"
```

#### Anthropic
```bash
export ANTHROPIC_API_KEY="your-anthropic-api-key"
```

## Demo Walkthrough

### Step 1: Launch the TUI

```bash
./maestro_tui
```

You'll see the welcome screen:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                              The Maestro TUI                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
Conversation History:
[SYSTEM] Welcome to The Maestro TUI!
[SYSTEM] Running in anonymous mode  # or "Authenticated as: user@example.com"
[SYSTEM] Type your message and press Enter to chat with the agent.
[SYSTEM] Press Ctrl-C or 'q' to exit.

╠══════════════════════════════════════════════════════════════════════════════╣
Status: Ready
╠══════════════════════════════════════════════════════════════════════════════╣
Input: 
Press Enter to send, Ctrl-C or 'q' to quit
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Step 2: Basic Conversation

Type a simple message and press Enter:

```
What is the current time?
```

You'll see the agent respond with streaming text, updating in real-time.

### Step 3: Tool Usage Demo

Try a command that uses tools:

```
Please read the README.md file in this directory
```

Watch as the TUI shows:
1. Status update: `📖 Using tool: read_file...`
2. Tool result display with formatted output
3. Agent's analysis of the file contents

### Step 4: Advanced Features

#### File Operations
```
Create a test file called demo.txt with some sample content
```

#### Shell Commands (if enabled and configured)
```
List the files in the current directory
```

#### API Interactions (if OpenAPI tools are configured)
```
Make an API call to check the status of a web service
```

### Step 5: Session Management

The TUI maintains conversation history and can handle:
- Long conversation threads
- Multiple tool calls in sequence
- Error handling and recovery
- Clean exit with Ctrl-C or typing 'q'

## TUI Features Demonstrated

### Visual Indicators

- **🤔 Thinking...**: Agent is processing your request
- **📖 Using tool: read_file...**: File system operations
- **✏️ Using tool: write_file...**: File writing operations
- **📁 Using tool: list_directory...**: Directory listing
- **⚡ Using tool: execute_command...**: Shell command execution
- **🌐 Using tool: api_call...**: API interactions

### Message Types

- **[USER]**: Your input messages (cyan)
- **[AGENT]**: AI agent responses (green)
- **[SYSTEM]**: System messages and status (yellow)
- **[TOOL]**: Tool execution results (magenta)

### Interface Elements

- **Header**: Application title and branding
- **Conversation History**: Scrollable message history
- **Status Line**: Current agent activity indicator
- **Input Area**: Command input with helpful hints
- **Borders**: Clean ASCII art borders for visual separation

## Troubleshooting

### Common Issues

#### Authentication Problems
```
Error: TUI embedded server startup failed
# or  
Error: Port 4001 already in use
```
**Solution**: The TUI's embedded OAuth server failed to start. This is usually a port conflict:

**Check for port conflicts:**
```bash
lsof -i :4001
# Kill any processes using port 4001 if needed
```

**Alternative ports**: The TUI will try different ports automatically, or you can switch to anonymous mode:
```bash
# Edit config/config.exs to bypass authentication:
config :the_maestro, require_authentication: false
# Then rebuild: MIX_ENV=prod mix escript.build
```

**Network Issues**: If you see connection timeouts, check that your browser can access `http://localhost:4001`. The TUI includes its own web server for OAuth.

#### Missing API Keys
```
Error: Failed to get agent response: no provider configured
```
**Solution**: Set your LLM provider API key:
```bash
export GEMINI_API_KEY="your-api-key"
```

#### Terminal Display Issues
```
Garbled output or poor formatting
```
**Solution**: Ensure your terminal supports ANSI escape codes and has sufficient dimensions (80x24 minimum)

#### Tool Execution Errors
```
Error: Tool execution failed: permission denied
```
**Solution**: Check tool configuration in `config/config.exs` and ensure proper permissions

### Debug Mode

For debugging, you can run with more verbose output:

```bash
ELIXIR_LOG_LEVEL=debug ./maestro_tui
```

## Configuration Options

### Terminal Settings

The TUI automatically detects terminal capabilities but works best with:
- Terminals supporting ANSI colors and escape codes
- Minimum 80x24 character display
- UTF-8 character encoding support

### Tool Configuration

Tools can be configured in `config/config.exs`:

```elixir
# File system tool configuration
config :the_maestro, :file_tool,
  allowed_directories: ["/tmp", "/home/user/projects"]

# Shell tool configuration  
config :the_maestro, :shell_tool,
  enabled: true,
  sandbox_enabled: true,
  timeout_seconds: 30
```

## Architecture Notes

The TUI demonstrates several key architectural patterns:

1. **Minimal OTP Application**: Uses `TheMaestro.TUI.Application` for reduced resource usage
2. **Process Isolation**: Each TUI session gets its own agent process
3. **Real-time Communication**: Uses Phoenix PubSub for streaming updates
4. **State Management**: Maintains conversation state across interactions
5. **Cross-Platform**: Pure Elixir implementation works on Mac, Linux, and Windows

## Next Steps

After exploring the TUI demo:

1. **Customize**: Modify `config/config.exs` to adjust settings
2. **Extend**: Add new tools using the `deftool` DSL
3. **Deploy**: Build production escripts for distribution
4. **Integrate**: Use the TUI in your development workflow

## File Structure

The TUI implementation consists of:

```
lib/the_maestro/tui/
├── application.ex     # Minimal OTP application for TUI
└── cli.ex            # Main TUI interface and logic

demos/epic4/
└── README.md         # This demo guide

tutorials/epic4/story4.5/
└── README.md         # Implementation tutorial
```

## Related Resources

- [Epic 4 Tutorial Series](../../tutorials/epic4/) - Implementation details
- [Main Application](../../) - Web interface and core agent
- [API Documentation](../../docs/) - Developer references
- [Configuration Guide](../../config/) - Setup and customization

---

**Congratulations!** You've successfully demonstrated The Maestro's Terminal User Interface, showcasing the complete CLI experience and feature parity with the web interface.