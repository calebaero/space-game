extends Control

const GAME_ROOT_SCENE_PATH: String = "res://scenes/main/GameRoot.tscn"

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_placeholder_dialog: AcceptDialog = %SettingsPlaceholderDialog


func _ready() -> void:
	continue_button.disabled = true

	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	var starting_sector_id: StringName = GalaxyManager.get_starting_sector_id()
	GameStateManager.request_new_game(starting_sector_id)
	get_tree().change_scene_to_file(GAME_ROOT_SCENE_PATH)


func _on_settings_pressed() -> void:
	# TODO(phase-later): open SettingsMenu once settings UI exists.
	settings_placeholder_dialog.popup_centered(Vector2(420.0, 180.0))


func _on_quit_pressed() -> void:
	get_tree().quit()
