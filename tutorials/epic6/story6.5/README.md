# Tutorial: MCP Configuration Management & CLI Tools

**Epic 6 Story 6.5** - Comprehensive guide to MCP server configuration and management using TheMaestro's CLI tools.

## Prerequisites

- TheMaestro installed and running
- Basic understanding of MCP (Model Context Protocol) servers
- Command line familiarity

## Overview

This tutorial covers the complete MCP Configuration Management & CLI Tools system, providing hands-on examples for:

1. **Configuration File Management** - Creating and managing `mcp_settings.json` files
2. **CLI Server Management** - Adding, configuring, and managing MCP servers
3. **Authentication & Trust** - Managing server authentication and trust levels
4. **Monitoring & Diagnostics** - Server health monitoring and troubleshooting
5. **Template System** - Using configuration templates for quick setup

## Table of Contents

1. [Quick Start](#quick-start)
2. [Configuration File Setup](#configuration-file-setup)
3. [Server Management](#server-management)
4. [Authentication & Security](#authentication--security)
5. [Monitoring & Diagnostics](#monitoring--diagnostics)
6. [Advanced Features](#advanced-features)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

### 1. Initial Setup

Start by initializing your MCP configuration:

```bash
# Run interactive setup wizard
maestro mcp setup

# Or create a basic configuration manually
maestro mcp config init
```

This creates the basic directory structure:
- `~/.maestro/mcp_settings.json` - Global configuration
- `./.maestro/mcp_settings.json` - Project-specific configuration

### 2. Add Your First Server

Add a simple Python-based MCP server:

```bash
# Add a filesystem server
maestro mcp add fileSystem \
  --command python \
  --args "-m" "filesystem_mcp_server" \
  --trust false \
  --description "Local filesystem access tools"

# Verify it was added
maestro mcp list
```

### 3. Test the Connection

```bash
# Test connection to your server
maestro mcp test fileSystem

# Check detailed status
maestro mcp status fileSystem
```

---

## Configuration File Setup

### Basic Configuration Structure

The `mcp_settings.json` file follows this structure:

```json
{
  "mcpServers": {
    "serverName": {
      "command": "python",
      "args": ["-m", "server_module"],
      "env": {
        "API_KEY": "$MY_API_KEY"
      },
      "trust": false,
      "timeout": 30000
    }
  },
  "globalSettings": {
    "defaultTimeout": 30000,
    "confirmationLevel": "medium",
    "auditLogging": true
  }
}
```

### Environment Variables

TheMaestro supports flexible environment variable resolution:

```json
{
  "env": {
    "API_KEY": "$MY_API_TOKEN",           // Simple substitution
    "DATABASE_URL": "${DB_URL}",          // Alternative syntax  
    "DEBUG": "${DEBUG:-false}",           // Default values
    "PATH": "${PATH}:/custom/bin"         // Path expansion
  }
}
```

### Configuration Inheritance

Configurations are layered with this precedence:
1. Project-specific: `./.maestro/mcp_settings.json`
2. Global: `~/.maestro/mcp_settings.json`
3. Environment overrides

```bash
# Load and merge configurations
maestro mcp config load

# Show effective configuration
maestro mcp config show

# Validate configuration
maestro mcp config validate
```

---

## Server Management

### Adding Servers

#### Command-Line Servers
```bash
# Python STDIO server
maestro mcp add myPythonServer \
  --command python \
  --args "-m" "my_mcp_server" \
  --cwd "./mcp-servers" \
  --timeout 30000 \
  --trust false

# Node.js server
maestro mcp add myNodeServer \
  --command node \
  --args "server.js" \
  --env "NODE_ENV=production" \
  --trust true
```

#### HTTP API Servers
```bash
# HTTP API server
maestro mcp add apiServer \
  --http-url "http://localhost:3000/mcp" \
  --headers "Content-Type=application/json" \
  --timeout 15000
```

#### Server-Sent Events (SSE) Servers
```bash
# SSE server
maestro mcp add weatherServer \
  --url "https://weather-api.example.com/sse" \
  --headers "Authorization=Bearer $WEATHER_TOKEN" \
  --trust true
```

### Managing Servers

```bash
# List all servers
maestro mcp list

# List with connection status
maestro mcp list --status

# List with available tools
maestro mcp list --tools

# Update server configuration
maestro mcp update myServer --timeout 60000
maestro mcp update myServer --trust true
maestro mcp update myServer --add-tool read_file
maestro mcp update myServer --remove-tool delete_file

# Remove server
maestro mcp remove myServer

# Force removal even if connected
maestro mcp remove myServer --force
```

### Server Templates

Use templates for quick server setup:

```bash
# List available templates
maestro mcp template list

# Apply a template
maestro mcp template apply python-stdio myNewServer \
  --set module_name=my_server_module

# Create custom template from existing server
maestro mcp template create my-template --from existingServer
```

---

## Authentication & Security

### Authentication Management

#### API Key Authentication
```bash
# Set API key for a server
maestro mcp auth login myServer

# Or set directly via CLI
maestro mcp apikey set myServer "sk-1234567890abcdef"

# Test API key
maestro mcp apikey test myServer

# List all configured API keys (masked)
maestro mcp apikey list

# Remove API key
maestro mcp apikey remove myServer
```

#### OAuth Authentication
```bash
# Login with OAuth (opens browser)
maestro mcp auth login oauthServer

# Check authentication status
maestro mcp auth status
```

#### Bearer Token Authentication
```bash
# Set bearer token
maestro mcp auth login bearerServer --token "eyJhbGciOiJIUzI1NiIs..."
```

### Trust Management

```bash
# Set server as trusted
maestro mcp trust allow myServer

# Set server as untrusted
maestro mcp trust block dangerousServer

# Set specific trust level
maestro mcp trust allow myServer --level high

# List trust levels for all servers
maestro mcp trust list

# Reset trust to default (medium)
maestro mcp trust reset myServer
```

Trust levels:
- **None**: Server blocked, no operations allowed
- **Low**: Basic operations only, confirmation required
- **Medium**: Standard operations (default)
- **High**: All operations allowed without confirmation

---

## Monitoring & Diagnostics

### Server Status & Health

```bash
# Overall system status
maestro mcp status

# Specific server status
maestro mcp status myServer

# Test all server connections
maestro mcp test --all

# Health monitoring
maestro mcp health

# Continuous health monitoring
maestro mcp health --watch
```

### Tool Management

```bash
# List all available tools
maestro mcp tools

# List tools from specific server
maestro mcp tools --server myServer

# Get tool description
maestro mcp tools --describe read_file

# Execute a tool
maestro mcp run read_file --path "/tmp/test.txt"

# Execute with specific server
maestro mcp run --server myServer read_file --path "/tmp/test.txt"

# Debug tool execution
maestro mcp debug read_file --path "/tmp/test.txt"

# Full execution trace
maestro mcp trace read_file --path "/tmp/test.txt"
```

### Performance Monitoring

```bash
# View performance metrics
maestro mcp metrics

# Server-specific metrics
maestro mcp metrics myServer

# Export metrics to JSON
maestro mcp metrics --export json

# Performance analysis
maestro mcp analyze

# Identify slow tools
maestro mcp analyze --slow-tools

# Analyze error rates
maestro mcp analyze --error-rates
```

### Diagnostic Tools

```bash
# Full system diagnosis
maestro mcp diagnose

# Server-specific diagnosis
maestro mcp diagnose myServer

# View server logs
maestro mcp logs myServer

# Follow logs in real-time
maestro mcp logs --follow

# Test network connectivity
maestro mcp ping myServer

# Full connection trace
maestro mcp trace myServer
```

---

## Advanced Features

### Configuration Import/Export

```bash
# Export all configurations
maestro mcp export > my_config_backup.json

# Export specific server
maestro mcp export myServer > server_config.json

# Export in YAML format
maestro mcp export --format yaml > config.yaml

# Import configuration
maestro mcp import backup_config.json

# Merge with existing configuration
maestro mcp import --merge additional_servers.json

# Validate configuration without importing
maestro mcp import --validate-only test_config.json
```

### Auto-Discovery

```bash
# Auto-discover servers in current directory
maestro mcp discover

# Discover in specific path
maestro mcp discover --path ./mcp-servers

# Network discovery
maestro mcp discover --network

# Apply discovered configuration
maestro mcp discover --apply
```

### Audit & Reporting

```bash
# View audit trail
maestro mcp audit

# Tool usage report
maestro mcp audit --tool-usage

# Security events
maestro mcp audit --security-events

# Export audit data
maestro mcp audit --export csv > audit_report.csv

# Generate daily report
maestro mcp report daily

# Server-specific report
maestro mcp report --server myServer
```

---

## Troubleshooting

### Common Issues

#### 1. Server Won't Connect
```bash
# Check server configuration
maestro mcp config show myServer

# Test connection
maestro mcp test myServer

# Check logs
maestro mcp logs myServer

# Diagnose connection
maestro mcp diagnose myServer
```

#### 2. Authentication Problems
```bash
# Check auth status
maestro mcp auth status

# Reset authentication
maestro mcp auth logout myServer
maestro mcp auth login myServer

# Verify API key
maestro mcp apikey test myServer
```

#### 3. Configuration Errors
```bash
# Validate configuration
maestro mcp config validate

# Check configuration syntax
maestro mcp config lint

# Reload configuration
maestro mcp config reload
```

#### 4. Tool Execution Failures
```bash
# Debug tool execution
maestro mcp debug problematic_tool --param value

# Check tool availability
maestro mcp tools --available

# Test with different server
maestro mcp run --server alternativeServer tool_name
```

### Environment Variable Issues

If environment variables aren't resolving:

```bash
# Check environment variable expansion
maestro mcp config show --expand-env

# Test specific variable
echo $MY_VARIABLE

# Update configuration with correct syntax
# Use ${VAR:-default} for variables with defaults
```

### Performance Issues

For slow server responses:

```bash
# Increase timeout
maestro mcp update myServer --timeout 60000

# Check server metrics
maestro mcp metrics myServer

# Analyze performance
maestro mcp analyze --slow-tools

# Enable connection pooling (if supported)
maestro mcp update myServer --pool-size 5
```

---

## Best Practices

### Configuration Management
- Use project-specific configurations for development
- Keep sensitive data in environment variables
- Regularly backup configurations with `maestro mcp export`
- Use templates for consistent server setups

### Security
- Start with `trust: false` for new servers
- Regularly rotate API keys
- Monitor authentication events with `maestro mcp audit --security-events`
- Use specific tool inclusion/exclusion lists

### Performance
- Set appropriate timeouts for different server types
- Monitor server metrics regularly
- Use connection pooling for high-traffic servers
- Implement proper error handling in server code

### Monitoring
- Set up regular health checks
- Monitor tool usage patterns
- Watch for error rate increases
- Keep audit logs for compliance

---

## Conclusion

The MCP Configuration Management & CLI Tools system provides comprehensive capabilities for managing MCP servers in TheMaestro. This tutorial covered:

✅ **Configuration Setup**: Creating and managing configuration files  
✅ **Server Management**: Adding, configuring, and managing servers  
✅ **Authentication**: Managing API keys, OAuth, and trust levels  
✅ **Monitoring**: Health checks, diagnostics, and performance monitoring  
✅ **Advanced Features**: Templates, discovery, import/export, and auditing  

For additional help:
- Run `maestro mcp --help` for command-specific help
- Check `maestro mcp diagnose` for system health
- View logs with `maestro mcp logs --follow`
- Consult the troubleshooting section for common issues

The system is designed to be both powerful and user-friendly, supporting everything from simple single-server setups to complex multi-server environments with advanced security and monitoring requirements.