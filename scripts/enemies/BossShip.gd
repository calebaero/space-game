extends EnemyShip
class_name BossShip

signal boss_health_changed(current_health: float, max_health: float, phase_index: int, total_phases: int)
signal boss_defeated(boss_id: StringName)
signal boss_intro_requested(boss_name: String, max_health: float, total_phases: int)

const PROXIMITY_MINE_SCENE: PackedScene = preload("res://scenes/world/ProximityMine.tscn")
const DEFENSE_NODE_SCENE: PackedScene = preload("res://scenes/world/DefenseNode.tscn")
const ENEMY_SHIP_SCENE: PackedScene = preload("res://scenes/enemies/EnemyShip.tscn")

@export var boss_id: StringName = &""
@export var total_phases: int = 1

var _boss_initialized: bool = false
var _current_phase: int = 1
var _last_phase: int = 1

var _mine_timer: float = 0.0
var _mine_deploy_window_remaining: float = 0.0

var _drone_spawn_timer: float = 0.0
var _drone_shield_cycle_timer: float = 0.0
var _drone_shield_window_open: bool = false
var _active_drone_nodes: Array[Node] = []

var _beam_angle: float = 0.0
var _beam_spawn_timer: float = 0.0
var _emp_pulse_timer: float = 0.0
var _defense_node_timer: float = 0.0
var _active_defense_nodes: Array[Node] = []


func _ready() -> void:
	super._ready()
	if ai_controller != null and is_instance_valid(ai_controller):
		ai_controller.set_physics_process(false)
	set_meta("is_boss", true)


func configure_boss(boss_definition: Dictionary) -> void:
	boss_id = StringName(String(boss_definition.get("id", boss_id)))
	if boss_id == &"":
		boss_id = &"pirate_gunship_captain"

	configure({
		"archetype_id": String(boss_id),
		"spawn_origin": global_position,
		"patrol_center": global_position,
		"patrol_radius": 220.0,
	})

	apply_runtime_modifiers({
		"is_boss": true,
		"boss_id": String(boss_id),
		"display_name": String(boss_definition.get("name", display_name)),
	})

	var hull_value: float = float(boss_definition.get("hull", damageable.max_hull))
	var shield_value: float = float(boss_definition.get("shield", damageable.max_shield))
	damageable.configure_from_values(hull_value, shield_value, 3.0, 4.5)

	thrust_force = float(boss_definition.get("thrust", thrust_force))
	max_speed = float(boss_definition.get("max_speed", max_speed))
	weapon_id = StringName(String(boss_definition.get("weapon_id", weapon_id)))
	_weapon_data = ContentDatabase.get_weapon_definition(weapon_id)
	if _weapon_data.is_empty():
		_weapon_data = ContentDatabase.get_weapon_definition(&"pirate_bombard")

	match String(boss_id):
		"pirate_gunship_captain":
			total_phases = 1
		"rogue_drone_carrier":
			total_phases = 2
		"ancient_guardian_flagship":
			total_phases = 3
		_:
			total_phases = 1

	_current_phase = 1
	_last_phase = 1
	_boss_initialized = true
	boss_intro_requested.emit(display_name.to_upper(), _get_total_health(), total_phases)
	boss_health_changed.emit(_get_total_health(), _get_total_max_health(), _current_phase, total_phases)


func _physics_process(delta: float) -> void:
	if not _boss_initialized:
		super._physics_process(delta)
		return
	if _death_handled:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		_player_ship = get_tree().get_first_node_in_group("player_ship") as Node2D
	if _player_ship == null or not is_instance_valid(_player_ship):
		super._physics_process(delta)
		return

	_update_phase_state(delta)
	_update_boss_command(delta)
	super._physics_process(delta)
	_update_boss_abilities(delta)
	boss_health_changed.emit(_get_total_health(), _get_total_max_health(), _current_phase, total_phases)


func apply_projectile_damage(amount: float, projectile: Node = null) -> void:
	var adjusted_amount: float = amount
	if boss_id == &"rogue_drone_carrier" and not _drone_shield_window_open:
		modulate = Color(0.52, 0.75, 1.0, 1.0)
		var tween: Tween = create_tween()
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.16)
		return
	if boss_id == &"pirate_gunship_captain" and _mine_deploy_window_remaining > 0.0:
		adjusted_amount *= 1.4
	super.apply_projectile_damage(adjusted_amount, projectile)


func _try_fire_projectile() -> void:
	if not _fire_intent:
		return
	if _weapon_data.is_empty():
		return
	if _fire_cooldown_remaining > 0.0:
		return

	if boss_id == &"pirate_gunship_captain":
		_fire_dual_cannons()
		_fire_cooldown_remaining = maxf(float(_weapon_data.get("fire_rate", 0.55)), 0.2)
		return

	if boss_id == &"ancient_guardian_flagship":
		_fire_single_projectile(Color(1.0, 0.68, 0.34, 1.0), 1.2)
		_fire_cooldown_remaining = maxf(float(_weapon_data.get("fire_rate", 0.6)) * 0.85, 0.14)
		return

	_fire_single_projectile(Color(1.0, 0.4, 0.4, 1.0), 1.0)
	_fire_cooldown_remaining = maxf(float(_weapon_data.get("fire_rate", 0.5)), 0.12)


func _fire_dual_cannons() -> void:
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var lateral: Vector2 = forward.orthogonal()
	var left_spawn: Vector2 = global_position + forward * 30.0 - lateral * 10.0
	var right_spawn: Vector2 = global_position + forward * 30.0 + lateral * 10.0
	_fire_projectile_from(left_spawn, forward.rotated(-0.03), Color(1.0, 0.4, 0.36, 1.0), 1.1)
	_fire_projectile_from(right_spawn, forward.rotated(0.03), Color(1.0, 0.4, 0.36, 1.0), 1.1)


func _fire_single_projectile(projectile_color: Color, scale: float) -> void:
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	_fire_projectile_from(global_position + forward * 28.0, forward, projectile_color, scale)


func _fire_projectile_from(spawn_position: Vector2, direction: Vector2, projectile_color: Color, scale: float) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	if projectile == null:
		return
	projectile.global_position = spawn_position
	get_parent().add_child(projectile)
	projectile.configure({
		"damage": float(_weapon_data.get("damage", 12.0)),
		"speed": float(_weapon_data.get("projectile_speed", 760.0)),
		"range": float(_weapon_data.get("range", 900.0)),
		"owner": "enemy",
		"source": self,
		"direction": direction.normalized(),
		"color": projectile_color,
		"scale": scale,
		"width": float(_weapon_data.get("width", 2.8)),
		"shield_disable_duration": float(_weapon_data.get("shield_disable_duration", 0.0)),
	})
	if _player_ship != null and is_instance_valid(_player_ship) and _player_ship.has_method("register_incoming_fire"):
		_player_ship.call("register_incoming_fire", global_position)
	AudioManager.play_sfx(&"weapon_fire", global_position)
	AudioManager.report_combat_activity()


func _update_boss_command(delta: float) -> void:
	var to_player: Vector2 = _player_ship.global_position - global_position
	var distance_to_player: float = to_player.length()
	if distance_to_player <= 0.001:
		distance_to_player = 1.0
	var normalized_to_player: Vector2 = to_player / distance_to_player
	var orbit_sign: float = 1.0 if int(Time.get_ticks_msec() / 1100) % 2 == 0 else -1.0

	if boss_id == &"pirate_gunship_captain":
		_mine_timer += delta
		if _mine_timer >= 8.0:
			_mine_timer = 0.0
			_spawn_proximity_mine()
			_mine_deploy_window_remaining = 2.0
		if _mine_deploy_window_remaining > 0.0:
			_mine_deploy_window_remaining = maxf(_mine_deploy_window_remaining - delta, 0.0)

		var desired_position: Vector2 = _player_ship.global_position - normalized_to_player * 620.0
		var strafe: float = 0.42 * orbit_sign
		var throttle: float = 0.78 if distance_to_player > 560.0 else 0.48
		var can_fire: bool = _mine_deploy_window_remaining <= 0.0 and distance_to_player <= get_weapon_range() * 1.08
		set_ai_command(desired_position, throttle, strafe, can_fire, false, _player_ship.global_position)
		return

	if boss_id == &"rogue_drone_carrier":
		var desired_offset: float = 760.0
		var desired_position_carrier: Vector2 = _player_ship.global_position - normalized_to_player * desired_offset
		var carrier_throttle: float = 0.7 if distance_to_player > desired_offset * 0.9 else 0.42
		var can_fire_carrier: bool = distance_to_player <= get_weapon_range() * 1.1
		set_ai_command(desired_position_carrier, carrier_throttle, 0.18 * orbit_sign, can_fire_carrier, false, _player_ship.global_position)
		return

	# Ancient Guardian flagship
	var preferred_distance: float = 880.0
	var guardian_target: Vector2 = _player_ship.global_position - normalized_to_player * preferred_distance
	var guardian_throttle: float = 0.64 if distance_to_player > preferred_distance * 0.92 else 0.36
	var guardian_fire: bool = distance_to_player <= get_weapon_range() * 1.18
	set_ai_command(guardian_target, guardian_throttle, 0.16 * orbit_sign, guardian_fire, false, _player_ship.global_position)


func _update_boss_abilities(delta: float) -> void:
	if boss_id == &"rogue_drone_carrier":
		_update_drone_carrier_abilities(delta)
	elif boss_id == &"ancient_guardian_flagship":
		_update_guardian_abilities(delta)


func _update_phase_state(delta: float) -> void:
	if boss_id == &"rogue_drone_carrier":
		_drone_shield_cycle_timer += delta
		if _drone_shield_window_open and _drone_shield_cycle_timer >= 5.0:
			_drone_shield_window_open = false
			_drone_shield_cycle_timer = 0.0
		elif not _drone_shield_window_open and _drone_shield_cycle_timer >= 8.0:
			_drone_shield_window_open = true
			_drone_shield_cycle_timer = 0.0
		_current_phase = 2 if _drone_shield_window_open else 1
		return

	if boss_id == &"ancient_guardian_flagship":
		var hull_ratio: float = damageable.get_hull_ratio()
		if hull_ratio > 0.6:
			_current_phase = 1
		elif hull_ratio > 0.3:
			_current_phase = 2
		else:
			_current_phase = 3
		if _current_phase != _last_phase:
			_last_phase = _current_phase
			UIManager.show_toast("%s entering phase %d" % [display_name, _current_phase], &"warning")
		return

	_current_phase = 1


func _update_drone_carrier_abilities(delta: float) -> void:
	_active_drone_nodes = _active_drone_nodes.filter(func(node: Node) -> bool:
		return node != null and is_instance_valid(node)
	)

	_drone_spawn_timer += delta
	if _drone_spawn_timer < 12.0:
		return
	_drone_spawn_timer = 0.0
	if _active_drone_nodes.size() >= 6:
		return

	var spawn_count: int = min(3, 6 - _active_drone_nodes.size())
	for i in spawn_count:
		var drone_ship: EnemyShip = ENEMY_SHIP_SCENE.instantiate() as EnemyShip
		if drone_ship == null:
			continue
		var angle: float = (TAU * float(i) / float(max(spawn_count, 1))) + randf_range(-0.3, 0.3)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(150.0, 260.0)
		drone_ship.global_position = global_position + offset
		get_parent().add_child(drone_ship)
		drone_ship.configure({
			"archetype_id": "drone_scout",
			"spawn_origin": drone_ship.global_position,
			"patrol_center": drone_ship.global_position,
			"patrol_radius": 280.0,
		})
		if _player_ship != null and is_instance_valid(_player_ship):
			drone_ship.set_player_ship(_player_ship)
		_active_drone_nodes.append(drone_ship)


func _update_guardian_abilities(delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	var beam_rotation_speed: float = TAU / 6.0
	if _current_phase == 2:
		beam_rotation_speed = TAU / 4.5
	elif _current_phase >= 3:
		beam_rotation_speed = TAU / 3.6
	_beam_angle = wrapf(_beam_angle + beam_rotation_speed * delta, -PI, PI)
	_apply_beam_damage(delta)

	var summon_interval: float = 20.0
	if _current_phase == 2:
		summon_interval = 16.0
	elif _current_phase >= 3:
		summon_interval = 12.0
	_defense_node_timer += delta
	if _defense_node_timer >= summon_interval:
		_defense_node_timer = 0.0
		_summon_defense_nodes(2)

	if _current_phase >= 2:
		_emp_pulse_timer += delta
		if _emp_pulse_timer >= (8.0 if _current_phase >= 3 else 10.0):
			_emp_pulse_timer = 0.0
			_emit_emp_pulse()

	if _current_phase >= 3:
		_apply_gravity_pull_to_player(delta)


func _apply_beam_damage(delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	var to_player: Vector2 = _player_ship.global_position - global_position
	var distance: float = to_player.length()
	if distance > 1400.0 or distance <= 0.001:
		return
	var beam_direction: Vector2 = Vector2.RIGHT.rotated(_beam_angle)
	var angle_error: float = absf(beam_direction.angle_to(to_player.normalized()))
	if angle_error > deg_to_rad(11.0):
		return
	if _player_ship.has_method("apply_external_damage"):
		var dps: float = 22.0
		if _current_phase == 2:
			dps = 28.0
		elif _current_phase >= 3:
			dps = 36.0
		_player_ship.call("apply_external_damage", dps * delta, "Ancient Beam")


func _emit_emp_pulse() -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if global_position.distance_to(_player_ship.global_position) <= 920.0:
		if _player_ship.has_method("apply_emp_disable"):
			_player_ship.call("apply_emp_disable", 3.0)
	UIManager.show_toast("EMP pulse emitted", &"warning")


func _apply_gravity_pull_to_player(delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if not (_player_ship is CharacterBody2D):
		return
	var player_body: CharacterBody2D = _player_ship as CharacterBody2D
	var to_center: Vector2 = global_position - player_body.global_position
	var distance: float = to_center.length()
	if distance <= 1.0 or distance > 1900.0:
		return
	var pull_strength: float = 220.0 * (1.0 - clampf(distance / 1900.0, 0.0, 1.0))
	player_body.velocity += to_center.normalized() * pull_strength * delta


func _summon_defense_nodes(count: int) -> void:
	_active_defense_nodes = _active_defense_nodes.filter(func(node: Node) -> bool:
		return node != null and is_instance_valid(node)
	)
	for i in count:
		var node: Node2D = DEFENSE_NODE_SCENE.instantiate() as Node2D
		if node == null:
			continue
		var angle: float = (TAU * float(i) / float(max(count, 1))) + randf_range(-0.35, 0.35)
		var position_offset: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(280.0, 420.0)
		node.global_position = global_position + position_offset
		get_parent().add_child(node)
		if node.has_method("configure"):
			node.call("configure", {
				"display_name": "Defense Node",
				"hull": 100.0,
				"faction": "alien",
				"damage": 10.0,
				"range": 920.0,
			})
		if _player_ship != null and is_instance_valid(_player_ship) and node.has_method("set_player_ship"):
			node.call("set_player_ship", _player_ship)
		_active_defense_nodes.append(node)


func _spawn_proximity_mine() -> void:
	var mine: Area2D = PROXIMITY_MINE_SCENE.instantiate() as Area2D
	if mine == null:
		return
	var backward: Vector2 = -Vector2.RIGHT.rotated(rotation)
	mine.global_position = global_position + backward * 44.0
	get_parent().add_child(mine)
	if mine.has_method("configure"):
		mine.call("configure", {
			"owner": "enemy",
			"arm_time": 1.0,
			"trigger_radius": 100.0,
			"damage": 25.0,
			"blast_radius": 80.0,
		})


func _get_total_health() -> float:
	return damageable.current_hull + damageable.current_shield


func _get_total_max_health() -> float:
	return damageable.max_hull + damageable.max_shield


func _on_destroyed() -> void:
	AudioManager.play_sfx(&"explosion_large", global_position)
	boss_defeated.emit(boss_id)
	super._on_destroyed()
