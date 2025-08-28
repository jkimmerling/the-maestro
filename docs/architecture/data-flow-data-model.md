# 4. Data Flow & Data Model

The data model is centered around the `sessions` and `messages` tables.

- **Data Model:** The schemas are defined in the PRD. The key relationship is `sessions` -> `conversations` -> `messages`. This ensures a complete, auditable log of every interaction. The `saved_authentications` table stores all secrets encrypted at rest using `cloak_ecto`.
    
- **Data Flow (New Message):**
    
    1. A message is sent from a UI (LiveView or TUI) to a `Session.Server` process.
        
    2. The `Session.Server` fetches the full conversation history from the `messages` table in Postgres.
        
    3. It constructs the API request payload.
        
    4. The request is sent through the `Tesla/Finch` client, which adds the appropriate authentication headers.
        
    5. The streaming response is received.
        
    6. The full request and final response payloads are written to the `messages` table, along with the calculated token counts and cost.
        
    7. The response is broadcast via PubSub to the UI.
        
