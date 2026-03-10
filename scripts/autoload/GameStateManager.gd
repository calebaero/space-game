extends Node

signal new_game_requested(starting_sector_id: StringName)
signal cargo_changed
signal hull_changed(current: float, max_value: float)
signal shield_changed(current: float, max_value: float)
signal player_damage_applied(shield_damage: float, hull_damage: float)
signal shield_depleted
signal player_destroyed
signal wreck_beacon_changed
signal loadout_changed
signal upgrades_changed
signal stats_recalculated

const STARTING_CREDITS: int = 200
const SHIELD_RECHARGE_DELAY_SECONDS: float = 3.0
const DEFAULT_PLAYER_STATS: Dictionary = {
	"hull": 100.0,
	"shield": 50.0,
	"thrust": 300.0,
	"max_speed": 360.0,
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
const LOADOUT_SLOT_NAMES: Array[StringName] = [&"primary_weapon", &"secondary_weapon", &"utility_module", &"special_module"]
const SLOT_TO_COMPAT_KEY: Dictionary = {
	"primary_weapon": "primary",
	"secondary_weapon": "secondary",
	"utility_module": "utility",
	"special_module": "special",
}
const COMPAT_KEY_TO_SLOT: Dictionary = {
	"primary": "primary_weapon",
	"secondary": "secondary_weapon",
	"utility": "utility_module",
	"special": "special_module",
}

var player_stats: Dictionary = {}
var credits: int = STARTING_CREDITS
var cargo: Array[Dictionary] = []
var relic_inventory: Dictionary = {}
var ship_loadout: Dictionary = {}
var owned_modules: Array[String] = []
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
var progression_flags: Dictionary = {}

var _queued_new_game_sector_id: StringName = &""
var _shield_recharge_delay_remaining: float = 0.0
var _player_destroyed_emitted: bool = false


func _ready() -> void:
	_ensure_input_actions()
	ContentDatabase.ensure_loaded()
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
	ContentDatabase.ensure_loaded()
	player_stats = DEFAULT_PLAYER_STATS.duplicate(true)
	credits = STARTING_CREDITS
	cargo = []
	relic_inventory = {}
	ship_loadout = {
		"primary_weapon": "pulse_laser",
		"secondary_weapon": "",
		"utility_module": "",
		"special_module": "",
	}
	owned_modules = _build_starting_owned_modules()
	installed_upgrades = {}
	for path_id_variant in ContentDatabase.get_all_upgrade_paths().keys():
		var path_id: String = String(path_id_variant)
		if path_id.is_empty():
			continue
		installed_upgrades[path_id] = 0
	_sync_equipped_modules_cache()
	current_sector_id = starting_sector_id
	last_docked_station_id = &"station_anchor_prime"
	is_docked = false
	docked_station_id = &""
	current_hull = get_max_hull()
	current_shield = get_max_shield()
	_shield_recharge_delay_remaining = 0.0
	_player_destroyed_emitted = false
	discovered_sectors = {}
	mark_sector_discovered(starting_sector_id)
	progression_flags = {}
	wreck_beacon_state = {
		"active": false,
		"sector_id": "",
		"position": Vector2.ZERO,
		"cargo_snapshot": [],
	}
	wreck_beacon_changed.emit()
	cargo_changed.emit()
	loadout_changed.emit()
	upgrades_changed.emit()
	stats_recalculated.emit()
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
	var stat_key: String = String(stat_name)
	if not player_stats.has(stat_key):
		return 0.0
	var base_value: float = float(player_stats[stat_key])
	var effective_value: float = _apply_upgrade_bonus(stat_key, base_value)
	effective_value = _apply_module_bonus(stat_key, effective_value)
	effective_value = _apply_mass_penalty_to_stat(stat_key, effective_value)
	effective_value = _apply_stat_special_cases(stat_key, effective_value)
	return effective_value


func get_upgrade_tier(path_id: StringName) -> int:
	var key: String = String(path_id)
	if key.is_empty():
		return 0
	return max(int(installed_upgrades.get(key, 0)), 0)


func get_next_upgrade_tier_data(path_id: StringName) -> Dictionary:
	var path_data: Dictionary = ContentDatabase.get_upgrade_path(path_id)
	if path_data.is_empty():
		return {}
	var tiers: Array = path_data.get("tiers", [])
	var current_tier: int = get_upgrade_tier(path_id)
	if current_tier >= tiers.size():
		return {}
	var tier_data_variant: Variant = tiers[current_tier]
	if tier_data_variant is not Dictionary:
		return {}
	var tier_data: Dictionary = (tier_data_variant as Dictionary).duplicate(true)
	tier_data["tier"] = current_tier + 1
	tier_data["path_id"] = String(path_id)
	tier_data["path_name"] = String(path_data.get("name", path_id))
	tier_data["stat_key"] = String(path_data.get("stat_key", ""))
	return tier_data


func preview_upgrade_stat(path_id: StringName) -> Dictionary:
	var path_data: Dictionary = ContentDatabase.get_upgrade_path(path_id)
	if path_data.is_empty():
		return {}
	var next_tier_data: Dictionary = get_next_upgrade_tier_data(path_id)
	if next_tier_data.is_empty():
		return {}
	var stat_key: StringName = StringName(String(path_data.get("stat_key", "")))
	var before_value: float = get_effective_stat(stat_key)
	var key: String = String(path_id)
	var previous_tier: int = get_upgrade_tier(path_id)
	installed_upgrades[key] = previous_tier + 1
	var after_value: float = get_effective_stat(stat_key)
	installed_upgrades[key] = previous_tier
	return {"before": before_value, "after": after_value, "stat_key": String(stat_key)}


func can_purchase_upgrade(path_id: StringName) -> Dictionary:
	var next_tier_data: Dictionary = get_next_upgrade_tier_data(path_id)
	if next_tier_data.is_empty():
		return {"can_purchase": false, "reason": "Max tier reached."}
	var credits_cost: int = int(next_tier_data.get("cost_credits", 0))
	if credits < credits_cost:
		return {"can_purchase": false, "reason": "Not enough credits.", "missing_credits": credits_cost - credits}
	var missing_inputs: Array[String] = []
	for cost_variant in next_tier_data.get("cost_items", []):
		if cost_variant is not Dictionary:
			continue
		var cost_data: Dictionary = cost_variant
		var item_id: StringName = StringName(String(cost_data.get("item_id", "")))
		var required_quantity: int = int(cost_data.get("quantity", 0))
		if required_quantity <= 0:
			continue
		if has_cargo(item_id, required_quantity):
			continue
		missing_inputs.append("%s x%d" % [_get_item_name(item_id), required_quantity])
	if not missing_inputs.is_empty():
		return {"can_purchase": false, "reason": "Missing materials.", "missing": missing_inputs}
	return {"can_purchase": true}


func purchase_upgrade(path_id: StringName) -> Dictionary:
	var path_data: Dictionary = ContentDatabase.get_upgrade_path(path_id)
	if path_data.is_empty():
		return {"success": false, "message": "Unknown upgrade path."}
	var check: Dictionary = can_purchase_upgrade(path_id)
	if not bool(check.get("can_purchase", false)):
		return {"success": false, "message": String(check.get("reason", "Requirements not met."))}
	var next_tier_data: Dictionary = get_next_upgrade_tier_data(path_id)
	if next_tier_data.is_empty():
		return {"success": false, "message": "Max tier reached."}

	var stat_key: StringName = StringName(String(path_data.get("stat_key", "")))
	var before_value: float = get_effective_stat(stat_key)
	var before_max_hull: float = get_max_hull()
	var before_max_shield: float = get_max_shield()
	var missing_hull: float = before_max_hull - current_hull
	var missing_shield: float = before_max_shield - current_shield

	credits -= int(next_tier_data.get("cost_credits", 0))
	for cost_variant in next_tier_data.get("cost_items", []):
		if cost_variant is not Dictionary:
			continue
		var cost_data: Dictionary = cost_variant
		var remove_id: StringName = StringName(String(cost_data.get("item_id", "")))
		var remove_qty: int = int(cost_data.get("quantity", 0))
		if remove_qty <= 0:
			continue
		remove_cargo(remove_id, remove_qty)

	var key: String = String(path_id)
	installed_upgrades[key] = get_upgrade_tier(path_id) + 1
	upgrades_changed.emit()
	stats_recalculated.emit()

	var after_max_hull: float = get_max_hull()
	var after_max_shield: float = get_max_shield()
	current_hull = clampf(after_max_hull - missing_hull, 0.0, after_max_hull)
	current_shield = clampf(after_max_shield - missing_shield, 0.0, after_max_shield)
	hull_changed.emit(current_hull, after_max_hull)
	shield_changed.emit(current_shield, after_max_shield)

	var after_value: float = get_effective_stat(stat_key)
	return {
		"success": true,
		"message": "%s Mk %d purchased." % [String(path_data.get("name", path_id)), int(next_tier_data.get("tier", 1))],
		"before_value": before_value,
		"after_value": after_value,
		"stat_key": String(stat_key),
	}


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


func disable_player_shields(duration: float) -> void:
	if duration <= 0.0:
		return
	var had_shield: bool = current_shield > 0.0
	current_shield = 0.0
	_shield_recharge_delay_remaining = maxf(_shield_recharge_delay_remaining, duration)
	shield_changed.emit(current_shield, get_max_shield())
	if had_shield:
		shield_depleted.emit()


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
		var item_def: Dictionary = ContentDatabase.get_item_definition(resource_id)
		if item_def.is_empty():
			item_def = ContentDatabase.get_resource_definition(resource_id)
		var cargo_size: int = int(item_def.get("cargo_size", 1))
		used += quantity * max(cargo_size, 1)
	return used


func get_cargo_capacity() -> int:
	return max(int(round(get_effective_stat(&"cargo_capacity"))), 0)


func get_cargo_free() -> int:
	return max(get_cargo_capacity() - get_cargo_used(), 0)


func has_cargo(resource_id: StringName, quantity: int) -> bool:
	if quantity <= 0:
		return true
	if _is_relic_inventory_item(resource_id):
		return get_relic_quantity(resource_id) >= quantity
	return _find_cargo_entry_quantity(resource_id) >= quantity


func add_cargo(resource_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0

	if _is_relic_inventory_item(resource_id):
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
	if _is_relic_inventory_item(resource_id):
		var relic_quantity: int = get_relic_quantity(resource_id)
		if relic_quantity < quantity:
			return false
		_add_relic_quantity(resource_id, -quantity)
		cargo_changed.emit()
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
	var compat_key: String = String(slot_name)
	if COMPAT_KEY_TO_SLOT.has(compat_key):
		return StringName(String(ship_loadout.get(String(COMPAT_KEY_TO_SLOT[compat_key]), "")))
	return StringName(String(ship_loadout.get(compat_key, "")))


func get_equipped_weapon_definition(slot_name: StringName) -> Dictionary:
	var weapon_id: StringName = get_equipped_weapon_id(slot_name)
	if weapon_id == &"":
		return {}
	return ContentDatabase.get_weapon_definition(weapon_id)


func set_equipped_weapon(slot_name: StringName, weapon_id: StringName) -> void:
	var compat_key: String = String(slot_name)
	var slot_key: String = compat_key
	if COMPAT_KEY_TO_SLOT.has(compat_key):
		slot_key = String(COMPAT_KEY_TO_SLOT[compat_key])
	var result: Dictionary = equip_module(StringName(slot_key), weapon_id, true)
	if not bool(result.get("success", false)):
		push_warning("GameStateManager failed to equip %s in %s: %s" % [weapon_id, slot_name, String(result.get("message", "unknown"))])


func get_equipped_module_id(slot_name: StringName) -> StringName:
	var key: String = String(slot_name)
	if key.is_empty():
		return &""
	return StringName(String(ship_loadout.get(key, "")))


func get_equipped_module_definition(slot_name: StringName) -> Dictionary:
	var module_id: StringName = get_equipped_module_id(slot_name)
	if module_id == &"":
		return {}
	return ContentDatabase.get_module_definition(module_id)


func get_owned_modules() -> Array[String]:
	return owned_modules.duplicate()


func get_ship_loadout() -> Dictionary:
	return ship_loadout.duplicate(true)


func is_module_owned(module_id: StringName) -> bool:
	var key: String = String(module_id)
	if key.is_empty():
		return false
	return owned_modules.has(key)


func add_owned_module(module_id: StringName) -> void:
	var key: String = String(module_id)
	if key.is_empty():
		return
	if owned_modules.has(key):
		return
	owned_modules.append(key)
	loadout_changed.emit()


func can_purchase_module(module_id: StringName) -> Dictionary:
	var module_data: Dictionary = ContentDatabase.get_module_definition(module_id)
	if module_data.is_empty():
		return {"can_purchase": false, "reason": "Unknown module."}
	if is_module_owned(module_id):
		return {"can_purchase": false, "reason": "Module already owned."}
	var credits_cost: int = int(module_data.get("cost_credits", 0))
	var missing: Array[String] = []
	if credits < credits_cost:
		missing.append("%d credits" % (credits_cost - credits))
	for cost_variant in module_data.get("cost_items", []):
		if cost_variant is not Dictionary:
			continue
		var cost_data: Dictionary = cost_variant
		var item_id: StringName = StringName(String(cost_data.get("item_id", "")))
		var quantity: int = int(cost_data.get("quantity", 0))
		if quantity <= 0:
			continue
		if has_cargo(item_id, quantity):
			continue
		missing.append("%s x%d" % [_get_item_name(item_id), quantity])
	if not missing.is_empty():
		return {"can_purchase": false, "reason": "Missing requirements: %s" % ", ".join(missing), "missing": missing}
	return {"can_purchase": true}


func purchase_module(module_id: StringName) -> Dictionary:
	var module_data: Dictionary = ContentDatabase.get_module_definition(module_id)
	if module_data.is_empty():
		return {"success": false, "message": "Unknown module."}
	var check: Dictionary = can_purchase_module(module_id)
	if not bool(check.get("can_purchase", false)):
		return {"success": false, "message": String(check.get("reason", "Requirements not met."))}
	credits -= int(module_data.get("cost_credits", 0))
	for cost_variant in module_data.get("cost_items", []):
		if cost_variant is not Dictionary:
			continue
		var cost_data: Dictionary = cost_variant
		var item_id: StringName = StringName(String(cost_data.get("item_id", "")))
		var quantity: int = int(cost_data.get("quantity", 0))
		if quantity <= 0:
			continue
		remove_cargo(item_id, quantity)
	add_owned_module(module_id)
	return {"success": true, "message": "%s acquired." % String(module_data.get("name", module_id))}


func can_equip_module(slot_name: StringName, module_id: StringName) -> Dictionary:
	var slot_key: String = String(slot_name)
	if slot_key.is_empty() or not LOADOUT_SLOT_NAMES.has(StringName(slot_key)):
		return {"can_equip": false, "reason": "Invalid slot."}
	if slot_key == "special_module" and not has_progression_flag(&"special_module_slot_unlocked"):
		return {"can_equip": false, "reason": "Special slot is locked."}
	if module_id != &"":
		var module_data: Dictionary = ContentDatabase.get_module_definition(module_id)
		if module_data.is_empty():
			return {"can_equip": false, "reason": "Unknown module."}
		if not is_module_owned(module_id):
			return {"can_equip": false, "reason": "Module not owned."}
		if String(module_data.get("slot", "")) != slot_key:
			return {"can_equip": false, "reason": "Wrong slot type."}

	var power_capacity: float = get_effective_stat(&"power_capacity")
	var projected_usage: float = _calculate_power_usage_with_override(slot_key, module_id)
	if projected_usage > power_capacity + 0.001:
		return {
			"can_equip": false,
			"reason": "Power budget exceeded.",
			"power_used": projected_usage,
			"power_capacity": power_capacity,
		}

	return {
		"can_equip": true,
		"power_used": projected_usage,
		"power_capacity": power_capacity,
	}


func equip_module(slot_name: StringName, module_id: StringName, allow_unsafe: bool = false) -> Dictionary:
	var slot_key: String = String(slot_name)
	if slot_key.is_empty():
		return {"success": false, "message": "Invalid slot."}
	if not allow_unsafe:
		var check: Dictionary = can_equip_module(slot_name, module_id)
		if not bool(check.get("can_equip", false)):
			return {"success": false, "message": String(check.get("reason", "Equip blocked."))}

	ship_loadout[slot_key] = String(module_id)
	_sync_equipped_modules_cache()
	loadout_changed.emit()
	stats_recalculated.emit()
	hull_changed.emit(current_hull, get_max_hull())
	shield_changed.emit(current_shield, get_max_shield())
	return {"success": true}


func get_power_usage() -> float:
	return _calculate_power_usage_with_override("", &"")


func get_power_capacity() -> float:
	return get_effective_stat(&"power_capacity")


func get_loadout_mass() -> float:
	return _calculate_loadout_mass_with_override("", &"")


func preview_power_usage(slot_name: StringName, module_id: StringName) -> float:
	return _calculate_power_usage_with_override(String(slot_name), module_id)


func preview_loadout_mass(slot_name: StringName, module_id: StringName) -> float:
	return _calculate_loadout_mass_with_override(String(slot_name), module_id)


func get_agility_multiplier_for_mass(mass_value: float = -1.0) -> float:
	if mass_value < 0.0:
		mass_value = get_total_mass()
	return maxf(0.3, 1.0 - (mass_value * 0.01))


func add_relic(relic_id: StringName, quantity: int) -> void:
	if quantity <= 0:
		return
	_add_relic_quantity(relic_id, quantity)
	cargo_changed.emit()


func get_relic_quantity(relic_id: StringName) -> int:
	return int(relic_inventory.get(String(relic_id), 0))


func repair_hull(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var max_hull: float = get_max_hull()
	var before: float = current_hull
	current_hull = minf(current_hull + amount, max_hull)
	if current_hull != before:
		hull_changed.emit(current_hull, max_hull)
	return current_hull - before


func set_progression_flag(flag_name: StringName, enabled: bool = true) -> void:
	var key: String = String(flag_name)
	if key.is_empty():
		return
	progression_flags[key] = enabled


func has_progression_flag(flag_name: StringName) -> bool:
	return bool(progression_flags.get(String(flag_name), false))


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
		var item_def: Dictionary = ContentDatabase.get_item_definition(resource_id)
		if item_def.is_empty():
			item_def = ContentDatabase.get_resource_definition(resource_id)
		var cargo_size: float = float(item_def.get("cargo_size", 1.0))
		total_weight += float(quantity) * cargo_size
	return total_weight


func get_total_mass() -> float:
	var loadout_mass: float = get_loadout_mass()
	var upgrade_mass: float = 0.0
	for tier_variant in installed_upgrades.values():
		var tier_value: int = max(int(tier_variant), 0)
		upgrade_mass += float(tier_value) * 0.45
	return loadout_mass + upgrade_mass


func _apply_upgrade_bonus(stat_key: String, base_value: float) -> float:
	var adjusted: float = base_value
	for path_variant in ContentDatabase.get_all_upgrade_paths().values():
		if path_variant is not Dictionary:
			continue
		var path_data: Dictionary = path_variant
		if String(path_data.get("stat_key", "")) != stat_key:
			continue

		var path_id: String = String(path_data.get("id", ""))
		if path_id.is_empty():
			continue
		var tier: int = get_upgrade_tier(StringName(path_id))
		if tier <= 0:
			continue
		var tiers: Array = path_data.get("tiers", [])
		if tier - 1 < 0 or tier - 1 >= tiers.size():
			continue
		var tier_data_variant: Variant = tiers[tier - 1]
		if tier_data_variant is not Dictionary:
			continue
		var tier_data: Dictionary = tier_data_variant
		var bonus_mode: String = String(tier_data.get("bonus_mode", "add"))
		var bonus_value: float = float(tier_data.get("bonus_value", 0.0))
		match bonus_mode:
			"add":
				adjusted = base_value + bonus_value
			"mul":
				adjusted = base_value * (1.0 + bonus_value)
			"set":
				adjusted = bonus_value
			_:
				adjusted = adjusted
	return adjusted


func _apply_module_bonus(stat_key: String, current_value: float) -> float:
	var adjusted: float = current_value
	for slot_variant in LOADOUT_SLOT_NAMES:
		var slot_key: String = String(slot_variant)
		var module_id: StringName = get_equipped_module_id(StringName(slot_key))
		if module_id == &"":
			continue
		var module_data: Dictionary = ContentDatabase.get_module_definition(module_id)
		if module_data.is_empty():
			continue
		var stat_bonuses: Dictionary = module_data.get("stat_bonuses", {})
		if not stat_bonuses.has(stat_key):
			continue
		var bonus_data_variant: Variant = stat_bonuses[stat_key]
		if bonus_data_variant is not Dictionary:
			continue
		var bonus_data: Dictionary = bonus_data_variant
		var mode: String = String(bonus_data.get("mode", "add"))
		var value: float = float(bonus_data.get("value", 0.0))
		match mode:
			"add":
				adjusted += value
			"mul":
				adjusted *= (1.0 + value)
			"set":
				adjusted = value
			_:
				adjusted = adjusted
	return adjusted


func _apply_mass_penalty_to_stat(stat_key: String, current_value: float) -> float:
	if stat_key != "thrust" and stat_key != "turn_speed":
		return current_value
	var mass_multiplier: float = maxf(0.3, 1.0 - (get_total_mass() * 0.01))
	return current_value * mass_multiplier


func _apply_stat_special_cases(stat_key: String, current_value: float) -> float:
	if stat_key == "scanner_cooldown":
		var scanner_tier: int = get_upgrade_tier(&"scanner")
		match scanner_tier:
			1:
				return 6.0
			2:
				return 4.0
			3:
				return 2.0
			_:
				return current_value
	return current_value


func _build_starting_owned_modules() -> Array[String]:
	var result: Array[String] = []
	for module_variant in ContentDatabase.get_all_module_definitions().values():
		if module_variant is not Dictionary:
			continue
		var module_data: Dictionary = module_variant
		if not bool(module_data.get("starting_owned", false)):
			continue
		var module_id: String = String(module_data.get("id", ""))
		if module_id.is_empty():
			continue
		result.append(module_id)
	if not result.has("pulse_laser"):
		result.append("pulse_laser")
	return result


func _sync_equipped_modules_cache() -> void:
	equipped_modules = {
		"primary": String(ship_loadout.get("primary_weapon", "")),
		"secondary": String(ship_loadout.get("secondary_weapon", "")),
		"utility": String(ship_loadout.get("utility_module", "")),
		"special": String(ship_loadout.get("special_module", "")),
	}


func _calculate_power_usage_with_override(slot_key: String, module_id: StringName) -> float:
	var total_power: float = 0.0
	for slot_variant in LOADOUT_SLOT_NAMES:
		var each_slot: String = String(slot_variant)
		var equipped_id: StringName = get_equipped_module_id(StringName(each_slot))
		if each_slot == slot_key:
			equipped_id = module_id
		if equipped_id == &"":
			continue
		var module_data: Dictionary = ContentDatabase.get_module_definition(equipped_id)
		if module_data.is_empty():
			var weapon_data: Dictionary = ContentDatabase.get_weapon_definition(equipped_id)
			total_power += float(weapon_data.get("power_draw", 0.0))
			continue
		total_power += float(module_data.get("power_draw", 0.0))
	return total_power


func _calculate_loadout_mass_with_override(slot_key: String, module_id: StringName) -> float:
	var total_mass: float = 0.0
	for slot_variant in LOADOUT_SLOT_NAMES:
		var each_slot: String = String(slot_variant)
		var equipped_id: StringName = get_equipped_module_id(StringName(each_slot))
		if each_slot == slot_key:
			equipped_id = module_id
		if equipped_id == &"":
			continue
		var module_data: Dictionary = ContentDatabase.get_module_definition(equipped_id)
		if module_data.is_empty():
			var weapon_data: Dictionary = ContentDatabase.get_weapon_definition(equipped_id)
			total_mass += float(weapon_data.get("mass", 0.0))
			continue
		total_mass += float(module_data.get("mass", 0.0))
	return total_mass


func _get_item_name(item_id: StringName) -> String:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	return String(item_def.get("name", item_id))


func _find_cargo_entry_quantity(resource_id: StringName) -> int:
	var key: String = String(resource_id)
	for entry_variant in cargo:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("resource_id", "")) == key:
			return int(entry.get("quantity", 0))
	return 0


func _is_relic_inventory_item(item_id: StringName) -> bool:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		return false
	if bool(item_def.get("store_in_relic_inventory", false)):
		return true
	return String(item_def.get("category", "")) == "mission_item"


func _add_relic_quantity(item_id: StringName, delta_quantity: int) -> void:
	if delta_quantity == 0:
		return
	var key: String = String(item_id)
	var next_value: int = int(relic_inventory.get(key, 0)) + delta_quantity
	if next_value <= 0:
		relic_inventory.erase(key)
		return
	relic_inventory[key] = next_value


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
