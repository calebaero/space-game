extends Control

@export var world_half_extent: float = 4000.0
@export var map_padding: float = 10.0
@export var ion_jitter_scale: float = 8.0

var _player_ship: Node2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_player_ship(player_ship: Node2D) -> void:
	_player_ship = player_ship
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var map_radius: float = max(minf(size.x, size.y) * 0.5 - map_padding, 8.0)

	draw_circle(center, map_radius, Color(0.03, 0.06, 0.12, 0.85))
	draw_arc(center, map_radius, 0.0, TAU, 60, Color(0.3, 0.5, 0.78, 0.65), 2.0)

	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	var jitter_strength: float = 0.0
	if _player_ship.has_method("get_minimap_jitter_strength"):
		jitter_strength = float(_player_ship.call("get_minimap_jitter_strength")) * ion_jitter_scale

	_draw_world_points("resource_node", Color(0.45, 1.0, 0.45, 0.9), 2.8, center, map_radius, jitter_strength)
	_draw_world_points("loot_crate", Color(1.0, 0.9, 0.32, 0.95), 2.6, center, map_radius, jitter_strength)
	_draw_world_points("anomaly_point", Color(0.82, 0.48, 1.0, 0.95), 3.0, center, map_radius, jitter_strength)
	_draw_world_points("wreck_beacon", Color(1.0, 1.0, 1.0, 0.95), 3.2, center, map_radius, jitter_strength)
	_draw_hazard_areas(center, map_radius, jitter_strength)

	# Player marker stays centered.
	draw_circle(center, 3.2, Color(0.9, 0.96, 1.0, 1.0))
	draw_circle(center, 1.5, Color(0.2, 0.6, 1.0, 1.0))


func _draw_world_points(group_name: String, color: Color, radius: float, center: Vector2, map_radius: float, jitter_strength: float) -> void:
	for node_variant in get_tree().get_nodes_in_group(group_name):
		var node: Node2D = node_variant as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if node is CanvasItem and not node.visible:
			continue

		var marker_position: Vector2 = _world_to_map_position(node.global_position, center, map_radius, jitter_strength)
		draw_circle(marker_position, radius, color)


func _draw_hazard_areas(center: Vector2, map_radius: float, jitter_strength: float) -> void:
	for zone_variant in get_tree().get_nodes_in_group("hazard_zone"):
		var zone: Node2D = zone_variant as Node2D
		if zone == null or not is_instance_valid(zone):
			continue

		var zone_position: Vector2 = _world_to_map_position(zone.global_position, center, map_radius, jitter_strength)
		var zone_radius_value: Variant = zone.get("radius")
		var zone_radius_world: float = float(zone_radius_value if zone_radius_value != null else 0.0)
		var zone_radius_map: float = clampf((zone_radius_world / world_half_extent) * map_radius, 4.0, map_radius)
		draw_circle(zone_position, zone_radius_map, Color(1.0, 0.58, 0.26, 0.16))
		draw_arc(zone_position, zone_radius_map, 0.0, TAU, 40, Color(1.0, 0.62, 0.3, 0.32), 1.0)


func _world_to_map_position(world_position: Vector2, center: Vector2, map_radius: float, jitter_strength: float) -> Vector2:
	var relative: Vector2 = world_position - _player_ship.global_position
	var normalized: Vector2 = relative / max(world_half_extent, 1.0)
	var mapped: Vector2 = center + normalized * map_radius
	var from_center: Vector2 = mapped - center
	if from_center.length() > map_radius:
		mapped = center + from_center.normalized() * map_radius

	if jitter_strength > 0.01:
		mapped += Vector2(randf_range(-jitter_strength, jitter_strength), randf_range(-jitter_strength, jitter_strength))
	return mapped
