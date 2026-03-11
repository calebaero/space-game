extends Node

signal save_completed(slot_id: int, metadata: Dictionary)
signal save_failed(slot_id: int, reason: String)
signal load_completed(slot_id: int, metadata: Dictionary)
signal load_failed(slot_id: int, reason: String)
signal settings_changed(settings: Dictionary)

const SAVE_VERSION: int = 1
const SAVE_DIR_PATH: String = "user://saves"
const SAVE_SLOT_COUNT: int = 3
const SETTINGS_PATH: String = "user://settings.json"

const DEFAULT_SETTINGS: Dictionary = {
	"audio": {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.85,
	},
	"display": {
		"fullscreen": false,
		"vsync": true,
		"screen_shake_intensity": 1.0,
	},
	"controls": {
		"show_reference": true,
	},
}

var current_slot_id: int = 1

var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _pending_loaded_state_available: bool = false


func _ready() -> void:
	_ensure_save_directory()
	load_settings()
	call_deferred("_apply_settings_deferred")


func save_game(slot_id: int = 0) -> bool:
	var target_slot: int = _resolve_slot_id(slot_id)
	if target_slot <= 0:
		return _emit_save_failed(0, "Invalid save slot.")

	var payload: Dictionary = _build_save_payload(target_slot)
	var save_path: String = _slot_path(target_slot)
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _emit_save_failed(target_slot, "Could not open save slot for writing.")

	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()

	current_slot_id = target_slot
	var metadata: Dictionary = payload.get("metadata", {})
	save_completed.emit(target_slot, metadata)
	AudioManager.play_sfx(&"game_save", Vector2.ZERO)
	return true


func load_game(slot_id: int = 0) -> bool:
	var target_slot: int = _resolve_slot_id(slot_id)
	if target_slot <= 0:
		return _emit_load_failed(0, "Invalid save slot.")

	var load_result: Dictionary = _read_slot_payload(target_slot)
	if not bool(load_result.get("success", false)):
		return _emit_load_failed(target_slot, String(load_result.get("reason", "Failed to read save.")))

	var payload: Dictionary = load_result.get("payload", {})
	var game_state: Dictionary = payload.get("game_state", {})
	var mission_state: Dictionary = payload.get("mission_state", {})
	var galaxy_state: Dictionary = payload.get("galaxy_state", {})
	var economy_state: Dictionary = payload.get("economy_state", {})

	GameStateManager.apply_save_state(game_state)
	MissionManager.apply_save_state(mission_state)
	GalaxyManager.apply_save_state(galaxy_state)
	EconomyManager.apply_save_state(economy_state)
	GalaxyManager.sync_unlocks_from_progression_flags()

	current_slot_id = target_slot
	_pending_loaded_state_available = true
	var metadata: Dictionary = payload.get("metadata", {})
	load_completed.emit(target_slot, metadata)
	return true


func load_most_recent_save() -> bool:
	var best_slot: int = 0
	var best_timestamp: int = -1
	for slot_id in range(1, SAVE_SLOT_COUNT + 1):
		var metadata: Dictionary = get_slot_metadata(slot_id)
		if metadata.is_empty():
			continue
		var timestamp: int = int(metadata.get("timestamp_unix", -1))
		if timestamp > best_timestamp:
			best_timestamp = timestamp
			best_slot = slot_id

	if best_slot <= 0:
		return _emit_load_failed(0, "No save slots found.")
	return load_game(best_slot)


func autosave() -> bool:
	return save_game(current_slot_id)


func get_slot_metadata(slot_id: int) -> Dictionary:
	var load_result: Dictionary = _read_slot_payload(slot_id)
	if not bool(load_result.get("success", false)):
		return {}
	var payload: Dictionary = load_result.get("payload", {})
	var metadata: Dictionary = payload.get("metadata", {})
	if metadata.is_empty():
		metadata = _build_metadata(slot_id)
	return metadata.duplicate(true)


func get_all_slot_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id in range(1, SAVE_SLOT_COUNT + 1):
		var metadata: Dictionary = get_slot_metadata(slot_id)
		if metadata.is_empty():
			continue
		result.append(metadata)
	return result


func has_any_saves() -> bool:
	for slot_id in range(1, SAVE_SLOT_COUNT + 1):
		if FileAccess.file_exists(_slot_path(slot_id)):
			return true
	return false


func has_pending_loaded_state() -> bool:
	return _pending_loaded_state_available


func consume_pending_loaded_state() -> bool:
	if not _pending_loaded_state_available:
		return false
	_pending_loaded_state_available = false
	return true


func clear_pending_loaded_state() -> void:
	_pending_loaded_state_available = false


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func load_settings() -> Dictionary:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	if not FileAccess.file_exists(SETTINGS_PATH):
		settings_changed.emit(get_settings())
		return get_settings()

	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		settings_changed.emit(get_settings())
		return get_settings()

	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		settings_changed.emit(get_settings())
		return get_settings()

	var json: JSON = JSON.new()
	var parse_error: int = json.parse(text)
	if parse_error != OK or json.data is not Dictionary:
		push_warning("Settings file is invalid, using defaults.")
		settings_changed.emit(get_settings())
		return get_settings()

	_merge_settings_dict(_settings, json.data as Dictionary)
	settings_changed.emit(get_settings())
	return get_settings()


func save_settings() -> bool:
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write settings file at %s" % SETTINGS_PATH)
		return false
	file.store_string(JSON.stringify(_settings, "\t"))
	file.flush()
	file.close()
	settings_changed.emit(get_settings())
	return true


func reset_settings_to_defaults() -> Dictionary:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	apply_settings()
	save_settings()
	return get_settings()


func set_audio_setting(key: StringName, value: float, save_immediately: bool = true) -> void:
	if not _settings.has("audio"):
		_settings["audio"] = {}
	(_settings["audio"] as Dictionary)[String(key)] = clampf(value, 0.0, 1.0)
	apply_settings()
	if save_immediately:
		save_settings()


func set_display_setting(key: StringName, value: Variant, save_immediately: bool = true) -> void:
	if not _settings.has("display"):
		_settings["display"] = {}
	(_settings["display"] as Dictionary)[String(key)] = value
	apply_settings()
	if save_immediately:
		save_settings()


func get_audio_setting(key: StringName, default_value: float = 1.0) -> float:
	var audio_settings: Dictionary = _settings.get("audio", {})
	return clampf(float(audio_settings.get(String(key), default_value)), 0.0, 1.0)


func get_display_setting(key: StringName, default_value: Variant = null) -> Variant:
	var display_settings: Dictionary = _settings.get("display", {})
	if display_settings.has(String(key)):
		return display_settings[String(key)]
	return default_value


func get_screen_shake_intensity() -> float:
	return clampf(float(get_display_setting(&"screen_shake_intensity", 1.0)), 0.0, 1.0)


func apply_settings() -> void:
	_apply_audio_settings()
	_apply_display_settings()
	settings_changed.emit(get_settings())


func _apply_settings_deferred() -> void:
	apply_settings()


func _apply_audio_settings() -> void:
	AudioManager.set_volume(&"Master", get_audio_setting(&"master_volume", 1.0))
	AudioManager.set_volume(&"Music", get_audio_setting(&"music_volume", 0.8))
	AudioManager.set_volume(&"SFX", get_audio_setting(&"sfx_volume", 0.85))


func _apply_display_settings() -> void:
	var fullscreen: bool = bool(get_display_setting(&"fullscreen", false))
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var vsync_enabled: bool = bool(get_display_setting(&"vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)


func _build_save_payload(slot_id: int) -> Dictionary:
	var metadata: Dictionary = _build_metadata(slot_id)
	return {
		"save_version": SAVE_VERSION,
		"saved_at_unix": int(metadata.get("timestamp_unix", Time.get_unix_time_from_system())),
		"metadata": metadata,
		"game_state": GameStateManager.get_save_state(),
		"mission_state": MissionManager.get_save_state(),
		"galaxy_state": GalaxyManager.get_save_state(),
		"economy_state": EconomyManager.get_save_state(),
	}


func _build_metadata(slot_id: int) -> Dictionary:
	var timestamp_unix: int = int(Time.get_unix_time_from_system())
	var sector_data: Dictionary = GalaxyManager.get_sector_data(GameStateManager.current_sector_id)
	var sector_name: String = String(sector_data.get("name", "Unknown Sector"))
	return {
		"slot": slot_id,
		"timestamp_unix": timestamp_unix,
		"timestamp_iso": Time.get_datetime_string_from_unix_time(timestamp_unix, true),
		"sector_name": sector_name,
		"credits": GameStateManager.credits,
		"playtime_seconds": int(round(GameStateManager.get_playtime_seconds())),
	}


func _read_slot_payload(slot_id: int) -> Dictionary:
	var target_slot: int = _resolve_slot_id(slot_id)
	if target_slot <= 0:
		return {"success": false, "reason": "Invalid save slot."}

	var path: String = _slot_path(target_slot)
	if not FileAccess.file_exists(path):
		return {"success": false, "reason": "Save slot is empty."}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"success": false, "reason": "Could not open save slot."}
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {"success": false, "reason": "Save corrupted."}

	var json: JSON = JSON.new()
	var parse_error: int = json.parse(text)
	if parse_error != OK or json.data is not Dictionary:
		return {"success": false, "reason": "Save corrupted."}

	var payload: Dictionary = json.data as Dictionary
	return {"success": true, "payload": payload}


func _resolve_slot_id(slot_id: int) -> int:
	if slot_id <= 0:
		slot_id = current_slot_id
	if slot_id <= 0:
		slot_id = 1
	if slot_id < 1 or slot_id > SAVE_SLOT_COUNT:
		return 0
	return slot_id


func _slot_path(slot_id: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR_PATH, slot_id]


func _ensure_save_directory() -> void:
	var absolute_save_dir: String = ProjectSettings.globalize_path(SAVE_DIR_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_save_dir)


func _merge_settings_dict(target: Dictionary, source: Dictionary) -> void:
	for key_variant in source.keys():
		var key: String = String(key_variant)
		if key.is_empty() or not target.has(key):
			continue
		var source_value: Variant = source[key_variant]
		if target[key] is Dictionary and source_value is Dictionary:
			_merge_settings_dict(target[key] as Dictionary, source_value as Dictionary)
		else:
			target[key] = source_value


func _emit_save_failed(slot_id: int, reason: String) -> bool:
	push_warning("Save failed for slot %d: %s" % [slot_id, reason])
	UIManager.show_toast("Save failed.", &"danger")
	save_failed.emit(slot_id, reason)
	return false


func _emit_load_failed(slot_id: int, reason: String) -> bool:
	push_warning("Load failed for slot %d: %s" % [slot_id, reason])
	if reason == "Save corrupted.":
		UIManager.show_toast("Save corrupted", &"danger")
	else:
		UIManager.show_toast("Load failed.", &"danger")
	load_failed.emit(slot_id, reason)
	return false
