extends Node
class_name EnemyAIController

signal lost_interest

enum AIState {
	PATROL,
	ALERT,
	CHASE,
	ATTACK,
	FLEE,
	LEASH_RETURN,
}

@export var alert_duration: float = 0.45
@export var patrol_point_count: int = 4
@export var attack_range_tolerance: float = 70.0

var _ship: EnemyShip = null
var _player_ship: Node2D = null
var _state: AIState = AIState.PATROL
var _state_elapsed: float = 0.0

var _spawn_origin: Vector2 = Vector2.ZERO
var _patrol_center: Vector2 = Vector2.ZERO
var _patrol_radius: float = 360.0
var _patrol_points: Array[Vector2] = []
var _patrol_index: int = 0

var _behavior: String = "flanker"
var _aggro_range: float = 500.0
var _leash_range: float = 1200.0
var _preferred_range: float = 320.0
var _patrol_speed_factor: float = 0.4
var _fight_to_death: bool = false


func _ready() -> void:
	set_physics_process(true)


func configure(ship: EnemyShip, archetype_data: Dictionary, spawn_origin: Vector2, patrol_center: Vector2, patrol_radius: float) -> void:
	_ship = ship
	_spawn_origin = spawn_origin
	_patrol_center = patrol_center
	_patrol_radius = maxf(patrol_radius, 120.0)

	_behavior = String(archetype_data.get("behavior", _behavior))
	_aggro_range = float(archetype_data.get("aggro_range", _aggro_range))
	_leash_range = float(archetype_data.get("leash_range", _leash_range))
	_preferred_range = float(archetype_data.get("preferred_range", _preferred_range))
	_patrol_speed_factor = float(archetype_data.get("patrol_speed_factor", _patrol_speed_factor))
	_fight_to_death = bool(archetype_data.get("fight_to_death", false))
	_aggro_range *= 1.55
	_leash_range *= 1.45
	_aggro_range = maxf(_aggro_range, 900.0)
	_leash_range = maxf(_leash_range, _aggro_range + 900.0)

	_build_patrol_points()
	_change_state(AIState.PATROL)


func set_player_ship(player_ship: Node2D) -> void:
	_player_ship = player_ship


func _physics_process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		_player_ship = get_tree().get_first_node_in_group("player_ship") as Node2D

	_state_elapsed += delta

	if _player_ship == null or not is_instance_valid(_player_ship):
		_run_patrol_behavior()
		return

	var to_player: Vector2 = _player_ship.global_position - _ship.global_position
	var distance_to_player: float = to_player.length()
	var distance_from_spawn: float = _ship.global_position.distance_to(_spawn_origin)
	var hull_ratio: float = _ship.get_hull_ratio()

	if _state != AIState.LEASH_RETURN and _state != AIState.FLEE and _should_break_off(distance_from_spawn, distance_to_player):
		_change_state(AIState.LEASH_RETURN)

	if hull_ratio < 0.2 and not _fight_to_death and _state != AIState.FLEE:
		_change_state(AIState.FLEE)

	match _state:
		AIState.PATROL:
			if distance_to_player <= _aggro_range:
				_change_state(AIState.ALERT)
				_run_alert_behavior()
			else:
				_run_patrol_behavior()
		AIState.ALERT:
			if distance_to_player > _aggro_range * 2.2:
				_change_state(AIState.PATROL)
				_run_patrol_behavior()
			elif _state_elapsed >= alert_duration:
				_change_state(AIState.CHASE)
				_run_chase_behavior(distance_to_player)
			else:
				_run_alert_behavior()
		AIState.CHASE:
			if _should_break_off(distance_from_spawn, distance_to_player):
				_change_state(AIState.LEASH_RETURN)
				_run_leash_return_behavior()
			elif distance_to_player <= _preferred_range + attack_range_tolerance:
				_change_state(AIState.ATTACK)
				_run_attack_behavior(to_player, distance_to_player)
			else:
				_run_chase_behavior(distance_to_player)
		AIState.ATTACK:
			if _should_break_off(distance_from_spawn, distance_to_player):
				_change_state(AIState.LEASH_RETURN)
				_run_leash_return_behavior()
			elif distance_to_player > _preferred_range + attack_range_tolerance * 1.8:
				_change_state(AIState.CHASE)
				_run_chase_behavior(distance_to_player)
			else:
				_run_attack_behavior(to_player, distance_to_player)
		AIState.FLEE:
			if distance_from_spawn > _leash_range * 1.25 or distance_to_player > _aggro_range * 2.2:
				_change_state(AIState.LEASH_RETURN)
				_run_leash_return_behavior()
			else:
				_run_flee_behavior()
		AIState.LEASH_RETURN:
			if distance_to_player <= _aggro_range * 0.9:
				_change_state(AIState.ALERT)
				_run_alert_behavior()
			elif distance_from_spawn <= 90.0:
				_change_state(AIState.PATROL)
				lost_interest.emit()
				_run_patrol_behavior()
			else:
				_run_leash_return_behavior()


func _change_state(next_state: AIState) -> void:
	if _state == next_state:
		return
	_state = next_state
	_state_elapsed = 0.0


func _run_patrol_behavior() -> void:
	var patrol_throttle: float = clampf(_patrol_speed_factor * 0.72, 0.2, 0.5)
	if _patrol_points.is_empty():
		_ship.set_ai_command(_patrol_center, patrol_throttle, 0.0, false, false)
		return

	var patrol_target: Vector2 = _patrol_points[_patrol_index]
	if _ship.global_position.distance_to(patrol_target) <= 120.0:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		patrol_target = _patrol_points[_patrol_index]

	_ship.set_ai_command(patrol_target, patrol_throttle, 0.0, false, false)


func _run_alert_behavior() -> void:
	if _player_ship == null:
		return
	var player_position: Vector2 = _player_ship.global_position
	_ship.set_ai_command(player_position, 0.62, 0.0, false, false, player_position)


func _run_chase_behavior(distance_to_player: float) -> void:
	if _player_ship == null:
		return

	var intercept_target: Vector2 = _player_ship.global_position
	var aim_target: Vector2 = _player_ship.global_position
	if _player_ship.has_method("get_velocity_vector"):
		var target_velocity: Vector2 = _player_ship.call("get_velocity_vector")
		intercept_target += target_velocity * 0.35
		aim_target += target_velocity * 0.18

	var throttle: float = 1.0
	if distance_to_player < _preferred_range * 0.95:
		throttle = 0.4
	var chase_strafe: float = 0.0
	if _behavior == "flanker" or _behavior == "interceptor":
		var strafe_sign: float = 1.0 if int(Time.get_ticks_msec() / 800) % 2 == 0 else -1.0
		chase_strafe = 0.18 * strafe_sign
	var can_fire: bool = distance_to_player <= _ship.get_weapon_range() * 1.1
	_ship.set_ai_command(intercept_target, throttle, chase_strafe, can_fire, false, aim_target)


func _run_attack_behavior(to_player: Vector2, distance_to_player: float) -> void:
	if _player_ship == null:
		return

	var player_position: Vector2 = _player_ship.global_position
	var aim_target: Vector2 = player_position
	if _player_ship.has_method("get_velocity_vector"):
		var player_velocity: Vector2 = _player_ship.call("get_velocity_vector")
		aim_target += player_velocity * 0.2

	var orbit_sign: float = 1.0 if int(Time.get_ticks_msec() / 900) % 2 == 0 else -1.0
	var strafe: float = 0.45 * orbit_sign
	if _behavior == "bomber":
		strafe = 0.12 * orbit_sign
	elif _behavior == "swarm":
		strafe = 0.68 * orbit_sign

	var desired_position: Vector2 = player_position
	if distance_to_player > _preferred_range:
		desired_position = player_position - to_player.normalized() * _preferred_range
	else:
		var orbit_basis: Vector2 = to_player.normalized()
		if orbit_basis.length_squared() <= 0.0001:
			orbit_basis = Vector2.RIGHT
		var orbit_direction: Vector2 = orbit_basis.rotated(orbit_sign * 0.9)
		desired_position = player_position + orbit_direction * _preferred_range

	var throttle: float = 0.72
	if distance_to_player < _preferred_range * 0.75:
		throttle = 0.48
	elif distance_to_player > _preferred_range * 1.2:
		throttle = 0.92

	var can_fire: bool = distance_to_player <= _ship.get_weapon_range() * 1.05
	_ship.set_ai_command(desired_position, throttle, strafe, can_fire, false, aim_target)


func _run_flee_behavior() -> void:
	if _player_ship == null:
		return
	var away_direction: Vector2 = (_ship.global_position - _player_ship.global_position).normalized()
	if away_direction.length_squared() <= 0.0001:
		away_direction = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var flee_target: Vector2 = _ship.global_position + away_direction * 900.0
	_ship.set_ai_command(flee_target, 1.0, 0.0, false, true)


func _run_leash_return_behavior() -> void:
	var distance_to_spawn: float = _ship.global_position.distance_to(_spawn_origin)
	var use_boost: bool = distance_to_spawn > _leash_range * 1.05
	_ship.set_ai_command(_spawn_origin, 0.95, 0.0, false, use_boost, _spawn_origin)


func _should_break_off(distance_from_spawn: float, distance_to_player: float) -> bool:
	if distance_from_spawn <= _leash_range:
		return false
	if distance_from_spawn > _leash_range * 1.45:
		return true
	var keep_fighting_radius: float = maxf(_preferred_range * 1.8, 560.0)
	return distance_to_player > keep_fighting_radius


func _build_patrol_points() -> void:
	_patrol_points.clear()
	for i in max(patrol_point_count, 3):
		var angle: float = TAU * float(i) / float(max(patrol_point_count, 3))
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * _patrol_radius
		_patrol_points.append(_patrol_center + offset)
	_patrol_index = 0
