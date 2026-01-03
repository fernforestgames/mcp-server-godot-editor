@tool
extends EditorDebuggerPlugin
## Runs in the editor process to communicate with the debug server in the game process.

const C := preload("constants.gd")

signal screenshot_received(webp_buffer: PackedByteArray)
signal session_ready(session_id: int)

var ready_sessions: Array[int]

func send_message(message: String, data: Array) -> void:
	for session_id in ready_sessions:
		var session := get_session(session_id)
		session.send_message("%s:%s" % [C.MESSAGE_PREFIX, message], data)

func _has_capture(capture: String) -> bool:
	return capture == C.MESSAGE_PREFIX

func _capture(message: String, data: Array, session_id: int) -> bool:
	match message:
		"%s:ready" % C.MESSAGE_PREFIX:
			ready_sessions.append(session_id)
			session_ready.emit(session_id)
			return true

		"%s:screenshot" % C.MESSAGE_PREFIX:
			var webp_buffer: PackedByteArray = data[0]
			screenshot_received.emit(webp_buffer)
			return true

		_:
			return false

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.stopped.connect(func() -> void: ready_sessions.erase(session_id))
