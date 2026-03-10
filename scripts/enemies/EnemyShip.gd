extends CharacterBody2D
class_name EnemyShip

signal enemy_destroyed(enemy_ship: EnemyShip, archetype_id: StringName)
signal aggro_lost(enemy_name: String)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/world/Projectile.tscn")
const LOOT_CRATE_SCENE: PackedScene = preload("res://scenes/world/LootCrate.tscn")

@export var thrust_force: float = 220.0
@export var max_speed: float = 220.0
@export var angular_acceleration: float = 4.5
@export var angular_drag: float = 3.0
@export var linear_damp: float = 0.1
@export var strafe_acceleration_ratio: float = 0.45
@export var boost_speed_multiplier: float = 1.2

@onready var hull_polygon: Polygon2D = %HullPolygon
@onready var accent_polygon: Polygon2D = %AccentPolygon
@onready var damageable: Damageable = %Damageable
@onready var ai_controller: EnemyAIController = %EnemyAIController

var archetype_id: StringName = &"pirate_skirmisher"
var archetype_data: Dictionary = {}

var faction: StringName = &"pirate"
var display_name: String = "Enemy Ship"
var weapon_id: StringName = &"pirate_repeater"

var _weapon_data: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _angular_velocity: float = 0.0
var _desired_angle: float = 0.0
var _thrust_intent: float = 0.0
var _strafe_intent: float = 0.0
var _fire_intent: bool = false
var _boost_intent: bool = false
var _fire_cooldown_remaining: float = 0.0
var _death_handled: bool = false
var _command_target_position: Vector2 = Vector2.ZERO
var _has_command_target: bool = false

var _spawn_origin: Vector2 = Vector2.ZERO
var _player_ship: Node2D = null
var _is_targeted: bool = false


func _ready() -> void:
	add_to_group("enemy_ship")
	if not ai_controller.lost_interest.is_connected(_on_ai_lost_interest):
		ai_controller.lost_interest.connect(_on_ai_lost_interest)
	if not damageable.destroyed.is_connected(_on_destroyed):
		damageable.destroyed.connect(_on_destroyed)
	_rng.seed = hash("enemy|%s|%s" % [str(get_instance_id()), str(Time.get_ticks_msec())])
	set_physics_process(true)
	queue_redraw()


func configure(enemy_data: Dictionary) -> void:
	archetype_id = StringName(String(enemy_data.get("archetype_id", archetype_id)))
	archetype_data = ContentDatabase.get_enemy_archetype_definition(archetype_id)
	if archetype_data.is_empty():
		archetype_data = enemy_data.duplicate(true)

	faction = StringName(String(archetype_data.get("faction", "pirate")))
	display_name = String(archetype_data.get("name", "Enemy Ship"))
	weapon_id = StringName(String(archetype_data.get("weapon_id", "pirate_repeater")))
	_weapon_data = ContentDatabase.get_weapon_definition(weapon_id)

	thrust_force = float(archetype_data.get("thrust", thrust_force))
	max_speed = float(archetype_data.get("max_speed", max_speed))
	var turn_speed: float = float(archetype_data.get("turn_speed", 3.0))
	angular_acceleration = 4.0 + turn_speed * 0.5
	angular_drag = 2.6 + turn_speed * 0.2

	var max_hull: float = float(archetype_data.get("hull", 40.0))
	var max_shield: float = float(archetype_data.get("shield", 0.0))
	damageable.configure_from_values(max_hull, max_shield, 3.0, 5.0)

	_spawn_origin = enemy_data.get("spawn_origin", global_position)
	var patrol_center: Vector2 = enemy_data.get("patrol_center", _spawn_origin)
	var patrol_radius: float = float(enemy_data.get("patrol_radius", 360.0))
	ai_controller.configure(self, archetype_data, _spawn_origin, patrol_center, patrol_radius)
	ai_controller.set_player_ship(_player_ship)

	_apply_faction_visuals()

	if is_inside_tree():
		queue_redraw()


func set_player_ship(player_ship: Node2D) -> void:
	_player_ship = player_ship
	ai_controller.set_player_ship(player_ship)


func set_ai_command(target_position: Vector2, thrust: float, strafe: float, fire_primary: bool, boost: bool) -> void:
	_desired_angle = (target_position - global_position).angle()
	_command_target_position = target_position
	_has_command_target = true
	_thrust_intent = clampf(thrust, 0.0, 1.0)
	_strafe_intent = clampf(strafe, -1.0, 1.0)
	_fire_intent = fire_primary
	_boost_intent = boost


func set_targeted(is_targeted: bool) -> void:
	if _is_targeted == is_targeted:
		return
	_is_targeted = is_targeted
	queue_redraw()


func get_weapon_range() -> float:
	if _weapon_data.is_empty():
		return 480.0
	return float(_weapon_data.get("range", 480.0))


func get_display_name() -> String:
	return display_name


func get_faction_name() -> String:
	return String(faction).capitalize()


func get_current_hull() -> float:
	return damageable.current_hull


func get_max_hull() -> float:
	return damageable.max_hull


func get_current_shield() -> float:
	return damageable.current_shield


func get_max_shield() -> float:
	return damageable.max_shield


func get_hull_ratio() -> float:
	return damageable.get_hull_ratio()


func get_targeting_priority() -> float:
	return maxf(damageable.current_hull + damageable.current_shield, 0.0)


func apply_projectile_damage(amount: float, _projectile: Node = null) -> void:
	if amount <= 0.0:
		return
	var result: Dictionary = damageable.take_damage(amount)
	if float(result.get("shield_damage", 0.0)) > 0.0:
		modulate = Color(0.72, 0.92, 1.0, 1.0)
	elif float(result.get("hull_damage", 0.0)) > 0.0:
		modulate = Color(1.0, 0.62, 0.62, 1.0)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)


func _physics_process(delta: float) -> void:
	if _death_handled:
		return

	if _fire_cooldown_remaining > 0.0:
		_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)

	_update_rotation(delta)
	_apply_movement(delta)
	_apply_hazard_forces(delta)
	_apply_soft_speed_limit(delta)
	move_and_slide()
	_nudge_from_sector_edge(delta)

	var shield_multiplier: float = _get_shield_recharge_multiplier()
	damageable.process_recharge(delta, shield_multiplier)
	_try_fire_projectile()


func _update_rotation(delta: float) -> void:
	var angle_error: float = wrapf(_desired_angle - rotation, -PI, PI)
	var steering_input: float = clampf(angle_error / PI, -1.0, 1.0)
	_angular_velocity += steering_input * angular_acceleration * 1.25 * delta
	_angular_velocity = move_toward(_angular_velocity, 0.0, angular_drag * delta)
	var max_turn_rate: float = maxf(angular_acceleration * 0.75, 2.8)
	_angular_velocity = clampf(_angular_velocity, -max_turn_rate, max_turn_rate)
	rotation += _angular_velocity * delta


func _apply_movement(delta: float) -> void:
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var angle_error: float = absf(wrapf(_desired_angle - rotation, -PI, PI))
	var heading_multiplier: float = clampf(1.0 - (angle_error / PI) * 0.75, 0.22, 1.0)
	if angle_error > 2.2:
		heading_multiplier = 0.08

	if _thrust_intent > 0.0:
		var boost_mult: float = boost_speed_multiplier if _boost_intent else 1.0
		velocity += forward * thrust_force * _thrust_intent * heading_multiplier * boost_mult * delta

	if absf(_strafe_intent) > 0.01:
		var strafe_direction: Vector2 = forward.rotated(signf(_strafe_intent) * PI * 0.5)
		velocity += strafe_direction * thrust_force * strafe_acceleration_ratio * absf(_strafe_intent) * delta

	if _has_command_target:
		var distance_to_target: float = global_position.distance_to(_command_target_position)
		if distance_to_target < 220.0:
			var braking_factor: float = 1.0 + ((220.0 - distance_to_target) / 220.0)
			velocity = velocity.move_toward(Vector2.ZERO, thrust_force * 0.65 * braking_factor * delta)

	velocity *= maxf(0.0, 1.0 - (linear_damp * delta))


func _apply_hazard_forces(delta: float) -> void:
	for zone_variant in get_tree().get_nodes_in_group("hazard_zone"):
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if not zone.has_method("get_gravity_pull_at"):
			continue
		var pull: Vector2 = zone.call("get_gravity_pull_at", global_position)
		velocity += pull * delta


func _apply_soft_speed_limit(delta: float) -> void:
	var speed_limit: float = max_speed
	if _boost_intent:
		speed_limit *= boost_speed_multiplier

	var current_speed: float = velocity.length()
	if current_speed <= speed_limit:
		return

	var target_velocity: Vector2 = velocity.normalized() * speed_limit
	velocity = velocity.move_toward(target_velocity, thrust_force * 0.7 * delta)


func _try_fire_projectile() -> void:
	if not _fire_intent:
		return
	if _weapon_data.is_empty():
		return
	if _fire_cooldown_remaining > 0.0:
		return

	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	if projectile == null:
		return

	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	projectile.global_position = global_position + forward * 26.0
	get_parent().add_child(projectile)
	projectile.configure({
		"damage": float(_weapon_data.get("damage", 6.0)),
		"speed": float(_weapon_data.get("projectile_speed", 720.0)),
		"range": float(_weapon_data.get("range", 500.0)),
		"is_homing": bool(_weapon_data.get("is_homing", false)),
		"owner": "enemy",
		"source": self,
		"direction": forward,
		"color": _weapon_data.get("color", Color(1.0, 0.35, 0.35, 1.0)),
		"scale": float(_weapon_data.get("scale", 1.0)),
	})

	if _player_ship != null and is_instance_valid(_player_ship) and _player_ship.has_method("register_incoming_fire"):
		_player_ship.call("register_incoming_fire", global_position)

	_fire_cooldown_remaining = float(_weapon_data.get("fire_rate", 0.4))


func _nudge_from_sector_edge(delta: float) -> void:
	const EDGE_LIMIT: float = 3920.0
	if absf(global_position.x) <= EDGE_LIMIT and absf(global_position.y) <= EDGE_LIMIT:
		return

	var inward: Vector2 = (Vector2.ZERO - global_position).normalized()
	if inward.length_squared() <= 0.0001:
		return
	velocity += inward * thrust_force * 1.25 * delta


func _get_shield_recharge_multiplier() -> float:
	var multiplier: float = 1.0
	for zone_variant in get_tree().get_nodes_in_group("hazard_zone"):
		var zone: Node2D = zone_variant as Node2D
		if zone == null or not is_instance_valid(zone):
			continue
		if not zone.has_method("contains_point") or not bool(zone.call("contains_point", global_position)):
			continue
		if zone.has_method("get_shield_recharge_multiplier"):
			multiplier = minf(multiplier, float(zone.call("get_shield_recharge_multiplier")))
	return multiplier


func _on_destroyed() -> void:
	if _death_handled:
		return
	_death_handled = true
	_spawn_explosion_effect()
	_spawn_loot_drops()
	enemy_destroyed.emit(self, archetype_id)
	queue_free()


func _spawn_loot_drops() -> void:
	var loot_table: Array = archetype_data.get("loot_table", [])
	if loot_table.is_empty():
		return

	var drop_min: int = int(archetype_data.get("drop_count_min", 1))
	var drop_max: int = int(archetype_data.get("drop_count_max", 2))
	if drop_max < drop_min:
		drop_max = drop_min

	var drop_count: int = _rng.randi_range(drop_min, drop_max)
	for i in drop_count:
		var selected: Dictionary = _pick_weighted_loot_entry(loot_table)
		if selected.is_empty():
			continue
		var quantity_min: int = max(int(selected.get("quantity_min", 1)), 1)
		var quantity_max: int = max(int(selected.get("quantity_max", quantity_min)), quantity_min)
		var quantity: int = _rng.randi_range(quantity_min, quantity_max)
		var drop_contents: Array = [{
			"item_type": String(selected.get("item_type", "credits")),
			"item_id": String(selected.get("item_id", "")),
			"quantity": quantity,
		}]

		var loot_crate: Area2D = LOOT_CRATE_SCENE.instantiate() as Area2D
		if loot_crate == null:
			continue
		loot_crate.global_position = global_position + Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-26.0, 26.0))
		get_parent().add_child(loot_crate)
		if loot_crate.has_method("configure"):
			loot_crate.call("configure", {"contents": drop_contents})


func _pick_weighted_loot_entry(entries: Array) -> Dictionary:
	var total_weight: float = 0.0
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		total_weight += maxf(float((entry_variant as Dictionary).get("weight", 1.0)), 0.0)
	if total_weight <= 0.0:
		return {}

	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		cursor += maxf(float(entry.get("weight", 1.0)), 0.0)
		if roll <= cursor:
			return entry.duplicate(true)
	return {}


func _spawn_explosion_effect() -> void:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.global_position = global_position
	particles.amount = 42
	particles.one_shot = true
	particles.lifetime = 0.52
	particles.explosiveness = 0.95
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 44.0
	particles.initial_velocity_max = 138.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.35
	particles.color = Color(1.0, 0.48, 0.3, 0.95)
	get_parent().add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _on_ai_lost_interest() -> void:
	UIManager.show_toast("%s lost interest" % display_name, &"info")
	aggro_lost.emit(display_name)


func _apply_faction_visuals() -> void:
	if faction == &"drone":
		hull_polygon.polygon = PackedVector2Array([
			Vector2(18.0, 0.0),
			Vector2(2.0, -14.0),
			Vector2(-12.0, -9.0),
			Vector2(-18.0, 0.0),
			Vector2(-12.0, 9.0),
			Vector2(2.0, 14.0),
		])
		hull_polygon.color = Color(0.24, 0.7, 0.85, 1.0)
		accent_polygon.polygon = PackedVector2Array([
			Vector2(-4.0, -7.0),
			Vector2(11.0, 0.0),
			Vector2(-4.0, 7.0),
		])
		accent_polygon.color = Color(0.82, 0.97, 1.0, 0.95)
	else:
		hull_polygon.polygon = PackedVector2Array([
			Vector2(20.0, 0.0),
			Vector2(0.0, -14.0),
			Vector2(-16.0, -6.0),
			Vector2(-18.0, 0.0),
			Vector2(-16.0, 6.0),
			Vector2(0.0, 14.0),
		])
		hull_polygon.color = Color(0.78, 0.22, 0.2, 1.0)
		accent_polygon.polygon = PackedVector2Array([
			Vector2(-6.0, -6.0),
			Vector2(10.0, 0.0),
			Vector2(-6.0, 6.0),
		])
		accent_polygon.color = Color(1.0, 0.64, 0.58, 0.95)


func _draw() -> void:
	if not _is_targeted:
		return

	var color: Color = Color(1.0, 0.92, 0.42, 0.95)
	var corner: float = 20.0
	var arm: float = 10.0

	draw_line(Vector2(-corner, -corner), Vector2(-corner + arm, -corner), color, 2.0)
	draw_line(Vector2(-corner, -corner), Vector2(-corner, -corner + arm), color, 2.0)
	draw_line(Vector2(corner, -corner), Vector2(corner - arm, -corner), color, 2.0)
	draw_line(Vector2(corner, -corner), Vector2(corner, -corner + arm), color, 2.0)
	draw_line(Vector2(-corner, corner), Vector2(-corner + arm, corner), color, 2.0)
	draw_line(Vector2(-corner, corner), Vector2(-corner, corner - arm), color, 2.0)
	draw_line(Vector2(corner, corner), Vector2(corner - arm, corner), color, 2.0)
	draw_line(Vector2(corner, corner), Vector2(corner, corner - arm), color, 2.0)
