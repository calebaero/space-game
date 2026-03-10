extends Node

signal new_game_requested(starting_sector_id: StringName)
signal cargo_changed
signal hull_changed(current: float, max_value: float)
signal shield_changed(current: float, max_value: float)
signal player_damage_applied(shield_damage: float, hull_damage: float)
signal shield_depleted
signal player_destroyed
signal wreck_beacon_changed

const STARTING_CREDITS: int = 200
const SHIELD_RECHARGE_DELAY_SECONDS: float = 3.0
const DEFAULT_PLAYER_STATS: Dictionary = {
	"hull": 100.0,
	"shield": 50.0,
	"thrust": 300.0,
	"max_speed": 400.0,
	"turn_speed": 4.6,
	"boost_strength": 2.5,
	"power_capacity": 60.0,
	"cargo_capacity": 20.0,
	"scanner_range": 600.0,
	"scanner_cooldown": 8.0,
	"mining_range": 200.0,
	"mining_efficiency": 1.0,
	"shield_recharge": 6.0,
}
const INPUT_ACTIONS: Dictionary = {
	"thrust_alt": ["W"],
	"brake": ["S"],
	"boost": ["Space", "Shift"],
	"rotate_left": ["A"],
	"rotate_right": ["D"],
	"interact": ["E"],
	"mine": ["F"],
	"scan": ["Q"],
	"fire_secondary": ["R"],
	"utility_activate": ["C"],
	"cycle_weapon_1": ["1"],
	"cycle_weapon_2": ["2"],
	"cycle_target": ["Tab"],
	"map_toggle": ["M"],
	"pause": ["Escape"],
}

var player_stats: Dictionary = {}
var credits: int = STARTING_CREDITS
var cargo: Array[Dictionary] = []
var relic_inventory: Dictionary = {}
var equipped_modules: Dictionary = {}
var installed_upgrades: Dictionary = {}
var current_sector_id: StringName = &"anchor_station"
var last_docked_station_id: StringName = &"station_anchor_prime"
var is_docked: bool = false
var docked_station_id: StringName = &""
var wreck_beacon_state: Dictionary = {}
var current_hull: float = 100.0
var current_shield: float = 50.0
var discovered_sectors: Dictionary = {}

var _queued_new_game_sector_id: StringName = &""
var _shield_recharge_delay_remaining: float = 0.0
var _player_destroyed_emitted: bool = false


func _ready() -> void:
	_ensure_input_actions()
	reset_runtime_state(&"anchor_station")


func request_new_game(starting_sector_id: StringName = &"anchor_station") -> void:
	reset_runtime_state(starting_sector_id)
	_queued_new_game_sector_id = starting_sector_id


func emit_queued_new_game_request_if_any() -> void:
	if _queued_new_game_sector_id == &"":
		return

	var queued_sector: StringName = _queued_new_game_sector_id
	_queued_new_game_sector_id = &""
	new_game_requested.emit(queued_sector)


func reset_runtime_state(starting_sector_id: StringName = &"anchor_station") -> void:
	player_stats = DEFAULT_PLAYER_STATS.duplicate(true)
	credits = STARTING_CREDITS
	cargo = []
	relic_inventory = {}
	equipped_modules = {
		"primary": "pulse_laser",
		"secondary": "",
		"utility": "",
		"special": "",
	}
	installed_upgrades = {}
	current_sector_id = starting_sector_id
	last_docked_station_id = &"station_anchor_prime"
	is_docked = false
	docked_station_id = &""
	current_hull = get_effective_stat(&"hull")
	current_shield = get_effective_stat(&"shield")
	_shield_recharge_delay_remaining = 0.0
	_player_destroyed_emitted = false
	discovered_sectors = {}
	mark_sector_discovered(starting_sector_id)
	wreck_beacon_state = {
		"active": false,
		"sector_id": "",
		"position": Vector2.ZERO,
		"cargo_snapshot": [],
	}
	wreck_beacon_changed.emit()
	cargo_changed.emit()
	hull_changed.emit(current_hull, get_max_hull())
	shield_changed.emit(current_shield, get_max_shield())


func set_current_sector(sector_id: StringName) -> void:
	current_sector_id = sector_id
	mark_sector_discovered(sector_id)


func mark_sector_discovered(sector_id: StringName) -> void:
	var key: String = String(sector_id)
	if key.is_empty():
		return
	discovered_sectors[key] = true


func is_sector_discovered(sector_id: StringName) -> bool:
	return bool(discovered_sectors.get(String(sector_id), false))


func get_discovered_sectors() -> Array[String]:
	var result: Array[String] = []
	for key_variant in discovered_sectors.keys():
		result.append(String(key_variant))
	return result


func get_effective_stat(stat_name: StringName) -> float:
	# TODO(phase-later): apply module, upgrade, cargo mass, and temporary effect modifiers.
	if not player_stats.has(String(stat_name)):
		return 0.0
	return float(player_stats[String(stat_name)])


func get_current_hull() -> float:
	return current_hull


func get_max_hull() -> float:
	return maxf(get_effective_stat(&"hull"), 1.0)


func get_current_shield() -> float:
	return current_shield


func get_max_shield() -> float:
	return maxf(get_effective_stat(&"shield"), 1.0)


func apply_damage(amount: float) -> Dictionary:
	if amount <= 0.0:
		return {"shield_damage": 0.0, "hull_damage": 0.0, "destroyed": false, "shield_depleted": false}

	var remaining: float = amount
	var shield_damage: float = 0.0
	var hull_damage: float = 0.0
	var shield_before: float = current_shield
	if current_shield > 0.0:
		shield_damage = minf(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		shield_changed.emit(current_shield, get_max_shield())

	if remaining > 0.0:
		hull_damage = minf(current_hull, remaining)
		current_hull = maxf(current_hull - hull_damage, 0.0)
		hull_changed.emit(current_hull, get_max_hull())

	_shield_recharge_delay_remaining = SHIELD_RECHARGE_DELAY_SECONDS
	var depleted_this_hit: bool = shield_before > 0.0 and current_shield <= 0.0
	if depleted_this_hit:
		shield_depleted.emit()
		UIManager.show_toast("Shield Down!", &"warning")

	player_damage_applied.emit(shield_damage, hull_damage)
	_check_player_destroyed()
	return {
		"shield_damage": shield_damage,
		"hull_damage": hull_damage,
		"destroyed": current_hull <= 0.0,
		"shield_depleted": depleted_this_hit,
	}


func apply_hull_damage(amount: float) -> Dictionary:
	if amount <= 0.0:
		return {"shield_damage": 0.0, "hull_damage": 0.0, "destroyed": false, "shield_depleted": false}

	var hull_damage: float = minf(current_hull, amount)
	current_hull = maxf(current_hull - hull_damage, 0.0)
	_shield_recharge_delay_remaining = SHIELD_RECHARGE_DELAY_SECONDS
	hull_changed.emit(current_hull, get_max_hull())
	player_damage_applied.emit(0.0, hull_damage)
	_check_player_destroyed()
	return {
		"shield_damage": 0.0,
		"hull_damage": hull_damage,
		"destroyed": current_hull <= 0.0,
		"shield_depleted": false,
	}


func restore_shield(amount: float) -> void:
	if amount <= 0.0:
		return
	current_shield = minf(current_shield + amount, get_max_shield())
	shield_changed.emit(current_shield, get_max_shield())


func recharge_shield(delta: float, multiplier: float = 1.0) -> void:
	if delta <= 0.0:
		return
	if multiplier <= 0.0:
		return
	if _shield_recharge_delay_remaining > 0.0:
		_shield_recharge_delay_remaining = maxf(_shield_recharge_delay_remaining - delta, 0.0)
		return
	var recharge_rate: float = get_effective_stat(&"shield_recharge")
	if recharge_rate <= 0.0:
		return
	restore_shield(recharge_rate * multiplier * delta)


func get_cargo_manifest() -> Array[Dictionary]:
	return cargo.duplicate(true)


func get_cargo_used() -> int:
	var used: int = 0
	for entry_variant in cargo:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var quantity: int = max(int(entry.get("quantity", 0)), 0)
		if quantity <= 0:
			continue
		var resource_id: StringName = StringName(String(entry.get("resource_id", "")))
		var resource_def: Dictionary = ContentDatabase.get_resource_definition(resource_id)
		var cargo_size: int = int(resource_def.get("cargo_size", 1))
		used += quantity * max(cargo_size, 1)
	return used


func get_cargo_capacity() -> int:
	return max(int(round(get_effective_stat(&"cargo_capacity"))), 0)


func get_cargo_free() -> int:
	return max(get_cargo_capacity() - get_cargo_used(), 0)


func has_cargo(resource_id: StringName, quantity: int) -> bool:
	if quantity <= 0:
		return true
	return _find_cargo_entry_quantity(resource_id) >= quantity


func add_cargo(resource_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0

	if resource_id == &"ancient_relics":
		add_relic(resource_id, quantity)
		return quantity

	var free_capacity: int = get_cargo_free()
	if free_capacity <= 0:
		UIManager.show_toast("Cargo Full!", &"warning")
		return 0

	var amount_to_add: int = min(quantity, free_capacity)
	if amount_to_add <= 0:
		UIManager.show_toast("Cargo Full!", &"warning")
		return 0

	var key: String = String(resource_id)
	var found_index: int = -1
	for i in cargo.size():
		var entry_variant: Variant = cargo[i]
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("resource_id", "")) == key:
			found_index = i
			break

	if found_index < 0:
		cargo.append({
			"resource_id": key,
			"quantity": amount_to_add,
		})
	else:
		var updated_entry: Dictionary = cargo[found_index]
		updated_entry["quantity"] = int(updated_entry.get("quantity", 0)) + amount_to_add
		cargo[found_index] = updated_entry

	cargo_changed.emit()

	if amount_to_add < quantity:
		var lost: int = quantity - amount_to_add
		UIManager.show_toast("Cargo Full! %d units lost" % lost, &"warning")

	return amount_to_add


func remove_cargo(resource_id: StringName, quantity: int) -> bool:
	if quantity <= 0:
		return true

	var key: String = String(resource_id)
	for i in cargo.size():
		var entry_variant: Variant = cargo[i]
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("resource_id", "")) != key:
			continue
		var current_quantity: int = int(entry.get("quantity", 0))
		if current_quantity < quantity:
			return false

		current_quantity -= quantity
		if current_quantity <= 0:
			cargo.remove_at(i)
		else:
			entry["quantity"] = current_quantity
			cargo[i] = entry
		cargo_changed.emit()
		return true

	return false


func clear_cargo_hold() -> void:
	cargo.clear()
	cargo_changed.emit()


func set_wreck_beacon_state(new_state: Dictionary) -> void:
	wreck_beacon_state = {
		"active": bool(new_state.get("active", false)),
		"sector_id": String(new_state.get("sector_id", "")),
		"position": new_state.get("position", Vector2.ZERO),
		"cargo_snapshot": new_state.get("cargo_snapshot", []),
	}
	wreck_beacon_changed.emit()


func clear_wreck_beacon_state() -> void:
	wreck_beacon_state = {
		"active": false,
		"sector_id": "",
		"position": Vector2.ZERO,
		"cargo_snapshot": [],
	}
	wreck_beacon_changed.emit()


func has_active_wreck_beacon() -> bool:
	return bool(wreck_beacon_state.get("active", false))


func get_wreck_beacon_state() -> Dictionary:
	return wreck_beacon_state.duplicate(true)


func restore_full_health() -> void:
	current_hull = get_max_hull()
	current_shield = get_max_shield()
	_shield_recharge_delay_remaining = 0.0
	_player_destroyed_emitted = false
	hull_changed.emit(current_hull, get_max_hull())
	shield_changed.emit(current_shield, get_max_shield())


func get_equipped_weapon_id(slot_name: StringName) -> StringName:
	return StringName(String(equipped_modules.get(String(slot_name), "")))


func get_equipped_weapon_definition(slot_name: StringName) -> Dictionary:
	var weapon_id: StringName = get_equipped_weapon_id(slot_name)
	if weapon_id == &"":
		return {}
	return ContentDatabase.get_weapon_definition(weapon_id)


func set_equipped_weapon(slot_name: StringName, weapon_id: StringName) -> void:
	equipped_modules[String(slot_name)] = String(weapon_id)


func add_relic(relic_id: StringName, quantity: int) -> void:
	if quantity <= 0:
		return
	var key: String = String(relic_id)
	relic_inventory[key] = int(relic_inventory.get(key, 0)) + quantity


func get_relic_quantity(relic_id: StringName) -> int:
	return int(relic_inventory.get(String(relic_id), 0))


func get_cargo_weight() -> float:
	var total_weight: float = 0.0
	for entry_variant in cargo:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var quantity: int = max(int(entry.get("quantity", 0)), 0)
		if quantity <= 0:
			continue
		var resource_id: StringName = StringName(String(entry.get("resource_id", "")))
		var resource_def: Dictionary = ContentDatabase.get_resource_definition(resource_id)
		var cargo_size: float = float(resource_def.get("cargo_size", 1.0))
		total_weight += float(quantity) * cargo_size
	return total_weight


func get_total_mass() -> float:
	# TODO(phase-later): derive exact mass from module and upgrade data definitions.
	var module_mass: float = 0.0
	for module_id_variant in equipped_modules.values():
		if String(module_id_variant) != "":
			module_mass += 1.5

	var upgrade_mass: float = float(installed_upgrades.size()) * 0.5
	var cargo_mass: float = get_cargo_weight() * 0.02
	return module_mass + upgrade_mass + cargo_mass


func _find_cargo_entry_quantity(resource_id: StringName) -> int:
	var key: String = String(resource_id)
	for entry_variant in cargo:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("resource_id", "")) == key:
			return int(entry.get("quantity", 0))
	return 0


func _ensure_input_actions() -> void:
	# Register all planned actions early so later phases can bind gameplay safely.
	_ensure_action("thrust")
	_ensure_action("fire_primary")
	for action_name_variant in INPUT_ACTIONS.keys():
		_ensure_action(StringName(String(action_name_variant)))

	InputMap.action_erase_events("thrust")
	InputMap.action_erase_events("fire_primary")
	_add_mouse_binding("thrust", MOUSE_BUTTON_LEFT)
	_add_mouse_binding("fire_primary", MOUSE_BUTTON_RIGHT)

	for action_name_variant in INPUT_ACTIONS.keys():
		var action_name: StringName = StringName(String(action_name_variant))
		InputMap.action_erase_events(action_name)
		var key_names: Array = INPUT_ACTIONS[String(action_name)]
		for key_name_variant in key_names:
			_add_key_binding(action_name, String(key_name_variant))


func _ensure_action(action_name: StringName) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)


func _add_key_binding(action_name: StringName, key_name: String) -> void:
	var keycode: int = OS.find_keycode_from_string(key_name)
	if keycode == 0:
		push_warning("Unknown key for action '%s': %s" % [action_name, key_name])
		return

	var input_event: InputEventKey = InputEventKey.new()
	input_event.keycode = keycode
	input_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, input_event)


func _add_mouse_binding(action_name: StringName, button_index: MouseButton) -> void:
	var input_event: InputEventMouseButton = InputEventMouseButton.new()
	input_event.button_index = button_index
	InputMap.action_add_event(action_name, input_event)


func _check_player_destroyed() -> void:
	if current_hull > 0.0:
		return
	if _player_destroyed_emitted:
		return
	_player_destroyed_emitted = true
	player_destroyed.emit()
