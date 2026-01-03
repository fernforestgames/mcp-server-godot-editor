@tool
extends Node
## Reads stdin in a separate thread and emits a signal when a full line is read.

signal stdin_started
signal stdin_line(line: String)
signal stdin_closed
signal stdin_error(error: String)

var _mutex := Mutex.new()
var _thread := Thread.new()
var _shutdown := false

func _ready() -> void:
	assert(Engine.is_editor_hint(), "Stdin reader should only be run in the editor.")

func _enter_tree() -> void:
	_mutex.lock()
	_shutdown = false
	_mutex.unlock()

	_thread.start(self._thread_main)

func _exit_tree() -> void:
	_mutex.lock()
	_shutdown = true
	_mutex.unlock()

	if _thread.is_started():
		_thread.wait_to_finish()

func _thread_main() -> void:
	OS.set_thread_name("mcp_server_godot_editor.stdin_reader")

	if OS.get_stdin_type() == OS.STD_HANDLE_INVALID:
		stdin_error.emit.call_deferred("No stdin available.")
		return
	
	stdin_started.emit.call_deferred()

	var input_buffer := PackedByteArray()
	while true:
		_mutex.lock()
		var should_shutdown := _shutdown
		_mutex.unlock()

		if should_shutdown:
			break
		
		var byte := OS.read_buffer_from_stdin(1)
		if not byte:
			stdin_closed.emit.call_deferred()
			break
		
		if byte[0] == ord('\n'):
			var line := input_buffer.get_string_from_utf8()
			stdin_line.emit.call_deferred(line)
			input_buffer.clear()
			continue
		
		input_buffer.append_array(byte)
