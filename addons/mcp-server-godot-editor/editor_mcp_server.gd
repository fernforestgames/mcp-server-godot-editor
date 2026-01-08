@tool
extends Node
## MCP server that runs in the Godot editor.

const PROTOCOL_VERSION := "2024-11-05"
const SERVER_NAME := "godot-editor"
const SERVER_VERSION := "0.1.0"
const DEFAULT_ENGINE_MESSAGE_TIMEOUT_SEC := 5.0

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

const C := preload("constants.gd")
const AwaitUtils := preload("await_utils.gd")
const EngineClient := preload("engine_client.gd")
const StdinReader := preload("stdin_reader.gd")

var engine_client: EngineClient

var _stdin_reader: Node
var _was_printing_to_stdout := false
var _state := State.UNINITIALIZED
var _client_capabilities := {}
var _client_info := {}

func _ready() -> void:
	assert(Engine.is_editor_hint(), "Editor MCP server should only be run in the editor.")

func _enter_tree() -> void:
	_was_printing_to_stdout = Engine.print_to_stdout
	if _was_printing_to_stdout:
		push_warning("[MCP] Disabling stdout printing for MCP server compatibility.")
		Engine.print_to_stdout = false
	
	_stdin_reader = StdinReader.new()
	_stdin_reader.stdin_started.connect(_on_stdin_started)
	_stdin_reader.stdin_line.connect(_on_stdin_line)
	_stdin_reader.stdin_closed.connect(_on_stdin_closed)
	_stdin_reader.stdin_error.connect(_on_stdin_error)
	add_child(_stdin_reader)

func _exit_tree() -> void:
	_stdin_reader.queue_free()
	_stdin_reader = null

	if _was_printing_to_stdout:
		Engine.print_to_stdout = true
		push_warning("[MCP] stdout printing re-enabled.")

func _on_stdin_started() -> void:
	push_warning("[MCP] MCP server started, listening for messages on stdin.")

func _on_stdin_error(error: String) -> void:
	push_error("[MCP] Stdin error: ", error, ". MCP server will not be active.")

func _on_stdin_closed() -> void:
	push_warning("[MCP] Stdin closed.")

func _on_stdin_line(line: String) -> void:
	if not line:
		return

	push_warning("[MCP] Received message: ", line)

	var parsed: Variant = JSON.parse_string(line)
	if parsed == null:
		push_error("[MCP] Failed to parse JSON: ", line)
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
					push_warning("[MCP] Ignoring notification before initialization: ", method)

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
					push_warning("[MCP] Ignoring notification during initialization: ", method)

		State.INITIALIZED:
			# Normal operation - dispatch to method handlers
			_dispatch_method(method, params, id)


func _handle_initialize(params: Dictionary, id: Variant) -> void:
	_state = State.INITIALIZING

	# Store client info
	_client_info = params.get("clientInfo", {})
	_client_capabilities = params.get("capabilities", {})
	var client_protocol_version: String = params.get("protocolVersion", "")

	push_warning("[MCP] Client: ", _client_info.get("name", "unknown"), " version ", _client_info.get("version", "unknown"))
	push_warning("[MCP] Client protocol version: ", client_protocol_version)

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
	push_warning("[MCP] Client sent initialized notification - server is now fully initialized")
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
				push_error("[MCP] Unknown notification: ", method)


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
		{
			"name": "synthesize_input",
			"description": "Synthesizes input events in the running game. Supports keyboard, mouse, and gamepad input.",
			"inputSchema": {
				"type": "object",
				"properties": {
					"type": {
						"type": "string",
						"enum": C.InputType.values(),
						"description": "The type of input event to synthesize.",
					},
					"pressed": {
						"type": "boolean",
						"description": "Whether the input is pressed (true) or released (false). Used for key, mouse_button, action, and joypad_button types.",
					},
					"keycode": {
						"type": "string",
						"description": "The key to press (e.g., 'A', 'Space', 'Enter', 'Escape', 'F1', 'Shift', 'Ctrl', 'Alt'). Used for key type.",
					},
					"button_index": {
						"type": "integer",
						"description": "Mouse button index (1=left, 2=right, 3=middle, 4=wheel_up, 5=wheel_down). Used for mouse_button type.",
					},
					"position": {
						"type": "object",
						"properties": {
							"x": {"type": "number"},
							"y": {"type": "number"},
						},
						"description": "Mouse position in viewport coordinates. Used for mouse_button and mouse_motion types.",
					},
					"relative": {
						"type": "object",
						"properties": {
							"x": {"type": "number"},
							"y": {"type": "number"},
						},
						"description": "Relative mouse movement. Used for mouse_motion type.",
					},
					"action": {
						"type": "string",
						"description": "The action name from the Input Map (e.g., 'ui_accept', 'jump', 'move_left'). Used for action type.",
					},
					"strength": {
						"type": "number",
						"description": "Action strength from 0.0 to 1.0. Used for action type. Defaults to 1.0.",
					},
					"joypad_button": {
						"type": "integer",
						"description": "Joypad button index (0=A/Cross, 1=B/Circle, 2=X/Square, 3=Y/Triangle, etc.). Used for joypad_button type.",
					},
					"axis": {
						"type": "integer",
						"description": "Joypad axis index (0=left_x, 1=left_y, 2=right_x, 3=right_y, 4=trigger_left, 5=trigger_right). Used for joypad_motion type.",
					},
					"axis_value": {
						"type": "number",
						"description": "Joypad axis value from -1.0 to 1.0. Used for joypad_motion type.",
					},
				},
				"required": ["type"],
			},
		},
	]
	_send_result(id, {"tools": tools})


func _handle_tools_call(params: Dictionary, id: Variant) -> void:
	var tool_name: String = params.get("name", "")
	var tool_args: Dictionary = params.get("arguments", {})

	match tool_name:
		"take_screenshot":
			_call_take_screenshot(id)

		"play_main_scene":
			_call_play_main_scene(id)

		"play_scene":
			var path: String = tool_args.get("path", "")
			if path.is_empty():
				_send_error(id, ERROR_INVALID_PARAMS, "Missing required parameter: path")
				return

			_call_play_scene(id, path)

		"stop_playing_scene":
			_call_stop_playing_scene(id)

		"synthesize_input":
			_call_synthesize_input(id, tool_args)

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


func _call_synthesize_input(id: Variant, args: Dictionary) -> void:
	if not engine_client:
		_send_error(id, ERROR_INTERNAL_ERROR, "Engine client not available")
		return

	if engine_client.ready_sessions.is_empty():
		_send_tool_error(id, "No game is currently running. Start the game from the editor first.")
		return

	var input_type: String = args.get("type", "")
	if input_type.is_empty():
		_send_error(id, ERROR_INVALID_PARAMS, "Missing required parameter: type")
		return

	# Build the input data to send to the game
	var input_data := {
		"type": input_type,
		"pressed": args.get("pressed", true),
	}

	match input_type:
		C.InputType.KEY:
			var keycode: String = args.get("keycode", "")
			if keycode.is_empty():
				_send_error(id, ERROR_INVALID_PARAMS, "Missing required parameter for key type: keycode")
				return
			input_data["keycode"] = keycode

		C.InputType.MOUSE_BUTTON:
			var button_index: int = args.get("button_index", 1)
			input_data["button_index"] = button_index
			var pos: Dictionary = args.get("position", {})
			input_data["position_x"] = pos.get("x", 0.0)
			input_data["position_y"] = pos.get("y", 0.0)

		C.InputType.MOUSE_MOTION:
			var pos: Dictionary = args.get("position", {})
			input_data["position_x"] = pos.get("x", 0.0)
			input_data["position_y"] = pos.get("y", 0.0)
			var rel: Dictionary = args.get("relative", {})
			input_data["relative_x"] = rel.get("x", 0.0)
			input_data["relative_y"] = rel.get("y", 0.0)

		C.InputType.ACTION:
			var action_name: String = args.get("action", "")
			if action_name.is_empty():
				_send_error(id, ERROR_INVALID_PARAMS, "Missing required parameter for action type: action")
				return
			input_data["action"] = action_name
			input_data["strength"] = args.get("strength", 1.0)

		C.InputType.JOYPAD_BUTTON:
			var joypad_btn: int = args.get("joypad_button", 0)
			input_data["joypad_button"] = joypad_btn

		C.InputType.JOYPAD_MOTION:
			var axis: int = args.get("axis", 0)
			var axis_value: float = args.get("axis_value", 0.0)
			input_data["axis"] = axis
			input_data["axis_value"] = axis_value

		_:
			_send_error(id, ERROR_INVALID_PARAMS, "Unknown input type: " + input_type)
			return

	# Send the input synthesis request to the running game
	engine_client.send_message("synthesize_input", [input_data])

	# Wait for acknowledgment
	var result: Variant = await _wait_on_signal(engine_client.input_synthesized)
	if result == null:
		_send_tool_error(id, "Timed out waiting for input synthesis acknowledgment.")
		return

	var success: bool = result.get("success", false)
	var message: String = result.get("message", "")

	if success:
		_send_tool_result(id, "Input synthesized: " + input_type + ". " + message)
	else:
		_send_tool_error(id, "Failed to synthesize input: " + message)


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

	# TODO: This almost certainly has a race condition. To be more robust, we could use a C++ extension that has direct access to the stdout handle.
	Engine.print_to_stdout = true
	printraw(json_str, "\n")
	Engine.print_to_stdout = false

func _wait_on_signal(sig: Signal, timeout_sec: float = DEFAULT_ENGINE_MESSAGE_TIMEOUT_SEC) -> Variant:
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
