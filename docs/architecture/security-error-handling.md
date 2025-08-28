# 6. Security & Error Handling

- **Security:**
    
    - **Credential Storage:** All API keys and OAuth tokens in the `saved_authentications` table **must** be encrypted at rest using a library like `cloak_ecto`.
        
    - **API Access:** The TUI API will be protected by a static, long-lived API token that must be sent in a header.
        
    - **Web UI:** Standard Phoenix session management will be used for the web interface.
        
- **Fault Tolerance:** The use of OTP supervisors is central. If a `Session.Server` process crashes due to an unexpected error, the `SessionManager` supervisor will restart it, allowing the user to reconnect and resume their session without bringing down the entire application. Finch's connection pooling also provides resilience against transient network issues with the external APIs.
    
