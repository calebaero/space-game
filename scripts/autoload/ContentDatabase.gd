extends Node

signal content_loaded

const GALAXY_DATA_PATHS := [
	"res://data/galaxies/galaxy_01_frontier_verge.tres",
	"res://data/galaxies/galaxy_02_ion_expanse.tres",
	"res://data/galaxies/galaxy_03_relic_reach.tres",
]
const RESOURCE_CATALOG_PATH: String = "res://data/items/resources.tres"
const ITEM_CATALOG_PATH: String = "res://data/items/items.tres"
const WEAPON_CATALOG_PATH: String = "res://data/items/weapons.tres"
const ENEMY_ARCHETYPES_PATH: String = "res://data/enemies/enemy_archetypes.tres"
const MARKET_PROFILE_PATH: String = "res://data/economy/market_profiles.tres"
const REFINING_RECIPES_PATH: String = "res://data/economy/refining_recipes.tres"
const CRAFTING_RECIPES_PATH: String = "res://data/economy/crafting_recipes.tres"

const SECTOR_DATA_PATHS := [
	"res://data/sectors/sector_anchor_station.tres",
	"res://data/sectors/sector_ferrite_belt.tres",
	"res://data/sectors/sector_red_corsair_run.tres",
	"res://data/sectors/sector_relay_market.tres",
	"res://data/sectors/sector_storm_fields.tres",
	"res://data/sectors/sector_drone_foundry.tres",
	"res://data/sectors/sector_archive_gate.tres",
	"res://data/sectors/sector_silent_orbit.tres",
	"res://data/sectors/sector_core_bastion.tres",
]

var _galaxies: Dictionary = {}
var _sectors: Dictionary = {}
var _resources_by_id: Dictionary = {}
var _items_by_id: Dictionary = {}
var _weapons_by_id: Dictionary = {}
var _enemy_archetypes_by_id: Dictionary = {}
var _node_tiers_by_tier: Dictionary = {}
var _hazard_types_by_id: Dictionary = {}
var _market_profile: Dictionary = {}
var _refining_recipes: Array[Dictionary] = []
var _crafting_recipes: Array[Dictionary] = []
var _is_loaded: bool = false


func _ready() -> void:
	load_content()


func load_content(force_reload: bool = false) -> void:
	if _is_loaded and not force_reload:
		return

	_galaxies.clear()
	_sectors.clear()
	_resources_by_id.clear()
	_items_by_id.clear()
	_weapons_by_id.clear()
	_enemy_archetypes_by_id.clear()
	_node_tiers_by_tier.clear()
	_hazard_types_by_id.clear()
	_market_profile.clear()
	_refining_recipes.clear()
	_crafting_recipes.clear()
	_load_resource_catalog()
	_load_item_catalog()
	_load_weapon_catalog()
	_load_enemy_archetypes()
	_load_market_profile()
	_load_recipe_catalogs()
	_load_galaxies()
	_load_sectors()
	_is_loaded = true
	content_loaded.emit()


func ensure_loaded() -> void:
	if not _is_loaded:
		load_content()


func get_all_galaxies() -> Dictionary:
	ensure_loaded()
	return _galaxies.duplicate(true)


func get_all_sectors() -> Dictionary:
	ensure_loaded()
	return _sectors.duplicate(true)


func get_galaxy(galaxy_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(galaxy_id)
	if not _galaxies.has(key):
		return {}
	return (_galaxies[key] as Dictionary).duplicate(true)


func get_sector(sector_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(sector_id)
	if not _sectors.has(key):
		return {}
	return (_sectors[key] as Dictionary).duplicate(true)


func get_starting_galaxy() -> Dictionary:
	ensure_loaded()
	for galaxy_data in _galaxies.values():
		var as_dict: Dictionary = galaxy_data
		if String(as_dict.get("unlock_requirement", "")) == "start":
			return as_dict.duplicate(true)
	return {}


func get_starting_sector_id() -> StringName:
	var starting_galaxy: Dictionary = get_starting_galaxy()
	if starting_galaxy.is_empty():
		return &"anchor_station"

	var sectors: Array = starting_galaxy.get("sectors", [])
	if sectors.is_empty():
		return &"anchor_station"

	return StringName(String(sectors[0]))


func get_all_resource_definitions() -> Dictionary:
	ensure_loaded()
	return _resources_by_id.duplicate(true)


func get_all_item_definitions() -> Dictionary:
	ensure_loaded()
	var merged: Dictionary = _items_by_id.duplicate(true)
	for key_variant in _resources_by_id.keys():
		var key: String = String(key_variant)
		if merged.has(key):
			continue
		merged[key] = (_resources_by_id[key] as Dictionary).duplicate(true)
	return merged


func get_resource_definition(resource_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(resource_id)
	if not _resources_by_id.has(key):
		return {}
	return (_resources_by_id[key] as Dictionary).duplicate(true)


func get_item_definition(item_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(item_id)
	if _items_by_id.has(key):
		return (_items_by_id[key] as Dictionary).duplicate(true)
	if _resources_by_id.has(key):
		return (_resources_by_id[key] as Dictionary).duplicate(true)
	return {}


func get_all_weapon_definitions() -> Dictionary:
	ensure_loaded()
	return _weapons_by_id.duplicate(true)


func get_weapon_definition(weapon_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(weapon_id)
	if not _weapons_by_id.has(key):
		return {}
	return (_weapons_by_id[key] as Dictionary).duplicate(true)


func get_all_enemy_archetypes() -> Dictionary:
	ensure_loaded()
	return _enemy_archetypes_by_id.duplicate(true)


func get_enemy_archetype_definition(archetype_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(archetype_id)
	if not _enemy_archetypes_by_id.has(key):
		return {}
	return (_enemy_archetypes_by_id[key] as Dictionary).duplicate(true)


func get_node_tier_definition(tier: int) -> Dictionary:
	ensure_loaded()
	if not _node_tiers_by_tier.has(tier):
		return {}
	return (_node_tiers_by_tier[tier] as Dictionary).duplicate(true)


func get_hazard_type_definition(hazard_id: StringName) -> Dictionary:
	ensure_loaded()
	var key: String = String(hazard_id)
	if not _hazard_types_by_id.has(key):
		return {}
	return (_hazard_types_by_id[key] as Dictionary).duplicate(true)


func get_all_hazard_type_definitions() -> Dictionary:
	ensure_loaded()
	return _hazard_types_by_id.duplicate(true)


func get_market_profile_data() -> Dictionary:
	ensure_loaded()
	return _market_profile.duplicate(true)


func get_refining_recipes() -> Array[Dictionary]:
	ensure_loaded()
	return _refining_recipes.duplicate(true)


func get_crafting_recipes() -> Array[Dictionary]:
	ensure_loaded()
	return _crafting_recipes.duplicate(true)


func _load_resource_catalog() -> void:
	var catalog_resource: Resource = load(RESOURCE_CATALOG_PATH)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load resource catalog at: %s" % RESOURCE_CATALOG_PATH)
		return
	if not (catalog_resource is ResourceCatalog):
		push_warning("Resource catalog has wrong type at: %s" % RESOURCE_CATALOG_PATH)
		return

	var catalog: ResourceCatalog = catalog_resource
	for resource_variant in catalog.resources:
		if resource_variant is not Dictionary:
			continue
		var resource_entry: Dictionary = (resource_variant as Dictionary).duplicate(true)
		var resource_id: String = String(resource_entry.get("id", ""))
		if resource_id.is_empty():
			continue
		_resources_by_id[resource_id] = resource_entry

	for tier_variant in catalog.node_tiers:
		if tier_variant is not Dictionary:
			continue
		var tier_entry: Dictionary = (tier_variant as Dictionary).duplicate(true)
		var tier: int = int(tier_entry.get("tier", -1))
		if tier < 0:
			continue
		_node_tiers_by_tier[tier] = tier_entry

	for hazard_variant in catalog.hazard_types:
		if hazard_variant is not Dictionary:
			continue
		var hazard_entry: Dictionary = (hazard_variant as Dictionary).duplicate(true)
		var hazard_id: String = String(hazard_entry.get("id", ""))
		if hazard_id.is_empty():
			continue
		_hazard_types_by_id[hazard_id] = hazard_entry


func _load_item_catalog() -> void:
	var catalog_resource: Resource = load(ITEM_CATALOG_PATH)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load item catalog at: %s" % ITEM_CATALOG_PATH)
		return
	if not (catalog_resource is ItemCatalog):
		push_warning("Item catalog has wrong type at: %s" % ITEM_CATALOG_PATH)
		return

	var catalog: ItemCatalog = catalog_resource
	for item_variant in catalog.items:
		if item_variant is not Dictionary:
			continue
		var item_entry: Dictionary = (item_variant as Dictionary).duplicate(true)
		var item_id: String = String(item_entry.get("id", ""))
		if item_id.is_empty():
			continue
		_items_by_id[item_id] = item_entry


func _load_weapon_catalog() -> void:
	var catalog_resource: Resource = load(WEAPON_CATALOG_PATH)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load weapon catalog at: %s" % WEAPON_CATALOG_PATH)
		return
	if not (catalog_resource is WeaponCatalog):
		push_warning("Weapon catalog has wrong type at: %s" % WEAPON_CATALOG_PATH)
		return

	var catalog: WeaponCatalog = catalog_resource
	for weapon_variant in catalog.weapons:
		if weapon_variant is not Dictionary:
			continue
		var weapon_entry: Dictionary = (weapon_variant as Dictionary).duplicate(true)
		var weapon_id: String = String(weapon_entry.get("id", ""))
		if weapon_id.is_empty():
			continue
		_weapons_by_id[weapon_id] = weapon_entry


func _load_enemy_archetypes() -> void:
	var catalog_resource: Resource = load(ENEMY_ARCHETYPES_PATH)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load enemy archetypes at: %s" % ENEMY_ARCHETYPES_PATH)
		return
	if not (catalog_resource is EnemyCatalog):
		push_warning("Enemy archetype catalog has wrong type at: %s" % ENEMY_ARCHETYPES_PATH)
		return

	var catalog: EnemyCatalog = catalog_resource
	for archetype_variant in catalog.archetypes:
		if archetype_variant is not Dictionary:
			continue
		var archetype_entry: Dictionary = (archetype_variant as Dictionary).duplicate(true)
		var archetype_id: String = String(archetype_entry.get("id", ""))
		if archetype_id.is_empty():
			continue
		_enemy_archetypes_by_id[archetype_id] = archetype_entry


func _load_market_profile() -> void:
	var catalog_resource: Resource = load(MARKET_PROFILE_PATH)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load market profile at: %s" % MARKET_PROFILE_PATH)
		return
	if not (catalog_resource is EconomyCatalog):
		push_warning("Market profile has wrong type at: %s" % MARKET_PROFILE_PATH)
		return

	var catalog: EconomyCatalog = catalog_resource
	_market_profile = {
		"station_type_modifiers": catalog.station_type_modifiers.duplicate(true),
		"commodity_availability": catalog.commodity_availability.duplicate(true),
		"station_price_variance_min": catalog.station_price_variance_min,
		"station_price_variance_max": catalog.station_price_variance_max,
		"commodity_stock_min": catalog.commodity_stock_min,
		"commodity_stock_max": catalog.commodity_stock_max,
	}


func _load_recipe_catalogs() -> void:
	_refining_recipes = _load_recipe_catalog(REFINING_RECIPES_PATH)
	_crafting_recipes = _load_recipe_catalog(CRAFTING_RECIPES_PATH)


func _load_recipe_catalog(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog_resource: Resource = load(path)
	if catalog_resource == null:
		push_warning("ContentDatabase failed to load recipe catalog at: %s" % path)
		return result
	if not (catalog_resource is RecipeCatalog):
		push_warning("Recipe catalog has wrong type at: %s" % path)
		return result

	var catalog: RecipeCatalog = catalog_resource
	for recipe_variant in catalog.recipes:
		if recipe_variant is not Dictionary:
			continue
		result.append((recipe_variant as Dictionary).duplicate(true))
	return result


func _load_galaxies() -> void:
	for path in GALAXY_DATA_PATHS:
		var resource: Resource = load(path)
		if resource == null:
			push_warning("ContentDatabase failed to load galaxy resource at: %s" % path)
			continue
		if not (resource is GalaxyDefinition):
			push_warning("Galaxy resource has wrong type at: %s" % path)
			continue

		var galaxy: GalaxyDefinition = resource
		var key: String = String(galaxy.id)
		_galaxies[key] = {
			"id": key,
			"name": galaxy.display_name,
			"sectors": galaxy.sector_ids.duplicate(),
			"unlock_requirement": String(galaxy.unlock_requirement),
		}


func _load_sectors() -> void:
	for path in SECTOR_DATA_PATHS:
		var resource: Resource = load(path)
		if resource == null:
			push_warning("ContentDatabase failed to load sector resource at: %s" % path)
			continue
		if not (resource is SectorDefinition):
			push_warning("Sector resource has wrong type at: %s" % path)
			continue

		var sector: SectorDefinition = resource
		var key: String = String(sector.id)
		var station_data: Dictionary = sector.station_data.duplicate(true)
		var station_id: Variant = station_data.get("id", null)
		var station_economy_type: Variant = station_data.get("economy_type", null)
		_sectors[key] = {
			"id": key,
			"name": sector.display_name,
			"galaxy_id": String(sector.galaxy_id),
			"connections": sector.connections.duplicate(true),
			"threat_level": sector.threat_level,
			"background_tint": sector.background_tint,
			"station": station_data,
			"planets": sector.planets.duplicate(true),
			"warp_gates": sector.warp_gates.duplicate(true),
			"anomaly_points": sector.anomaly_points.duplicate(true),
			"resource_nodes": sector.resource_nodes.duplicate(true),
			"asteroid_fields": sector.asteroid_fields.duplicate(true),
			"hazard_zones": sector.hazard_zones.duplicate(true),
			"loot_crates": sector.loot_crates.duplicate(true),
			"enemy_patrols": sector.enemy_patrols.duplicate(true),
			"station_id": station_id,
			"station_economy_type": station_economy_type,
			"hazard_types": Array(sector.hazard_types),
			"content_tags": Array(sector.content_tags),
		}
