extends Control

const GAME_ROOT_SCENE_PATH: String = "res://scenes/main/GameRoot.tscn"

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var settings_button: Button = %SettingsButton
@onready var about_button: Button = %AboutButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: CanvasLayer = %SettingsMenu
@onready var about_screen: CanvasLayer = %AboutScreen


func _ready() -> void:
	_refresh_continue_button_state()
	AudioManager.play_music(&"menu_theme")

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	about_button.pressed.connect(_on_about_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	if not SaveManager.save_completed.is_connected(_on_save_slots_updated):
		SaveManager.save_completed.connect(_on_save_slots_updated)
	if not SaveManager.load_completed.is_connected(_on_save_slots_updated):
		SaveManager.load_completed.connect(_on_save_slots_updated)
	if settings_menu != null and is_instance_valid(settings_menu):
		if not settings_menu.close_requested.is_connected(_on_settings_menu_closed):
			settings_menu.close_requested.connect(_on_settings_menu_closed)
	if about_screen != null and is_instance_valid(about_screen):
		if not about_screen.close_requested.is_connected(_on_about_closed):
			about_screen.close_requested.connect(_on_about_closed)


func _on_new_game_pressed() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	SaveManager.clear_pending_loaded_state()
	var starting_sector_id: StringName = GalaxyManager.get_starting_sector_id()
	GameStateManager.request_new_game(starting_sector_id)
	get_tree().change_scene_to_file(GAME_ROOT_SCENE_PATH)


func _on_continue_pressed() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	if not SaveManager.load_most_recent_save():
		return
	get_tree().change_scene_to_file(GAME_ROOT_SCENE_PATH)


func _on_settings_pressed() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	if settings_menu == null or not is_instance_valid(settings_menu):
		return
	settings_menu.open_menu(&"main_menu")


func _on_about_pressed() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	if about_screen == null or not is_instance_valid(about_screen):
		return
	if about_screen.has_method("open_panel"):
		about_screen.call("open_panel")
	else:
		about_screen.visible = true


func _on_quit_pressed() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	get_tree().quit()


func _on_save_slots_updated(_slot_id: int, _metadata: Dictionary) -> void:
	_refresh_continue_button_state()


func _refresh_continue_button_state() -> void:
	continue_button.disabled = not SaveManager.has_any_saves()


func _on_settings_menu_closed() -> void:
	_refresh_continue_button_state()


func _on_about_closed() -> void:
	_refresh_continue_button_state()
