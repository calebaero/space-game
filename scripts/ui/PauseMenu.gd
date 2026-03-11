extends Control

signal resume_requested
signal save_requested
signal settings_requested
signal quit_to_menu_requested

@onready var resume_button: Button = %ResumeButton
@onready var save_button: Button = %SaveButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_to_menu_button: Button = %QuitToMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false

	resume_button.pressed.connect(_on_resume_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_button_pressed)


func show_menu() -> void:
	save_button.disabled = not GameStateManager.is_docked
	visible = true


func hide_menu() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_save_button_pressed() -> void:
	save_requested.emit()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_quit_to_menu_button_pressed() -> void:
	quit_to_menu_requested.emit()
