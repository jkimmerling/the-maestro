# 5. Deployment & Infrastructure

- **Deployment Strategy:** The application will be deployed as a single monolith using Elixir releases. This creates a self-contained, portable artifact.
    
- **Infrastructure Requirements:**
    
    - A server (VM or container) capable of running the Elixir BEAM.
        
    - A managed PostgreSQL database.
        
    - A managed Redis instance.
        
- **Configuration:** All sensitive information (database URLs, API secrets, etc.) will be managed via environment variables and loaded at runtime, following 12-factor app principles.
    
