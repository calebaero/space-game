extends Node2D

const SECTOR_SIZE: Vector2 = Vector2(8000.0, 8000.0)
const SECTOR_HALF: Vector2 = SECTOR_SIZE * 0.5
const PLAYER_SHIP_SCENE: PackedScene = preload("res://scenes/player/PlayerShip.tscn")

const BOUNDARY_THICKNESS: float = 220.0
const BOUNDARY_WARNING_DEPTH: float = 240.0
const EDGE_DETECTION_THRESHOLD: float = 320.0

signal player_spawned(player_ship: CharacterBody2D)

@onready var content_root: Node2D = %ContentRoot
@onready var boundary_walls: Node2D = %BoundaryWalls
@onready var boundary_warning_areas: Node2D = %BoundaryWarningAreas
@onready var debug_label: Label = %DebugLabel

var _sector_data: Dictionary = {}
var _galaxy_data: Dictionary = {}
var _player_ship: CharacterBody2D = null
var _station_node: Node2D = null
var _warp_gate_nodes: Array = []
var _enemy_ship_nodes: Array = []
var _wreck_beacon_node: WreckBeacon = null
var _background_tint: Color = Color(0.2, 0.3, 0.55, 1.0)
var _sector_populator: SectorPopulator = SectorPopulator.new()


func _ready() -> void:
	queue_redraw()
	if not _sector_data.is_empty():
		_apply_sector_data()


func _draw() -> void:
	var bounds: Rect2 = Rect2(-SECTOR_HALF, SECTOR_SIZE)
	var tint: Color = _background_tint
	tint.a = 0.12
	draw_rect(bounds, tint, true)
	draw_rect(bounds, Color(0.7, 0.8, 1.0, 0.07), false, 32.0, true)
	draw_rect(bounds, Color(0.3, 0.4, 0.55, 0.12), false, 6.0, true)


func setup_sector(sector_data: Dictionary, galaxy_data: Dictionary) -> void:
	_sector_data = sector_data.duplicate(true)
	_galaxy_data = galaxy_data.duplicate(true)

	if is_inside_tree():
		_apply_sector_data()


func spawn_player_ship(spawn_position: Vector2 = Vector2.ZERO) -> CharacterBody2D:
	if _player_ship != null and is_instance_valid(_player_ship):
		_player_ship.queue_free()
		_player_ship = null

	var player_ship: CharacterBody2D = PLAYER_SHIP_SCENE.instantiate() as CharacterBody2D
	if player_ship == null:
		push_error("SectorScene failed to instance PlayerShip scene as CharacterBody2D.")
		return null

	player_ship.position = spawn_position
	content_root.add_child(player_ship)
	_player_ship = player_ship
	_assign_player_to_enemies()
	player_spawned.emit(player_ship)
	return player_ship


func get_player_spawn_position() -> Vector2:
	if _station_node != null and is_instance_valid(_station_node):
		if _station_node.has_method("get_undock_spawn_position"):
			return _station_node.call("get_undock_spawn_position")
		return _station_node.global_position + Vector2(-260.0, 150.0)
	return Vector2.ZERO


func get_arrival_spawn_position(from_sector_id: StringName) -> Vector2:
	for gate_variant in _warp_gate_nodes:
		var gate_node: Node2D = gate_variant as Node2D
		if gate_node == null or not is_instance_valid(gate_node):
			continue
		var destination_sector: StringName = StringName(String(gate_node.get("destination_sector_id")))
		if destination_sector == from_sector_id:
			var gate_position: Vector2 = gate_node.global_position
			var inward: Vector2 = _get_inward_normal_for_gate_position(gate_position)
			return gate_position + inward * 320.0
	return get_player_spawn_position()


func get_player_ship() -> CharacterBody2D:
	return _player_ship


func get_enemy_ships() -> Array:
	var ships: Array = []
	for enemy_variant in _enemy_ship_nodes:
		var enemy: EnemyShip = enemy_variant as EnemyShip
		if enemy == null or not is_instance_valid(enemy):
			continue
		ships.append(enemy)
	return ships


func get_wreck_beacon() -> WreckBeacon:
	if _wreck_beacon_node == null or not is_instance_valid(_wreck_beacon_node):
		return null
	return _wreck_beacon_node


func _apply_sector_data() -> void:
	if _player_ship != null and is_instance_valid(_player_ship):
		_player_ship.queue_free()
		_player_ship = null

	var population: Dictionary = _sector_populator.populate_sector(content_root, _sector_data)
	var station_variant: Variant = population.get("station", null)
	_station_node = station_variant if station_variant is Node2D else null
	_warp_gate_nodes = population.get("warp_gates", [])
	_enemy_ship_nodes = population.get("enemy_ships", [])
	_wreck_beacon_node = population.get("wreck_beacon", null)
	_assign_player_to_enemies()

	_background_tint = _sector_data.get("background_tint", Color(0.2, 0.3, 0.55, 1.0))
	_build_sector_boundaries()

	var galaxy_name: String = String(_galaxy_data.get("name", "Unknown Galaxy"))
	var sector_name: String = String(_sector_data.get("name", "Unknown Sector"))
	debug_label.text = "%s — %s\nPhase 06 Build Shell" % [galaxy_name, sector_name]
	queue_redraw()


func _assign_player_to_enemies() -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	for enemy_variant in _enemy_ship_nodes:
		var enemy: EnemyShip = enemy_variant as EnemyShip
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("set_player_ship"):
			enemy.call("set_player_ship", _player_ship)


func _build_sector_boundaries() -> void:
	for child in boundary_walls.get_children():
		child.queue_free()
	for child in boundary_warning_areas.get_children():
		child.queue_free()

	_create_boundary_segment("left", -SECTOR_HALF.y, SECTOR_HALF.y)
	_create_boundary_segment("right", -SECTOR_HALF.y, SECTOR_HALF.y)
	_create_boundary_segment("top", -SECTOR_HALF.x, SECTOR_HALF.x)
	_create_boundary_segment("bottom", -SECTOR_HALF.x, SECTOR_HALF.x)


func _create_boundary_segment(edge: String, start_coord: float, end_coord: float) -> void:
	var segment_length: float = end_coord - start_coord
	if segment_length <= 8.0:
		return

	var wall_size: Vector2
	var wall_position: Vector2
	var warning_size: Vector2
	var warning_position: Vector2

	if edge == "left" or edge == "right":
		var x_sign: float = -1.0 if edge == "left" else 1.0
		wall_size = Vector2(BOUNDARY_THICKNESS, segment_length)
		wall_position = Vector2((SECTOR_HALF.x + BOUNDARY_THICKNESS * 0.5) * x_sign, (start_coord + end_coord) * 0.5)
		warning_size = Vector2(BOUNDARY_WARNING_DEPTH, segment_length)
		warning_position = Vector2((SECTOR_HALF.x - BOUNDARY_WARNING_DEPTH * 0.5) * x_sign, (start_coord + end_coord) * 0.5)
	else:
		var y_sign: float = -1.0 if edge == "top" else 1.0
		wall_size = Vector2(segment_length, BOUNDARY_THICKNESS)
		wall_position = Vector2((start_coord + end_coord) * 0.5, (SECTOR_HALF.y + BOUNDARY_THICKNESS * 0.5) * y_sign)
		warning_size = Vector2(segment_length, BOUNDARY_WARNING_DEPTH)
		warning_position = Vector2((start_coord + end_coord) * 0.5, (SECTOR_HALF.y - BOUNDARY_WARNING_DEPTH * 0.5) * y_sign)

	var wall_body: StaticBody2D = StaticBody2D.new()
	wall_body.position = wall_position
	var wall_collision_shape: CollisionShape2D = CollisionShape2D.new()
	var wall_rect: RectangleShape2D = RectangleShape2D.new()
	wall_rect.size = wall_size
	wall_collision_shape.shape = wall_rect
	wall_body.add_child(wall_collision_shape)
	boundary_walls.add_child(wall_body)

	var warning_area: Area2D = Area2D.new()
	warning_area.position = warning_position
	warning_area.monitoring = false
	warning_area.monitorable = true
	warning_area.set_meta("interaction_type", "boundary_warning")
	warning_area.set_meta("interaction_priority", 10)
	warning_area.set_meta("interaction_prompt", "Sector Boundary - No Gate Here")
	var warning_collision_shape: CollisionShape2D = CollisionShape2D.new()
	var warning_rect: RectangleShape2D = RectangleShape2D.new()
	warning_rect.size = warning_size
	warning_collision_shape.shape = warning_rect
	warning_area.add_child(warning_collision_shape)
	boundary_warning_areas.add_child(warning_area)


func _edge_from_gate_position(gate_position: Vector2) -> String:
	if absf(gate_position.x) >= SECTOR_HALF.x - EDGE_DETECTION_THRESHOLD:
		return "right" if gate_position.x > 0.0 else "left"
	if absf(gate_position.y) >= SECTOR_HALF.y - EDGE_DETECTION_THRESHOLD:
		return "bottom" if gate_position.y > 0.0 else "top"
	return ""


func _get_inward_normal_for_gate_position(gate_position: Vector2) -> Vector2:
	var edge: String = _edge_from_gate_position(gate_position)
	match edge:
		"left":
			return Vector2.RIGHT
		"right":
			return Vector2.LEFT
		"top":
			return Vector2.DOWN
		"bottom":
			return Vector2.UP
		_:
			return Vector2.ZERO
