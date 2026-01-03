@tool
extends Node

var _mutex := Mutex.new()
var _thread := Thread.new()
var _keep_running := false

func _enter_tree() -> void:
	_mutex.lock()
	_keep_running = true
	_mutex.unlock()

	_thread.start(self._thread_main)

func _exit_tree() -> void:
	_mutex.lock()
	_keep_running = false
	_mutex.unlock()

	_thread.wait_to_finish()

func _thread_main() -> void:
	OS.set_thread_name("MCPServer")

	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID:
		push_warning("[MCP] No stdin available. MCP server will not be active.")
		return
	
	print("[MCP] MCP server started, listening for messages on stdin.")
	var input_buffer := PackedByteArray()

	while true:
		_mutex.lock()
		var running := _keep_running
		_mutex.unlock()

		if not running:
			break
		
		var byte := OS.read_buffer_from_stdin(1)
		if not byte:
			print("[MCP] No data read from stdin.")
			break
		
		if byte[0] == ord('\n'):
			_thread_process_messages(input_buffer)
			input_buffer.clear()
			continue
		
		input_buffer.append_array(byte)

func _thread_process_messages(input_buffer: PackedByteArray) -> void:
	print("[MCP] Received message: ", input_buffer.get_string_from_utf8())
