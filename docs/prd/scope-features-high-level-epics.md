# 3. Scope & Features (High-Level Epics)

1. **Epic 1: Foundational Authentication & API Fidelity:**
    
    - This is the highest priority epic. It involves creating a multi-provider HTTP client layer and authentication management system that **exactly mirrors** the implementation, headers, and authentication flows of the `llxprt` and `gemini-cli` applications for Anthropic, OpenAI, and Gemini. This includes API key and OAuth methods.
        
2. **Epic 2: Core System & Persistence:**
    
    - This epic covers the backend infrastructure, including setting up the PostgreSQL database schemas for conversations, sessions, and credentials. It also includes configuring Redis for real-time state management and Oban for background jobs like token refreshing.
        
3. **Epic 3: Agent Capabilities & Tooling:**
    
    - This epic focuses on empowering the agents. It includes implementing a comprehensive set of tools for file system access, code execution, and system commands. Crucially, this epic also covers the full implementation of the **Model Context Protocol (MCP)** to allow agents to discover and use MCP servers, as well as the functionality to use other configured agents as sub-agents.
        
4. **Epic 4: Web User Interface:**
    
    - This covers the creation of the Phoenix LiveView-based web application. It includes the authentication management pages, the card-based session dashboard with system monitoring, and the real-time chat interface with on-the-fly customization of personas, models, and tools.
        
5. **Epic 5: Token & Cost Management:**
    
    - This covers the implementation of token usage tracking. The system will monitor and attribute token consumption to specific activities (conversation, tool use, etc.) and store this data with the conversation history.
        
6. **Epic 6: Terminal User Interface (TUI):**
    
    - This epic involves building the standalone, multi-platform TUI client. It will connect to the main application via a dedicated API. Key features include tab-based management of multiple sessions and the **API capability to receive passthrough streams** of the agents' "thought" processes.
        
