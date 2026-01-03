@tool
extends EditorPlugin

const EditorMcpServer := preload("editor_mcp_server.gd")
const EngineClient := preload("engine_client.gd")

var _editor_mcp_server: EditorMcpServer
var _engine_client: EngineClient

func _enable_plugin() -> void:
	# Add autoloads here.
	pass

func _disable_plugin() -> void:
	# Remove autoloads here.
	pass

func _enter_tree() -> void:
	_engine_client = EngineClient.new()
	add_debugger_plugin(_engine_client)

	_editor_mcp_server = EditorMcpServer.new()
	_editor_mcp_server.engine_client = _engine_client
	add_child(_editor_mcp_server)

func _exit_tree() -> void:
	_editor_mcp_server.queue_free()
	_editor_mcp_server = null

	remove_debugger_plugin(_engine_client)
	_engine_client = null
