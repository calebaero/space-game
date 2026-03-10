extends Area2D
class_name HazardZone

@export var zone_id: StringName = &""
@export var hazard_type: StringName = &"debris_field"
@export var radius: float = 700.0
@export var gravity_strength: float = 180.0

@export_group("Minefield")
@export var mine_count: int = 12
@export var mine_trigger_radius: float = 100.0
@export var mine_blast_radius: float = 80.0
@export var mine_arm_time: float = 1.0
@export var mine_damage: float = 25.0

@onready var zone_collision_shape: CollisionShape2D = %ZoneCollisionShape
@onready var debris_root: Node2D = %DebrisRoot

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _mines: Array[Dictionary] = []
var _visual_time: float = 0.0


func _ready() -> void:
	add_to_group("hazard_zone")
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_seed_rng()
	_apply_zone_shape()
	_rebuild_zone_content()

	set_process(true)
	queue_redraw()


func configure(data: Dictionary) -> void:
	zone_id = StringName(String(data.get("id", zone_id)))
	hazard_type = StringName(String(data.get("hazard_type", hazard_type)))
	radius = float(data.get("radius", radius))
	gravity_strength = float(data.get("gravity_strength", gravity_strength))
	mine_count = int(data.get("mine_count", mine_count))
	mine_trigger_radius = float(data.get("mine_trigger_radius", mine_trigger_radius))
	mine_blast_radius = float(data.get("mine_blast_radius", mine_blast_radius))
	mine_arm_time = float(data.get("mine_arm_time", mine_arm_time))
	mine_damage = float(data.get("mine_damage", mine_damage))

	_seed_rng()
	if is_inside_tree():
		_apply_zone_shape()
		_rebuild_zone_content()
		queue_redraw()


func get_hazard_type() -> StringName:
	return hazard_type


func get_display_name() -> String:
	var hazard_def: Dictionary = ContentDatabase.get_hazard_type_definition(hazard_type)
	if hazard_def.is_empty():
		return String(hazard_type).replace("_", " ").capitalize()
	return String(hazard_def.get("name", hazard_type))


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func get_shield_recharge_multiplier() -> float:
	match String(hazard_type):
		"radiation_cloud":
			return 0.25
		"emp_zone":
			return 0.0
		_:
			return 1.0


func get_steering_noise_strength() -> float:
	if hazard_type == &"ion_storm":
		return 0.12
	return 0.0


func get_gravity_pull_at(world_point: Vector2) -> Vector2:
	if hazard_type != &"gravity_well":
		return Vector2.ZERO

	var to_center: Vector2 = global_position - world_point
	var distance: float = maxf(to_center.length(), 16.0)
	if distance >= radius:
		return Vector2.ZERO

	var strength_scale: float = clampf(1.0 - (distance / radius), 0.1, 1.0)
	return to_center.normalized() * gravity_strength * strength_scale


func disables_utility_modules() -> bool:
	return hazard_type == &"emp_zone"


func _process(delta: float) -> void:
	_visual_time += delta
	if hazard_type == &"minefield":
		_update_minefield(delta)
	queue_redraw()


func _draw() -> void:
	var color: Color = _get_hazard_color()
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(color.r, color.g, color.b, 0.42), 3.0)

	if hazard_type == &"minefield":
		_draw_minefield_markers()
	elif hazard_type == &"ion_storm":
		_draw_ion_storm_lines(color)


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player_ship"):
		return
	UIManager.show_toast("Entering %s" % get_display_name(), &"warning")


func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player_ship"):
		return
	UIManager.show_toast("Leaving %s" % get_display_name(), &"info")


func _apply_zone_shape() -> void:
	var circle: CircleShape2D = zone_collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		zone_collision_shape.shape = circle
	circle.radius = radius


func _rebuild_zone_content() -> void:
	for child in debris_root.get_children():
		child.queue_free()
	_mines.clear()

	if hazard_type == &"debris_field":
		_spawn_debris_pieces()
	elif hazard_type == &"minefield":
		_spawn_mines()


func _spawn_debris_pieces() -> void:
	var debris_count: int = 18
	for i in debris_count:
		var piece: StaticBody2D = StaticBody2D.new()
		piece.add_to_group("debris_piece")
		piece.position = _random_point_in_zone(radius * 0.9)
		piece.rotation = _rng.randf_range(0.0, TAU)

		var piece_radius: float = _rng.randf_range(5.0, 11.0)
		var points: PackedVector2Array = PackedVector2Array()
		var point_count: int = _rng.randi_range(5, 8)
		for j in point_count:
			var angle: float = TAU * float(j) / float(point_count)
			var local_radius: float = piece_radius * _rng.randf_range(0.75, 1.25)
			points.append(Vector2(cos(angle), sin(angle)) * local_radius)

		var collision_polygon: CollisionPolygon2D = CollisionPolygon2D.new()
		collision_polygon.polygon = points
		piece.add_child(collision_polygon)

		var visual: Polygon2D = Polygon2D.new()
		visual.polygon = points
		visual.color = Color(0.56, 0.52, 0.46, 0.95)
		piece.add_child(visual)
		debris_root.add_child(piece)


func _spawn_mines() -> void:
	for i in mine_count:
		_mines.append({
			"position": _random_point_in_zone(radius * 0.9),
			"armed": false,
			"arm_timer": mine_arm_time,
			"exploded": false,
			"explosion_timer": 0.0,
		})


func _update_minefield(delta: float) -> void:
	var player_ship: Node2D = get_tree().get_first_node_in_group("player_ship") as Node2D
	if player_ship == null:
		return

	for mine_entry_variant in _mines:
		var mine_entry: Dictionary = mine_entry_variant
		if bool(mine_entry.get("exploded", false)):
			var remaining: float = maxf(float(mine_entry.get("explosion_timer", 0.0)) - delta, 0.0)
			mine_entry["explosion_timer"] = remaining
			continue

		var mine_position: Vector2 = mine_entry.get("position", Vector2.ZERO)
		var world_mine_position: Vector2 = global_position + mine_position
		var distance: float = world_mine_position.distance_to(player_ship.global_position)

		if not bool(mine_entry.get("armed", false)) and distance <= mine_trigger_radius:
			mine_entry["armed"] = true
			mine_entry["arm_timer"] = mine_arm_time
			continue

		if bool(mine_entry.get("armed", false)):
			var arm_timer: float = float(mine_entry.get("arm_timer", 0.0)) - delta
			mine_entry["arm_timer"] = arm_timer
			if arm_timer <= 0.0:
				mine_entry["exploded"] = true
				mine_entry["explosion_timer"] = 0.35
				if distance <= mine_blast_radius and player_ship.has_method("apply_external_damage"):
					player_ship.call("apply_external_damage", mine_damage, "Minefield")


func _draw_minefield_markers() -> void:
	for mine_entry_variant in _mines:
		var mine_entry: Dictionary = mine_entry_variant
		var mine_position: Vector2 = mine_entry.get("position", Vector2.ZERO)
		if bool(mine_entry.get("exploded", false)):
			var timer: float = float(mine_entry.get("explosion_timer", 0.0))
			if timer > 0.0:
				var blast_alpha: float = clampf(timer / 0.35, 0.0, 1.0)
				draw_circle(mine_position, mine_blast_radius, Color(1.0, 0.3, 0.18, 0.25 * blast_alpha))
			continue

		var blink: float = 0.45 + 0.55 * sin(_visual_time * 8.0 + mine_position.x * 0.02)
		var armed: bool = bool(mine_entry.get("armed", false))
		var color: Color = Color(1.0, 0.22, 0.22, 0.5 + 0.5 * blink)
		if armed:
			color = Color(1.0, 0.68, 0.2, 0.65 + 0.35 * blink)
		draw_circle(mine_position, 5.0, color)


func _draw_ion_storm_lines(base_color: Color) -> void:
	for i in 8:
		var phase: float = _visual_time * 2.0 + float(i) * 0.72
		var angle: float = phase
		var start: Vector2 = Vector2(cos(angle), sin(angle)) * (radius * 0.2)
		var finish: Vector2 = Vector2(cos(angle + 0.8), sin(angle + 0.8)) * (radius * 0.85)
		draw_line(start, finish, Color(base_color.r, base_color.g, base_color.b, 0.25), 2.0)


func _get_hazard_color() -> Color:
	match String(hazard_type):
		"debris_field":
			return Color(0.82, 0.62, 0.3, 0.12)
		"radiation_cloud":
			return Color(0.72, 0.9, 0.24, 0.15)
		"ion_storm":
			return Color(0.35, 0.7, 1.0, 0.15)
		"minefield":
			return Color(0.88, 0.28, 0.24, 0.11)
		"gravity_well":
			return Color(0.4, 0.46, 0.92, 0.14)
		"emp_zone":
			return Color(0.68, 0.36, 0.88, 0.15)
		_:
			return Color(1.0, 0.5, 0.22, 0.1)


func _seed_rng() -> void:
	var seed_source: String = String(zone_id)
	if seed_source.is_empty():
		seed_source = "%s|%s" % [String(hazard_type), str(position)]
	_rng.seed = hash(seed_source)


func _random_point_in_zone(max_radius: float) -> Vector2:
	var angle: float = _rng.randf_range(0.0, TAU)
	var distance: float = sqrt(_rng.randf()) * max_radius
	return Vector2(cos(angle), sin(angle)) * distance
