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
@onready var warp_transition_overlay: CanvasLayer = %WarpTransitionOverlay

var _active_sector_scene: Node2D = null
var _active_player_ship: PlayerShip = null
var _docked_station: Node = null
var _is_station_menu_open: bool = false
var _is_map_open: bool = false
var _is_warp_transitioning: bool = false
var _is_game_over_open: bool = false
var _is_wreck_panel_open: bool = false


func _ready() -> void:
	if not GameStateManager.new_game_requested.is_connected(_on_new_game_requested):
		GameStateManager.new_game_requested.connect(_on_new_game_requested)

	if pause_menu.has_signal("resume_requested"):
		pause_menu.connect("resume_requested", _on_pause_resume_requested)
	if pause_menu.has_signal("settings_requested"):
		pause_menu.connect("settings_requested", _on_pause_settings_requested)
	if pause_menu.has_signal("quit_to_menu_requested"):
		pause_menu.connect("quit_to_menu_requested", _on_pause_quit_to_menu_requested)

	if station_menu.has_signal("undock_requested"):
		station_menu.connect("undock_requested", _on_station_menu_undock_requested)
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

	pause_menu.visible = false
	station_menu.visible = false
	galaxy_map_screen.visible = false
	boss_health_bar.visible = true
	if boss_health_bar.has_method("end_encounter"):
		boss_health_bar.call("end_encounter")
	game_over_screen.visible = false
	wreck_recovery_panel.visible = false
	if warp_transition_overlay.has_method("clear_overlay"):
		warp_transition_overlay.call("clear_overlay")

	get_tree().paused = false
	GameStateManager.emit_queued_new_game_request_if_any()


func _unhandled_input(event: InputEvent) -> void:
	if _is_warp_transitioning or _is_game_over_open or _is_wreck_panel_open:
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
	_is_game_over_open = false
	_is_wreck_panel_open = false
	var starting_sector_data: Dictionary = GalaxyManager.start_new_game(starting_sector_id)
	if starting_sector_data.is_empty():
		push_error("GameRoot could not load starting sector: %s" % starting_sector_id)
		return

	load_sector(starting_sector_data, &"")
	var sector_name: String = String(starting_sector_data.get("name", "current"))
	UIManager.show_toast("Welcome to %s sector" % sector_name, &"info")


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


func _on_pause_settings_requested() -> void:
	UIManager.show_toast("Pause settings are not implemented yet.", &"info")


func _on_pause_quit_to_menu_requested() -> void:
	get_tree().paused = false
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

	GameStateManager.is_docked = false
	GameStateManager.docked_station_id = &""
	_is_station_menu_open = false
	get_tree().paused = false

	if _active_player_ship != null and is_instance_valid(_active_player_ship):
		if _docked_station != null and is_instance_valid(_docked_station) and _docked_station.has_method("get_undock_spawn_position"):
			_active_player_ship.global_position = _docked_station.call("get_undock_spawn_position")
		_active_player_ship.velocity = Vector2.ZERO
		_active_player_ship.set_controls_enabled(true)

	_docked_station = null


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

	var repair_fee: int = max(50, int(round(float(GameStateManager.credits) * 0.1)))
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

	UIManager.show_toast("Respawn complete. Return to your wreck beacon to recover cargo.", &"info")


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


func _on_boss_encounter_triggered(boss_name: String, boss_max_health: float, total_phases: int) -> void:
	if boss_health_bar.has_method("begin_encounter"):
		boss_health_bar.call("begin_encounter", boss_name, boss_max_health, total_phases)
