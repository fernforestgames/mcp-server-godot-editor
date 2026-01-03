@tool
extends Node
## MCP server that runs in the Godot editor.

const PROTOCOL_VERSION := "2024-11-05"
const SERVER_NAME := "godot-editor"
const SERVER_VERSION := "0.1.0"

enum State {
	UNINITIALIZED,
	INITIALIZING,
	INITIALIZED,
}

# JSON-RPC error codes
enum {
	ERROR_PARSE_ERROR = -32700,
	ERROR_INVALID_REQUEST = -32600,
	ERROR_METHOD_NOT_FOUND = -32601,
	ERROR_INVALID_PARAMS = -32602,
	ERROR_INTERNAL_ERROR = -32603,
}

var _mutex := Mutex.new()
var _thread := Thread.new()
var _keep_running := false
var _was_printing_to_stdout := false
var _state := State.UNINITIALIZED
var _client_capabilities := {}
var _client_info := {}

func _ready() -> void:
	assert(Engine.is_editor_hint(), "editor_server.gd should only be run in the editor.")

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

	if _thread.is_started():
		_thread.wait_to_finish()

	if _was_printing_to_stdout:
		Engine.print_to_stdout = true
		printerr("[MCP] stdout printing re-enabled.")

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
			_thread_process_message(input_buffer)
			input_buffer.clear()
			continue
		
		input_buffer.append_array(byte)

func _thread_process_message(input_buffer: PackedByteArray) -> void:
	var message := input_buffer.get_string_from_utf8()
	if message.is_empty():
		return

	printerr("[MCP] Received message: ", message)

	var parsed: Variant = JSON.parse_string(message)
	if parsed == null:
		printerr("[MCP] Failed to parse JSON: ", message)
		_send_error(null, ERROR_PARSE_ERROR, "Parse error")
		return

	if not parsed is Dictionary:
		_send_error(null, ERROR_INVALID_REQUEST, "Invalid Request: expected object")
		return

	var msg: Dictionary = parsed

	# Validate JSON-RPC version
	if msg.get("jsonrpc") != "2.0":
		_send_error(msg.get("id"), ERROR_INVALID_REQUEST, "Invalid Request: missing or invalid jsonrpc version")
		return

	var method: Variant = msg.get("method")
	var id: Variant = msg.get("id")
	var params: Variant = msg.get("params", {})

	# Determine if this is a request (has id) or notification (no id)
	var is_request := msg.has("id")

	if method == null or not method is String:
		if is_request:
			_send_error(id, ERROR_INVALID_REQUEST, "Invalid Request: missing or invalid method")
		return

	# Handle the message based on current state
	_handle_message(method, params if params is Dictionary else {}, id if is_request else null)

func _handle_message(method: String, params: Dictionary, id: Variant) -> void:
	var is_request := id != null

	match _state:
		State.UNINITIALIZED:
			# Only accept initialize request before initialization
			if method == "initialize" and is_request:
				_handle_initialize(params, id)
			elif method == "ping" and is_request:
				# Ping is allowed before initialization per spec
				_send_result(id, {})
			else:
				if is_request:
					_send_error(id, ERROR_INVALID_REQUEST, "Server not initialized. Send 'initialize' request first.")
				else:
					printerr("[MCP] Ignoring notification before initialization: ", method)

		State.INITIALIZING:
			# Only accept initialized notification or ping
			if method == "notifications/initialized" and not is_request:
				_handle_initialized()
			elif method == "ping" and is_request:
				_send_result(id, {})
			else:
				if is_request:
					_send_error(id, ERROR_INVALID_REQUEST, "Server is initializing. Wait for 'initialized' notification.")
				else:
					printerr("[MCP] Ignoring notification during initialization: ", method)

		State.INITIALIZED:
			# Normal operation - dispatch to method handlers
			_dispatch_method(method, params, id)


func _handle_initialize(params: Dictionary, id: Variant) -> void:
	printerr("[MCP] Handling initialize request")
	_state = State.INITIALIZING

	# Store client info
	_client_info = params.get("clientInfo", {})
	_client_capabilities = params.get("capabilities", {})
	var client_protocol_version: String = params.get("protocolVersion", "")

	printerr("[MCP] Client: ", _client_info.get("name", "unknown"), " v", _client_info.get("version", "unknown"))
	printerr("[MCP] Client protocol version: ", client_protocol_version)

	# Version negotiation: respond with our supported version
	# If client doesn't support our version, they should disconnect
	var response := {
		"protocolVersion": PROTOCOL_VERSION,
		"capabilities": _get_server_capabilities(),
		"serverInfo": {
			"name": SERVER_NAME,
			"version": SERVER_VERSION,
		},
	}

	_send_result(id, response)


func _handle_initialized() -> void:
	printerr("[MCP] Client sent initialized notification - server is now fully initialized")
	_state = State.INITIALIZED


func _dispatch_method(method: String, params: Dictionary, id: Variant) -> void:
	var is_request := id != null

	# Handle standard MCP methods
	match method:
		"ping":
			if is_request:
				_send_result(id, {})

		# TODO: Add more method handlers here (tools/list, tools/call, etc.)

		_:
			if is_request:
				_send_error(id, ERROR_METHOD_NOT_FOUND, "Method not found: " + method)
			else:
				printerr("[MCP] Unknown notification: ", method)


func _get_server_capabilities() -> Dictionary:
	# For now, declare minimal capabilities
	# TODO: Add more capabilities as we implement features
	return {
		"logging": {},
		"tools": {},
	}


func _send_result(id: Variant, result: Dictionary) -> void:
	var response := {
		"jsonrpc": "2.0",
		"id": id,
		"result": result,
	}
	_send_json(response)


func _send_error(id: Variant, code: int, message: String, data: Variant = null) -> void:
	var error_obj := {
		"code": code,
		"message": message,
	}
	if data != null:
		error_obj["data"] = data

	var response := {
		"jsonrpc": "2.0",
		"id": id,
		"error": error_obj,
	}
	_send_json(response)


func _send_notification(method: String, params: Dictionary = {}) -> void:
	var notification := {
		"jsonrpc": "2.0",
		"method": method,
	}
	if not params.is_empty():
		notification["params"] = params
	_send_json(notification)


func _send_json(obj: Dictionary) -> void:
	var json_str := JSON.stringify(obj)
	printerr("[MCP] Sending: ", json_str)
	# TODO: This almost certainly has a race condition. To be more robust, we could use a C++ extension that has direct access to the stdout handle.
	Engine.print_to_stdout = true
	printraw(json_str, "\n")
	Engine.print_to_stdout = false
