extends CanvasLayer
class_name AboutScreen

signal close_requested

@onready var close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)


func open_panel() -> void:
	visible = true
	close_button.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close_panel()


func _on_close_button_pressed() -> void:
	close_panel()
