# Epic 2 Demo: Phoenix LiveView UI & User Authentication

This demo showcases the Phoenix LiveView web interface and configurable user authentication system implemented in Epic 2 of The Maestro project. It demonstrates both authenticated and anonymous modes, real-time streaming responses, and transparent tool usage feedback.

## What This Demo Demonstrates

### 🌐 **Phoenix LiveView Interface**
- **Real-Time Chat**: Live conversation interface with streaming text responses
- **Agent Integration**: Direct connection to Agent GenServer processes
- **Status Updates**: Live feedback when the agent is using tools
- **Session Management**: Process discovery and isolation per user/session

### 🔐 **Configurable Authentication**
- **Google OAuth Flow**: Secure web-based authentication with Ueberauth
- **Anonymous Mode**: Single-user mode without authentication requirement
- **Flexible Configuration**: Easy switching between authenticated and anonymous modes
- **Session Isolation**: Proper user/session-based agent process management

### 📱 **User Experience Features**
- **Responsive Design**: Clean, developer-focused interface with dark mode support
- **Streaming Responses**: Word-by-word streaming with visual loading indicators
- **Tool Transparency**: Clear display of tool usage and structured results
- **Error Handling**: Graceful error recovery and user feedback

### 🏗️ **Phoenix Architecture**
- **LiveView Patterns**: Stateful real-time interactions over WebSocket
- **Context Separation**: Clean separation between UI and core business logic
- **Authentication Plugs**: Reusable authentication middleware
- **Route Protection**: Conditional route protection based on configuration

## Prerequisites

Before running this demo, ensure you have:

### 1. **Elixir Environment**
```bash
# Elixir 1.14+ and Erlang/OTP 25+
elixir --version
```

### 2. **Dependencies Installed**
```bash
# From the project root
mix deps.get
```

### 3. **Database Setup**
```bash
# Set up the database (if using persistent sessions)
mix ecto.setup
```

### 4. **LLM Authentication** (Choose One)

#### Option A: Google Account OAuth (Web Login)
```bash
# No environment variables needed!
# Users simply click "Login" in the web interface
# OAuth credentials are built into the application (like gemini-cli)
```

#### Option B: API Key (Direct)
```bash
export GEMINI_API_KEY="your-gemini-api-key-here"
```
Get your API key from: https://makersuite.google.com/app/apikey

#### Option C: Service Account (Enterprise/Corporate)
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

## Running the Demo

### Mode 1: Authenticated Mode (Default)

This mode requires users to log in with Google OAuth before accessing the agent.

#### Configuration
```bash
# Ensure authentication is enabled (default)
# In config/config.exs:
# config :the_maestro, require_authentication: true
```

#### Required Environment Variables
```bash
# For LLM access, choose one:
export GEMINI_API_KEY="your-gemini-api-key"  # Option 1: API Key
# OR
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"  # Option 2: Service Account
# Option 3: Google Account OAuth requires no environment variables
```

#### Running the Server
```bash
# From the project root directory
mix phx.server
```

#### Step-by-Step Usage

1. **Start the Server**
   ```bash
   mix phx.server
   ```
   You should see:
   ```
   [info] Running TheMaestroWeb.Endpoint with Bandit 1.0.0 at 127.0.0.1:4000 (http)
   [info] Access TheMaestroWeb.Endpoint at http://localhost:4000
   [watch] build finished, watching for changes...
   ```

2. **Open Your Browser**
   ```
   http://localhost:4000
   ```

3. **Log In with Google**
   - Click the "Login" button on the home page
   - You'll be redirected to Google OAuth consent screen
   - Grant permissions to the application
   - You'll be redirected back to the application

4. **Access the Agent Interface**
   - After successful login, click "Chat with Agent" or navigate to `/agent`
   - You'll see the real-time chat interface

5. **Send a Message**
   ```
   Type: "Hello! Please introduce yourself and then read a file from the demos directory."
   ```

6. **Observe Streaming Response**
   - Watch the response stream in word-by-word
   - Notice the loading indicator when tools are being used
   - See structured tool output when file operations complete

7. **Expected Behavior**
   ```
   💬 You: Hello! Please introduce yourself and then read a file from the demos directory.
   
   🤖 Agent: Hello! I'm an AI assistant powered by The Maestro system...
   
   [🔧 Using tool: read_file...]
   ✅ read_file: Read 247 bytes from demos/epic1/test_file.txt
   
   I can see this is a test file for Epic 1 Demo! The file contains...
   ```

### Mode 2: Anonymous Mode (Single-User)

This mode allows direct access without authentication, suitable for single-user environments.

#### Configuration

Update your configuration to disable authentication:

```elixir
# config/dev.exs or config/config.exs
config :the_maestro,
  require_authentication: false
```

Or use environment variable:
```bash
export MAESTRO_REQUIRE_AUTH=false
```

#### Required Environment Variables
```bash
# For LLM access, choose one:
export GEMINI_API_KEY="your-gemini-api-key"  # Option 1: API Key
# OR
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"  # Option 2: Service Account
# Option 3: Google Account OAuth requires no environment variables (but needs authentication enabled)
```

#### Running the Server
```bash
# From the project root directory
mix phx.server
```

#### Step-by-Step Usage

1. **Start the Server**
   ```bash
   mix phx.server
   ```

2. **Open Your Browser**
   ```
   http://localhost:4000
   ```

3. **Access Agent Directly**
   - No login required - the home page will show "Chat with Agent" button
   - Click to go directly to `/agent`
   - Or navigate directly to `http://localhost:4000/agent`

4. **Send a Message and Observe**
   - Same interaction pattern as authenticated mode
   - Agent process is tied to browser session instead of user account

## Configuration Details

### Environment Variables

| Variable | Purpose | Required When |
|----------|---------|---------------|
| `GEMINI_API_KEY` | LLM API authentication | Using API Key option |
| `GOOGLE_APPLICATION_CREDENTIALS` | Service account credentials | Using Enterprise/Corporate option |
| `MAESTRO_REQUIRE_AUTH` | Override auth requirement | Want to force anonymous mode |

**Note**: Google Account OAuth (web login) requires no environment variables - OAuth credentials are built into the application like gemini-cli.

### Application Configuration

#### Authentication Configuration
```elixir
# config/config.exs
config :the_maestro,
  # Set to false to disable authentication requirement
  require_authentication: true  # or false for anonymous mode

# OAuth configuration (built into application, no environment variables needed)
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, []}
  ]

# OAuth credentials are hardcoded in the Gemini provider
# (like gemini-cli does) - no configuration needed
```

#### File System Tool Configuration
```elixir
# config/config.exs
config :the_maestro, :file_system_tool,
  allowed_directories: [
    "/tmp",
    Path.join([File.cwd!(), "demos"]),
    Path.join([File.cwd!(), "test", "fixtures"])
  ],
  max_file_size: 10 * 1024 * 1024  # 10MB
```

#### LLM Provider Configuration
```elixir
# config/config.exs
config :the_maestro, :llm_provider,
  default_provider: TheMaestro.Providers.Gemini,
  gemini: [
    model: "gemini-2.5-pro",
    temperature: 0.7,
    max_tokens: 8192
  ]
```

### Development vs Production Settings

#### Development (config/dev.exs)
```elixir
# More permissive file access for development
config :the_maestro, :file_system_tool,
  allowed_directories: [
    Path.join([File.cwd!(), "demos"]),
    Path.join([File.cwd!(), "test"]),
    "/tmp"
  ]

# Debug logging enabled
config :logger, level: :debug
```

#### Production (config/prod.exs)
```elixir
# Restrictive file access for production
config :the_maestro, :file_system_tool,
  allowed_directories: ["/app/safe_files"],
  max_file_size: 1 * 1024 * 1024  # 1MB

# Authentication required in production
config :the_maestro,
  require_authentication: true
```

## Testing the Demo

### Quick Verification Checklist

#### Authenticated Mode
- [ ] Server starts without errors
- [ ] Home page shows login button
- [ ] Google OAuth flow works correctly
- [ ] After login, agent interface is accessible
- [ ] Streaming responses work correctly
- [ ] Tool usage is displayed transparently
- [ ] Logout functionality works

#### Anonymous Mode
- [ ] Server starts without errors
- [ ] Home page shows direct agent access
- [ ] No login required to access `/agent`
- [ ] Streaming responses work correctly
- [ ] Tool usage is displayed transparently
- [ ] Session isolation works (try multiple browser tabs)

### Test Scenarios

#### Scenario 1: Basic Conversation
```
Message: "Hello! Please tell me what you can do."
Expected: Streaming response explaining agent capabilities
```

#### Scenario 2: File Tool Usage
```
Message: "Please read the test file in the demos/epic1 directory."
Expected: Tool usage indicator → file content display
```

#### Scenario 3: Error Handling
```
Message: "Please read a file that doesn't exist."
Expected: Error handling with clear explanation
```

## Troubleshooting

### Authentication Issues

#### Problem: OAuth redirect errors
```
Error: invalid_redirect_uri
```
**Solution**: OAuth configuration is built into the application
```bash
# OAuth credentials are hardcoded (like gemini-cli)
# Redirect URI is pre-configured: http://localhost:4000/auth/google/callback
# No user configuration needed
```

#### Problem: Authentication required but disabled
```
Error: Authentication required
```
**Solution**: Check configuration consistency
```elixir
# Ensure config matches your intended mode
config :the_maestro, require_authentication: false  # for anonymous
```

### LiveView Issues

#### Problem: WebSocket connection fails
```
Error: websocket connection failed
```
**Solution**: Check Phoenix endpoint configuration
```bash
# Ensure the server is accessible
curl -I http://localhost:4000
```

#### Problem: Agent not responding
```
Error: Agent process not found
```
**Solution**: Check agent supervision
```bash
# Look for agent process errors in logs
mix phx.server
# Check for supervision tree startup messages
```

### Streaming Issues

#### Problem: Responses not streaming
```
Symptom: Entire response appears at once
```
**Solution**: Check Phoenix LiveView version and streaming setup
```elixir
# Ensure proper LiveView streaming configuration
# Check agent message sending patterns
```

### Configuration Issues

#### Problem: Environment variables not loaded
```
Error: Authentication configuration missing
```
**Solution**: Check environment variable loading
```bash
# Check LLM authentication variables
echo $GEMINI_API_KEY  # If using API Key
echo $GOOGLE_APPLICATION_CREDENTIALS  # If using Service Account

# OAuth credentials are built-in, no need to check
```

## Understanding the Architecture

### Key Components

#### 1. **Phoenix LiveView Integration**
```elixir
# Real-time chat interface
defmodule TheMaestroWeb.AgentLive do
  use TheMaestroWeb, :live_view
  
  def mount(_params, session, socket) do
    # Session-based or user-based agent discovery
  end
  
  def handle_event("send_message", %{"message" => content}, socket) do
    # Send to agent GenServer and update UI
  end
end
```

#### 2. **Authentication System**
```elixir
# Configurable authentication plug
defmodule TheMaestroWeb.Plugs.RequireAuth do
  def init(opts), do: opts
  
  def call(conn, _opts) do
    if Application.get_env(:the_maestro, :require_authentication) do
      # Check authentication
    else
      # Allow anonymous access
    end
  end
end
```

#### 3. **Agent Session Management**
```elixir
# User/session-based agent processes
def get_or_start_agent(user_id_or_session) do
  case TheMaestro.Agents.find_agent(user_id_or_session) do
    {:ok, pid} -> {:ok, pid}
    :not_found -> TheMaestro.Agents.start_agent(user_id_or_session)
  end
end
```

### Security Considerations

- **Session Isolation**: Each user/session gets their own agent process
- **Authentication Bypass**: Only when explicitly configured for single-user environments
- **CSRF Protection**: Phoenix's built-in CSRF protection remains active
- **WebSocket Security**: LiveView handles secure WebSocket connections
- **Tool Sandboxing**: File system tools remain sandboxed regardless of auth mode

## Next Steps

After running this demo successfully:

1. **Explore the LiveView Code**: Review the implementation in `lib/the_maestro_web/live/`
2. **Try Different Configurations**: Switch between authenticated and anonymous modes
3. **Test Tool Integration**: Try different prompts that trigger various tools
4. **Review Authentication**: Understand the OAuth flow and session management
5. **Check Epic 3**: See advanced capabilities like session checkpointing

## Related Documentation

- [Story 2.6 Tutorial](../../tutorials/epic2/story2.6/README.md) - Detailed explanation of demo creation
- [Phoenix Integration](../../tutorials/epic2/story2.1/README.md) - Understanding Phoenix LiveView patterns
- [Authentication System](../../tutorials/epic2/story2.2/README.md) - OAuth and configurable auth patterns
- [Agent LiveView](../../tutorials/epic2/story2.3/README.md) - Real-time chat interface implementation
- [Streaming & Status](../../tutorials/epic2/story2.4/README.md) - Real-time updates and tool feedback

---

**Built with The Maestro** - Demonstrating Phoenix LiveView excellence in real-time AI agent interfaces.