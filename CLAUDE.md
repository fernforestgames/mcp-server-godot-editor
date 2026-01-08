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
- `click_node` - Finds a node by path/unique name/accessibility name and clicks it
- `hover_node` - Finds a node and moves the mouse to it (for hover states, tooltips)

## Development Notes

- This is a `@tool` script codebase; editor scripts run in the editor context
- The MCP server runs on a separate thread to avoid blocking the editor
- Screenshot data is transferred as WebP and base64-encoded for MCP response
- The server disables `Engine.print_to_stdout` to prevent Godot's print statements from corrupting the JSON-RPC stream
- Message prefix "mcp" is used for debugger message capture routing (see constants.gd)

**LSP Diagnostics:** After modifying GDScript files, the LSP may show false errors until restarted. If you see errors like "Cannot find member" for constants/methods that clearly exist, the LSP likely needs a restart.

## Testing Workflow

When testing MCP tools that require a running game:
1. Call `play_main_scene` or `play_scene` first
2. Immediately follow up with the tool you want to test (e.g., `take_screenshot`, `synthesize_input`)
3. Always call `stop_playing_scene` when done

**Important:** Never call `play_main_scene` without a follow-up action or stop command, as the game will run indefinitely and block further testing.

**MCP Server Restart:** You are already connected to this MCP server via the `mcp__godot-editor__*` tools. After modifying the plugin code, ask the user to restart the MCP server so changes take effect before testing.

## Test Scenes

The project includes test scenes for verifying MCP tool functionality:

### test_2d.tscn
A 2D UI test scene with interactive Control nodes:
- **TestButton** (unique name) - Click to increment a counter displayed in the status label
- **HoverButton** (unique name) - Hover to see visual feedback (button text changes, status updates)
- **StatusLabel** (unique name) - Displays interaction feedback

Use this to test `click_node` and `hover_node` with Control nodes.

### test_3d.tscn
A 3D test scene with two cubes and a camera:
- **ClickableCube** (unique name) - Left cube; click to see counter increment and brief color flash
- **HoverableCube** (unique name) - Right cube; hover to turn it green
- **ClickStatus** / **HoverStatus** (unique names) - UI labels showing interaction state

Use this to test `click_node` and `hover_node` with Node3D nodes. Verifies that 3D-to-screen projection via `camera.unproject_position()` works correctly.
