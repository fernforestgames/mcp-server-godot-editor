@tool
extends Node

var _mutex := Mutex.new()
var _thread := Thread.new()
var _keep_running := false
var _was_printing_to_stdout := false

func _enter_tree() -> void:
	_was_printing_to_stdout = Engine.print_to_stdout
	if _was_printing_to_stdout:
		printerr("[MCP] Disabling stdout printing for MCP server compatibility.")
		Engine.print_to_stdout = false

	_mutex.lock()
	_keep_running = true
	_mutex.unlock()

	_thread.start(self._thread_main)

func _exit_tree() -> void:
	_shutdown()

func _shutdown() -> void:
	_mutex.lock()
	_keep_running = false
	_mutex.unlock()

	_thread.wait_to_finish()
	Engine.print_to_stdout = _was_printing_to_stdout

func _thread_main() -> void:
	OS.set_thread_name("MCPServer")

	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID:
		push_warning("[MCP] No stdin available. MCP server will not be active.")
		_shutdown.call_deferred()
		return
	
	printerr("[MCP] MCP server started, listening for messages on stdin.")
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
	var messages := input_buffer.get_string_from_utf8().split("\n")
	for message in messages:
		printerr("[MCP] Received message: ", message)

		var parsed_message: Variant = JSON.parse_string(message)
		if parsed_message == null:
			printerr("[MCP] Failed to parse message: ", message)
			continue
		
		# TODO: Unwrap JSON-RPC payload and handle methods.

func send_message(message: String) -> void:
	# TODO: This almost certainly has a race condition. To be more robust, we could use a C++ extension that has direct access to the stdout handle.
	Engine.print_to_stdout = true
	printraw(message, "\n")
	Engine.print_to_stdout = false
