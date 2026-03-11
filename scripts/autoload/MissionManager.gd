extends Node

signal contract_board_updated(station_id: StringName)
signal mission_state_changed
signal mission_progressed(mission_id: StringName)
signal mission_completed(mission_id: StringName)
signal mission_turned_in(mission_id: StringName)
signal mission_accepted(mission_id: StringName)
signal tracked_mission_changed(mission_id: StringName)
signal mission_markers_changed
signal boss_spawn_requested(boss_id: StringName, mission_id: StringName, objective_id: StringName, sector_id: StringName)
signal victory_sequence_requested(lines: PackedStringArray)

const CONTRACT_COUNT_MIN: int = 3
const CONTRACT_COUNT_MAX: int = 5
const CONTRACT_REFRESH_COOLDOWN_SEC: float = 25.0

const GALAXY_REWARD_RANGES: Dictionary = {
	"galaxy_1": Vector2i(100, 300),
	"galaxy_2": Vector2i(300, 800),
	"galaxy_3": Vector2i(800, 2000),
}

const CONTRACT_TYPES_BY_ECONOMY: Dictionary = {
	"industrial": ["mining_quota", "delivery", "destroy_base", "recover_cargo"],
	"research": ["scan_anomaly", "recover_cargo", "delivery", "bounty"],
	"frontier": ["delivery", "rescue", "mining_quota", "escort"],
	"military": ["bounty", "destroy_base", "defend_station", "escort"],
}

var active_missions: Array[Dictionary] = []
var completed_mission_ids: Array[String] = []
var story_flags: Dictionary = {}
var contract_board: Dictionary = {}

var _available_story_mission_ids: Array[String] = []
var _tracked_mission_id: StringName = &""
var _mission_counter: int = 0
var _last_contract_generation_time: Dictionary = {}
var _spawned_boss_objectives: Dictionary = {}
var _active_boss_nodes: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	ContentDatabase.ensure_loaded()
	_rng.seed = hash("mission-manager|%s" % Time.get_unix_time_from_system())
	if not GameStateManager.cargo_changed.is_connected(_on_cargo_changed):
		GameStateManager.cargo_changed.connect(_on_cargo_changed)
	if not GameStateManager.new_game_requested.is_connected(_on_new_game_requested):
		GameStateManager.new_game_requested.connect(_on_new_game_requested)
	reset_for_new_game()


func reset_for_new_game() -> void:
	active_missions.clear()
	completed_mission_ids.clear()
	story_flags.clear()
	contract_board.clear()
	_available_story_mission_ids.clear()
	_tracked_mission_id = &""
	_mission_counter = 0
	_last_contract_generation_time.clear()
	_spawned_boss_objectives.clear()
	_active_boss_nodes.clear()

	var story_templates: Array[Dictionary] = _get_story_templates_sorted()
	if not story_templates.is_empty():
		var first_id: String = String(story_templates[0].get("id", ""))
		if not first_id.is_empty():
			_available_story_mission_ids.append(first_id)
			_set_story_flag("story_chain_started", true)

	mission_state_changed.emit()
	mission_markers_changed.emit()
	tracked_mission_changed.emit(_tracked_mission_id)


func generate_contracts(station_id: StringName, force: bool = false) -> Array[Dictionary]:
	var station_key: String = String(station_id)
	if station_key.is_empty():
		return []

	var now_timestamp: float = Time.get_unix_time_from_system()
	var last_gen_time: float = float(_last_contract_generation_time.get(station_key, -INF))
	if not force and (now_timestamp - last_gen_time) < CONTRACT_REFRESH_COOLDOWN_SEC and contract_board.has(station_key):
		return _clone_mission_array(contract_board[station_key])

	var station_data: Dictionary = EconomyManager.get_station_data(station_id)
	if station_data.is_empty():
		contract_board[station_key] = []
		contract_board_updated.emit(station_id)
		return []

	var templates: Array[Dictionary] = ContentDatabase.get_contract_templates()
	if templates.is_empty():
		contract_board[station_key] = []
		contract_board_updated.emit(station_id)
		return []

	var offer_count: int = _rng.randi_range(CONTRACT_COUNT_MIN, CONTRACT_COUNT_MAX)
	var offers: Array[Dictionary] = []
	for _i in offer_count:
		var template: Dictionary = _pick_contract_template_for_station(templates, station_data)
		if template.is_empty():
			continue
		var offer: Dictionary = _build_contract_offer(template, station_data)
		if offer.is_empty():
			continue
		offers.append(offer)

	contract_board[station_key] = offers
	_last_contract_generation_time[station_key] = now_timestamp
	contract_board_updated.emit(station_id)
	mission_state_changed.emit()
	return _clone_mission_array(offers)


func get_contracts_for_station(station_id: StringName) -> Array[Dictionary]:
	var station_key: String = String(station_id)
	if station_key.is_empty():
		return []
	if not contract_board.has(station_key):
		return []
	return _clone_mission_array(contract_board[station_key])


func get_story_missions_for_station(station_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mission_id in _available_story_mission_ids:
		var template: Dictionary = _get_story_template(StringName(mission_id))
		if template.is_empty():
			continue
		if StringName(String(template.get("source_station_id", ""))) != station_id:
			continue
		var instance: Dictionary = _instantiate_mission_from_template(template, true)
		instance["is_offer"] = true
		result.append(instance)
	return result


func get_active_missions() -> Array[Dictionary]:
	return _clone_mission_array(active_missions)


func get_completed_mission_ids() -> Array[String]:
	return completed_mission_ids.duplicate()


func get_save_state() -> Dictionary:
	var serialized_contract_board: Dictionary = {}
	for station_id_variant in contract_board.keys():
		var station_id: String = String(station_id_variant)
		if station_id.is_empty():
			continue
		serialized_contract_board[station_id] = _serialize_mission_array(contract_board.get(station_id_variant, []))
	return {
		"active_missions": _serialize_mission_array(active_missions),
		"completed_mission_ids": completed_mission_ids.duplicate(),
		"story_flags": story_flags.duplicate(true),
		"contract_board": serialized_contract_board,
		"available_story_mission_ids": _available_story_mission_ids.duplicate(),
		"tracked_mission_id": String(_tracked_mission_id),
		"mission_counter": _mission_counter,
		"last_contract_generation_time": _last_contract_generation_time.duplicate(true),
		"spawned_boss_objectives": _spawned_boss_objectives.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	active_missions = _deserialize_mission_array(state.get("active_missions", []))
	completed_mission_ids = []
	for mission_id_variant in Array(state.get("completed_mission_ids", [])):
		var mission_id: String = String(mission_id_variant)
		if mission_id.is_empty():
			continue
		if not completed_mission_ids.has(mission_id):
			completed_mission_ids.append(mission_id)

	story_flags = {}
	for flag_key_variant in Dictionary(state.get("story_flags", {})).keys():
		var flag_key: String = String(flag_key_variant)
		if flag_key.is_empty():
			continue
		story_flags[flag_key] = bool((state.get("story_flags", {}) as Dictionary).get(flag_key_variant, false))
		GameStateManager.set_progression_flag(StringName(flag_key), bool(story_flags[flag_key]))

	contract_board = {}
	var saved_contract_board: Dictionary = state.get("contract_board", {})
	for station_id_variant in saved_contract_board.keys():
		var station_id: String = String(station_id_variant)
		if station_id.is_empty():
			continue
		contract_board[station_id] = _deserialize_mission_array(saved_contract_board.get(station_id_variant, []))

	_available_story_mission_ids = []
	for story_id_variant in Array(state.get("available_story_mission_ids", [])):
		var story_id: String = String(story_id_variant)
		if story_id.is_empty():
			continue
		if not _available_story_mission_ids.has(story_id):
			_available_story_mission_ids.append(story_id)

	if _available_story_mission_ids.is_empty():
		for template in _get_story_templates_sorted():
			var template_id: String = String(template.get("id", ""))
			if template_id.is_empty():
				continue
			if completed_mission_ids.has(template_id):
				continue
			var is_active: bool = false
			for mission_variant in active_missions:
				if mission_variant is not Dictionary:
					continue
				if String((mission_variant as Dictionary).get("template_id", "")) == template_id:
					is_active = true
					break
			if not is_active:
				_available_story_mission_ids.append(template_id)
			break

	_tracked_mission_id = StringName(String(state.get("tracked_mission_id", "")))
	if _tracked_mission_id != &"" and _find_active_mission_index(_tracked_mission_id) < 0:
		_assign_fallback_tracked_mission()
	_mission_counter = max(int(state.get("mission_counter", active_missions.size())), active_missions.size())
	_last_contract_generation_time = Dictionary(state.get("last_contract_generation_time", {})).duplicate(true)
	_spawned_boss_objectives = Dictionary(state.get("spawned_boss_objectives", {})).duplicate(true)
	_active_boss_nodes.clear()

	mission_state_changed.emit()
	mission_markers_changed.emit()
	tracked_mission_changed.emit(_tracked_mission_id)


func accept_contract(station_id: StringName, mission_id: StringName) -> Dictionary:
	var station_key: String = String(station_id)
	if station_key.is_empty() or not contract_board.has(station_key):
		return {"success": false, "message": "No contract board at this station."}

	var offers: Array = contract_board[station_key]
	var accepted: Dictionary = {}
	for i in offers.size():
		var offer_variant: Variant = offers[i]
		if offer_variant is not Dictionary:
			continue
		var offer: Dictionary = offer_variant
		if StringName(String(offer.get("id", ""))) != mission_id:
			continue
		accepted = offer.duplicate(true)
		offers.remove_at(i)
		break

	if accepted.is_empty():
		return {"success": false, "message": "Contract not found."}

	contract_board[station_key] = offers
	contract_board_updated.emit(station_id)
	return _activate_mission_instance(accepted)


func accept_story_mission(template_id: StringName) -> Dictionary:
	var template_key: String = String(template_id)
	if template_key.is_empty():
		return {"success": false, "message": "Invalid story mission."}
	if not _available_story_mission_ids.has(template_key):
		return {"success": false, "message": "Story mission unavailable."}

	var template: Dictionary = _get_story_template(template_id)
	if template.is_empty():
		return {"success": false, "message": "Story mission template missing."}

	_available_story_mission_ids.erase(template_key)
	var mission_instance: Dictionary = _instantiate_mission_from_template(template, true)
	mission_instance["is_offer"] = false
	return _activate_mission_instance(mission_instance)


func abandon_mission(mission_id: StringName) -> Dictionary:
	for i in active_missions.size():
		var mission_variant: Variant = active_missions[i]
		if mission_variant is not Dictionary:
			continue
		var mission: Dictionary = mission_variant
		if StringName(String(mission.get("id", ""))) != mission_id:
			continue
		var is_story: bool = bool(mission.get("is_story", false))
		active_missions.remove_at(i)
		if is_story:
			var template_id: String = String(mission.get("template_id", ""))
			if not template_id.is_empty() and not _available_story_mission_ids.has(template_id) and not completed_mission_ids.has(template_id):
				_available_story_mission_ids.append(template_id)
		if _tracked_mission_id == mission_id:
			_assign_fallback_tracked_mission()
		mission_state_changed.emit()
		mission_markers_changed.emit()
		return {"success": true}
	return {"success": false, "message": "Mission not active."}


func turn_in_mission(mission_id: StringName, station_id: StringName) -> Dictionary:
	var mission_index: int = _find_active_mission_index(mission_id)
	if mission_index < 0:
		return {"success": false, "message": "Mission not active."}

	var mission: Dictionary = active_missions[mission_index]
	if not _is_mission_completed(mission):
		return {"success": false, "message": "Mission objectives incomplete."}

	var turn_in_station_id: StringName = StringName(String(mission.get("turn_in_station_id", mission.get("source_station_id", ""))))
	if turn_in_station_id != &"" and turn_in_station_id != station_id:
		return {"success": false, "message": "Turn in at the assigned station."}

	if not _consume_turn_in_requirements(mission):
		return {"success": false, "message": "Missing turn-in requirements."}

	_apply_mission_rewards(mission)
	var template_id: String = String(mission.get("template_id", mission.get("id", "")))
	if not template_id.is_empty() and not completed_mission_ids.has(template_id):
		completed_mission_ids.append(template_id)

	active_missions.remove_at(mission_index)
	mission_turned_in.emit(mission_id)
	mission_state_changed.emit()
	mission_markers_changed.emit()
	if _tracked_mission_id == mission_id:
		_assign_fallback_tracked_mission()

	if bool(mission.get("is_story", false)):
		_unlock_next_story_mission(mission)

	SaveManager.autosave()
	return {"success": true, "message": "Mission turned in.", "mission": mission}


func can_turn_in_mission(mission_id: StringName, station_id: StringName) -> bool:
	var mission_index: int = _find_active_mission_index(mission_id)
	if mission_index < 0:
		return false
	var mission: Dictionary = active_missions[mission_index]
	if not _is_mission_completed(mission):
		return false
	var turn_in_station_id: StringName = StringName(String(mission.get("turn_in_station_id", mission.get("source_station_id", ""))))
	if turn_in_station_id == &"":
		return true
	return turn_in_station_id == station_id


func get_tracked_mission_id() -> StringName:
	return _tracked_mission_id


func set_tracked_mission(mission_id: StringName) -> void:
	if mission_id == &"":
		_tracked_mission_id = &""
		tracked_mission_changed.emit(_tracked_mission_id)
		mission_markers_changed.emit()
		return

	if _find_active_mission_index(mission_id) < 0:
		return
	_tracked_mission_id = mission_id
	tracked_mission_changed.emit(_tracked_mission_id)
	mission_markers_changed.emit()


func cycle_tracked_mission() -> void:
	if active_missions.is_empty():
		set_tracked_mission(&"")
		return

	var ids: Array[StringName] = []
	for mission_variant in active_missions:
		if mission_variant is not Dictionary:
			continue
		ids.append(StringName(String((mission_variant as Dictionary).get("id", ""))))
	if ids.is_empty():
		set_tracked_mission(&"")
		return

	if _tracked_mission_id == &"" or not ids.has(_tracked_mission_id):
		set_tracked_mission(ids[0])
		return

	var current_index: int = ids.find(_tracked_mission_id)
	if current_index < 0:
		set_tracked_mission(ids[0])
		return
	var next_index: int = (current_index + 1) % ids.size()
	set_tracked_mission(ids[next_index])


func get_tracked_mission_summary() -> Dictionary:
	if _tracked_mission_id == &"":
		return {}
	var mission: Dictionary = _get_active_mission(_tracked_mission_id)
	if mission.is_empty():
		return {}

	var objective: Dictionary = _get_primary_incomplete_objective(mission)
	if objective.is_empty():
		objective = _get_last_objective(mission)
	return {
		"mission_id": String(mission.get("id", "")),
		"title": String(mission.get("title", "Mission")),
		"objective": objective,
		"objective_text": _format_objective_progress(objective),
	}


func get_tracked_objective_context(current_sector_id: StringName, player_position: Vector2 = Vector2.ZERO) -> Dictionary:
	var mission: Dictionary = _get_active_mission(_tracked_mission_id)
	if mission.is_empty():
		return {"active": false}
	var objective: Dictionary = _get_primary_incomplete_objective(mission)
	if objective.is_empty():
		return {"active": false}

	var objective_sector: StringName = _resolve_objective_sector_id(objective)
	var world_position: Vector2 = Vector2.ZERO
	var same_sector: bool = objective_sector == current_sector_id

	if same_sector:
		world_position = _resolve_objective_world_position(objective, current_sector_id)
	elif objective_sector != &"":
		world_position = _get_gateway_position_toward_sector(current_sector_id, objective_sector)

	var distance: float = 0.0
	if world_position != Vector2.ZERO:
		distance = player_position.distance_to(world_position)

	return {
		"active": true,
		"mission_id": String(mission.get("id", "")),
		"title": String(mission.get("title", "Mission")),
		"objective_text": _format_objective_progress(objective),
		"target_sector_id": String(objective_sector),
		"same_sector": same_sector,
		"world_position": world_position,
		"distance": distance,
	}


func get_mission_markers_for_sector(sector_id: StringName) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if sector_id == &"":
		return markers

	for mission_variant in active_missions:
		if mission_variant is not Dictionary:
			continue
		var mission: Dictionary = mission_variant
		var objective: Dictionary = _get_primary_incomplete_objective(mission)
		if objective.is_empty():
			continue
		var objective_sector: StringName = _resolve_objective_sector_id(objective)
		if objective_sector != sector_id:
			continue
		var marker_position: Vector2 = _resolve_objective_world_position(objective, sector_id)
		if marker_position == Vector2.ZERO:
			continue
		markers.append({
			"id": String(objective.get("id", "")),
			"mission_id": String(mission.get("id", "")),
			"label": String(mission.get("title", "Mission")),
			"objective_text": _format_objective_progress(objective),
			"position": marker_position,
		})
	return markers


func get_pending_boss_spawn_for_sector(sector_id: StringName) -> Dictionary:
	for mission_variant in active_missions:
		if mission_variant is not Dictionary:
			continue
		var mission: Dictionary = mission_variant
		var mission_id: String = String(mission.get("id", ""))
		if mission_id.is_empty():
			continue
		var objectives: Array = mission.get("objectives", [])
		for objective_variant in objectives:
			if objective_variant is not Dictionary:
				continue
			var objective: Dictionary = objective_variant
			if String(objective.get("type", "")) != "defeat_boss":
				continue
			if not bool(objective.get("boss_spawn", false)):
				continue
			if _is_objective_complete(objective):
				continue
			var objective_id: String = String(objective.get("id", ""))
			if _spawned_boss_objectives.has("%s:%s" % [mission_id, objective_id]):
				continue
			var objective_sector: StringName = _resolve_objective_sector_id(objective)
			if objective_sector != sector_id:
				continue
			if not _is_objective_unlocked(mission, objective):
				continue

			var boss_id: StringName = StringName(String(objective.get("target", "")))
			if boss_id == &"":
				continue
			var boss_data: Dictionary = ContentDatabase.get_boss_archetype_definition(boss_id)
			if boss_data.is_empty():
				continue
			return {
				"mission_id": mission_id,
				"objective_id": objective_id,
				"boss_id": String(boss_id),
				"boss_data": boss_data,
			}
	return {}


func get_pending_elite_spawns_for_sector(sector_id: StringName) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	for mission_variant in active_missions:
		if mission_variant is not Dictionary:
			continue
		var mission: Dictionary = mission_variant
		if not mission.has("elite_spawn"):
			continue
		var elite_spawn: Dictionary = mission.get("elite_spawn", {})
		if elite_spawn.is_empty():
			continue
		if StringName(String(elite_spawn.get("sector_id", ""))) != sector_id:
			continue
		var objective: Dictionary = _get_primary_incomplete_objective(mission)
		if objective.is_empty():
			continue
		if String(objective.get("type", "")) != "destroy_enemy":
			continue
		var spawn_data: Dictionary = elite_spawn.duplicate(true)
		spawn_data["mission_id"] = String(mission.get("id", ""))
		spawn_data["position"] = _resolve_objective_world_position(objective, sector_id)
		spawns.append(spawn_data)
	return spawns


func format_objective_progress(objective: Dictionary) -> String:
	return _format_objective_progress(objective)


func register_spawned_boss(mission_id: StringName, objective_id: StringName, boss_id: StringName, boss_node: Node) -> void:
	var key: String = "%s:%s" % [String(mission_id), String(objective_id)]
	_spawned_boss_objectives[key] = String(boss_id)
	if boss_node != null and is_instance_valid(boss_node):
		_active_boss_nodes[String(boss_id)] = boss_node
	mission_markers_changed.emit()


func report_sector_entered(sector_id: StringName) -> void:
	if sector_id == &"":
		return

	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if String(objective.get("type", "")) != "reach_sector":
				continue
			if not _is_objective_unlocked(mission, objective):
				continue
			if StringName(String(objective.get("target", ""))) != sector_id:
				continue
			changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)

	mission_markers_changed.emit()
	mission_state_changed.emit()


func report_player_position(sector_id: StringName, player_position: Vector2) -> void:
	if sector_id == &"":
		return
	var any_changed: bool = false
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if String(objective.get("type", "")) != "reach_point":
				continue
			if not _is_objective_unlocked(mission, objective):
				continue
			if StringName(String(objective.get("sector_id", ""))) != sector_id:
				continue
			var point: Vector2 = _coerce_vector2(objective.get("world_position", Vector2.ZERO))
			if point == Vector2.ZERO:
				continue
			var radius: float = float(objective.get("radius", 180.0))
			if player_position.distance_to(point) > radius:
				continue
			changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			any_changed = true
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)
	if any_changed:
		mission_state_changed.emit()
		mission_markers_changed.emit()


func report_player_docked(station_id: StringName) -> void:
	if station_id == &"":
		return

	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			var objective_type: String = String(objective.get("type", ""))
			if objective_type == "dock_station":
				if StringName(String(objective.get("target", ""))) == station_id:
					changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
			elif objective_type == "deliver_item":
				if StringName(String(objective.get("station_id", ""))) != station_id:
					continue
				var item_id: StringName = StringName(String(objective.get("target", "")))
				var required: int = max(int(objective.get("required", 1)), 1)
				if not GameStateManager.has_cargo(item_id, required):
					continue
				if bool(objective.get("consume_on_complete", true)):
					GameStateManager.remove_cargo(item_id, required)
				changed = _set_objective_progress(mission, j, required) or changed
			elif objective_type == "turn_in_station":
				if StringName(String(objective.get("target", ""))) == station_id:
					changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)

	generate_contracts(station_id)
	mission_markers_changed.emit()
	mission_state_changed.emit()


func report_item_sold(item_id: StringName, quantity: int, station_id: StringName) -> void:
	if quantity <= 0:
		return
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			if String(objective.get("type", "")) != "sell_item":
				continue
			if StringName(String(objective.get("target", ""))) != item_id:
				continue
			var station_requirement: StringName = StringName(String(objective.get("station_id", "")))
			if station_requirement != &"" and station_requirement != station_id:
				continue
			var next_value: int = int(objective.get("current", 0)) + quantity
			changed = _set_objective_progress(mission, j, next_value) or changed
		if changed:
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)
	mission_state_changed.emit()


func report_enemy_destroyed(archetype_id: StringName, faction: StringName, sector_id: StringName, is_boss: bool = false, boss_id: StringName = &"", mission_tag: StringName = &"") -> void:
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			var objective_type: String = String(objective.get("type", ""))
			if objective_type == "destroy_enemy":
				var required_sector: StringName = StringName(String(objective.get("sector_id", "")))
				if required_sector != &"" and required_sector != sector_id:
					continue
				var match_mode: String = String(objective.get("match_mode", "archetype"))
				if match_mode == "faction":
					if StringName(String(objective.get("faction", ""))) != faction:
						continue
				elif StringName(String(objective.get("target", ""))) != archetype_id:
					continue
				if StringName(String(objective.get("mission_tag", ""))) != &"" and StringName(String(objective.get("mission_tag", ""))) != mission_tag:
					continue
				changed = _set_objective_progress(mission, j, int(objective.get("current", 0)) + 1) or changed
			elif objective_type == "defeat_boss":
				if not is_boss:
					continue
				if StringName(String(objective.get("target", ""))) != boss_id:
					continue
				changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)

	if is_boss and boss_id != &"":
		_active_boss_nodes.erase(String(boss_id))
	mission_markers_changed.emit()
	mission_state_changed.emit()


func report_anomaly_scanned(anomaly_id: StringName, anomaly_type: StringName, sector_id: StringName) -> void:
	var any_changed: bool = false
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			if String(objective.get("type", "")) != "scan_anomaly":
				continue
			var required_sector: StringName = StringName(String(objective.get("sector_id", "")))
			if required_sector != &"" and required_sector != sector_id:
				continue
			var target_id: StringName = StringName(String(objective.get("target", "")))
			if target_id != &"" and target_id != anomaly_id:
				continue
			var target_type: StringName = StringName(String(objective.get("anomaly_type", "")))
			if target_type != &"" and target_type != anomaly_type:
				continue
			changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			any_changed = true
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)
	if any_changed:
		mission_state_changed.emit()
		mission_markers_changed.emit()


func report_anomaly_interacted(anomaly_id: StringName, anomaly_type: StringName, sector_id: StringName) -> void:
	var any_changed: bool = false
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			if String(objective.get("type", "")) != "interact_anomaly":
				continue
			var required_sector: StringName = StringName(String(objective.get("sector_id", "")))
			if required_sector != &"" and required_sector != sector_id:
				continue
			var target_id: StringName = StringName(String(objective.get("target", "")))
			if target_id != &"" and target_id != anomaly_id:
				continue
			var target_type: StringName = StringName(String(objective.get("anomaly_type", "")))
			if target_type != &"" and target_type != anomaly_type:
				continue
			changed = _set_objective_progress(mission, j, int(objective.get("required", 1))) or changed
		if changed:
			any_changed = true
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)
	if any_changed:
		mission_state_changed.emit()
		mission_markers_changed.emit()


func report_loot_collected(contents: Array[Dictionary], sector_id: StringName) -> void:
	var unit_count: int = 0
	for entry_variant in contents:
		if entry_variant is not Dictionary:
			continue
		unit_count += max(int((entry_variant as Dictionary).get("quantity", 0)), 0)
	if unit_count <= 0:
		return

	var any_changed: bool = false
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if not _is_objective_unlocked(mission, objective):
				continue
			if String(objective.get("type", "")) != "collect_loot":
				continue
			var required_sector: StringName = StringName(String(objective.get("sector_id", "")))
			if required_sector != &"" and required_sector != sector_id:
				continue
			changed = _set_objective_progress(mission, j, int(objective.get("current", 0)) + unit_count) or changed
		if changed:
			any_changed = true
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)
	if any_changed:
		mission_state_changed.emit()
		mission_markers_changed.emit()


func get_story_flag(flag_id: StringName) -> bool:
	return bool(story_flags.get(String(flag_id), false))


func set_story_flag(flag_id: StringName, enabled: bool = true) -> void:
	_set_story_flag(String(flag_id), enabled)


func _on_new_game_requested(_starting_sector_id: StringName) -> void:
	reset_for_new_game()


func _on_cargo_changed() -> void:
	_refresh_collect_item_objectives()


func _refresh_collect_item_objectives() -> void:
	var any_changed: bool = false
	for i in active_missions.size():
		var mission: Dictionary = active_missions[i]
		var changed: bool = false
		for j in _get_objective_count(mission):
			var objective: Dictionary = _get_objective(mission, j)
			if String(objective.get("type", "")) != "collect_item":
				continue
			if not _is_objective_unlocked(mission, objective):
				continue
			var item_id: StringName = StringName(String(objective.get("target", "")))
			var required: int = max(int(objective.get("required", 1)), 1)
			var quantity: int = _get_inventory_quantity(item_id)
			changed = _set_objective_progress(mission, j, min(quantity, required)) or changed
		if changed:
			any_changed = true
			active_missions[i] = mission
			mission_progressed.emit(StringName(String(mission.get("id", ""))))
			_try_complete_mission(i)

	if any_changed:
		mission_state_changed.emit()
		mission_markers_changed.emit()


func _activate_mission_instance(instance: Dictionary) -> Dictionary:
	var mission_id: String = String(instance.get("id", ""))
	if mission_id.is_empty():
		mission_id = _generate_mission_instance_id(String(instance.get("template_id", "mission")))
		instance["id"] = mission_id

	instance["accepted_time"] = Time.get_unix_time_from_system()
	instance["status"] = "active"
	instance["is_offer"] = false
	active_missions.append(instance)

	if _tracked_mission_id == &"":
		_tracked_mission_id = StringName(mission_id)
		tracked_mission_changed.emit(_tracked_mission_id)

	var grants: Array = instance.get("grant_on_accept", [])
	for grant_variant in grants:
		if grant_variant is not Dictionary:
			continue
		var grant: Dictionary = grant_variant
		var item_id: StringName = StringName(String(grant.get("item_id", "")))
		var quantity: int = max(int(grant.get("quantity", 0)), 0)
		if item_id == &"" or quantity <= 0:
			continue
		GameStateManager.add_cargo(item_id, quantity)

	mission_accepted.emit(StringName(mission_id))
	AudioManager.play_sfx(&"mission_accept", Vector2.ZERO)
	mission_state_changed.emit()
	mission_markers_changed.emit()
	return {"success": true, "message": "Mission accepted.", "mission": instance}


func _try_complete_mission(mission_index: int) -> void:
	if mission_index < 0 or mission_index >= active_missions.size():
		return
	var mission: Dictionary = active_missions[mission_index]
	if _is_mission_completed(mission):
		if String(mission.get("status", "")) == "completed":
			return
		mission["status"] = "completed"
		active_missions[mission_index] = mission
		mission_completed.emit(StringName(String(mission.get("id", ""))))
		UIManager.show_toast("Mission complete: %s" % String(mission.get("title", "Mission")), &"success")
		AudioManager.play_sfx(&"mission_complete", Vector2.ZERO)
		SaveManager.autosave()
		if bool(mission.get("auto_turn_in", false)):
			var mission_id: StringName = StringName(String(mission.get("id", "")))
			var turn_in_station: StringName = StringName(String(mission.get("turn_in_station_id", mission.get("source_station_id", ""))))
			var auto_station: StringName = turn_in_station if turn_in_station != &"" else GameStateManager.last_docked_station_id
			turn_in_mission(mission_id, auto_station)


func _is_mission_completed(mission: Dictionary) -> bool:
	var objectives: Array = mission.get("objectives", [])
	if objectives.is_empty():
		return false
	for objective_variant in objectives:
		if objective_variant is not Dictionary:
			continue
		if not _is_objective_complete(objective_variant as Dictionary):
			return false
	return true


func _is_objective_complete(objective: Dictionary) -> bool:
	return int(objective.get("current", 0)) >= max(int(objective.get("required", 1)), 1)


func _set_objective_progress(mission: Dictionary, objective_index: int, next_value: int) -> bool:
	var objectives: Array = mission.get("objectives", [])
	if objective_index < 0 or objective_index >= objectives.size():
		return false
	var objective_variant: Variant = objectives[objective_index]
	if objective_variant is not Dictionary:
		return false
	var objective: Dictionary = objective_variant
	var required: int = max(int(objective.get("required", 1)), 1)
	var clamped_value: int = clampi(next_value, 0, required)
	if clamped_value == int(objective.get("current", 0)):
		return false
	objective["current"] = clamped_value
	objectives[objective_index] = objective
	mission["objectives"] = objectives
	return true


func _get_primary_incomplete_objective(mission: Dictionary) -> Dictionary:
	var objectives: Array = mission.get("objectives", [])
	for objective_variant in objectives:
		if objective_variant is not Dictionary:
			continue
		var objective: Dictionary = objective_variant
		if not _is_objective_unlocked(mission, objective):
			continue
		if _is_objective_complete(objective):
			continue
		return objective.duplicate(true)
	return {}


func _get_last_objective(mission: Dictionary) -> Dictionary:
	var objectives: Array = mission.get("objectives", [])
	if objectives.is_empty():
		return {}
	var objective_variant: Variant = objectives[objectives.size() - 1]
	if objective_variant is not Dictionary:
		return {}
	return (objective_variant as Dictionary).duplicate(true)


func _is_objective_unlocked(mission: Dictionary, objective: Dictionary) -> bool:
	var required_objective_id: String = String(objective.get("requires_objective_complete", ""))
	if not required_objective_id.is_empty():
		return _is_mission_objective_complete(mission, required_objective_id)
	return true


func _is_mission_objective_complete(mission: Dictionary, objective_id: String) -> bool:
	for objective_variant in mission.get("objectives", []):
		if objective_variant is not Dictionary:
			continue
		var objective: Dictionary = objective_variant
		if String(objective.get("id", "")) != objective_id:
			continue
		return _is_objective_complete(objective)
	return false


func _resolve_objective_sector_id(objective: Dictionary) -> StringName:
	var sector_id: StringName = StringName(String(objective.get("sector_id", "")))
	if sector_id != &"":
		return sector_id

	var station_id: StringName = StringName(String(objective.get("station_id", objective.get("target", ""))))
	if station_id != &"":
		return _find_sector_for_station(station_id)
	return &""


func _resolve_objective_world_position(objective: Dictionary, sector_id: StringName) -> Vector2:
	if objective.has("world_position"):
		var objective_pos: Vector2 = _coerce_vector2(objective.get("world_position"))
		if objective_pos != Vector2.ZERO:
			return objective_pos

	var objective_type: String = String(objective.get("type", ""))
	if objective_type == "dock_station" or objective_type == "turn_in_station" or objective_type == "deliver_item":
		var station_id: StringName = StringName(String(objective.get("station_id", objective.get("target", ""))))
		var station_position: Variant = _find_station_position(station_id)
		if station_position is Vector2 and _find_sector_for_station(station_id) == sector_id:
			return station_position

	if objective_type == "scan_anomaly" or objective_type == "interact_anomaly":
		var target_anomaly_id: String = String(objective.get("target", ""))
		if not target_anomaly_id.is_empty():
			var anomaly_position: Vector2 = _find_anomaly_position(sector_id, target_anomaly_id)
			if anomaly_position != Vector2.ZERO:
				return anomaly_position
		var anomaly_type: String = String(objective.get("anomaly_type", ""))
		if not anomaly_type.is_empty():
			var typed_position: Vector2 = _find_anomaly_position_by_type(sector_id, anomaly_type)
			if typed_position != Vector2.ZERO:
				return typed_position
		var fallback_anomaly_position: Vector2 = _find_first_anomaly_position(sector_id)
		if fallback_anomaly_position != Vector2.ZERO:
			return fallback_anomaly_position

	if objective_type == "defeat_boss":
		var boss_id: String = String(objective.get("target", ""))
		if _active_boss_nodes.has(boss_id):
			var boss_node: Node = _active_boss_nodes[boss_id]
			if boss_node is Node2D and is_instance_valid(boss_node):
				return (boss_node as Node2D).global_position
		var sector_boss_arena: Dictionary = ContentDatabase.get_sector(sector_id).get("boss_arena", {})
		if not sector_boss_arena.is_empty():
			var arena_pos: Variant = sector_boss_arena.get("position", null)
			if arena_pos is Vector2:
				return arena_pos

	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	if not sector_data.is_empty():
		if sector_data.has("station"):
			var station_data: Dictionary = sector_data.get("station", {})
			if not station_data.is_empty():
				var station_pos: Variant = station_data.get("position", null)
				if station_pos is Vector2:
					return station_pos
	return Vector2.ZERO


func _get_gateway_position_toward_sector(from_sector_id: StringName, target_sector_id: StringName) -> Vector2:
	if from_sector_id == &"" or target_sector_id == &"":
		return Vector2.ZERO
	if from_sector_id == target_sector_id:
		return Vector2.ZERO

	var next_sector: StringName = _find_next_sector_in_path(from_sector_id, target_sector_id)
	if next_sector == &"":
		return Vector2.ZERO

	var from_sector_data: Dictionary = ContentDatabase.get_sector(from_sector_id)
	for gate_variant in from_sector_data.get("warp_gates", []):
		if gate_variant is not Dictionary:
			continue
		var gate_data: Dictionary = gate_variant
		if StringName(String(gate_data.get("destination_sector_id", ""))) != next_sector:
			continue
		var gate_position: Variant = gate_data.get("position", null)
		if gate_position is Vector2:
			return gate_position
	return Vector2.ZERO


func _find_next_sector_in_path(start_sector_id: StringName, target_sector_id: StringName) -> StringName:
	if start_sector_id == target_sector_id:
		return start_sector_id
	var visited: Dictionary = {}
	var queue: Array[StringName] = [start_sector_id]
	var parent: Dictionary = {}
	visited[String(start_sector_id)] = true

	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if current == target_sector_id:
			break
		var sector_data: Dictionary = ContentDatabase.get_sector(current)
		for connection_variant in sector_data.get("connections", []):
			if connection_variant is not Dictionary:
				continue
			var connection: Dictionary = connection_variant
			var neighbor: StringName = StringName(String(connection.get("sector_id", "")))
			if neighbor == &"":
				continue
			if visited.has(String(neighbor)):
				continue
			visited[String(neighbor)] = true
			parent[String(neighbor)] = String(current)
			queue.append(neighbor)

	if not visited.has(String(target_sector_id)):
		return &""

	var step: String = String(target_sector_id)
	while parent.has(step):
		var previous: String = String(parent[step])
		if previous == String(start_sector_id):
			return StringName(step)
		step = previous
	return &""


func _find_sector_for_station(station_id: StringName) -> StringName:
	if station_id == &"":
		return &""
	for sector_variant in ContentDatabase.get_all_sectors().values():
		if sector_variant is not Dictionary:
			continue
		var sector_data: Dictionary = sector_variant
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			continue
		if StringName(String(station_data.get("id", ""))) == station_id:
			return StringName(String(sector_data.get("id", "")))
	return &""


func _find_station_position(station_id: StringName) -> Variant:
	if station_id == &"":
		return null
	for sector_variant in ContentDatabase.get_all_sectors().values():
		if sector_variant is not Dictionary:
			continue
		var sector_data: Dictionary = sector_variant
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			continue
		if StringName(String(station_data.get("id", ""))) != station_id:
			continue
		return station_data.get("position", null)
	return null


func _find_anomaly_position(sector_id: StringName, anomaly_id: String) -> Vector2:
	if sector_id == &"" or anomaly_id.is_empty():
		return Vector2.ZERO
	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	for anomaly_variant in sector_data.get("anomaly_points", []):
		if anomaly_variant is not Dictionary:
			continue
		var anomaly: Dictionary = anomaly_variant
		if String(anomaly.get("id", "")) != anomaly_id:
			continue
		var position_variant: Variant = anomaly.get("position", null)
		if position_variant is Vector2:
			return position_variant
	return Vector2.ZERO


func _find_anomaly_position_by_type(sector_id: StringName, anomaly_type: String) -> Vector2:
	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	for anomaly_variant in sector_data.get("anomaly_points", []):
		if anomaly_variant is not Dictionary:
			continue
		var anomaly: Dictionary = anomaly_variant
		if String(anomaly.get("type", "")) != anomaly_type:
			continue
		var position_variant: Variant = anomaly.get("position", null)
		if position_variant is Vector2:
			return position_variant
	return Vector2.ZERO


func _find_first_anomaly_position(sector_id: StringName) -> Vector2:
	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	for anomaly_variant in sector_data.get("anomaly_points", []):
		if anomaly_variant is not Dictionary:
			continue
		var anomaly: Dictionary = anomaly_variant
		var position_variant: Variant = anomaly.get("position", null)
		if position_variant is Vector2:
			return position_variant
	return Vector2.ZERO


func _build_contract_offer(template: Dictionary, station_data: Dictionary) -> Dictionary:
	var template_id: String = String(template.get("id", ""))
	var contract_type: String = String(template.get("type", ""))
	if template_id.is_empty() or contract_type.is_empty():
		return {}

	var source_station_id: StringName = StringName(String(station_data.get("id", "")))
	var source_station_name: String = String(station_data.get("name", "Station"))
	var source_sector_id: StringName = _find_sector_for_station(source_station_id)
	if source_sector_id == &"":
		source_sector_id = GameStateManager.current_sector_id
	var source_sector: Dictionary = ContentDatabase.get_sector(source_sector_id)
	var galaxy_id: String = String(source_sector.get("galaxy_id", "galaxy_1"))

	var reward_range: Vector2i = _get_reward_range_for_galaxy(galaxy_id)
	var reward_scale: float = float(template.get("reward_scale", 1.0))
	var progression_scale: float = _get_progression_difficulty_scale()
	var base_reward: int = _rng.randi_range(reward_range.x, reward_range.y)
	var reward_credits: int = int(round(float(base_reward) * reward_scale * progression_scale))
	if get_story_flag(&"game_complete"):
		reward_credits = int(round(float(reward_credits) * 1.25))

	var mission: Dictionary = {
		"id": _generate_mission_instance_id(template_id),
		"template_id": template_id,
		"type": contract_type,
		"title": String(template.get("title", "Contract")),
		"description": String(template.get("description", "")),
		"objectives": [],
		"rewards": {
			"credits": reward_credits,
			"materials": {},
			"items": [],
			"flags": [],
		},
		"source_station_id": String(source_station_id),
		"turn_in_station_id": String(source_station_id),
		"is_story": false,
		"auto_turn_in": false,
	}

	match contract_type:
		"mining_quota":
			var resource_id: StringName = _pick_contract_resource_id(template, galaxy_id)
			var required_amount: int = _pick_required_amount(template)
			var item_name: String = _get_item_name(resource_id)
			mission["title"] = "Mining Quota: %s" % item_name
			mission["description"] = "Collect %d %s and return to %s." % [required_amount, item_name, source_station_name]
			mission["objectives"] = [
				{"id": "%s_collect" % template_id, "type": "collect_item", "target": String(resource_id), "current": 0, "required": required_amount, "sector_id": ""},
				{"id": "%s_return" % template_id, "type": "turn_in_station", "target": String(source_station_id), "current": 0, "required": 1},
			]
		"delivery":
			var destination_station: Dictionary = _pick_destination_station(source_station_id)
			if destination_station.is_empty():
				return {}
			var commodity_id: StringName = _pick_commodity_id(template)
			var delivery_amount: int = _pick_required_amount(template)
			var commodity_name: String = _get_item_name(commodity_id)
			mission["title"] = "Courier: %s" % commodity_name
			mission["description"] = "Deliver %d %s to %s." % [delivery_amount, commodity_name, String(destination_station.get("name", "Destination"))]
			mission["turn_in_station_id"] = String(destination_station.get("id", ""))
			mission["grant_on_accept"] = [{"item_id": String(commodity_id), "quantity": delivery_amount}]
			mission["objectives"] = [
				{"id": "%s_deliver" % template_id, "type": "deliver_item", "target": String(commodity_id), "current": 0, "required": delivery_amount, "station_id": String(destination_station.get("id", "")), "consume_on_complete": true},
			]
		"bounty":
			var target_sector_id: StringName = _pick_target_sector(source_sector_id)
			var elite_archetype: StringName = _pick_elite_archetype(template, galaxy_id)
			var elite_name: String = "%s (Elite)" % _get_enemy_name(elite_archetype)
			mission["title"] = "Bounty Hunt: %s" % elite_name
			mission["description"] = "Destroy %s in %s." % [elite_name, _get_sector_name(target_sector_id)]
			mission["objectives"] = [
				{"id": "%s_elite" % template_id, "type": "destroy_enemy", "target": String(elite_archetype), "current": 0, "required": 1, "sector_id": String(target_sector_id), "mission_tag": String(mission["id"]), "match_mode": "archetype"},
			]
			mission["elite_spawn"] = {
				"archetype_id": String(elite_archetype),
				"sector_id": String(target_sector_id),
				"display_name": elite_name,
				"hull_multiplier": 1.25,
				"shield_multiplier": 1.25,
				"damage_multiplier": 1.25,
				"mission_tag": String(mission["id"]),
			}
		"escort":
			var escort_sector: StringName = _pick_target_sector(source_sector_id)
			var escort_kills: int = _pick_required_amount(template)
			mission["title"] = "Escort Through %s" % _get_sector_name(escort_sector)
			mission["description"] = "Protect convoy transit and defeat %d hostiles in %s." % [escort_kills, _get_sector_name(escort_sector)]
			mission["objectives"] = [
				{"id": "%s_reach" % template_id, "type": "reach_sector", "target": String(escort_sector), "current": 0, "required": 1, "sector_id": String(escort_sector)},
				{"id": "%s_clear" % template_id, "type": "destroy_enemy", "target": "", "match_mode": "any", "current": 0, "required": max(escort_kills, 2), "sector_id": String(escort_sector)},
			]
		"rescue":
			var rescue_sector: StringName = _pick_target_sector(source_sector_id)
			mission["title"] = "Rescue Operation"
			mission["description"] = "Investigate distress signal in %s and return to %s." % [_get_sector_name(rescue_sector), source_station_name]
			mission["objectives"] = [
				{"id": "%s_scan" % template_id, "type": "interact_anomaly", "target": "", "anomaly_type": "distress_signal", "current": 0, "required": 1, "sector_id": String(rescue_sector)},
				{"id": "%s_return" % template_id, "type": "dock_station", "target": String(source_station_id), "current": 0, "required": 1},
			]
		"scan_anomaly":
			var scan_sector: StringName = _pick_target_sector(source_sector_id)
			mission["title"] = "Anomaly Survey"
			mission["description"] = "Scan a marked anomaly in %s." % _get_sector_name(scan_sector)
			mission["objectives"] = [
				{"id": "%s_scan" % template_id, "type": "scan_anomaly", "target": "", "current": 0, "required": 1, "sector_id": String(scan_sector)},
			]
		"destroy_base":
			var base_sector: StringName = _pick_target_sector(source_sector_id)
			var base_kills: int = max(_pick_required_amount(template), 4)
			mission["title"] = "Destroy Hostile Base"
			mission["description"] = "Clear hostile outpost defenders in %s (%d kills)." % [_get_sector_name(base_sector), base_kills]
			mission["objectives"] = [
				{"id": "%s_reach" % template_id, "type": "reach_sector", "target": String(base_sector), "current": 0, "required": 1, "sector_id": String(base_sector)},
				{"id": "%s_clear" % template_id, "type": "destroy_enemy", "target": "", "match_mode": "any", "current": 0, "required": base_kills, "sector_id": String(base_sector)},
			]
		"recover_cargo":
			var cargo_sector: StringName = _pick_target_sector(source_sector_id)
			var cargo_amount: int = max(_pick_required_amount(template), 2)
			mission["title"] = "Recover Cargo"
			mission["description"] = "Recover %d cargo units from loot in %s." % [cargo_amount, _get_sector_name(cargo_sector)]
			mission["objectives"] = [
				{"id": "%s_collect" % template_id, "type": "collect_loot", "target": "", "current": 0, "required": cargo_amount, "sector_id": String(cargo_sector)},
			]
		"defend_station":
			var defend_kills: int = max(_pick_required_amount(template), 6)
			mission["title"] = "Defend %s" % source_station_name
			mission["description"] = "Repel %d hostile wave ships near %s." % [defend_kills, source_station_name]
			mission["objectives"] = [
				{"id": "%s_clear" % template_id, "type": "destroy_enemy", "target": "", "match_mode": "any", "current": 0, "required": defend_kills, "sector_id": String(source_sector_id)},
			]
		"cleanup":
			var cleanup_sector: StringName = _pick_target_sector(source_sector_id)
			var cleanup_required: int = max(_pick_required_amount(template), 8)
			mission["title"] = "Cleanup Operation"
			mission["description"] = "Eliminate %d hostiles in %s." % [cleanup_required, _get_sector_name(cleanup_sector)]
			mission["objectives"] = [
				{"id": "%s_cleanup" % template_id, "type": "destroy_enemy", "target": "", "match_mode": "any", "current": 0, "required": cleanup_required, "sector_id": String(cleanup_sector)},
			]
		"artifact_hunt":
			var artifact_sector: StringName = _pick_target_sector(source_sector_id)
			var artifact_count: int = max(_pick_required_amount(template), 1)
			mission["title"] = "Artifact Hunt"
			mission["description"] = "Recover %d relic artifacts from anomalies in %s." % [artifact_count, _get_sector_name(artifact_sector)]
			mission["objectives"] = [
				{"id": "%s_relic" % template_id, "type": "interact_anomaly", "target": "", "anomaly_type": "relic_fragment", "current": 0, "required": artifact_count, "sector_id": String(artifact_sector)},
			]
		_:
			return {}

	return mission


func _get_reward_range_for_galaxy(galaxy_id: String) -> Vector2i:
	var fallback: Vector2i = GALAXY_REWARD_RANGES.get(galaxy_id, Vector2i(100, 300))
	var contract_config: Dictionary = ContentDatabase.get_balance_config_data().get("contract_rewards", {})
	if contract_config.is_empty() or not contract_config.has(galaxy_id):
		return fallback
	var range_data: Dictionary = contract_config.get(galaxy_id, {})
	var min_value: int = int(range_data.get("min", fallback.x))
	var max_value: int = int(range_data.get("max", fallback.y))
	if max_value < min_value:
		max_value = min_value
	return Vector2i(min_value, max_value)


func _instantiate_mission_from_template(template: Dictionary, is_story: bool) -> Dictionary:
	var mission: Dictionary = template.duplicate(true)
	var template_id: String = String(template.get("id", "mission"))
	mission["template_id"] = template_id
	mission["id"] = _generate_mission_instance_id(template_id)
	mission["type"] = String(template.get("type", template_id))
	mission["is_story"] = is_story
	mission["is_offer"] = false
	mission["status"] = "active"
	for i in _get_objective_count(mission):
		var objective: Dictionary = _get_objective(mission, i)
		objective["current"] = int(objective.get("current", 0))
		_set_objective_direct(mission, i, objective)
	return mission


func _set_objective_direct(mission: Dictionary, index: int, objective: Dictionary) -> void:
	var objectives: Array = mission.get("objectives", [])
	if index < 0 or index >= objectives.size():
		return
	objectives[index] = objective
	mission["objectives"] = objectives


func _pick_contract_template_for_station(templates: Array[Dictionary], station_data: Dictionary) -> Dictionary:
	var economy_type: String = String(station_data.get("economy_type", "frontier"))
	var allowed_types: Array = CONTRACT_TYPES_BY_ECONOMY.get(economy_type, [])
	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []

	for template in templates:
		var template_type: String = String(template.get("type", ""))
		if template_type.is_empty():
			continue
		if bool(template.get("post_game_only", false)) and not get_story_flag(&"game_complete"):
			continue
		if not bool(template.get("post_game_only", false)) and get_story_flag(&"game_complete"):
			# Keep regular contracts available post-game, but bias to post-game templates.
			pass
		if not allowed_types.is_empty() and not allowed_types.has(template_type) and not bool(template.get("post_game_only", false)):
			continue
		var weight_by_economy: Dictionary = template.get("weight_by_economy", {})
		var weight: float = float(weight_by_economy.get(economy_type, 1.0))
		if get_story_flag(&"game_complete") and bool(template.get("post_game_only", false)):
			weight *= 2.4
		if weight <= 0.0:
			continue
		candidates.append(template)
		weights.append(weight)

	if candidates.is_empty():
		return {}
	return _weighted_pick(candidates, weights)


func _weighted_pick(candidates: Array[Dictionary], weights: Array[float]) -> Dictionary:
	var total_weight: float = 0.0
	for weight in weights:
		total_weight += maxf(weight, 0.0)
	if total_weight <= 0.0:
		return candidates[0].duplicate(true)
	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for i in candidates.size():
		cursor += maxf(weights[i], 0.0)
		if roll <= cursor:
			return candidates[i].duplicate(true)
	return candidates.back().duplicate(true)


func _pick_target_sector(source_sector_id: StringName) -> StringName:
	var source_sector: Dictionary = ContentDatabase.get_sector(source_sector_id)
	var galaxy_id: StringName = StringName(String(source_sector.get("galaxy_id", "")))
	var candidates: Array[StringName] = []
	for sector_variant in ContentDatabase.get_all_sectors().values():
		if sector_variant is not Dictionary:
			continue
		var sector_data: Dictionary = sector_variant
		var sector_id: StringName = StringName(String(sector_data.get("id", "")))
		if sector_id == &"" or sector_id == source_sector_id:
			continue
		if StringName(String(sector_data.get("galaxy_id", ""))) != galaxy_id and not GameStateManager.is_sector_discovered(sector_id):
			continue
		if not GameStateManager.is_sector_discovered(sector_id):
			continue
		candidates.append(sector_id)

	if candidates.is_empty():
		for connection_variant in source_sector.get("connections", []):
			if connection_variant is not Dictionary:
				continue
			var connection: Dictionary = connection_variant
			var neighbor: StringName = StringName(String(connection.get("sector_id", "")))
			if neighbor != &"":
				candidates.append(neighbor)

	if candidates.is_empty():
		return source_sector_id
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _pick_destination_station(source_station_id: StringName) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for sector_variant in ContentDatabase.get_all_sectors().values():
		if sector_variant is not Dictionary:
			continue
		var sector_data: Dictionary = sector_variant
		if not GameStateManager.is_sector_discovered(StringName(String(sector_data.get("id", "")))):
			continue
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			continue
		if StringName(String(station_data.get("id", ""))) == source_station_id:
			continue
		candidates.append(station_data)
	if candidates.is_empty():
		return {}
	return candidates[_rng.randi_range(0, candidates.size() - 1)].duplicate(true)


func _pick_contract_resource_id(template: Dictionary, galaxy_id: String) -> StringName:
	var resource_pool: Dictionary = template.get("resource_pool", {})
	var pool: Array = resource_pool.get(galaxy_id, [])
	if pool.is_empty():
		pool = resource_pool.get("galaxy_1", [])
	if pool.is_empty():
		return &"common_ore"
	return StringName(String(pool[_rng.randi_range(0, pool.size() - 1)]))


func _pick_commodity_id(template: Dictionary) -> StringName:
	var pool: Array = template.get("commodity_pool", [])
	if pool.is_empty():
		pool = ["medical_supplies", "machinery_parts", "food_packs"]
	return StringName(String(pool[_rng.randi_range(0, pool.size() - 1)]))


func _pick_elite_archetype(template: Dictionary, galaxy_id: String) -> StringName:
	var elite_pool: Dictionary = template.get("elite_pool", {})
	var pool: Array = elite_pool.get(galaxy_id, [])
	if pool.is_empty():
		pool = elite_pool.get("galaxy_1", [])
	if pool.is_empty():
		return &"pirate_skirmisher"
	return StringName(String(pool[_rng.randi_range(0, pool.size() - 1)]))


func _pick_required_amount(template: Dictionary) -> int:
	var required_range_variant: Variant = template.get("required_range", Vector2i(3, 8))
	var amount: int = 3
	if required_range_variant is Vector2i:
		var required_range: Vector2i = required_range_variant
		amount = _rng.randi_range(min(required_range.x, required_range.y), max(required_range.x, required_range.y))
	else:
		amount = int(_rng.randi_range(3, 8))

	var progression_scale: float = _get_progression_difficulty_scale()
	if progression_scale > 1.0:
		var amount_scale: float = 1.0 + (progression_scale - 1.0) * 0.5
		amount = int(round(float(amount) * amount_scale))
	return max(amount, 1)


func _get_progression_difficulty_scale() -> float:
	var total_tier: int = 0
	var tier_count: int = 0
	for tier_variant in GameStateManager.installed_upgrades.values():
		total_tier += max(int(tier_variant), 0)
		tier_count += 1
	var average_tier: float = float(total_tier) / float(max(tier_count, 1))

	var galaxy_bonus: float = 0.0
	if GalaxyManager.is_galaxy_unlocked(&"galaxy_2") or GameStateManager.has_progression_flag(&"galaxy_2_unlocked"):
		galaxy_bonus += 0.2
	if GalaxyManager.is_galaxy_unlocked(&"galaxy_3") or GameStateManager.has_progression_flag(&"galaxy_3_unlocked"):
		galaxy_bonus += 0.3

	return clampf(1.0 + average_tier * 0.08 + galaxy_bonus, 1.0, 2.4)


func _unlock_next_story_mission(mission: Dictionary) -> void:
	var next_id: String = String(mission.get("next_id", ""))
	if next_id.is_empty():
		return
	if completed_mission_ids.has(next_id):
		return
	if _available_story_mission_ids.has(next_id):
		return
	_available_story_mission_ids.append(next_id)


func _apply_mission_rewards(mission: Dictionary) -> void:
	var rewards: Dictionary = mission.get("rewards", {})
	GameStateManager.credits += int(rewards.get("credits", 0))

	var material_rewards: Dictionary = rewards.get("materials", {})
	for item_id_variant in material_rewards.keys():
		var item_id: StringName = StringName(String(item_id_variant))
		var quantity: int = int(material_rewards[item_id_variant])
		if quantity > 0:
			GameStateManager.add_cargo(item_id, quantity)

	for item_variant in rewards.get("items", []):
		if item_variant is not Dictionary:
			continue
		var item_data: Dictionary = item_variant
		var item_id: StringName = StringName(String(item_data.get("item_id", "")))
		var quantity: int = int(item_data.get("quantity", 0))
		if item_id == &"" or quantity <= 0:
			continue
		GameStateManager.add_cargo(item_id, quantity)

	for flag_variant in rewards.get("flags", []):
		_set_story_flag(String(flag_variant), true)

	if get_story_flag(&"game_complete"):
		victory_sequence_requested.emit(PackedStringArray([
			"The ancient route network hums to life...",
			"Navigation beacons reactivate.",
			"The frontier is open.",
			"[RESTORER]",
		]))
		UIManager.show_toast("Post-game content unlocked", &"success")


func _consume_turn_in_requirements(mission: Dictionary) -> bool:
	if String(mission.get("type", "")) != "mining_quota":
		return true
	for objective_variant in mission.get("objectives", []):
		if objective_variant is not Dictionary:
			continue
		var objective: Dictionary = objective_variant
		if String(objective.get("type", "")) != "collect_item":
			continue
		var item_id: StringName = StringName(String(objective.get("target", "")))
		var required: int = max(int(objective.get("required", 1)), 1)
		if not GameStateManager.has_cargo(item_id, required):
			return false
		if not GameStateManager.remove_cargo(item_id, required):
			return false
	return true


func _set_story_flag(flag_key: String, enabled: bool) -> void:
	if flag_key.is_empty():
		return
	story_flags[flag_key] = enabled
	GameStateManager.set_progression_flag(StringName(flag_key), enabled)


func _get_story_templates_sorted() -> Array[Dictionary]:
	var templates: Array[Dictionary] = ContentDatabase.get_story_mission_templates()
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 9999)) < int(b.get("order", 9999))
	)
	return templates


func _get_story_template(template_id: StringName) -> Dictionary:
	for template in ContentDatabase.get_story_mission_templates():
		if StringName(String(template.get("id", ""))) == template_id:
			return template.duplicate(true)
	return {}


func _find_active_mission_index(mission_id: StringName) -> int:
	for i in active_missions.size():
		var mission_variant: Variant = active_missions[i]
		if mission_variant is not Dictionary:
			continue
		if StringName(String((mission_variant as Dictionary).get("id", ""))) == mission_id:
			return i
	return -1


func _get_active_mission(mission_id: StringName) -> Dictionary:
	var index: int = _find_active_mission_index(mission_id)
	if index < 0:
		return {}
	return (active_missions[index] as Dictionary).duplicate(true)


func _get_objective_count(mission: Dictionary) -> int:
	return Array(mission.get("objectives", [])).size()


func _get_objective(mission: Dictionary, index: int) -> Dictionary:
	var objectives: Array = mission.get("objectives", [])
	if index < 0 or index >= objectives.size():
		return {}
	var objective_variant: Variant = objectives[index]
	if objective_variant is not Dictionary:
		return {}
	return objective_variant


func _assign_fallback_tracked_mission() -> void:
	if active_missions.is_empty():
		_tracked_mission_id = &""
		tracked_mission_changed.emit(_tracked_mission_id)
		return
	_tracked_mission_id = StringName(String(active_missions[0].get("id", "")))
	tracked_mission_changed.emit(_tracked_mission_id)


func _clone_mission_array(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is not Array:
		return result
	for entry_variant in source:
		if entry_variant is not Dictionary:
			continue
		result.append((entry_variant as Dictionary).duplicate(true))
	return result


func _serialize_mission_array(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is not Array:
		return result
	for entry_variant in source:
		if entry_variant is not Dictionary:
			continue
		result.append(_serialize_variant(entry_variant) as Dictionary)
	return result


func _serialize_variant(value: Variant) -> Variant:
	if value is Vector2:
		var vector_value: Vector2 = value
		return {
			"_type": "Vector2",
			"x": vector_value.x,
			"y": vector_value.y,
		}
	if value is Vector2i:
		var vector2i_value: Vector2i = value
		return {
			"_type": "Vector2i",
			"x": vector2i_value.x,
			"y": vector2i_value.y,
		}
	if value is Array:
		var result_array: Array = []
		for nested_variant in value:
			result_array.append(_serialize_variant(nested_variant))
		return result_array
	if value is Dictionary:
		var dict_value: Dictionary = value
		var result_dict: Dictionary = {}
		for key_variant in dict_value.keys():
			result_dict[key_variant] = _serialize_variant(dict_value[key_variant])
		return result_dict
	return value


func _deserialize_mission_array(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is not Array:
		return result
	for entry_variant in source:
		if entry_variant is not Dictionary:
			continue
		result.append(_deserialize_variant(entry_variant) as Dictionary)
	return result


func _deserialize_variant(value: Variant) -> Variant:
	if value is Array:
		var result_array: Array = []
		for nested_variant in value:
			result_array.append(_deserialize_variant(nested_variant))
		return result_array
	if value is Dictionary:
		var dict_value: Dictionary = value
		var type_id: String = String(dict_value.get("_type", ""))
		if type_id == "Vector2":
			return Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
		if type_id == "Vector2i":
			return Vector2i(int(dict_value.get("x", 0)), int(dict_value.get("y", 0)))
		if dict_value.has("x") and dict_value.has("y") and dict_value.size() <= 4:
			return Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
		if dict_value.has("X") and dict_value.has("Y") and dict_value.size() <= 4:
			return Vector2(float(dict_value.get("X", 0.0)), float(dict_value.get("Y", 0.0)))
		var result_dict: Dictionary = {}
		for key_variant in dict_value.keys():
			result_dict[key_variant] = _deserialize_variant(dict_value[key_variant])
		return result_dict
	if value is String:
		var parsed_vector: Vector2 = _parse_vector2_string(String(value))
		if is_finite(parsed_vector.x) and is_finite(parsed_vector.y):
			return parsed_vector
	return value


func _coerce_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		var vector2i_value: Vector2i = value
		return Vector2(float(vector2i_value.x), float(vector2i_value.y))
	if value is Dictionary:
		var dict_value: Dictionary = value
		if dict_value.has("x") and dict_value.has("y"):
			return Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
		if dict_value.has("X") and dict_value.has("Y"):
			return Vector2(float(dict_value.get("X", 0.0)), float(dict_value.get("Y", 0.0)))
		if String(dict_value.get("_type", "")) == "Vector2" or String(dict_value.get("_type", "")) == "Vector2i":
			return Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
	if value is String:
		var parsed: Vector2 = _parse_vector2_string(String(value))
		if is_finite(parsed.x) and is_finite(parsed.y):
			return parsed
	return Vector2.ZERO


func _parse_vector2_string(raw_value: String) -> Vector2:
	var text: String = raw_value.strip_edges()
	if text.length() < 5:
		return Vector2(INF, INF)
	if not text.begins_with("(") or not text.ends_with(")"):
		return Vector2(INF, INF)
	var inner: String = text.substr(1, text.length() - 2)
	var parts: PackedStringArray = inner.split(",", false, 2)
	if parts.size() != 2:
		return Vector2(INF, INF)
	var x_text: String = String(parts[0]).strip_edges()
	var y_text: String = String(parts[1]).strip_edges()
	if not x_text.is_valid_float() or not y_text.is_valid_float():
		return Vector2(INF, INF)
	return Vector2(x_text.to_float(), y_text.to_float())


func _generate_mission_instance_id(prefix: String) -> String:
	_mission_counter += 1
	return "%s_%06d" % [prefix, _mission_counter]


func _format_objective_progress(objective: Dictionary) -> String:
	if objective.is_empty():
		return ""
	var objective_type: String = String(objective.get("type", "objective"))
	var target: String = String(objective.get("target", ""))
	var current: int = int(objective.get("current", 0))
	var required: int = max(int(objective.get("required", 1)), 1)

	match objective_type:
		"collect_item":
			return "Collect %d %s (%d/%d)" % [required, _get_item_name(StringName(target)), current, required]
		"sell_item":
			return "Sell %d %s (%d/%d)" % [required, _get_item_name(StringName(target)), current, required]
		"deliver_item":
			return "Deliver %d %s (%d/%d)" % [required, _get_item_name(StringName(target)), current, required]
		"destroy_enemy":
			var faction: String = String(objective.get("faction", ""))
			if String(objective.get("match_mode", "")) == "faction" and not faction.is_empty():
				return "Destroy %d %s ships (%d/%d)" % [required, faction.capitalize(), current, required]
			if target.is_empty():
				return "Destroy enemies (%d/%d)" % [current, required]
			return "Destroy %d %s (%d/%d)" % [required, _get_enemy_name(StringName(target)), current, required]
		"defeat_boss":
			return "Defeat %s (%d/%d)" % [_get_enemy_name(StringName(target)), current, required]
		"scan_anomaly":
			return "Scan anomaly (%d/%d)" % [current, required]
		"interact_anomaly":
			return "Activate beacon (%d/%d)" % [current, required]
		"reach_sector":
			return "Travel to %s" % _get_sector_name(StringName(target))
		"dock_station", "turn_in_station":
			return "Dock at %s" % _get_station_name(StringName(target))
		"reach_point":
			return "Reach navigation beacon"
		"collect_loot":
			return "Recover cargo (%d/%d)" % [current, required]
		_:
			return "%s (%d/%d)" % [objective_type.capitalize().replace("_", " "), current, required]


func _get_item_name(item_id: StringName) -> String:
	var item_data: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_data.is_empty():
		item_data = ContentDatabase.get_resource_definition(item_id)
	if item_data.is_empty():
		return String(item_id)
	return String(item_data.get("name", item_id))


func _get_enemy_name(archetype_id: StringName) -> String:
	var enemy_data: Dictionary = ContentDatabase.get_enemy_archetype_definition(archetype_id)
	if enemy_data.is_empty():
		enemy_data = ContentDatabase.get_boss_archetype_definition(archetype_id)
	if enemy_data.is_empty():
		return String(archetype_id)
	return String(enemy_data.get("name", archetype_id))


func _get_sector_name(sector_id: StringName) -> String:
	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	if sector_data.is_empty():
		return String(sector_id)
	return String(sector_data.get("name", sector_id))


func _get_station_name(station_id: StringName) -> String:
	var station_data: Dictionary = EconomyManager.get_station_data(station_id)
	if station_data.is_empty():
		return String(station_id)
	return String(station_data.get("name", station_id))


func _get_inventory_quantity(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	if GameStateManager.get_relic_quantity(item_id) > 0:
		return GameStateManager.get_relic_quantity(item_id)
	for cargo_entry_variant in GameStateManager.get_cargo_manifest():
		if cargo_entry_variant is not Dictionary:
			continue
		var cargo_entry: Dictionary = cargo_entry_variant
		if StringName(String(cargo_entry.get("resource_id", ""))) != item_id:
			continue
		return int(cargo_entry.get("quantity", 0))
	return 0
