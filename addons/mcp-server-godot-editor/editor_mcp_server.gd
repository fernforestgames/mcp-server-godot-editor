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

const AwaitUtils := preload("await_utils.gd")
const EngineClient := preload("engine_client.gd")

var engine_client: EngineClient

var _mutex := Mutex.new()
var _thread := Thread.new()
var _keep_running := false
var _was_printing_to_stdout := false
var _state := State.UNINITIALIZED
var _client_capabilities := {}
var _client_info := {}

func _ready() -> void:
	assert(Engine.is_editor_hint(), "Editor MCP server should only be run in the editor.")

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

	printerr("[MCP] Client: ", _client_info.get("name", "unknown"), " version ", _client_info.get("version", "unknown"))
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

		"tools/list":
			if is_request:
				_handle_tools_list(id)

		"tools/call":
			if is_request:
				_handle_tools_call(params, id)
		
		"notifications/cancelled":
			if not is_request:
				# Currently no-op
				pass

		_:
			if is_request:
				_send_error(id, ERROR_METHOD_NOT_FOUND, "Method not found: " + method)
			else:
				printerr("[MCP] Unknown notification: ", method)


func _handle_tools_list(id: Variant) -> void:
	var tools := [
		{
			"name": "take_screenshot",
			"description": "Takes a screenshot of the currently running game. The game must be running in debug mode from the editor.",
			"inputSchema": {
				"type": "object",
				"properties": {},
				"required": [],
			},
		},
		{
			"name": "play_main_scene",
			"description": "Plays the project's main scene in the Godot editor.",
			"inputSchema": {
				"type": "object",
				"properties": {},
				"required": [],
			},
		},
		{
			"name": "play_scene",
			"description": "Plays a specific scene in the Godot editor.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "The resource path to the scene file (e.g., 'res://scenes/level.tscn').",
					},
				},
				"required": ["path"],
			},
		},
		{
			"name": "stop_playing_scene",
			"description": "Stops the currently running scene in the Godot editor.",
			"inputSchema": {
				"type": "object",
				"properties": {},
				"required": [],
			},
		},
	]
	_send_result(id, {"tools": tools})


func _handle_tools_call(params: Dictionary, id: Variant) -> void:
	var tool_name: String = params.get("name", "")
	var tool_args: Dictionary = params.get("arguments", {})

	match tool_name:
		"take_screenshot":
			_call_take_screenshot.call_deferred(id)

		"play_main_scene":
			_call_play_main_scene.call_deferred(id)

		"play_scene":
			var path: String = tool_args.get("path", "")
			if path.is_empty():
				_send_error(id, ERROR_INVALID_PARAMS, "Missing required parameter: path")
				return
			_call_play_scene.call_deferred(id, path)

		"stop_playing_scene":
			_call_stop_playing_scene.call_deferred(id)

		_:
			_send_error(id, ERROR_INVALID_PARAMS, "Unknown tool: " + tool_name)


func _call_take_screenshot(id: Variant) -> void:
	if not engine_client:
		_send_error(id, ERROR_INTERNAL_ERROR, "Engine client not available")
		return

	if engine_client.ready_sessions.is_empty():
		_send_tool_error(id, "No game is currently running. Start the game from the editor first.")
		return

	# Send the screenshot request to the running game
	engine_client.send_message("take_screenshot", [])

	# Wait for the screenshot response
	var webp_buffer: PackedByteArray = await _wait_on_signal(engine_client.screenshot_received)

	# Convert to base64
	var base64_data := Marshalls.raw_to_base64(webp_buffer)

	_send_result(id, {
		"content": [
			{
				"type": "image",
				"data": base64_data,
				"mimeType": "image/webp",
			}
		],
	})


func _call_play_main_scene(id: Variant) -> void:
	if not engine_client:
		_send_error(id, ERROR_INTERNAL_ERROR, "Engine client not available")
		return

	EditorInterface.play_main_scene()

	# Wait for the game to signal it's ready
	var session_id: Variant = await _wait_on_signal(engine_client.session_ready)
	if session_id == null:
		_send_tool_error(id, "Timed out waiting for game to start.")
		return

	_send_tool_result(id, "Started playing main scene.")


func _call_play_scene(id: Variant, path: String) -> void:
	if not engine_client:
		_send_error(id, ERROR_INTERNAL_ERROR, "Engine client not available")
		return

	if not FileAccess.file_exists(path):
		_send_tool_error(id, "Scene file not found: " + path)
		return

	EditorInterface.play_custom_scene(path)

	# Wait for the game to signal it's ready
	var session_id: Variant = await _wait_on_signal(engine_client.session_ready)
	if session_id == null:
		_send_tool_error(id, "Timed out waiting for game to start.")
		return

	_send_tool_result(id, "Started playing scene: " + path)


func _call_stop_playing_scene(id: Variant) -> void:
	EditorInterface.stop_playing_scene()
	_send_tool_result(id, "Stopped playing scene.")


func _send_tool_result(id: Variant, message: String) -> void:
	_send_result(id, {
		"content": [
			{
				"type": "text",
				"text": message,
			}
		],
	})


func _send_tool_error(id: Variant, message: String) -> void:
	_send_result(id, {
		"content": [
			{
				"type": "text",
				"text": message,
			}
		],
		"isError": true,
	})


func _get_server_capabilities() -> Dictionary:
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

func _wait_on_signal(sig: Signal, timeout_sec: float = 1.0) -> Variant:
	var result: Array[Variant]
	await AwaitUtils.await_any([
		func() -> void:
			var value: Variant = await sig
			result.append(value),

		func() -> void:
			var timer := get_tree().create_timer(timeout_sec, true, false, true)
			await timer.timeout,
	])

	if result:
		return result[0]
	else:
		return null
