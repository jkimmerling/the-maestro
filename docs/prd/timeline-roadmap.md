# 6. Timeline & Roadmap

**Goal:** Establish clear delivery milestones and dependencies for all epics.

## **High-Level Timeline**

- **Phase 1 (Weeks 1-4): Foundation** - Epic 1 & 2 (Authentication & Core System)
    
- **Phase 2 (Weeks 5-8): Agent Capabilities** - Epic 3 (Tooling & MCP Integration)
    
- **Phase 3 (Weeks 9-12): User Interfaces** - Epic 4 & 5 (Web UI & Token Management)
    
- **Phase 4 (Weeks 13-16): TUI & Polish** - Epic 6 (Terminal Interface)
    

## **Detailed Milestone Breakdown**

### **Phase 1: Foundation (Critical Path)**

**Week 1-2: Authentication Infrastructure**

- Epic 1.1-1.5: Anthropic API Key + OAuth implementation
    
- Epic 1.6-1.7: OpenAI API Key + OAuth implementation
    
- **Risk:** OAuth approval delays from providers
    

**Week 3-4: Core System Setup**

- Epic 2.1-2.4: Database schemas and migrations
    
- Epic 2.5-2.6: Oban and Redis integration
    
- Epic 1.8-1.10: Gemini OAuth + streaming foundation
    

### **Phase 2: Agent Capabilities**

**Week 5-6: Tool Framework**

- Epic 3.1-3.4: Agent templates and core file system tools
    
- Epic 3.8: Tool inventory and database seeding
    

**Week 7-8: Advanced Tooling**

- Epic 3.5-3.7: Code execution, MCP integration, sub-agent capabilities
    

### **Phase 3: User Interfaces**

**Week 9-10: Web UI Foundation**

- Epic 4.1-4.3: Authentication management and settings pages
    
- Epic 5.1-5.3: Token tracking implementation
    

**Week 11-12: Chat Interface**

- Epic 4.4-4.6: Dashboard and real-time chat interface
    
- Epic 5.4-5.5: Token aggregation and fallback counting
    

### **Phase 4: TUI & Finalization**

**Week 13-14: TUI Development**

- Epic 6.1-6.3: API endpoints and basic TUI application
    

**Week 15-16: TUI Polish & Packaging**

- Epic 6.4-6.5: Tabbed interface and standalone executable
    

## **Critical Path Dependencies**

- **Week 1-2:** OAuth approvals from providers (potential 1-2 week delay risk)
    
- **Week 3:** Database design must be finalized before UI development begins
    
- **Week 9:** Core tooling framework must be complete before web UI integration
    
- **Week 13:** Web API must be stable before TUI development

