@tool
extends EditorPlugin

const EDITOR_SERVER_SCRIPT: GDScript = preload("res://addons/mcp-server-godot-editor/editor_server.gd")

var _editor_server: Node

func _enable_plugin() -> void:
	# Add autoloads here.
	pass

func _disable_plugin() -> void:
	# Remove autoloads here.
	pass

func _enter_tree() -> void:
	_editor_server = EDITOR_SERVER_SCRIPT.new()
	add_child(_editor_server)

func _exit_tree() -> void:
	_editor_server.queue_free()
	_editor_server = null
