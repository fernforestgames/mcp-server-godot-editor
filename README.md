# mcp-server-godot-editor

A Godot 4.5 editor plugin that implements a [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server, enabling AI agents to control the Godot editor.

## Features

The MCP server exposes the following tools:

| Tool | Description |
|------|-------------|
| `take_screenshot` | Captures a screenshot from the running game (returns WebP image) |
| `play_main_scene` | Starts the project's main scene |
| `play_scene` | Starts a specific scene by resource path |
| `stop_playing_scene` | Stops the currently running scene |
| `synthesize_input` | Injects input events into the running game (key, mouse, action, joypad) |
| `click_node` | Simulates a mouse click on a specific node in the running game |
| `hover_node` | Simulates a mouse hover over a specific node in the running game |

## Installation

1. Copy the `addons/mcp-server-godot-editor` folder into your Godot project's `addons` directory
2. Enable the plugin in **Project > Project Settings > Plugins**
3. Configure your MCP client to connect to the Godot editor (see below)

## MCP client configuration

The server communicates with MCP clients over Godot's own stdin/stdout. You'll need to launch Godot from the CLI in editor mode, and with the `--no-header` option to disable the initial stdout messages (which would otherwise conflict with MCP messages).

Here's an example `.mcp.json` configuration:

```json
{
  "servers": {
    "godot-editor": {
      "type": "stdio",
      "command": "path/to/godot",
      "args": ["--editor", "--no-header"]
    }
  }
}
```

## Architecture

The plugin uses a two-layer communication system:

```
MCP Client <--stdin/stdout--> Editor MCP Server <--EngineDebugger--> Game Process
```

- **Editor MCP Server**: runs inside the Godot editor, handles JSON-RPC protocol and editor commands
- **Game Process**: the running game instance; receives commands (like screenshot capture) from the editor via Godot's debugger messaging system

## License

Released under the [MIT license](LICENSE).
