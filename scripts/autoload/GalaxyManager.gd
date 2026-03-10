extends Node

signal sector_changed(sector_id: StringName)

var unlocked_galaxies: Dictionary = {}
var current_sector_id: StringName = &""
var current_galaxy_id: StringName = &""


func _ready() -> void:
	ContentDatabase.ensure_loaded()


func start_new_game(preferred_sector_id: StringName = &"anchor_station") -> Dictionary:
	initialize_unlocks_for_new_game()

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
	unlocked_galaxies[String(galaxy_id)] = true


func is_connection_unlocked(connection_data: Dictionary) -> bool:
	var required_unlock: String = String(connection_data.get("required_unlock", ""))
	if required_unlock.is_empty():
		return true

	# Required unlocks currently match galaxy IDs for inter-galaxy gate checks.
	return is_galaxy_unlocked(StringName(required_unlock))
