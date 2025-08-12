# Epic 3 Demos: Advanced Agent Capabilities & Tooling

This directory contains demos showcasing the advanced capabilities implemented in Epic 3.

## Story 3.2: Full File System Tool (Write & List)

**Demo**: `story3.2_demo.exs`

Demonstrates the new file system tools that extend the agent's capabilities beyond just reading files:

### Features Demonstrated

- **write_file tool**: Securely write content to files with automatic directory creation
- **list_directory tool**: List directory contents with rich metadata and sorting
- **Multi-tool workflows**: Using multiple tools together to accomplish complex tasks
- **Security validation**: Path validation and sandboxing across all operations

### Running the Demo

```bash
# Basic demo (tests tools directly)
mix run demos/epic3/story3.2_demo.exs

# Full demo with AI agent (requires API key)
GEMINI_API_KEY=your_key mix run demos/epic3/story3.2_demo.exs
```

### What You'll See

1. **Tool Registration Verification**: Confirms all file system tools are available
2. **Direct Tool Testing**: Tests each tool through the tooling system
3. **Complex Workflows**: Demonstrates nested directory creation and file operations
4. **Agent Integration**: Shows how the AI agent can use the tools (if API key provided)

### Sample Output

```
🚀 Epic 3 Story 3.2 Demo: Full File System Tool (Write & List)
============================================================

📁 Setting up demo environment...
   ✅ Demo directory created: /tmp/epic3_story32_demo
   ✅ File system tool configured for demo directory

🔧 Verifying file system tools are available...
   ✅ read_file tool available
   ✅ write_file tool available
   ✅ list_directory tool available
   ✅ All file system tools are properly registered

🧪 Testing tools directly through the tooling system...
   ✅ All direct tool tests passed!

🤖 Testing tools with AI agent...
   ✅ Tools are properly configured and ready for LLM use

🎉 Demo completed successfully!
```

### Technical Verification

The demo verifies:
- ✅ Tool definitions are in correct JSON format for OpenAI Function Calling
- ✅ All tools execute successfully through the tooling system  
- ✅ Security sandboxing works correctly
- ✅ Agent processes have access to the tools
- ✅ Complex file operations work (nested directories, multiple operations)

This demonstrates that the new file system tools are ready for production use with Gemini and other LLM providers.