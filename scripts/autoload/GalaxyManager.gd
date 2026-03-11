extends Node

signal sector_changed(sector_id: StringName)
signal galaxy_unlocked(galaxy_id: StringName)

var unlocked_galaxies: Dictionary = {}
var current_sector_id: StringName = &""
var current_galaxy_id: StringName = &""


func _ready() -> void:
	ContentDatabase.ensure_loaded()
	sync_unlocks_from_progression_flags()


func start_new_game(preferred_sector_id: StringName = &"anchor_station") -> Dictionary:
	initialize_unlocks_for_new_game()
	sync_unlocks_from_progression_flags()

	var chosen_sector_id: StringName = preferred_sector_id
	if ContentDatabase.get_sector(chosen_sector_id).is_empty():
		chosen_sector_id = get_starting_sector_id()

	set_current_sector(chosen_sector_id)
	return get_sector_data(chosen_sector_id)


func initialize_unlocks_for_new_game() -> void:
	unlocked_galaxies.clear()
	var galaxies: Dictionary = ContentDatabase.get_all_galaxies()
	for galaxy_data in galaxies.values():
		var as_dict: Dictionary = galaxy_data
		var galaxy_id: String = String(as_dict.get("id", ""))
		if galaxy_id.is_empty():
			continue
		var unlock_requirement: String = String(as_dict.get("unlock_requirement", ""))
		unlocked_galaxies[galaxy_id] = unlock_requirement == "start"


func get_save_state() -> Dictionary:
	return {
		"unlocked_galaxies": unlocked_galaxies.duplicate(true),
		"current_sector_id": String(current_sector_id),
		"current_galaxy_id": String(current_galaxy_id),
	}


func apply_save_state(state: Dictionary) -> void:
	initialize_unlocks_for_new_game()
	for galaxy_id_variant in Dictionary(state.get("unlocked_galaxies", {})).keys():
		var galaxy_id: String = String(galaxy_id_variant)
		if galaxy_id.is_empty():
			continue
		if not bool((state.get("unlocked_galaxies", {}) as Dictionary).get(galaxy_id_variant, false)):
			continue
		unlocked_galaxies[galaxy_id] = true

	sync_unlocks_from_progression_flags()

	var saved_sector_id: StringName = StringName(String(state.get("current_sector_id", "")))
	if saved_sector_id == &"":
		saved_sector_id = GameStateManager.current_sector_id
	if saved_sector_id == &"":
		saved_sector_id = get_starting_sector_id()
	set_current_sector(saved_sector_id)


func get_starting_sector_id() -> StringName:
	return ContentDatabase.get_starting_sector_id()


func get_sector_data(sector_id: StringName) -> Dictionary:
	return ContentDatabase.get_sector(sector_id)


func get_galaxy_data(galaxy_id: StringName) -> Dictionary:
	return ContentDatabase.get_galaxy(galaxy_id)


func get_current_sector_data() -> Dictionary:
	if current_sector_id == &"":
		return {}
	return get_sector_data(current_sector_id)


func get_current_galaxy_data() -> Dictionary:
	if current_galaxy_id == &"":
		return {}
	return get_galaxy_data(current_galaxy_id)


func set_current_sector(sector_id: StringName) -> void:
	var sector_data: Dictionary = get_sector_data(sector_id)
	if sector_data.is_empty():
		push_warning("GalaxyManager could not set unknown sector: %s" % sector_id)
		return

	current_sector_id = sector_id
	current_galaxy_id = StringName(String(sector_data.get("galaxy_id", "")))
	sector_changed.emit(current_sector_id)


func is_galaxy_unlocked(galaxy_id: StringName) -> bool:
	var key: String = String(galaxy_id)
	return bool(unlocked_galaxies.get(key, false))


func unlock_galaxy(galaxy_id: StringName) -> void:
	var key: String = String(galaxy_id)
	if key.is_empty():
		return
	var already_unlocked: bool = bool(unlocked_galaxies.get(key, false))
	unlocked_galaxies[key] = true
	if not already_unlocked:
		galaxy_unlocked.emit(galaxy_id)


func is_connection_unlocked(connection_data: Dictionary) -> bool:
	var required_unlock: String = String(connection_data.get("required_unlock", ""))
	if required_unlock.is_empty():
		return true

	# Required unlocks currently match galaxy IDs for inter-galaxy gate checks.
	return is_galaxy_unlocked(StringName(required_unlock))


func apply_unlock_target(unlock_target: StringName) -> bool:
	match String(unlock_target):
		"galaxy_2":
			return _unlock_galaxy_with_feedback(&"galaxy_2", &"galaxy_2_unlocked", "Galaxy 2 Unlocked - Ion Expanse")
		"galaxy_3":
			return _unlock_galaxy_with_feedback(&"galaxy_3", &"galaxy_3_unlocked", "Galaxy 3 Unlocked - Relic Reach")
		_:
			return false


func sync_unlocks_from_progression_flags() -> void:
	if GameStateManager.has_progression_flag(&"crafted_warp_stabilizer_mk1"):
		unlock_galaxy(&"galaxy_2")
		GameStateManager.set_progression_flag(&"galaxy_2_unlocked", true)
	if GameStateManager.has_progression_flag(&"crafted_long_range_warp_drive"):
		unlock_galaxy(&"galaxy_3")
		GameStateManager.set_progression_flag(&"galaxy_3_unlocked", true)


func _unlock_galaxy_with_feedback(galaxy_id: StringName, story_flag: StringName, toast_message: String) -> bool:
	if is_galaxy_unlocked(galaxy_id):
		return false
	unlock_galaxy(galaxy_id)
	GameStateManager.set_progression_flag(story_flag, true)
	UIManager.show_toast(toast_message, &"success")
	UIManager.request_screen_flash(Color(0.82, 0.9, 1.0, 1.0), 0.25, 0.3)
	UIManager.show_toast("Warp gate routes updated.", &"info")
	SaveManager.autosave()
	return true
