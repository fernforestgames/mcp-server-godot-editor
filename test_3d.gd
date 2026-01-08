extends Node3D

@onready var clickable_cube: MeshInstance3D = %ClickableCube
@onready var hoverable_cube: MeshInstance3D = %HoverableCube
@onready var click_status: Label = %ClickStatus
@onready var hover_status: Label = %HoverStatus

var click_count := 0
var last_click_pos := Vector2.ZERO
var last_hover_pos := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_check_click(mouse_event.position)

	elif event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		_check_hover(motion_event.position)

func _check_click(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# Project cube position to screen and check if click is near it
	var cube_screen_pos := camera.unproject_position(clickable_cube.global_position)
	var distance := screen_pos.distance_to(cube_screen_pos)

	if distance < 100:  # Click within 100 pixels of cube center
		click_count += 1
		last_click_pos = screen_pos
		click_status.text = "Left cube: Clicked %d time(s) at (%d, %d)" % [click_count, int(screen_pos.x), int(screen_pos.y)]

		# Visual feedback - change color briefly
		var material := clickable_cube.get_surface_override_material(0) as StandardMaterial3D
		if material:
			material.albedo_color = Color(1, 0.3, 0.3)  # Red flash
			get_tree().create_timer(0.2).timeout.connect(func():
				material.albedo_color = Color(0.2, 0.6, 1)  # Back to blue
			)

func _check_hover(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# Project cube position to screen and check if mouse is near it
	var cube_screen_pos := camera.unproject_position(hoverable_cube.global_position)
	var distance := screen_pos.distance_to(cube_screen_pos)

	var material := hoverable_cube.get_surface_override_material(0) as StandardMaterial3D
	if distance < 100:  # Hover within 100 pixels of cube center
		last_hover_pos = screen_pos
		hover_status.text = "Right cube: Hovering at (%d, %d)" % [int(screen_pos.x), int(screen_pos.y)]
		if material:
			material.albedo_color = Color(0.3, 1, 0.3)  # Green when hovering
	else:
		hover_status.text = "Right cube: Not hovered"
		if material:
			material.albedo_color = Color(0.2, 0.6, 1)  # Blue when not hovering
