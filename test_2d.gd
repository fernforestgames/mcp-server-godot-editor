extends Control

@onready var test_button: Button = %TestButton
@onready var hover_button: Button = %HoverButton
@onready var status_label: Label = %StatusLabel

var click_count := 0

func _ready() -> void:
	test_button.pressed.connect(_on_test_button_pressed)
	hover_button.mouse_entered.connect(_on_hover_button_mouse_entered)
	hover_button.mouse_exited.connect(_on_hover_button_mouse_exited)

func _on_test_button_pressed() -> void:
	click_count += 1
	status_label.text = "Status: Button clicked %d time(s)!" % click_count

func _on_hover_button_mouse_entered() -> void:
	status_label.text = "Status: Hovering over button!"
	hover_button.text = "You're hovering!"

func _on_hover_button_mouse_exited() -> void:
	status_label.text = "Status: Mouse left hover button"
	hover_button.text = "Hover Over Me"
