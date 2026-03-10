extends Node2D
class_name AsteroidField

const RESOURCE_NODE_SCENE: PackedScene = preload("res://scenes/world/ResourceNode.tscn")

@export var field_id: StringName = &""
@export var asteroid_count_min: int = 5
@export var asteroid_count_max: int = 15
@export var field_radius: float = 520.0
@export var mineable_ratio: float = 0.35
@export var resource_id: StringName = &"common_ore"
@export var tier: int = 1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rotating_asteroids: Array[Dictionary] = []


func _ready() -> void:
	set_process(true)
	if get_child_count() == 0:
		_seed_rng()
		_generate_field()


func configure(data: Dictionary) -> void:
	field_id = StringName(String(data.get("id", field_id)))
	asteroid_count_min = int(data.get("asteroid_count_min", asteroid_count_min))
	asteroid_count_max = int(data.get("asteroid_count_max", asteroid_count_max))
	field_radius = float(data.get("radius", field_radius))
	mineable_ratio = float(data.get("mineable_ratio", mineable_ratio))
	resource_id = StringName(String(data.get("resource_id", resource_id)))
	tier = int(data.get("tier", tier))

	_seed_rng()
	if is_inside_tree():
		_generate_field()


func _process(delta: float) -> void:
	for entry_variant in _rotating_asteroids:
		var entry: Dictionary = entry_variant
		var asteroid_body: Node2D = entry.get("node", null)
		if asteroid_body == null or not is_instance_valid(asteroid_body):
			continue
		var speed: float = float(entry.get("rotation_speed", 0.0))
		asteroid_body.rotation += speed * delta


func _generate_field() -> void:
	for child in get_children():
		child.queue_free()
	_rotating_asteroids.clear()

	if asteroid_count_max < asteroid_count_min:
		asteroid_count_max = asteroid_count_min

	var asteroid_count: int = _rng.randi_range(asteroid_count_min, asteroid_count_max)
	for i in asteroid_count:
		var asteroid_position: Vector2 = _random_point_in_radius(field_radius)
		var asteroid_radius: float = _rng.randf_range(10.0, 50.0)
		var asteroid_body: StaticBody2D = _create_asteroid_body(asteroid_radius)
		asteroid_body.position = asteroid_position
		add_child(asteroid_body)

		_rotating_asteroids.append({
			"node": asteroid_body,
			"rotation_speed": _rng.randf_range(-0.18, 0.18),
		})

		if _rng.randf() <= mineable_ratio:
			_spawn_embedded_resource_node(i, asteroid_position, asteroid_radius)


func _create_asteroid_body(asteroid_radius: float) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.add_to_group("asteroid_body")

	var points: PackedVector2Array = _build_asteroid_points(asteroid_radius)

	var collision_polygon: CollisionPolygon2D = CollisionPolygon2D.new()
	collision_polygon.polygon = points
	body.add_child(collision_polygon)

	var visual: Polygon2D = Polygon2D.new()
	visual.polygon = points
	var gray_mix: float = _rng.randf_range(0.38, 0.6)
	visual.color = Color(gray_mix, gray_mix * 0.95, gray_mix * 0.85, 1.0)
	body.add_child(visual)

	return body


func _spawn_embedded_resource_node(index: int, asteroid_position: Vector2, asteroid_radius: float) -> void:
	var node: StaticBody2D = RESOURCE_NODE_SCENE.instantiate() as StaticBody2D
	if node == null:
		return

	var offset: Vector2 = Vector2(_rng.randf_range(-asteroid_radius * 0.35, asteroid_radius * 0.35), _rng.randf_range(-asteroid_radius * 0.35, asteroid_radius * 0.35))
	node.position = asteroid_position + offset
	add_child(node)
	if node.has_method("configure"):
		node.call("configure", {
			"id": "%s_node_%d" % [String(field_id), index],
			"resource_id": String(resource_id),
			"tier": tier,
		})


func _seed_rng() -> void:
	var source_id: String = String(field_id)
	if source_id.is_empty():
		source_id = "field_%s" % str(position)
	_rng.seed = hash(source_id)


func _random_point_in_radius(radius: float) -> Vector2:
	var angle: float = _rng.randf_range(0.0, TAU)
	var distance: float = sqrt(_rng.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * distance


func _build_asteroid_points(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var point_count: int = _rng.randi_range(7, 10)
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count)
		var local_radius: float = radius * _rng.randf_range(0.68, 1.22)
		points.append(Vector2(cos(angle), sin(angle)) * local_radius)
	return points
