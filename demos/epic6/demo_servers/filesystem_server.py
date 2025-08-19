#!/usr/bin/env python3
"""
Simple MCP Filesystem Server Demo

This is a demonstration MCP server that provides basic filesystem operations.
It shows how to implement security features like path validation and user confirmation.
"""

import json
import sys
import os
from pathlib import Path
from typing import Dict, List, Any

class MCPFilesystemServer:
    """Demo MCP server for filesystem operations"""
    
    def __init__(self):
        self.tools = [
            {
                "name": "read_file",
                "description": "Read contents of a file with path validation",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path to the file to read"
                        }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "list_directory", 
                "description": "List contents of a directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path to the directory to list"
                        }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "write_file",
                "description": "Write content to a file (requires confirmation)",
                "inputSchema": {
                    "type": "object", 
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path where to write the file"
                        },
                        "content": {
                            "type": "string",
                            "description": "Content to write to the file"
                        }
                    },
                    "required": ["path", "content"]
                }
            }
        ]
        
        # Demo safe paths - restrict access to safe directories
        self.safe_paths = [
            "demos/",
            "test/",
            "docs/",
            "/tmp/",
            os.path.expanduser("~/Downloads/"),
            os.path.expanduser("~/Documents/")
        ]
    
    def handle_request(self, request: Dict) -> Dict:
        """Handle incoming MCP request"""
        method = request.get("method")
        params = request.get("params", {})
        
        if method == "tools/list":
            return {
                "tools": self.tools
            }
        elif method == "tools/call":
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            return self.call_tool(tool_name, arguments)
        else:
            return {
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }
    
    def call_tool(self, tool_name: str, arguments: Dict) -> Dict:
        """Execute a tool with the given arguments"""
        try:
            if tool_name == "read_file":
                return self.read_file(arguments.get("path"))
            elif tool_name == "list_directory":
                return self.list_directory(arguments.get("path"))
            elif tool_name == "write_file":
                return self.write_file(arguments.get("path"), arguments.get("content"))
            else:
                return {
                    "error": {
                        "code": -32602,
                        "message": f"Unknown tool: {tool_name}"
                    }
                }
        except Exception as e:
            return {
                "error": {
                    "code": -32603,
                    "message": f"Tool execution failed: {str(e)}"
                }
            }
    
    def is_safe_path(self, path: str) -> bool:
        """Check if the path is safe to access"""
        try:
            # Resolve the path to prevent directory traversal
            resolved_path = os.path.abspath(path)
            
            # Check against safe paths
            for safe_path in self.safe_paths:
                safe_resolved = os.path.abspath(safe_path)
                if resolved_path.startswith(safe_resolved):
                    return True
            
            return False
        except:
            return False
    
    def read_file(self, path: str) -> Dict:
        """Read file contents with safety checks"""
        if not path:
            return {"error": {"code": -32602, "message": "Path is required"}}
        
        if not self.is_safe_path(path):
            return {
                "error": {
                    "code": -32603,
                    "message": f"Access denied: Path '{path}' is outside safe directories"
                }
            }
        
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            return {
                "content": [
                    {
                        "type": "text",
                        "text": f"Contents of {path}:\n\n{content}"
                    }
                ]
            }
        except FileNotFoundError:
            return {"error": {"code": -32603, "message": f"File not found: {path}"}}
        except PermissionError:
            return {"error": {"code": -32603, "message": f"Permission denied: {path}"}}
    
    def list_directory(self, path: str) -> Dict:
        """List directory contents with safety checks"""
        if not path:
            return {"error": {"code": -32602, "message": "Path is required"}}
        
        if not self.is_safe_path(path):
            return {
                "error": {
                    "code": -32603,
                    "message": f"Access denied: Path '{path}' is outside safe directories"
                }
            }
        
        try:
            entries = []
            for entry in os.listdir(path):
                entry_path = os.path.join(path, entry)
                is_dir = os.path.isdir(entry_path)
                size = os.path.getsize(entry_path) if not is_dir else 0
                
                entries.append({
                    "name": entry,
                    "type": "directory" if is_dir else "file",
                    "size": size
                })
            
            entries.sort(key=lambda x: (x["type"] == "file", x["name"]))
            
            result_text = f"Contents of directory {path}:\n\n"
            for entry in entries:
                icon = "📁" if entry["type"] == "directory" else "📄"
                size_str = f" ({entry['size']} bytes)" if entry["type"] == "file" else ""
                result_text += f"{icon} {entry['name']}{size_str}\n"
            
            return {
                "content": [
                    {
                        "type": "text",
                        "text": result_text
                    }
                ]
            }
        except FileNotFoundError:
            return {"error": {"code": -32603, "message": f"Directory not found: {path}"}}
        except PermissionError:
            return {"error": {"code": -32603, "message": f"Permission denied: {path}"}}
    
    def write_file(self, path: str, content: str) -> Dict:
        """Write file with safety checks and confirmation requirement"""
        if not path or content is None:
            return {"error": {"code": -32602, "message": "Path and content are required"}}
        
        if not self.is_safe_path(path):
            return {
                "error": {
                    "code": -32603,
                    "message": f"Access denied: Path '{path}' is outside safe directories"
                }
            }
        
        # In a real implementation, this would trigger user confirmation
        # For this demo, we simulate the confirmation
        confirmation_required = True
        
        if confirmation_required:
            return {
                "content": [
                    {
                        "type": "text",
                        "text": f"⚠️ File write operation requires confirmation:\n"
                               f"Path: {path}\n"
                               f"Content length: {len(content)} characters\n"
                               f"This operation would create/overwrite a file.\n"
                               f"Please confirm this action through the UI."
                    }
                ],
                "metadata": {
                    "requires_confirmation": True,
                    "operation": "file_write",
                    "risk_level": "medium"
                }
            }
        
        # If confirmed (not implemented in this demo)
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            return {
                "content": [
                    {
                        "type": "text", 
                        "text": f"✅ Successfully wrote {len(content)} characters to {path}"
                    }
                ]
            }
        except PermissionError:
            return {"error": {"code": -32603, "message": f"Permission denied: {path}"}}

def main():
    """Main server loop"""
    server = MCPFilesystemServer()
    
    # Simple stdio-based MCP protocol implementation
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            
            request = json.loads(line.strip())
            response = server.handle_request(request)
            
            # Send response
            print(json.dumps(response))
            sys.stdout.flush()
            
        except json.JSONDecodeError:
            error_response = {
                "error": {
                    "code": -32700,
                    "message": "Parse error: Invalid JSON"
                }
            }
            print(json.dumps(error_response))
            sys.stdout.flush()
        except KeyboardInterrupt:
            break
        except Exception as e:
            error_response = {
                "error": {
                    "code": -32603,
                    "message": f"Internal error: {str(e)}"
                }
            }
            print(json.dumps(error_response))
            sys.stdout.flush()

if __name__ == "__main__":
    main()