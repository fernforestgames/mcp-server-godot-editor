# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Godot 4.5 editor plugin that implements an MCP (Model Context Protocol) server, allowing AI agents to control the Godot editor. The server communicates via JSON-RPC over stdin/stdout.

## Architecture

The plugin consists of two communication layers:

### Editor Side (runs in the Godot editor process)
- **plugin.gd** - EditorPlugin entry point that initializes the MCP server and debugger plugin
- **editor_mcp_server.gd** - Main MCP server implementation; handles JSON-RPC protocol, reads from stdin, writes to stdout
- **engine_client.gd** - EditorDebuggerPlugin that communicates with running game instances via Godot's debugger messaging system

### Game Side (runs in the debugged game process)
- **engine_server.gd** - Autoload node injected into the running game; handles commands like taking screenshots and sends responses back to the editor

### Communication Flow
```
MCP Client <--stdin/stdout--> editor_mcp_server.gd <--EngineDebugger--> engine_server.gd (in game)
                                      |
                                engine_client.gd (debugger plugin)
```

## MCP Tools Exposed

- `take_screenshot` - Captures a screenshot from the running game (requires game to be running)
- `play_main_scene` - Starts the project's main scene
- `play_scene` - Starts a specific scene by path
- `stop_playing_scene` - Stops the currently running scene
- `synthesize_input` - Injects input events into the running game (key, mouse, action, joypad)

## Development Notes

- This is a `@tool` script codebase; editor scripts run in the editor context
- The MCP server runs on a separate thread to avoid blocking the editor
- Screenshot data is transferred as WebP and base64-encoded for MCP response
- The server disables `Engine.print_to_stdout` to prevent Godot's print statements from corrupting the JSON-RPC stream
- Message prefix "mcp" is used for debugger message capture routing (see constants.gd)

## Testing Workflow

When testing MCP tools that require a running game:
1. Call `play_main_scene` or `play_scene` first
2. Immediately follow up with the tool you want to test (e.g., `take_screenshot`, `synthesize_input`)
3. Always call `stop_playing_scene` when done

**Important:** Never call `play_main_scene` without a follow-up action or stop command, as the game will run indefinitely and block further testing.

**MCP Server Restart:** You are already connected to this MCP server via the `mcp__godot-editor__*` tools. After modifying the plugin code, ask the user to restart the MCP server so changes take effect before testing.
