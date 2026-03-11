extends Node

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main/MainMenu.tscn"
const SECTOR_SCENE: PackedScene = preload("res://scenes/world/SectorScene.tscn")

signal player_docked(station_id: StringName)

@onready var active_sector_container: Node2D = %ActiveSectorContainer
@onready var pause_menu: Control = %PauseMenu
@onready var hud: CanvasLayer = %HUD
@onready var station_menu: CanvasLayer = %StationMenu
@onready var galaxy_map_screen: CanvasLayer = %GalaxyMapScreen
@onready var boss_health_bar: CanvasLayer = %BossHealthBar
@onready var game_over_screen: CanvasLayer = %GameOverScreen
@onready var wreck_recovery_panel: CanvasLayer = %WreckRecoveryPanel
@onready var victory_overlay: CanvasLayer = %VictoryOverlay
@onready var settings_menu: CanvasLayer = %SettingsMenu
@onready var tutorial_overlay: CanvasLayer = %TutorialOverlay
@onready var tutorial_start_prompt: CanvasLayer = %TutorialStartPrompt
@onready var warp_transition_overlay: CanvasLayer = %WarpTransitionOverlay

var _active_sector_scene: Node2D = null
var _active_player_ship: PlayerShip = null
var _docked_station: Node = null
var _is_station_menu_open: bool = false
var _is_map_open: bool = false
var _is_warp_transitioning: bool = false
var _is_game_over_open: bool = false
var _is_wreck_panel_open: bool = false
var _is_settings_open: bool = false
var _is_tutorial_prompt_open: bool = false
var _mission_position_report_accumulator: float = 0.0
var _enemy_bind_accumulator: float = 0.0
var _active_boss_ship: Node = null


func _ready() -> void:
	if not GameStateManager.new_game_requested.is_connected(_on_new_game_requested):
		GameStateManager.new_game_requested.connect(_on_new_game_requested)

	if pause_menu.has_signal("resume_requested"):
		pause_menu.connect("resume_requested", _on_pause_resume_requested)
	if pause_menu.has_signal("save_requested"):
		pause_menu.connect("save_requested", _on_pause_save_requested)
	if pause_menu.has_signal("settings_requested"):
		pause_menu.connect("settings_requested", _on_pause_settings_requested)
	if pause_menu.has_signal("quit_to_menu_requested"):
		pause_menu.connect("quit_to_menu_requested", _on_pause_quit_to_menu_requested)

	if station_menu.has_signal("undock_requested"):
		station_menu.connect("undock_requested", _on_station_menu_undock_requested)
	if station_menu.has_signal("save_requested"):
		station_menu.connect("save_requested", _on_station_menu_save_requested)
	if station_menu.has_signal("cargo_sold"):
		station_menu.connect("cargo_sold", _on_station_menu_cargo_sold)
	if station_menu.has_signal("galaxy_map_requested"):
		station_menu.connect("galaxy_map_requested", _on_station_menu_galaxy_map_requested)
	if galaxy_map_screen.has_signal("close_requested"):
		galaxy_map_screen.connect("close_requested", _on_galaxy_map_close_requested)
	if UIManager.has_signal("wreck_recovery_requested"):
		UIManager.wreck_recovery_requested.connect(_on_wreck_recovery_requested)
	if game_over_screen.has_signal("continue_requested"):
		game_over_screen.connect("continue_requested", _on_game_over_continue_requested)
	if wreck_recovery_panel.has_signal("close_requested"):
		wreck_recovery_panel.connect("close_requested", _on_wreck_recovery_close_requested)
	if settings_menu != null and is_instance_valid(settings_menu) and settings_menu.has_signal("close_requested"):
		settings_menu.connect("close_requested", _on_settings_menu_close_requested)
	if tutorial_overlay != null and is_instance_valid(tutorial_overlay):
		if tutorial_overlay.has_signal("tutorial_step_changed") and not tutorial_overlay.tutorial_step_changed.is_connected(_on_tutorial_step_changed):
			tutorial_overlay.tutorial_step_changed.connect(_on_tutorial_step_changed)
		if tutorial_overlay.has_signal("tutorial_completed") and not tutorial_overlay.tutorial_completed.is_connected(_on_tutorial_end):
			tutorial_overlay.tutorial_completed.connect(_on_tutorial_end)
		if tutorial_overlay.has_signal("tutorial_skipped") and not tutorial_overlay.tutorial_skipped.is_connected(_on_tutorial_end):
			tutorial_overlay.tutorial_skipped.connect(_on_tutorial_end)
	if tutorial_start_prompt != null and is_instance_valid(tutorial_start_prompt):
		if tutorial_start_prompt.has_signal("start_requested") and not tutorial_start_prompt.start_requested.is_connected(_on_tutorial_prompt_start_requested):
			tutorial_start_prompt.start_requested.connect(_on_tutorial_prompt_start_requested)
		if tutorial_start_prompt.has_signal("skip_requested") and not tutorial_start_prompt.skip_requested.is_connected(_on_tutorial_prompt_skip_requested):
			tutorial_start_prompt.skip_requested.connect(_on_tutorial_prompt_skip_requested)

	pause_menu.visible = false
	station_menu.visible = false
	galaxy_map_screen.visible = false
	boss_health_bar.visible = true
	if boss_health_bar.has_method("end_encounter"):
		boss_health_bar.call("end_encounter")
	game_over_screen.visible = false
	wreck_recovery_panel.visible = false
	victory_overlay.visible = false
	settings_menu.visible = false
	tutorial_overlay.visible = false
	tutorial_start_prompt.visible = false
	_is_settings_open = false
	_is_tutorial_prompt_open = false
	if warp_transition_overlay.has_method("clear_overlay"):
		warp_transition_overlay.call("clear_overlay")
	if not MissionManager.mission_state_changed.is_connected(_on_mission_state_changed):
		MissionManager.mission_state_changed.connect(_on_mission_state_changed)
	if not MissionManager.mission_markers_changed.is_connected(_on_mission_markers_changed):
		MissionManager.mission_markers_changed.connect(_on_mission_markers_changed)
	if not MissionManager.victory_sequence_requested.is_connected(_on_victory_sequence_requested):
		MissionManager.victory_sequence_requested.connect(_on_victory_sequence_requested)

	get_tree().paused = false
	set_process(true)
	if SaveManager.consume_pending_loaded_state():
		_start_loaded_game()
		return
	GameStateManager.emit_queued_new_game_request_if_any()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _active_sector_scene != null and is_instance_valid(_active_sector_scene):
		GameStateManager.add_playtime(delta)
	if _active_player_ship == null or not is_instance_valid(_active_player_ship):
		_enemy_bind_accumulator += delta
		if _enemy_bind_accumulator >= 0.5:
			_enemy_bind_accumulator = 0.0
			_bind_enemy_destroy_signals()
		return
	_mission_position_report_accumulator += delta
	_enemy_bind_accumulator += delta
	if _mission_position_report_accumulator >= 0.12:
		_mission_position_report_accumulator = 0.0
		MissionManager.report_player_position(GameStateManager.current_sector_id, _active_player_ship.global_position)
	if _enemy_bind_accumulator >= 0.5:
		_enemy_bind_accumulator = 0.0
		_bind_enemy_destroy_signals()


func _unhandled_input(event: InputEvent) -> void:
	if _is_warp_transitioning or _is_game_over_open or _is_wreck_panel_open or _is_settings_open or _is_tutorial_prompt_open:
		return

	if not get_tree().paused:
		if event.is_action_pressed("map_toggle"):
			_open_galaxy_map()
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("pause"):
			_pause_game()
			get_viewport().set_input_as_handled()


func _on_new_game_requested(starting_sector_id: StringName) -> void:
	MissionManager.reset_for_new_game()
	_is_game_over_open = false
	_is_wreck_panel_open = false
	var starting_sector_data: Dictionary = GalaxyManager.start_new_game(starting_sector_id)
	if starting_sector_data.is_empty():
		push_error("GameRoot could not load starting sector: %s" % starting_sector_id)
		return

	load_sector(starting_sector_data, &"")
	AudioManager.set_exploration_context(int(starting_sector_data.get("threat_level", 1)), false)
	var sector_name: String = String(starting_sector_data.get("name", "current"))
	UIManager.show_toast("Welcome to %s sector" % sector_name, &"info")
	_show_new_game_tutorial_prompt_if_needed()


func _start_loaded_game() -> void:
	var respawn_sector_id: StringName = _find_sector_id_for_station(GameStateManager.last_docked_station_id)
	if respawn_sector_id == &"":
		respawn_sector_id = GameStateManager.current_sector_id
	if respawn_sector_id == &"":
		respawn_sector_id = &"anchor_station"

	var sector_data: Dictionary = GalaxyManager.get_sector_data(respawn_sector_id)
	if sector_data.is_empty():
		respawn_sector_id = &"anchor_station"
		sector_data = GalaxyManager.get_sector_data(respawn_sector_id)
	if sector_data.is_empty():
		push_error("GameRoot could not load resume sector.")
		return

	load_sector(sector_data, &"")
	GameStateManager.is_docked = false
	GameStateManager.docked_station_id = &""
	AudioManager.set_exploration_context(int(sector_data.get("threat_level", 1)), false)
	UIManager.show_toast("Save loaded.", &"success")


func load_sector(sector_data: Dictionary, arrival_from_sector_id: StringName) -> void:
	if _active_sector_scene != null and is_instance_valid(_active_sector_scene):
		_active_sector_scene.queue_free()
		_active_sector_scene = null

	var sector_scene: Node2D = SECTOR_SCENE.instantiate() as Node2D
	if sector_scene == null:
		push_error("GameRoot failed to instance SectorScene as Node2D.")
		return

	var galaxy_id: StringName = StringName(String(sector_data.get("galaxy_id", "")))
	var galaxy_data: Dictionary = GalaxyManager.get_galaxy_data(galaxy_id)
	if sector_scene.has_method("setup_sector"):
		sector_scene.call("setup_sector", sector_data, galaxy_data)

	active_sector_container.add_child(sector_scene)
	_active_sector_scene = sector_scene

	var spawn_position: Vector2 = Vector2.ZERO
	if arrival_from_sector_id != &"" and sector_scene.has_method("get_arrival_spawn_position"):
		var arrival_position_variant: Variant = sector_scene.call("get_arrival_spawn_position", arrival_from_sector_id)
		if arrival_position_variant is Vector2:
			spawn_position = arrival_position_variant
	elif sector_scene.has_method("get_player_spawn_position"):
		var default_spawn_variant: Variant = sector_scene.call("get_player_spawn_position")
		if default_spawn_variant is Vector2:
			spawn_position = default_spawn_variant
	_spawn_player_for_sector(sector_scene, spawn_position)
	_bind_boss_triggers()

	var loaded_sector_id: StringName = StringName(String(sector_data.get("id", "")))
	if loaded_sector_id != &"":
		GameStateManager.set_current_sector(loaded_sector_id)
		GalaxyManager.set_current_sector(loaded_sector_id)
		MissionManager.report_sector_entered(loaded_sector_id)
	_refresh_mission_markers()
	_spawn_pending_mission_encounters(loaded_sector_id, sector_data, true)
	_bind_enemy_destroy_signals()
	_refresh_tutorial_state()


func _spawn_player_for_sector(sector_scene: Node2D, spawn_position: Vector2) -> void:
	_active_player_ship = null
	if not sector_scene.has_method("spawn_player_ship"):
		return

	var spawned_ship_variant: Variant = sector_scene.call("spawn_player_ship", spawn_position)
	if spawned_ship_variant is not PlayerShip:
		return

	_active_player_ship = spawned_ship_variant
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		if not _active_player_ship.station_dock_requested.is_connected(_on_player_station_dock_requested):
			_active_player_ship.station_dock_requested.connect(_on_player_station_dock_requested)
		if not _active_player_ship.warp_gate_requested.is_connected(_on_player_warp_gate_requested):
			_active_player_ship.warp_gate_requested.connect(_on_player_warp_gate_requested)
		if not _active_player_ship.player_destroyed.is_connected(_on_player_destroyed):
			_active_player_ship.player_destroyed.connect(_on_player_destroyed)
		_active_player_ship.set_controls_enabled(true)

	if hud.has_method("set_player_ship"):
		hud.call("set_player_ship", _active_player_ship)
	if tutorial_overlay != null and is_instance_valid(tutorial_overlay) and tutorial_overlay.has_method("set_player_ship"):
		tutorial_overlay.call("set_player_ship", _active_player_ship)


func _pause_game() -> void:
	if _is_station_menu_open or _is_map_open or _is_warp_transitioning or _is_game_over_open or _is_wreck_panel_open:
		return

	get_tree().paused = true
	if pause_menu.has_method("show_menu"):
		pause_menu.call("show_menu")
	else:
		pause_menu.visible = true


func _resume_game() -> void:
	if pause_menu.has_method("hide_menu"):
		pause_menu.call("hide_menu")
	else:
		pause_menu.visible = false
	get_tree().paused = false


func _open_galaxy_map() -> void:
	if _is_station_menu_open or _is_map_open or _is_game_over_open or _is_wreck_panel_open:
		return
	if not is_instance_valid(_active_player_ship):
		return

	_is_map_open = true
	_active_player_ship.set_controls_enabled(false)
	get_tree().paused = true
	if galaxy_map_screen.has_method("open_map"):
		galaxy_map_screen.call("open_map", GameStateManager.current_sector_id)
	else:
		galaxy_map_screen.visible = true


func _on_pause_resume_requested() -> void:
	_resume_game()


func _on_pause_save_requested() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	if not GameStateManager.is_docked:
		UIManager.show_toast("Manual save is only available while docked.", &"warning")
		return
	if SaveManager.save_game():
		UIManager.show_toast("Game saved.", &"success")


func _on_pause_settings_requested() -> void:
	if settings_menu == null or not is_instance_valid(settings_menu):
		return
	_is_settings_open = true
	if pause_menu.has_method("hide_menu"):
		pause_menu.call("hide_menu")
	else:
		pause_menu.visible = false
	if settings_menu.has_method("open_menu"):
		settings_menu.call("open_menu", &"pause_menu")
	else:
		settings_menu.visible = true


func _on_pause_quit_to_menu_requested() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	get_tree().paused = false
	_is_settings_open = false
	if hud.has_method("set_player_ship"):
		hud.call("set_player_ship", null)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_player_station_dock_requested(station_node: Node) -> void:
	if _is_warp_transitioning or _is_station_menu_open or _is_game_over_open or _is_wreck_panel_open:
		return
	if station_node == null or not is_instance_valid(station_node):
		return

	_docked_station = station_node
	var station_data: Dictionary = {}
	if station_node.has_method("get_station_data"):
		station_data = station_node.call("get_station_data")

	GameStateManager.last_docked_station_id = StringName(String(station_data.get("id", "")))
	GameStateManager.is_docked = true
	GameStateManager.docked_station_id = GameStateManager.last_docked_station_id
	player_docked.emit(GameStateManager.docked_station_id)
	SaveManager.autosave()
	MissionManager.report_player_docked(GameStateManager.last_docked_station_id)
	AudioManager.play_sfx(&"dock_confirm", Vector2.ZERO)
	AudioManager.set_exploration_context(int(GalaxyManager.get_current_sector_data().get("threat_level", 1)), true)

	if is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(false)
		_active_player_ship.velocity = Vector2.ZERO

	_is_station_menu_open = true
	get_tree().paused = true
	if station_menu.has_method("open_for_station"):
		station_menu.call("open_for_station", station_data)
	else:
		station_menu.visible = true


func _on_station_menu_undock_requested() -> void:
	if not _is_station_menu_open:
		return

	if _is_map_open:
		_on_galaxy_map_close_requested()

	if station_menu.has_method("close_menu"):
		station_menu.call("close_menu")
	else:
		station_menu.visible = false
	if station_menu.has_method("set_market_tab_tutorial_highlight"):
		station_menu.call("set_market_tab_tutorial_highlight", false)

	GameStateManager.is_docked = false
	GameStateManager.docked_station_id = &""
	_is_station_menu_open = false
	get_tree().paused = false
	AudioManager.play_sfx(&"undock", Vector2.ZERO)
	AudioManager.set_exploration_context(int(GalaxyManager.get_current_sector_data().get("threat_level", 1)), false)

	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		if _docked_station != null and is_instance_valid(_docked_station) and _docked_station.has_method("get_undock_spawn_position"):
			_active_player_ship.global_position = _docked_station.call("get_undock_spawn_position")
		_active_player_ship.velocity = Vector2.ZERO
		_active_player_ship.set_controls_enabled(true)

	_docked_station = null


func _on_station_menu_save_requested() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	if SaveManager.save_game():
		UIManager.show_toast("Game saved.", &"success")


func _on_station_menu_cargo_sold(total_quantity: int, total_credits: int) -> void:
	if tutorial_overlay == null or not is_instance_valid(tutorial_overlay):
		return
	if tutorial_overlay.has_method("report_cargo_sold"):
		tutorial_overlay.call("report_cargo_sold", total_quantity, total_credits)


func _on_tutorial_step_changed(step_index: int) -> void:
	if station_menu == null or not is_instance_valid(station_menu):
		return
	if station_menu.has_method("set_market_tab_tutorial_highlight"):
		station_menu.call("set_market_tab_tutorial_highlight", step_index == 8)


func _on_tutorial_end() -> void:
	if station_menu == null or not is_instance_valid(station_menu):
		return
	if station_menu.has_method("set_market_tab_tutorial_highlight"):
		station_menu.call("set_market_tab_tutorial_highlight", false)


func _show_new_game_tutorial_prompt_if_needed() -> void:
	if GameStateManager.has_progression_flag(&"tutorial_completed"):
		return
	if tutorial_start_prompt == null or not is_instance_valid(tutorial_start_prompt):
		return
	_is_tutorial_prompt_open = true
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(false)
	get_tree().paused = true
	if tutorial_start_prompt.has_method("open_prompt"):
		tutorial_start_prompt.call("open_prompt")
	else:
		tutorial_start_prompt.visible = true


func _on_tutorial_prompt_start_requested() -> void:
	_is_tutorial_prompt_open = false
	get_tree().paused = false
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(true)
	_ensure_first_steps_story_mission_active()
	_refresh_tutorial_state()
	if tutorial_overlay != null and is_instance_valid(tutorial_overlay) and tutorial_overlay.has_method("is_active"):
		if not bool(tutorial_overlay.call("is_active")) and tutorial_overlay.has_method("start_tutorial"):
			tutorial_overlay.call("start_tutorial", _active_player_ship, _resolve_first_steps_beacon_position(), &"station_anchor_prime")


func _on_tutorial_prompt_skip_requested() -> void:
	_is_tutorial_prompt_open = false
	get_tree().paused = false
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(true)
	GameStateManager.set_progression_flag(&"tutorial_completed", true)
	UIManager.show_toast("Tutorial skipped. Use Missions at Anchor Station to play it later.", &"info")
	SaveManager.autosave()


func _ensure_first_steps_story_mission_active() -> void:
	if GameStateManager.has_progression_flag(&"story_first_steps_complete"):
		return
	for mission_variant in MissionManager.get_active_missions():
		if mission_variant is not Dictionary:
			continue
		if String((mission_variant as Dictionary).get("template_id", "")) == "story_first_steps":
			return
	MissionManager.accept_story_mission(&"story_first_steps")


func _on_station_menu_galaxy_map_requested() -> void:
	if not _is_station_menu_open:
		return
	if _is_map_open:
		return

	_is_map_open = true
	station_menu.visible = false
	get_tree().paused = true
	if galaxy_map_screen.has_method("open_map"):
		galaxy_map_screen.call("open_map", GameStateManager.current_sector_id)
	else:
		galaxy_map_screen.visible = true


func _on_player_warp_gate_requested(destination_sector_id: StringName, _source_gate_id: StringName) -> void:
	if _is_warp_transitioning or _is_station_menu_open or _is_map_open or _is_game_over_open or _is_wreck_panel_open:
		return

	await _perform_warp_transition(destination_sector_id)


func _perform_warp_transition(destination_sector_id: StringName) -> void:
	if destination_sector_id == &"":
		return

	var destination_sector_data: Dictionary = GalaxyManager.get_sector_data(destination_sector_id)
	if destination_sector_data.is_empty():
		UIManager.show_toast("Warp destination unavailable.", &"danger")
		return

	_is_warp_transitioning = true
	var previous_sector_id: StringName = GameStateManager.current_sector_id

	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(false)
		_active_player_ship.velocity = Vector2.ZERO

	AudioManager.play_sfx(&"warp_transition", Vector2.ZERO)
	if warp_transition_overlay.has_method("play_warp_prelude"):
		await warp_transition_overlay.call("play_warp_prelude")

	GalaxyManager.set_current_sector(destination_sector_id)
	load_sector(destination_sector_data, previous_sector_id)
	await get_tree().create_timer(0.4).timeout

	if warp_transition_overlay.has_method("fade_from_black"):
		await warp_transition_overlay.call("fade_from_black", 0.3)

	_is_warp_transitioning = false
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(true)

	var destination_name: String = String(destination_sector_data.get("name", "Unknown Sector"))
	AudioManager.set_exploration_context(int(destination_sector_data.get("threat_level", 1)), false)
	UIManager.show_toast("Warped to %s" % destination_name, &"success")


func _on_galaxy_map_close_requested() -> void:
	if not _is_map_open:
		return

	_is_map_open = false
	if galaxy_map_screen.visible:
		galaxy_map_screen.visible = false

	if _is_station_menu_open:
		station_menu.visible = true
		get_tree().paused = true
		return

	get_tree().paused = false

	if _active_player_ship != null and is_instance_valid(_active_player_ship) and not _is_station_menu_open:
		_active_player_ship.set_controls_enabled(true)


func _on_player_destroyed(death_position: Vector2) -> void:
	if _is_game_over_open:
		return

	_spawn_player_death_effect(death_position)
	AudioManager.play_sfx(&"explosion_player", death_position)
	AudioManager.play_music(&"death_sting")

	var had_previous_wreck: bool = GameStateManager.has_active_wreck_beacon()
	if had_previous_wreck:
		UIManager.show_toast("Previous wreck destroyed", &"warning")

	var cargo_snapshot: Array[Dictionary] = _build_wreck_cargo_snapshot_with_loss(death_position)
	GameStateManager.set_wreck_beacon_state({
		"active": true,
		"id": "active_wreck",
		"sector_id": String(GameStateManager.current_sector_id),
		"position": death_position,
		"cargo_snapshot": cargo_snapshot,
	})

	for wreck_variant in get_tree().get_nodes_in_group("wreck_beacon"):
		var wreck_node: Node = wreck_variant
		if wreck_node != null and is_instance_valid(wreck_node):
			wreck_node.queue_free()

	var death_penalty_config: Dictionary = ContentDatabase.get_balance_config_data().get("death_penalty", {})
	var repair_fee_ratio: float = clampf(float(death_penalty_config.get("credit_loss_ratio", 0.1)), 0.0, 1.0)
	var minimum_repair_fee: int = max(int(death_penalty_config.get("minimum_repair_fee", 50)), 0)
	var repair_fee: int = max(minimum_repair_fee, int(round(float(GameStateManager.credits) * repair_fee_ratio)))
	GameStateManager.credits = max(GameStateManager.credits - repair_fee, 0)
	GameStateManager.clear_cargo_hold()

	_is_game_over_open = true
	get_tree().paused = true
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(false)

	var wreck_sector_data: Dictionary = GalaxyManager.get_sector_data(GameStateManager.current_sector_id)
	var wreck_sector_name: String = String(wreck_sector_data.get("name", "Unknown Sector"))
	if game_over_screen.has_method("show_game_over"):
		game_over_screen.call("show_game_over", repair_fee, wreck_sector_name, had_previous_wreck)
	else:
		game_over_screen.visible = true


func _on_game_over_continue_requested() -> void:
	if game_over_screen.has_method("close_screen"):
		game_over_screen.call("close_screen")
	else:
		game_over_screen.visible = false

	_is_game_over_open = false
	get_tree().paused = false

	var respawn_sector_id: StringName = _find_sector_id_for_station(GameStateManager.last_docked_station_id)
	if respawn_sector_id == &"":
		respawn_sector_id = &"anchor_station"
	var sector_data: Dictionary = GalaxyManager.get_sector_data(respawn_sector_id)
	if sector_data.is_empty():
		sector_data = GalaxyManager.get_sector_data(&"anchor_station")
		respawn_sector_id = &"anchor_station"

	load_sector(sector_data, &"")
	GameStateManager.set_current_sector(respawn_sector_id)
	GalaxyManager.set_current_sector(respawn_sector_id)
	GameStateManager.restore_full_health()
	GameStateManager.is_docked = false
	GameStateManager.docked_station_id = &""
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.velocity = Vector2.ZERO
		_active_player_ship.set_controls_enabled(true)

	AudioManager.set_exploration_context(int(GalaxyManager.get_current_sector_data().get("threat_level", 1)), false)
	UIManager.show_toast("Respawn complete. Return to your wreck beacon to recover cargo.", &"info")
	_refresh_mission_markers()


func _on_wreck_recovery_requested(wreck_beacon: Node) -> void:
	if _is_game_over_open or _is_station_menu_open or _is_warp_transitioning or _is_map_open:
		return
	if wreck_beacon == null or not is_instance_valid(wreck_beacon):
		return

	_is_wreck_panel_open = true
	get_tree().paused = true
	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		_active_player_ship.set_controls_enabled(false)

	if wreck_recovery_panel.has_method("open_for_wreck"):
		wreck_recovery_panel.call("open_for_wreck", wreck_beacon)
	else:
		wreck_recovery_panel.visible = true


func _on_wreck_recovery_close_requested() -> void:
	_is_wreck_panel_open = false
	if wreck_recovery_panel.has_method("close_panel"):
		wreck_recovery_panel.call("close_panel")
	else:
		wreck_recovery_panel.visible = false

	get_tree().paused = false
	if _active_player_ship != null and is_instance_valid(_active_player_ship) and not _is_station_menu_open:
		_active_player_ship.set_controls_enabled(true)


func _on_settings_menu_close_requested() -> void:
	_is_settings_open = false
	if _is_station_menu_open or _is_map_open or _is_game_over_open or _is_wreck_panel_open:
		return
	if get_tree().paused:
		if pause_menu.has_method("show_menu"):
			pause_menu.call("show_menu")
		else:
			pause_menu.visible = true


func _build_wreck_cargo_snapshot_with_loss(death_position: Vector2) -> Array[Dictionary]:
	var manifest: Array[Dictionary] = GameStateManager.get_cargo_manifest()
	if manifest.is_empty():
		return []

	var nearby_enemy_count: int = 0
	for enemy_variant in get_tree().get_nodes_in_group("enemy_ship"):
		var enemy_node: Node2D = enemy_variant as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.global_position.distance_to(death_position) <= 900.0:
			nearby_enemy_count += 1

	var loss_ratio: float = 0.0
	if nearby_enemy_count > 0:
		loss_ratio = randf_range(0.1, 0.3)

	var snapshot: Array[Dictionary] = []
	for entry_variant in manifest:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		var quantity: int = max(int(entry.get("quantity", 0)), 0)
		if quantity <= 0:
			continue
		var kept_quantity: int = quantity
		if loss_ratio > 0.0:
			kept_quantity = int(floor(float(quantity) * (1.0 - loss_ratio)))
		if kept_quantity <= 0:
			continue
		entry["quantity"] = kept_quantity
		snapshot.append(entry)

	return snapshot


func _find_sector_id_for_station(station_id: StringName) -> StringName:
	if station_id == &"":
		return &""

	for sector_variant in ContentDatabase.get_all_sectors().values():
		var sector_data: Dictionary = sector_variant
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			continue
		if StringName(String(station_data.get("id", ""))) == station_id:
			return StringName(String(sector_data.get("id", "")))
	return &""


func _spawn_player_death_effect(world_position: Vector2) -> void:
	if _active_sector_scene == null or not is_instance_valid(_active_sector_scene):
		return
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.global_position = world_position
	particles.amount = 80
	particles.one_shot = true
	particles.lifetime = 0.8
	particles.explosiveness = 0.96
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 70.0
	particles.initial_velocity_max = 190.0
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.6
	particles.color = Color(1.0, 0.45, 0.25, 0.95)
	_active_sector_scene.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _bind_boss_triggers() -> void:
	for trigger_variant in get_tree().get_nodes_in_group("boss_encounter_trigger"):
		var trigger_node: Node = trigger_variant
		if trigger_node == null or not is_instance_valid(trigger_node):
			continue
		if not trigger_node.has_signal("boss_encounter_triggered"):
			continue
		var callback: Callable = Callable(self, "_on_boss_encounter_triggered")
		if not trigger_node.is_connected("boss_encounter_triggered", callback):
			trigger_node.connect("boss_encounter_triggered", callback)


func _bind_enemy_destroy_signals() -> void:
	var callback: Callable = Callable(self, "_on_enemy_destroyed")
	for enemy_variant in get_tree().get_nodes_in_group("enemy_ship"):
		var enemy_node: Node = enemy_variant
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if not enemy_node.has_signal("enemy_destroyed"):
			continue
		if bool(enemy_node.get_meta("kill_signal_bound", false)):
			continue
		if not enemy_node.is_connected("enemy_destroyed", callback):
			enemy_node.connect("enemy_destroyed", callback)
		enemy_node.set_meta("kill_signal_bound", true)


func _on_enemy_destroyed(enemy_ship: EnemyShip, archetype_id: StringName) -> void:
	if enemy_ship == null:
		return
	var world_position: Vector2 = enemy_ship.global_position
	var reward_credits: int = _resolve_enemy_kill_credit_reward(archetype_id, bool(enemy_ship.get_meta("is_boss", false)))
	if reward_credits <= 0:
		return
	GameStateManager.credits += reward_credits
	_spawn_world_floating_text(world_position, "+%d cr" % reward_credits, Color(1.0, 0.92, 0.36, 0.96))
	AudioManager.play_sfx(&"pickup_credits", world_position)


func _resolve_enemy_kill_credit_reward(archetype_id: StringName, is_boss: bool) -> int:
	if is_boss:
		var boss_data: Dictionary = ContentDatabase.get_boss_archetype_definition(archetype_id)
		if boss_data.is_empty():
			return 180
		var explicit_reward: int = int(boss_data.get("kill_credit_reward", 0))
		if explicit_reward > 0:
			return explicit_reward
		return max(int(round(float(boss_data.get("hull", 300.0)) * 0.35)), 180)

	var archetype_data: Dictionary = ContentDatabase.get_enemy_archetype_definition(archetype_id)
	if archetype_data.is_empty():
		return 0
	var explicit_credit_reward: int = int(archetype_data.get("kill_credit_reward", 0))
	if explicit_credit_reward > 0:
		return explicit_credit_reward
	var hull_component: float = float(archetype_data.get("hull", 40.0)) * 0.22
	var shield_component: float = float(archetype_data.get("shield", 0.0)) * 0.18
	return max(int(round(hull_component + shield_component)), 8)


func _spawn_world_floating_text(world_position: Vector2, text: String, color: Color) -> void:
	if _active_sector_scene == null or not is_instance_valid(_active_sector_scene):
		return
	var label: Label = Label.new()
	label.text = text
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 140
	label.top_level = true
	label.global_position = world_position + Vector2(-40.0, -64.0)
	_active_sector_scene.add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -52.0), 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)


func _on_boss_encounter_triggered(boss_name: String, boss_max_health: float, total_phases: int) -> void:
	if boss_health_bar.has_method("begin_encounter"):
		boss_health_bar.call("begin_encounter", boss_name, boss_max_health, total_phases)


func _on_mission_state_changed() -> void:
	_refresh_mission_markers()
	_spawn_pending_mission_encounters(GameStateManager.current_sector_id, GalaxyManager.get_current_sector_data(), false)
	_refresh_tutorial_state()


func _on_mission_markers_changed() -> void:
	_refresh_mission_markers()


func _refresh_tutorial_state() -> void:
	if tutorial_overlay == null or not is_instance_valid(tutorial_overlay):
		return
	if _is_tutorial_prompt_open:
		return
	if GameStateManager.has_progression_flag(&"tutorial_completed"):
		return
	if GameStateManager.has_progression_flag(&"story_first_steps_complete"):
		GameStateManager.set_progression_flag(&"tutorial_completed", true)
		return
	if tutorial_overlay.has_method("is_active") and bool(tutorial_overlay.call("is_active")):
		return

	var first_steps_mission: Dictionary = _find_active_first_steps_mission()
	if first_steps_mission.is_empty():
		return

	if tutorial_overlay.has_method("start_tutorial"):
		tutorial_overlay.call("start_tutorial", _active_player_ship, _resolve_first_steps_beacon_position(first_steps_mission), &"station_anchor_prime")


func _find_active_first_steps_mission() -> Dictionary:
	for mission_variant in MissionManager.get_active_missions():
		if mission_variant is not Dictionary:
			continue
		var mission_data: Dictionary = mission_variant
		if String(mission_data.get("template_id", "")) == "story_first_steps":
			return mission_data
	return {}


func _resolve_first_steps_beacon_position(mission_data: Dictionary = {}) -> Vector2:
	var source_mission: Dictionary = mission_data
	if source_mission.is_empty():
		source_mission = _find_active_first_steps_mission()
	var beacon_position: Vector2 = Vector2(1480.0, -280.0)
	for objective_variant in source_mission.get("objectives", []):
		if objective_variant is not Dictionary:
			continue
		var objective: Dictionary = objective_variant
		if String(objective.get("type", "")) != "reach_point":
			continue
		var world_position: Variant = objective.get("world_position", Vector2.ZERO)
		if world_position is Vector2:
			return world_position
		if world_position is Dictionary and world_position.has("x") and world_position.has("y"):
			return Vector2(float(world_position.get("x", 0.0)), float(world_position.get("y", 0.0)))
	return beacon_position


func _refresh_mission_markers() -> void:
	if _active_sector_scene == null or not is_instance_valid(_active_sector_scene):
		return
	if not _active_sector_scene.has_method("set_mission_markers"):
		return
	var markers: Array[Dictionary] = MissionManager.get_mission_markers_for_sector(GameStateManager.current_sector_id)
	_active_sector_scene.call("set_mission_markers", markers)


func _on_victory_sequence_requested(lines: PackedStringArray) -> void:
	AudioManager.play_music(&"victory_fanfare")
	if victory_overlay != null and is_instance_valid(victory_overlay) and victory_overlay.has_method("show_sequence"):
		victory_overlay.call("show_sequence", lines)
	else:
		for line in lines:
			if line.is_empty():
				continue
			UIManager.show_toast(line, &"success")
	UIManager.show_toast("Post-game content unlocked", &"success")


func _spawn_pending_mission_encounters(sector_id: StringName, sector_data: Dictionary, include_elites: bool) -> void:
	if _active_sector_scene == null or not is_instance_valid(_active_sector_scene):
		return

	_active_boss_ship = null
	if boss_health_bar.has_method("end_encounter"):
		boss_health_bar.call("end_encounter")

	if include_elites and _active_sector_scene.has_method("spawn_runtime_enemy"):
		var elite_spawns: Array[Dictionary] = MissionManager.get_pending_elite_spawns_for_sector(sector_id)
		for spawn_data in elite_spawns:
			var elite_enemy: Node = _active_sector_scene.call("spawn_runtime_enemy", spawn_data)
			if elite_enemy == null:
				continue
			elite_enemy.set_meta("mission_tag", String(spawn_data.get("mission_tag", "")))

	var pending_boss: Dictionary = MissionManager.get_pending_boss_spawn_for_sector(sector_id)
	if pending_boss.is_empty():
		_bind_enemy_destroy_signals()
		return
	if not _active_sector_scene.has_method("spawn_runtime_boss"):
		_bind_enemy_destroy_signals()
		return

	var spawn_position: Vector2 = _pick_boss_spawn_position(sector_data)
	var boss_ship: Node = _active_sector_scene.call("spawn_runtime_boss", {
		"boss_data": pending_boss.get("boss_data", {}),
		"mission_id": String(pending_boss.get("mission_id", "")),
		"objective_id": String(pending_boss.get("objective_id", "")),
		"position": spawn_position,
	})
	if boss_ship == null:
		return

	_active_boss_ship = boss_ship
	if boss_ship.has_signal("boss_intro_requested") and not boss_ship.boss_intro_requested.is_connected(_on_boss_intro_requested):
		boss_ship.boss_intro_requested.connect(_on_boss_intro_requested)
	if boss_ship.has_signal("boss_health_changed") and not boss_ship.boss_health_changed.is_connected(_on_boss_health_changed):
		boss_ship.boss_health_changed.connect(_on_boss_health_changed)
	if boss_ship.has_signal("boss_defeated") and not boss_ship.boss_defeated.is_connected(_on_boss_defeated):
		boss_ship.boss_defeated.connect(_on_boss_defeated)

	MissionManager.register_spawned_boss(
		StringName(String(pending_boss.get("mission_id", ""))),
		StringName(String(pending_boss.get("objective_id", ""))),
		StringName(String(pending_boss.get("boss_id", ""))),
		boss_ship
	)
	UIManager.show_toast("%s detected" % String((pending_boss.get("boss_data", {}) as Dictionary).get("name", "Boss")), &"danger")
	_bind_enemy_destroy_signals()


func _pick_boss_spawn_position(sector_data: Dictionary) -> Vector2:
	var arena_data: Dictionary = sector_data.get("boss_arena", {})
	if not arena_data.is_empty():
		var arena_position: Variant = arena_data.get("position", null)
		if arena_position is Vector2:
			return arena_position
	for patrol_variant in sector_data.get("enemy_patrols", []):
		if patrol_variant is not Dictionary:
			continue
		var patrol_center: Variant = patrol_variant.get("center", null)
		if patrol_center is Vector2:
			return patrol_center
	return Vector2(0.0, -1200.0)


func _on_boss_intro_requested(boss_name: String, max_health: float, total_phases: int) -> void:
	AudioManager.play_sfx(&"boss_appear", Vector2.ZERO)
	AudioManager.play_boss_music()
	if boss_health_bar.has_method("begin_encounter"):
		boss_health_bar.call("begin_encounter", boss_name, max_health, total_phases)


func _on_boss_health_changed(current_health: float, max_health: float, phase_index: int, total_phases: int) -> void:
	if not boss_health_bar.visible and boss_health_bar.has_method("begin_encounter") and _active_boss_ship != null and is_instance_valid(_active_boss_ship):
		var boss_name: String = String(_active_boss_ship.get("display_name"))
		if boss_name.is_empty():
			boss_name = "BOSS"
		boss_health_bar.call("begin_encounter", boss_name.to_upper(), max_health, total_phases)
	if boss_health_bar.has_method("update_encounter"):
		boss_health_bar.call("update_encounter", current_health, phase_index)


func _on_boss_defeated(_boss_id: StringName) -> void:
	AudioManager.end_boss_music()
	if boss_health_bar.has_method("end_encounter"):
		boss_health_bar.call("end_encounter")
	_active_boss_ship = null
