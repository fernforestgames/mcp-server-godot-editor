extends Node
## Runs in the game process (the engine) to communicate with the MCP server in the editor.

const C := preload("constants.gd")

func _enter_tree() -> void:
	print("[MCP] Registering message capture for MCP engine server.")
	EngineDebugger.register_message_capture(C.MESSAGE_PREFIX, self._on_message_captured)
	EngineDebugger.send_message("%s:ready" % C.MESSAGE_PREFIX, [])

func _exit_tree() -> void:
	EngineDebugger.unregister_message_capture(C.MESSAGE_PREFIX)

func _on_message_captured(message: String, data: Array) -> bool:
	match message:
		"take_screenshot":
			print("[MCP] Taking screenshot")
			var image := get_viewport().get_texture().get_image()
			var buffer := image.save_webp_to_buffer()
			EngineDebugger.send_message("%s:screenshot" % C.MESSAGE_PREFIX, [buffer])
			return true

		"synthesize_input":
			var input_data: Dictionary = data[0] if data else {}
			_handle_synthesize_input(input_data)
			return true

		"node_interaction":
			var interaction_data: Dictionary = data[0] if data else {}
			_handle_node_interaction(interaction_data)
			return true

		"get_node_tree":
			var tree_request: Dictionary = data[0] if data else {}
			_handle_get_node_tree(tree_request)
			return true

		_:
			return false


func _handle_synthesize_input(input_data: Dictionary) -> void:
	var input_type: String = input_data.get("type", "")
	var pressed: bool = input_data.get("pressed", true)

	print("[MCP] Synthesizing input: ", input_type)

	var event: InputEvent = null
	var message := ""

	match input_type:
		C.InputType.KEY:
			event = _create_key_event(input_data, pressed)
			if event:
				message = "Key '%s' %s" % [input_data.get("keycode", ""), "pressed" if pressed else "released"]

		C.InputType.MOUSE_BUTTON:
			event = _create_mouse_button_event(input_data, pressed)
			if event:
				message = "Mouse button %d %s at (%d, %d)" % [
					input_data.get("button_index", 1),
					"pressed" if pressed else "released",
					int(input_data.get("position_x", 0)),
					int(input_data.get("position_y", 0))
				]

		C.InputType.MOUSE_MOTION:
			event = _create_mouse_motion_event(input_data)
			if event:
				message = "Mouse moved to (%d, %d)" % [
					int(input_data.get("position_x", 0)),
					int(input_data.get("position_y", 0))
				]

		C.InputType.ACTION:
			event = _create_action_event(input_data, pressed)
			if event:
				message = "Action '%s' %s" % [input_data.get("action", ""), "pressed" if pressed else "released"]

		C.InputType.JOYPAD_BUTTON:
			event = _create_joypad_button_event(input_data, pressed)
			if event:
				message = "Joypad button %d %s" % [
					input_data.get("joypad_button", 0),
					"pressed" if pressed else "released"
				]

		C.InputType.JOYPAD_MOTION:
			event = _create_joypad_motion_event(input_data)
			if event:
				message = "Joypad axis %d set to %.2f" % [
					input_data.get("axis", 0),
					input_data.get("axis_value", 0.0)
				]

		_:
			_send_input_result(false, "Unknown input type: " + input_type)
			return

	if event:
		Input.parse_input_event(event)
		_send_input_result(true, message)
	else:
		_send_input_result(false, "Failed to create input event for type: " + input_type)


func _create_key_event(input_data: Dictionary, pressed: bool) -> InputEventKey:
	var keycode_str: String = input_data.get("keycode", "")
	var keycode := _string_to_keycode(keycode_str)

	if keycode == KEY_NONE:
		print("[MCP] Unknown keycode: ", keycode_str)
		return null

	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _create_mouse_button_event(input_data: Dictionary, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = input_data.get("button_index", 1)
	event.pressed = pressed
	event.position = Vector2(
		input_data.get("position_x", 0.0),
		input_data.get("position_y", 0.0)
	)
	event.global_position = event.position
	return event


func _create_mouse_motion_event(input_data: Dictionary) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(
		input_data.get("position_x", 0.0),
		input_data.get("position_y", 0.0)
	)
	event.global_position = event.position
	event.relative = Vector2(
		input_data.get("relative_x", 0.0),
		input_data.get("relative_y", 0.0)
	)
	return event


func _create_action_event(input_data: Dictionary, pressed: bool) -> InputEventAction:
	var action_name: String = input_data.get("action", "")
	var strength: float = input_data.get("strength", 1.0)

	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength if pressed else 0.0
	return event


func _create_joypad_button_event(input_data: Dictionary, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = input_data.get("joypad_button", 0)
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	return event


func _create_joypad_motion_event(input_data: Dictionary) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = input_data.get("axis", 0)
	event.axis_value = input_data.get("axis_value", 0.0)
	return event


func _send_input_result(success: bool, message: String) -> void:
	EngineDebugger.send_message("%s:input_synthesized" % C.MESSAGE_PREFIX, [ {
		"success": success,
		"message": message,
	}])


func _string_to_keycode(key_str: String) -> Key:
	# Handle common key names
	var upper := key_str.to_upper()

	# Single character keys (A-Z, 0-9)
	if key_str.length() == 1:
		var code := key_str.unicode_at(0)
		# Letters A-Z
		if code >= 65 and code <= 90:
			return code as Key
		# Lowercase a-z -> convert to uppercase
		if code >= 97 and code <= 122:
			return (code - 32) as Key
		# Numbers 0-9
		if code >= 48 and code <= 57:
			return code as Key

	# Named keys
	match upper:
		# Function keys
		"F1": return KEY_F1
		"F2": return KEY_F2
		"F3": return KEY_F3
		"F4": return KEY_F4
		"F5": return KEY_F5
		"F6": return KEY_F6
		"F7": return KEY_F7
		"F8": return KEY_F8
		"F9": return KEY_F9
		"F10": return KEY_F10
		"F11": return KEY_F11
		"F12": return KEY_F12

		# Modifier keys
		"SHIFT", "LSHIFT", "LEFT_SHIFT": return KEY_SHIFT
		"CTRL", "CONTROL", "LCTRL", "LEFT_CTRL": return KEY_CTRL
		"ALT", "LALT", "LEFT_ALT": return KEY_ALT
		"META", "SUPER", "WIN", "WINDOWS", "CMD", "COMMAND": return KEY_META

		# Navigation
		"UP", "ARROW_UP": return KEY_UP
		"DOWN", "ARROW_DOWN": return KEY_DOWN
		"LEFT", "ARROW_LEFT": return KEY_LEFT
		"RIGHT", "ARROW_RIGHT": return KEY_RIGHT
		"HOME": return KEY_HOME
		"END": return KEY_END
		"PAGEUP", "PAGE_UP": return KEY_PAGEUP
		"PAGEDOWN", "PAGE_DOWN": return KEY_PAGEDOWN

		# Editing keys
		"ENTER", "RETURN": return KEY_ENTER
		"TAB": return KEY_TAB
		"SPACE", " ": return KEY_SPACE
		"BACKSPACE", "BACK": return KEY_BACKSPACE
		"DELETE", "DEL": return KEY_DELETE
		"INSERT", "INS": return KEY_INSERT
		"ESCAPE", "ESC": return KEY_ESCAPE

		# Punctuation and symbols
		"MINUS", "-": return KEY_MINUS
		"EQUAL", "EQUALS", "=": return KEY_EQUAL
		"BRACKETLEFT", "[": return KEY_BRACKETLEFT
		"BRACKETRIGHT", "]": return KEY_BRACKETRIGHT
		"BACKSLASH", "\\": return KEY_BACKSLASH
		"SEMICOLON", ";": return KEY_SEMICOLON
		"APOSTROPHE", "QUOTE", "'": return KEY_APOSTROPHE
		"COMMA", ",": return KEY_COMMA
		"PERIOD", ".": return KEY_PERIOD
		"SLASH", "/": return KEY_SLASH
		"QUOTELEFT", "GRAVE", "BACKTICK", "`": return KEY_QUOTELEFT

		# Lock keys
		"CAPSLOCK", "CAPS_LOCK": return KEY_CAPSLOCK
		"NUMLOCK", "NUM_LOCK": return KEY_NUMLOCK
		"SCROLLLOCK", "SCROLL_LOCK": return KEY_SCROLLLOCK

		# Other
		"PRINT", "PRINTSCREEN", "PRINT_SCREEN": return KEY_PRINT
		"PAUSE": return KEY_PAUSE
		"MENU": return KEY_MENU

	return KEY_NONE


# ============================================================================
# Node Interaction
# ============================================================================

func _handle_node_interaction(interaction_data: Dictionary) -> void:
	var interaction_type: String = interaction_data.get("interaction_type", "")
	var identifier_type: String = interaction_data.get("identifier_type", "")
	var identifier_value: String = interaction_data.get("identifier_value", "")
	var button_index: int = interaction_data.get("button_index", 1)
	var offset_x: float = interaction_data.get("offset_x", 0.0)
	var offset_y: float = interaction_data.get("offset_y", 0.0)

	print("[MCP] Node interaction: %s, identifier: %s = '%s'" % [interaction_type, identifier_type, identifier_value])

	# Find the node
	var node := _find_node(identifier_type, identifier_value)
	if node == null:
		_send_node_interaction_result(false, "Node not found with %s: '%s'" % [identifier_type, identifier_value])
		return

	# Get the screen position for the node
	var screen_pos_result := _get_node_screen_position(node)
	if not screen_pos_result.success:
		_send_node_interaction_result(false, screen_pos_result.message)
		return

	var screen_pos: Vector2 = screen_pos_result.position
	screen_pos += Vector2(offset_x, offset_y)

	# Perform the interaction
	match interaction_type:
		C.NodeInteraction.CLICK:
			_perform_click(screen_pos, button_index)
			_send_node_interaction_result(true, "Clicked node '%s' at position (%d, %d)" % [
				node.name, int(screen_pos.x), int(screen_pos.y)
			])

		C.NodeInteraction.HOVER:
			_perform_hover(screen_pos)
			_send_node_interaction_result(true, "Moved mouse to node '%s' at position (%d, %d)" % [
				node.name, int(screen_pos.x), int(screen_pos.y)
			])

		_:
			_send_node_interaction_result(false, "Unknown interaction type: " + interaction_type)


func _find_node(identifier_type: String, identifier_value: String) -> Node:
	var root := get_tree().root

	match identifier_type:
		C.NodeIdentifier.NODE_PATH:
			if root.has_node(identifier_value):
				return root.get_node(identifier_value)
			return null

		C.NodeIdentifier.UNIQUE_NAME:
			return _find_node_by_unique_name(root, identifier_value)

		C.NodeIdentifier.ACCESSIBILITY_NAME:
			return _find_node_by_accessibility_name(root, identifier_value)

		_:
			return null


func _find_node_by_unique_name(node: Node, unique_name: String) -> Node:
	# Check if this node has the unique name
	if node.unique_name_in_owner and node.name == unique_name:
		return node

	# Recursively search children
	for child in node.get_children():
		var found := _find_node_by_unique_name(child, unique_name)
		if found:
			return found

	return null


func _find_node_by_accessibility_name(node: Node, accessibility_name: String) -> Node:
	# Check if this node is a Control with matching accessibility name
	if node is Control:
		var control := node as Control
		if control.accessibility_name == accessibility_name:
			return control

	# Recursively search children
	for child in node.get_children():
		var found := _find_node_by_accessibility_name(child, accessibility_name)
		if found:
			return found

	return null


func _get_node_screen_position(node: Node) -> Dictionary:
	if node is Control:
		var control := node as Control
		var center := control.get_global_rect().get_center()
		return {"success": true, "position": center, "message": ""}

	elif node is Node2D:
		var node2d := node as Node2D
		# For Node2D, global_position is in canvas coordinates which matches screen coords
		return {"success": true, "position": node2d.global_position, "message": ""}

	elif node is Node3D:
		var node3d := node as Node3D
		var camera := get_viewport().get_camera_3d()

		if camera == null:
			return {"success": false, "position": Vector2.ZERO, "message": "No 3D camera found in viewport"}

		# Check if the point is in front of the camera
		if not camera.is_position_in_frustum(node3d.global_position):
			return {"success": false, "position": Vector2.ZERO, "message": "Node3D position is not visible (outside camera frustum)"}

		# Project 3D position to screen coordinates
		var screen_pos := camera.unproject_position(node3d.global_position)

		# Check if it's behind the camera
		var to_point := node3d.global_position - camera.global_position
		var forward := -camera.global_transform.basis.z
		if to_point.dot(forward) < 0:
			return {"success": false, "position": Vector2.ZERO, "message": "Node3D is behind the camera"}

		return {"success": true, "position": screen_pos, "message": ""}

	else:
		return {"success": false, "position": Vector2.ZERO, "message": "Node type '%s' is not supported. Must be Control, Node2D, or Node3D." % node.get_class()}


func _perform_click(position: Vector2, button_index: int) -> void:
	# Create and send mouse button press event
	var press_event := InputEventMouseButton.new()
	press_event.button_index = button_index
	press_event.pressed = true
	press_event.position = position
	press_event.global_position = position
	Input.parse_input_event(press_event)

	# Create and send mouse button release event
	var release_event := InputEventMouseButton.new()
	release_event.button_index = button_index
	release_event.pressed = false
	release_event.position = position
	release_event.global_position = position
	Input.parse_input_event(release_event)


func _perform_hover(position: Vector2) -> void:
	# Create and send mouse motion event
	var motion_event := InputEventMouseMotion.new()
	motion_event.position = position
	motion_event.global_position = position
	Input.parse_input_event(motion_event)


func _send_node_interaction_result(success: bool, message: String) -> void:
	EngineDebugger.send_message("%s:node_interaction_completed" % C.MESSAGE_PREFIX, [ {
		"success": success,
		"message": message,
	}])


# ============================================================================
# Node Tree
# ============================================================================

func _handle_get_node_tree(tree_request: Dictionary) -> void:
	var root_path: String = tree_request.get("root_path", "/root")
	var max_depth: int = tree_request.get("max_depth", -1)

	print("[MCP] Getting node tree from: %s (max_depth: %d)" % [root_path, max_depth])

	var root := get_tree().root
	var start_node: Node = null

	if root_path == "/root" or root_path.is_empty():
		start_node = root
	elif root.has_node(root_path):
		start_node = root.get_node(root_path)

	if start_node == null:
		_send_node_tree_result(false, "", "Node not found at path: " + root_path)
		return

	var tree_str := _format_node_tree(start_node, 0, max_depth)
	_send_node_tree_result(true, tree_str, "")


func _format_node_tree(node: Node, depth: int, max_depth: int) -> String:
	var result := ""

	# Build the line for this node (tabs are more token-efficient than spaces)
	var indent := "\t".repeat(depth)
	var line := indent + node.name + " (" + node.get_class() + ")"

	# Add script type if present
	var script: Script = node.get_script()
	if script and script.resource_path:
		var script_name := script.resource_path.get_file()
		line += " [" + script_name + "]"

	result += line + "\n"

	# Recurse into children if not at max depth
	if max_depth < 0 or depth < max_depth:
		for child in node.get_children():
			result += _format_node_tree(child, depth + 1, max_depth)

	return result


func _send_node_tree_result(success: bool, tree: String, message: String) -> void:
	EngineDebugger.send_message("%s:node_tree" % C.MESSAGE_PREFIX, [ {
		"success": success,
		"tree": tree,
		"message": message,
	}])
