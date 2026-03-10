extends Area2D
class_name Projectile

@export var damage: float = 8.0
@export var speed: float = 800.0
@export var max_range: float = 500.0
@export var lifetime: float = 1.2
@export var is_homing: bool = false

@onready var trail_line: Line2D = %TrailLine

var owner_type: StringName = &"neutral"
var source_node: Node = null

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
	owner_type = StringName(String(projectile_data.get("owner", owner_type)))
	source_node = projectile_data.get("source", null)

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

	_apply_gravity_well_forces(delta)
	var displacement: Vector2 = _velocity * delta
	global_position += displacement
	_distance_traveled += displacement.length()

	if _distance_traveled >= max_range:
		queue_free()


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
		_spawn_impact_flash(global_position, Color(1.0, 0.88, 0.66, 1.0))
		queue_free()
		return

	if owner_type == &"enemy" and body.is_in_group("player_ship"):
		if body.has_method("apply_projectile_damage"):
			body.call("apply_projectile_damage", damage, self)
		_spawn_impact_flash(global_position, Color(1.0, 0.3, 0.3, 1.0))
		queue_free()
		return

	if body is StaticBody2D:
		_spawn_impact_flash(global_position, Color(1.0, 0.9, 0.7, 0.9))
		queue_free()


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
