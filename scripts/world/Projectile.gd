extends Area2D
class_name Projectile

@export var damage: float = 8.0
@export var speed: float = 800.0
@export var max_range: float = 500.0
@export var lifetime: float = 1.2
@export var is_homing: bool = false
@export var homing_turn_rate: float = 7.0

@onready var trail_line: Line2D = %TrailLine

var owner_type: StringName = &"neutral"
var source_node: Node = null
var aoe_radius: float = 0.0
var shield_disable_duration: float = 0.0
var homing_target: Node2D = null

var _velocity: Vector2 = Vector2.ZERO
var _distance_traveled: float = 0.0
var _lifetime_remaining: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	set_physics_process(true)

	if owner_type == &"player":
		add_to_group("player_projectile")
	elif owner_type == &"enemy":
		add_to_group("enemy_projectile")

	_lifetime_remaining = lifetime
	if _velocity == Vector2.ZERO:
		_velocity = Vector2.RIGHT.rotated(rotation) * speed


func configure(projectile_data: Dictionary) -> void:
	damage = float(projectile_data.get("damage", damage))
	speed = float(projectile_data.get("speed", speed))
	max_range = float(projectile_data.get("range", max_range))
	lifetime = float(projectile_data.get("lifetime", lifetime))
	is_homing = bool(projectile_data.get("is_homing", is_homing))
	homing_turn_rate = float(projectile_data.get("homing_turn_rate", homing_turn_rate))
	owner_type = StringName(String(projectile_data.get("owner", owner_type)))
	source_node = projectile_data.get("source", null)
	aoe_radius = float(projectile_data.get("aoe_radius", aoe_radius))
	shield_disable_duration = float(projectile_data.get("shield_disable_duration", shield_disable_duration))
	if projectile_data.has("homing_target"):
		var candidate: Node = projectile_data.get("homing_target", null)
		if candidate is Node2D:
			homing_target = candidate as Node2D

	var direction: Vector2 = projectile_data.get("direction", Vector2.RIGHT)
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT.rotated(rotation)
	direction = direction.normalized()
	rotation = direction.angle()
	_velocity = direction * speed

	var color: Color = projectile_data.get("color", Color(0.8, 0.9, 1.0, 1.0))
	trail_line.default_color = color
	trail_line.width = float(projectile_data.get("width", trail_line.width))
	trail_line.scale = Vector2.ONE * float(projectile_data.get("scale", 1.0))


func _physics_process(delta: float) -> void:
	if _lifetime_remaining <= 0.0:
		queue_free()
		return

	_lifetime_remaining -= delta
	_update_homing(delta)

	_apply_gravity_well_forces(delta)
	var displacement: Vector2 = _velocity * delta
	global_position += displacement
	_distance_traveled += displacement.length()

	if _distance_traveled >= max_range:
		queue_free()


func _update_homing(delta: float) -> void:
	if not is_homing:
		return
	if homing_target == null or not is_instance_valid(homing_target):
		homing_target = _find_default_homing_target()
		if homing_target == null:
			return

	var to_target: Vector2 = homing_target.global_position - global_position
	if to_target.length_squared() <= 0.001:
		return
	var desired_direction: Vector2 = to_target.normalized()
	var current_direction: Vector2 = _velocity.normalized()
	if current_direction.length_squared() <= 0.001:
		current_direction = desired_direction
	var turn_weight: float = clampf(homing_turn_rate * delta, 0.0, 1.0)
	var next_direction: Vector2 = current_direction.slerp(desired_direction, turn_weight).normalized()
	var current_speed: float = maxf(_velocity.length(), speed)
	_velocity = next_direction * current_speed


func _find_default_homing_target() -> Node2D:
	var target_group: StringName = &"enemy_ship" if owner_type == &"player" else &"player_ship"
	var best_target: Node2D = null
	var best_distance: float = INF
	for candidate_variant in get_tree().get_nodes_in_group(target_group):
		var candidate: Node2D = candidate_variant as Node2D
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate == source_node:
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	return best_target


func _apply_gravity_well_forces(delta: float) -> void:
	for zone_variant in get_tree().get_nodes_in_group("hazard_zone"):
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if not zone.has_method("get_gravity_pull_at"):
			continue
		var pull: Vector2 = zone.call("get_gravity_pull_at", global_position)
		_velocity += pull * delta

	if _velocity.length_squared() > 0.0001:
		rotation = _velocity.angle()


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if source_node != null and body == source_node:
		return

	if body.is_in_group("resource_node"):
		return
	if body.is_in_group("asteroid_body"):
		_spawn_impact_flash(global_position, Color(1.0, 0.74, 0.58, 1.0))
		queue_free()
		return

	if owner_type == &"player" and body.is_in_group("enemy_ship"):
		if body.has_method("apply_projectile_damage"):
			body.call("apply_projectile_damage", damage, self)
		if shield_disable_duration > 0.0 and body.has_method("apply_emp_disable"):
			body.call("apply_emp_disable", shield_disable_duration)
		_apply_area_payload(global_position, body)
		_spawn_impact_flash(global_position, Color(1.0, 0.88, 0.66, 1.0))
		queue_free()
		return

	if owner_type == &"enemy" and body.is_in_group("player_ship"):
		if body.has_method("apply_projectile_damage"):
			body.call("apply_projectile_damage", damage, self)
		if shield_disable_duration > 0.0 and body.has_method("apply_emp_disable"):
			body.call("apply_emp_disable", shield_disable_duration)
		_apply_area_payload(global_position, body)
		_spawn_impact_flash(global_position, Color(1.0, 0.3, 0.3, 1.0))
		queue_free()
		return

	if body is StaticBody2D:
		_apply_area_payload(global_position, null)
		_spawn_impact_flash(global_position, Color(1.0, 0.9, 0.7, 0.9))
		queue_free()


func _apply_area_payload(world_position: Vector2, excluded_target: Node) -> void:
	if aoe_radius <= 0.0 and shield_disable_duration <= 0.0:
		return
	var target_group: StringName = &"enemy_ship" if owner_type == &"player" else &"player_ship"
	for target_variant in get_tree().get_nodes_in_group(target_group):
		var target_node: Node2D = target_variant as Node2D
		if target_node == null or not is_instance_valid(target_node):
			continue
		if target_node == excluded_target or target_node == source_node:
			continue
		if target_node.global_position.distance_to(world_position) > maxf(aoe_radius, 0.0):
			continue
		if damage > 0.0 and target_node.has_method("apply_projectile_damage"):
			target_node.call("apply_projectile_damage", damage, self)
		if shield_disable_duration > 0.0 and target_node.has_method("apply_emp_disable"):
			target_node.call("apply_emp_disable", shield_disable_duration)

	if aoe_radius > 0.0:
		_spawn_impact_flash(world_position, Color(0.65, 0.92, 1.0, 1.0))


func get_shield_disable_duration() -> float:
	return shield_disable_duration


func _spawn_impact_flash(world_position: Vector2, color: Color) -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var flash: CPUParticles2D = CPUParticles2D.new()
	flash.global_position = world_position
	flash.amount = 10
	flash.one_shot = true
	flash.lifetime = 0.15
	flash.explosiveness = 0.9
	flash.emitting = true
	flash.direction = Vector2.ZERO
	flash.spread = 180.0
	flash.gravity = Vector2.ZERO
	flash.initial_velocity_min = 26.0
	flash.initial_velocity_max = 90.0
	flash.scale_amount_min = 0.5
	flash.scale_amount_max = 1.1
	flash.color = color
	parent_node.add_child(flash)
	flash.finished.connect(flash.queue_free)
