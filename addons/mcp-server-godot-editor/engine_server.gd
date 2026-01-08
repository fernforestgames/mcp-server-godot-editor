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
	EngineDebugger.send_message("%s:input_synthesized" % C.MESSAGE_PREFIX, [{
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
