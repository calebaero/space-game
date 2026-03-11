extends CanvasLayer
class_name TutorialStartPrompt

signal start_requested
signal skip_requested

@onready var start_button: Button = %StartTutorialButton
@onready var skip_button: Button = %SkipTutorialButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	start_button.pressed.connect(_on_start_pressed)
	skip_button.pressed.connect(_on_skip_pressed)


func open_prompt() -> void:
	visible = true
	start_button.grab_focus()


func close_prompt() -> void:
	visible = false


func _on_start_pressed() -> void:
	close_prompt()
	start_requested.emit()


func _on_skip_pressed() -> void:
	close_prompt()
	skip_requested.emit()
