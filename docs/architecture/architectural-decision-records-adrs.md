# 13. Architectural Decision Records (ADRs)

**Goal:** Document key architectural decisions with rationale to support future development and maintenance.

## ADR-001: Phoenix Monolith vs Microservices

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Single-user application with complex real-time requirements
- Solo developer maintenance constraints
- Need for rapid development and deployment

**Decision:** 
Implement as Phoenix monolith with separate TUI client

**Rationale:**
- **Simplicity**: Single deployment, single database, unified logging
- **Performance**: No network latency between components
- **Development Speed**: Shared code, single test suite, easier debugging
- **OTP Benefits**: Built-in supervision, actor model for sessions

**Consequences:**
- ✅ Faster development and maintenance
- ✅ Better performance for real-time features
- ✅ Simpler deployment and monitoring
- ❌ Less flexibility for independent scaling
- ❌ All components share failure domains

## ADR-002: Tesla + Finch for HTTP Client

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Need exact header fidelity with reference implementations
- Multiple provider APIs with different requirements
- High-performance concurrent connections required

**Decision:** 
Use Tesla middleware pattern with Finch connection pooling

**Rationale:**
- **Header Control**: Tesla middleware allows exact header ordering
- **Performance**: Finch provides efficient HTTP/2 connection pooling
- **Flexibility**: Easy to swap adapters or add provider-specific middleware
- **Testing**: Tesla makes mocking and testing straightforward

**Consequences:**
- ✅ Precise control over HTTP requests
- ✅ Excellent performance under load
- ✅ Easy to test and mock
- ❌ Additional dependency complexity

## ADR-003: GenServer Per Session Pattern

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Need to maintain session state and conversation context
- Real-time streaming requirements
- Multiple concurrent sessions per user

**Decision:** 
One GenServer process per active session under DynamicSupervisor

**Rationale:**
- **Isolation**: Session failures don't affect others
- **Performance**: In-memory state for fast access
- **Real-time**: Direct PubSub broadcasting from session processes
- **OTP Benefits**: Automatic restart and supervision

**Consequences:**
- ✅ Excellent fault tolerance
- ✅ High performance for concurrent sessions
- ✅ Natural fit for real-time features
- ❌ Memory usage scales with active sessions
- ❌ State management complexity

## ADR-004: Database-First Tool Configuration

**Status:** Accepted  
**Date:** 2024-01-01  

**Context:**
- Tools need to be dynamically enabled/disabled
- Different sessions may have different tool availability
- Need audit trail of tool usage

**Decision:** 
Store tool definitions and enablement in database with registry pattern

**Rationale:**
- **Flexibility**: Runtime tool configuration without code changes
- **Auditing**: Track tool usage and configuration changes
- **Security**: Granular control over tool availability
- **Extensibility**: Easy to add new tools and MCP servers

**Consequences:**
- ✅ Runtime configurability
- ✅ Complete audit trail
- ✅ Fine-grained security control
- ❌ Database dependency for tool registry
- ❌ Slightly more complex tool execution path