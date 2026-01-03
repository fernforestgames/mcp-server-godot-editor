extends Node
## Runs in the game process (the engine) to communicate with the MCP server in the editor.

const C := preload("constants.gd")

func _enter_tree() -> void:
	EngineDebugger.register_message_capture(C.MESSAGE_PREFIX, self._on_message_captured)
	EngineDebugger.send_message("%s:ready" % C.MESSAGE_PREFIX, [])

func _exit_tree() -> void:
	EngineDebugger.unregister_message_capture(C.MESSAGE_PREFIX)

func _on_message_captured(message: String, data: Array) -> bool:
	match message:
		"take_screenshot":
			var image := get_viewport().get_texture().get_image()
			EngineDebugger.send_message("%s:screenshot" % C.MESSAGE_PREFIX, [image])
			return true

		_:
			return false
