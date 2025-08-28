# 3. Process View & Concurrency

The system's concurrency model is built on OTP.

- **Application Supervision Tree:** The main application supervisor will manage several key children:
    
    - The Phoenix Endpoint (for web requests).
        
    - The Ecto Repo.
        
    - The Oban supervisor.
        
    - The `SessionManager` dynamic supervisor.
        
- **Request Lifecycle (LiveView):**
    
    1. User connects to a session's LiveView.
        
    2. The LiveView process starts a `Session.Server` GenServer process via the `SessionManager` if one isn't already running for that session ID.
        
    3. The LiveView process subscribes to the session's PubSub topic (e.g., `maestro:session_123`).
        
    4. When the user sends a message, the LiveView process sends a cast message to the `Session.Server`.
        
    5. The `Session.Server` constructs the API call, sends it to the Provider Integration Layer, and receives the streaming response.
        
    6. As chunks arrive, the `Session.Server` broadcasts them over the PubSub topic.
        
    7. The LiveView process receives the broadcasted chunks and updates the UI.
        
