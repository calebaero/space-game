extends RefCounted
class_name SectorPopulator

const PLANET_SCENE: PackedScene = preload("res://scenes/world/Planet.tscn")
const STATION_SCENE: PackedScene = preload("res://scenes/world/SpaceStation.tscn")
const WARP_GATE_SCENE: PackedScene = preload("res://scenes/world/WarpGate.tscn")
const ANOMALY_POINT_SCENE: PackedScene = preload("res://scenes/world/AnomalyPoint.tscn")
const RESOURCE_NODE_SCENE: PackedScene = preload("res://scenes/world/ResourceNode.tscn")
const ASTEROID_FIELD_SCENE: PackedScene = preload("res://scenes/world/AsteroidField.tscn")
const HAZARD_ZONE_SCENE: PackedScene = preload("res://scenes/world/HazardZone.tscn")
const LOOT_CRATE_SCENE: PackedScene = preload("res://scenes/world/LootCrate.tscn")
const ENEMY_SHIP_SCENE: PackedScene = preload("res://scenes/enemies/EnemyShip.tscn")
const WRECK_BEACON_SCENE: PackedScene = preload("res://scenes/world/WreckBeacon.tscn")


func populate_sector(content_root: Node2D, sector_data: Dictionary) -> Dictionary:
	_clear_root(content_root)

	var result: Dictionary = {
		"station": null,
		"planets": [],
		"warp_gates": [],
		"anomalies": [],
		"resource_nodes": [],
		"asteroid_fields": [],
		"hazard_zones": [],
		"loot_crates": [],
		"enemy_ships": [],
		"wreck_beacon": null,
	}

	var seed_value: int = hash(String(sector_data.get("id", "")))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	for hazard_data_variant in sector_data.get("hazard_zones", []):
		if hazard_data_variant is not Dictionary:
			continue
		var hazard_data: Dictionary = (hazard_data_variant as Dictionary).duplicate(true)
		var hazard_node: Area2D = HAZARD_ZONE_SCENE.instantiate() as Area2D
		if hazard_node == null:
			continue

		hazard_node.position = hazard_data.get("position", Vector2.ZERO)
		content_root.add_child(hazard_node)
		if hazard_node.has_method("configure"):
			hazard_node.call("configure", hazard_data)
		result["hazard_zones"].append(hazard_node)

	for field_data_variant in sector_data.get("asteroid_fields", []):
		if field_data_variant is not Dictionary:
			continue
		var field_data: Dictionary = (field_data_variant as Dictionary).duplicate(true)
		var field_node: Node2D = ASTEROID_FIELD_SCENE.instantiate() as Node2D
		if field_node == null:
			continue

		field_node.position = field_data.get("position", Vector2.ZERO)
		content_root.add_child(field_node)
		if field_node.has_method("configure"):
			field_node.call("configure", field_data)
		result["asteroid_fields"].append(field_node)

	for planet_data_variant in sector_data.get("planets", []):
		if planet_data_variant is not Dictionary:
			continue
		var planet_data: Dictionary = (planet_data_variant as Dictionary).duplicate(true)
		var planet_node: Node2D = PLANET_SCENE.instantiate() as Node2D
		if planet_node == null:
			continue

		planet_node.position = planet_data.get("position", Vector2.ZERO)
		content_root.add_child(planet_node)
		if planet_node.has_method("configure"):
			planet_node.call("configure", planet_data)
		result["planets"].append(planet_node)

	for node_data_variant in sector_data.get("resource_nodes", []):
		if node_data_variant is not Dictionary:
			continue
		var node_data: Dictionary = (node_data_variant as Dictionary).duplicate(true)
		var resource_node: StaticBody2D = RESOURCE_NODE_SCENE.instantiate() as StaticBody2D
		if resource_node == null:
			continue

		var node_position: Vector2 = node_data.get("position", Vector2.ZERO)
		if node_position == Vector2.ZERO:
			node_position = Vector2(rng.randf_range(-2100.0, 2100.0), rng.randf_range(-2100.0, 2100.0))
		resource_node.position = node_position
		content_root.add_child(resource_node)
		if resource_node.has_method("configure"):
			resource_node.call("configure", node_data)
		result["resource_nodes"].append(resource_node)

	for loot_data_variant in sector_data.get("loot_crates", []):
		if loot_data_variant is not Dictionary:
			continue
		var loot_data: Dictionary = (loot_data_variant as Dictionary).duplicate(true)
		var loot_node: Area2D = LOOT_CRATE_SCENE.instantiate() as Area2D
		if loot_node == null:
			continue

		loot_node.position = loot_data.get("position", Vector2.ZERO)
		content_root.add_child(loot_node)
		if loot_node.has_method("configure"):
			loot_node.call("configure", loot_data)
		result["loot_crates"].append(loot_node)

	var station_data: Dictionary = sector_data.get("station", {})
	if not station_data.is_empty():
		var station_node: Node2D = STATION_SCENE.instantiate() as Node2D
		if station_node != null:
			station_node.position = station_data.get("position", Vector2.ZERO)
			content_root.add_child(station_node)
			if station_node.has_method("configure"):
				station_node.call("configure", station_data)
			result["station"] = station_node

	for gate_data_variant in sector_data.get("warp_gates", []):
		if gate_data_variant is not Dictionary:
			continue
		var gate_data: Dictionary = (gate_data_variant as Dictionary).duplicate(true)
		var gate_node: Area2D = WARP_GATE_SCENE.instantiate() as Area2D
		if gate_node == null:
			continue

		gate_node.position = gate_data.get("position", Vector2.ZERO)
		content_root.add_child(gate_node)
		if gate_node.has_method("configure"):
			gate_node.call("configure", gate_data)
		result["warp_gates"].append(gate_node)

	for anomaly_data_variant in sector_data.get("anomaly_points", []):
		if anomaly_data_variant is not Dictionary:
			continue
		var anomaly_data: Dictionary = (anomaly_data_variant as Dictionary).duplicate(true)
		var anomaly_node: Area2D = ANOMALY_POINT_SCENE.instantiate() as Area2D
		if anomaly_node == null:
			continue

		var anomaly_position: Vector2 = anomaly_data.get("position", Vector2.ZERO)
		if anomaly_position == Vector2.ZERO:
			anomaly_position = Vector2(rng.randf_range(-2200.0, 2200.0), rng.randf_range(-2200.0, 2200.0))
		anomaly_node.position = anomaly_position
		content_root.add_child(anomaly_node)
		if anomaly_node.has_method("configure"):
			anomaly_node.call("configure", anomaly_data)
		result["anomalies"].append(anomaly_node)

	for patrol_data_variant in sector_data.get("enemy_patrols", []):
		if patrol_data_variant is not Dictionary:
			continue
		var patrol_data: Dictionary = (patrol_data_variant as Dictionary).duplicate(true)
		var patrol_center: Vector2 = patrol_data.get("center", Vector2.ZERO)
		var patrol_radius: float = float(patrol_data.get("radius", 360.0))
		var archetypes: Array = patrol_data.get("archetypes", [])
		for archetype_variant in archetypes:
			var archetype_id: String = String(archetype_variant)
			if archetype_id.is_empty():
				continue
			var enemy_ship: EnemyShip = ENEMY_SHIP_SCENE.instantiate() as EnemyShip
			if enemy_ship == null:
				continue

			var spawn_angle: float = rng.randf_range(0.0, TAU)
			var spawn_distance: float = sqrt(rng.randf()) * patrol_radius * 0.8
			var spawn_position: Vector2 = patrol_center + Vector2(cos(spawn_angle), sin(spawn_angle)) * spawn_distance

			enemy_ship.position = spawn_position
			content_root.add_child(enemy_ship)
			if enemy_ship.has_method("configure"):
				enemy_ship.call("configure", {
					"archetype_id": archetype_id,
					"spawn_origin": spawn_position,
					"patrol_center": patrol_center,
					"patrol_radius": patrol_radius,
				})
			result["enemy_ships"].append(enemy_ship)

	var sector_id: StringName = StringName(String(sector_data.get("id", "")))
	var wreck_state: Dictionary = GameStateManager.get_wreck_beacon_state()
	if bool(wreck_state.get("active", false)) and StringName(String(wreck_state.get("sector_id", ""))) == sector_id:
		var wreck_beacon: WreckBeacon = WRECK_BEACON_SCENE.instantiate() as WreckBeacon
		if wreck_beacon != null:
			var wreck_position: Vector2 = wreck_state.get("position", Vector2.ZERO)
			wreck_beacon.position = wreck_position
			content_root.add_child(wreck_beacon)
			if wreck_beacon.has_method("configure"):
				wreck_beacon.call("configure", wreck_state)
			result["wreck_beacon"] = wreck_beacon

	return result


func _clear_root(content_root: Node2D) -> void:
	for child in content_root.get_children():
		child.queue_free()
