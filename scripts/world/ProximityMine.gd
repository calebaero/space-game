extends Area2D
class_name ProximityMine

@export var arm_time: float = 1.0
@export var trigger_radius: float = 100.0
@export var blast_radius: float = 80.0
@export var damage: float = 25.0

@onready var collision_shape: CollisionShape2D = %CollisionShape
@onready var trigger_indicator: ColorRect = %TriggerIndicator

var owner_type: StringName = &"enemy"
var _arm_time_remaining: float = 1.0
var _detonation_delay: float = -1.0
var _is_armed: bool = false


func _ready() -> void:
	add_to_group("proximity_mine")
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	set_process(true)
	_apply_trigger_radius()
	queue_redraw()


func configure(data: Dictionary) -> void:
	owner_type = StringName(String(data.get("owner", owner_type)))
	arm_time = float(data.get("arm_time", arm_time))
	trigger_radius = float(data.get("trigger_radius", trigger_radius))
	blast_radius = float(data.get("blast_radius", blast_radius))
	damage = float(data.get("damage", damage))
	_arm_time_remaining = arm_time
	if is_inside_tree():
		_apply_trigger_radius()


func _process(delta: float) -> void:
	if not _is_armed:
		_arm_time_remaining = maxf(_arm_time_remaining - delta, 0.0)
		if _arm_time_remaining <= 0.0:
			_is_armed = true
			trigger_indicator.color = Color(1.0, 0.3, 0.3, 0.9)
		return

	if _detonation_delay >= 0.0:
		_detonation_delay = maxf(_detonation_delay - delta, 0.0)
		if _detonation_delay <= 0.0:
			_explode()


func _on_body_entered(body: Node) -> void:
	if not _is_armed:
		return
	if body == null or not body.is_in_group("player_ship"):
		return
	if _detonation_delay >= 0.0:
		return
	_detonation_delay = 0.45
	trigger_indicator.color = Color(1.0, 0.86, 0.28, 1.0)


func _explode() -> void:
	for player_variant in get_tree().get_nodes_in_group("player_ship"):
		var player_node: Node2D = player_variant as Node2D
		if player_node == null or not is_instance_valid(player_node):
			continue
		if player_node.global_position.distance_to(global_position) > blast_radius:
			continue
		if player_node.has_method("apply_external_damage"):
			player_node.call("apply_external_damage", damage, "Proximity Mine")

	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.global_position = global_position
	particles.amount = 24
	particles.one_shot = true
	particles.lifetime = 0.35
	particles.explosiveness = 0.92
	particles.spread = 180.0
	particles.direction = Vector2.ZERO
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 180.0
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.2
	particles.color = Color(1.0, 0.42, 0.28, 0.95)
	get_parent().add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	queue_free()


func _apply_trigger_radius() -> void:
	var circle: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		collision_shape.shape = circle
	circle.radius = maxf(trigger_radius, 30.0)


func _draw() -> void:
	var mine_color: Color = Color(0.82, 0.2, 0.2, 0.95) if _is_armed else Color(0.62, 0.2, 0.2, 0.75)
	draw_circle(Vector2.ZERO, 10.0, mine_color)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(1.0, 0.66, 0.42, 0.7), 2.0)
