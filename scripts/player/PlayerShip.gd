extends CharacterBody2D
class_name PlayerShip

signal boost_activated
signal station_dock_requested(station_node: Node)
signal warp_gate_requested(destination_sector_id: StringName, source_gate_id: StringName)
signal player_destroyed(death_position: Vector2)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/world/Projectile.tscn")

@export_group("Flight Base")
@export var thrust_force: float = 300.0
@export var max_speed: float = 360.0
@export var angular_acceleration: float = 8.4
@export var angular_drag: float = 6.2
@export var rotational_assist_torque: float = 7.5
@export var linear_damp: float = 0.1
@export var brake_multiplier: float = 0.8
@export var control_zone_linear_damp: float = 0.5

@export_group("Boost")
@export var boost_multiplier: float = 2.5
@export var boost_max_speed_bonus: float = 0.35
@export var boost_duration: float = 2.0
@export var boost_cooldown: float = 5.0
@export var boost_cost: float = 40.0
@export var boost_recharge_rate: float = 15.0
@export var max_boost_energy: float = 100.0

@export_group("Scanner")
@export var scanner_visual_duration: float = 1.0

@export_group("Mining")
@export var mining_cone_degrees: float = 45.0

@export_group("Combat")
@export var target_lock_range: float = 600.0

@export_group("Camera")
@export var camera_lead_scale: float = 0.3
@export var camera_max_lead: float = 80.0
@export var high_speed_zoom: float = 1.3
@export var zoom_lerp_speed: float = 2.0

@export_group("Screen Shake")
@export var trauma_decay_rate: float = 1.7
@export var max_shake_offset: float = 8.0

@onready var ship_camera: Camera2D = %ShipCamera
@onready var control_zone_detector: Area2D = %ControlZoneDetector
@onready var interaction_area: Area2D = $InteractionArea
@onready var mining_beam: Line2D = %MiningBeam
@onready var mining_sparks: CPUParticles2D = %MiningSparks

var angular_velocity: float = 0.0
var boost_energy: float = 100.0
var controls_enabled: bool = true

var _boost_time_remaining: float = 0.0
var _boost_cooldown_remaining: float = 0.0
var _scanner_cooldown_remaining: float = 0.0
var _scanner_visual_remaining: float = 0.0
var _scanner_visual_range: float = 600.0

var _trauma: float = 0.0
var _active_control_zones: Dictionary = {}
var _interaction_areas: Array[Area2D] = []
var _active_hazard_zones: Dictionary = {}
var _debris_contact_timers: Dictionary = {}

var _active_mining_node: Node2D = null
var _mining_progress_time: float = 0.0
var _mining_required_time: float = 0.0
var _last_interaction_prompt_key: String = ""

var _primary_fire_cooldown_remaining: float = 0.0
var _secondary_fire_cooldown_remaining: float = 0.0
var _secondary_toast_cooldown: float = 0.0
var _current_target: EnemyShip = null
var _target_candidates: Array[EnemyShip] = []
var _target_cycle_index: int = -1
var _has_target_lead: bool = false
var _target_lead_world_position: Vector2 = Vector2.ZERO
var _incoming_warning_timer: float = 0.0
var _incoming_warning_source_position: Vector2 = Vector2.ZERO
var _shield_hit_flash_remaining: float = 0.0
var _hull_hit_flash_remaining: float = 0.0
var _death_emitted: bool = false


func _ready() -> void:
	add_to_group("player_ship")
	boost_energy = max_boost_energy
	_death_emitted = false

	ship_camera.position_smoothing_enabled = true
	ship_camera.position_smoothing_speed = 3.0
	ship_camera.zoom = Vector2.ONE

	control_zone_detector.area_entered.connect(_on_control_zone_area_entered)
	control_zone_detector.area_exited.connect(_on_control_zone_area_exited)
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	mining_beam.visible = false
	mining_sparks.emitting = false

	if not GameStateManager.player_damage_applied.is_connected(_on_player_damage_applied):
		GameStateManager.player_damage_applied.connect(_on_player_damage_applied)
	if not GameStateManager.player_destroyed.is_connected(_on_player_state_destroyed):
		GameStateManager.player_destroyed.connect(_on_player_state_destroyed)


func _physics_process(delta: float) -> void:
	_update_active_hazards()
	_update_debris_contact_timers(delta)
	_update_combat_timers(delta)

	if controls_enabled:
		if Input.is_action_just_pressed("utility_activate") and _is_utility_disabled():
			UIManager.show_toast("Utility systems disabled in EMP zone.", &"warning")

		_update_boost_state(delta)
		_update_scanner_state(delta)
		_update_rotation(delta)
		_apply_linear_forces(delta)
		_apply_hazard_forces(delta)
		_apply_soft_speed_limit(delta)
		_update_weapon_state()
		_update_targeting()
		_update_mining(delta)

		if Input.is_action_just_pressed("interact"):
			_try_interact_with_current_target()
		_update_interaction_prompt()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, _get_effective_thrust() * 0.6 * delta)
		_stop_mining(false)
		_update_scanner_state(delta)
		_clear_target_lock()

	_update_shield_recharge(delta)
	move_and_slide()
	_handle_slide_hazard_collisions()
	_update_camera(delta)


func _process(delta: float) -> void:
	if _shield_hit_flash_remaining > 0.0:
		_shield_hit_flash_remaining = maxf(_shield_hit_flash_remaining - delta, 0.0)
	if _hull_hit_flash_remaining > 0.0:
		_hull_hit_flash_remaining = maxf(_hull_hit_flash_remaining - delta, 0.0)
	if _incoming_warning_timer > 0.0:
		_incoming_warning_timer = maxf(_incoming_warning_timer - delta, 0.0)

	if _scanner_visual_remaining > 0.0 or _shield_hit_flash_remaining > 0.0 or _hull_hit_flash_remaining > 0.0:
		queue_redraw()


func _draw() -> void:
	if _scanner_visual_remaining > 0.0:
		var progress: float = 1.0 - (_scanner_visual_remaining / maxf(scanner_visual_duration, 0.01))
		var ring_radius: float = lerpf(0.0, _scanner_visual_range, clampf(progress, 0.0, 1.0))
		var alpha: float = 0.45 * (1.0 - clampf(progress, 0.0, 1.0))
		draw_circle(Vector2.ZERO, ring_radius, Color(0.34, 0.8, 1.0, alpha * 0.28))
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 64, Color(0.4, 0.9, 1.0, alpha), 3.0)

	if _shield_hit_flash_remaining > 0.0:
		var shield_alpha: float = clampf(_shield_hit_flash_remaining / 0.16, 0.0, 1.0) * 0.85
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 48, Color(0.48, 0.82, 1.0, shield_alpha), 3.0)

	if _hull_hit_flash_remaining > 0.0:
		var hull_alpha: float = clampf(_hull_hit_flash_remaining / 0.12, 0.0, 1.0) * 0.35
		draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.2, 0.2, hull_alpha))


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not controls_enabled:
		angular_velocity = 0.0
		_last_interaction_prompt_key = ""
		_stop_mining(false)
		_clear_target_lock()


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func apply_external_damage(amount: float, source: String = "Hazard") -> void:
	if amount <= 0.0:
		return

	if source == "Debris Impact":
		GameStateManager.apply_hull_damage(amount)
	else:
		GameStateManager.apply_damage(amount)


func apply_projectile_damage(amount: float, _projectile: Node = null) -> void:
	if amount <= 0.0:
		return
	GameStateManager.apply_damage(amount)


func is_boost_active() -> bool:
	return _boost_time_remaining > 0.0


func get_boost_energy_ratio() -> float:
	if max_boost_energy <= 0.0:
		return 0.0
	return boost_energy / max_boost_energy


func get_current_speed() -> float:
	return velocity.length()


func get_velocity_vector() -> Vector2:
	return velocity


func get_boost_cooldown_remaining() -> float:
	return _boost_cooldown_remaining


func get_scanner_cooldown_remaining() -> float:
	return _scanner_cooldown_remaining


func get_scanner_cooldown_total() -> float:
	var cooldown: float = GameStateManager.get_effective_stat(&"scanner_cooldown")
	if cooldown <= 0.0:
		return 8.0
	return cooldown


func get_scanner_cooldown_ratio() -> float:
	var total: float = get_scanner_cooldown_total()
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - (_scanner_cooldown_remaining / total), 0.0, 1.0)


func get_minimap_jitter_strength() -> float:
	return _get_steering_noise_strength()


func get_current_target_info() -> Dictionary:
	if _current_target == null or not is_instance_valid(_current_target):
		return {}

	var distance: float = global_position.distance_to(_current_target.global_position)
	var info: Dictionary = {
		"name": _current_target.get_display_name() if _current_target.has_method("get_display_name") else "Unknown Target",
		"faction": _current_target.get_faction_name() if _current_target.has_method("get_faction_name") else "Unknown",
		"distance": distance,
		"hull": _current_target.get_current_hull() if _current_target.has_method("get_current_hull") else 0.0,
		"max_hull": _current_target.get_max_hull() if _current_target.has_method("get_max_hull") else 1.0,
		"shield": _current_target.get_current_shield() if _current_target.has_method("get_current_shield") else 0.0,
		"max_shield": _current_target.get_max_shield() if _current_target.has_method("get_max_shield") else 1.0,
	}
	return info


func has_target_lead_indicator() -> bool:
	return _has_target_lead


func get_target_lead_world_position() -> Vector2:
	return _target_lead_world_position


func get_incoming_warning_data() -> Dictionary:
	if _incoming_warning_timer <= 0.0:
		return {"active": false}
	if _is_world_position_on_screen(_incoming_warning_source_position):
		return {"active": false}

	var direction: Vector2 = (_incoming_warning_source_position - global_position).normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	return {
		"active": true,
		"direction": direction,
		"strength": clampf(_incoming_warning_timer / 0.9, 0.0, 1.0),
	}


func register_incoming_fire(source_position: Vector2) -> void:
	_incoming_warning_source_position = source_position
	_incoming_warning_timer = maxf(_incoming_warning_timer, 0.9)


func _update_rotation(delta: float) -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() < 0.001:
		return

	var desired_angle: float = to_mouse.angle()
	var steering_noise: float = _get_steering_noise_strength()
	if steering_noise > 0.0:
		desired_angle += randf_range(-steering_noise, steering_noise)

	var angle_error: float = wrapf(desired_angle - rotation, -PI, PI)

	var base_turn_speed: float = GameStateManager.get_effective_stat(&"turn_speed")
	if base_turn_speed <= 0.0:
		base_turn_speed = 3.0

	var total_mass: float = GameStateManager.get_total_mass()
	var mass_multiplier: float = maxf(0.25, 1.0 - (total_mass * 0.01))
	var effective_turn_speed: float = base_turn_speed * mass_multiplier

	var steering_input: float = clampf(angle_error / PI, -1.0, 1.0)
	var manual_torque: float = Input.get_action_strength("rotate_right") - Input.get_action_strength("rotate_left")

	var max_turn_rate: float = maxf(effective_turn_speed * 4.0, 6.8)
	var desired_turn_rate: float = clampf(angle_error * effective_turn_speed * 2.9, -max_turn_rate, max_turn_rate)
	desired_turn_rate += manual_torque * rotational_assist_torque

	var turn_response: float = angular_acceleration * effective_turn_speed * (1.0 + absf(steering_input) * 0.65)
	angular_velocity = move_toward(
		angular_velocity,
		desired_turn_rate,
		turn_response * delta
	)

	var settling_drag: float = angular_drag
	if absf(angle_error) < 0.35:
		settling_drag *= 2.4
	elif absf(angle_error) < 0.8:
		settling_drag *= 1.5
	angular_velocity = move_toward(angular_velocity, 0.0, settling_drag * delta)
	rotation += angular_velocity * delta


func _apply_linear_forces(delta: float) -> void:
	var effective_thrust: float = _get_effective_thrust()
	var forward_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	var steering_angle_error: float = absf(wrapf((get_global_mouse_position() - global_position).angle() - rotation, -PI, PI))
	var turn_thrust_scale: float = 1.0
	if steering_angle_error > 0.65:
		turn_thrust_scale = clampf(1.0 - ((steering_angle_error - 0.65) * 0.62), 0.4, 1.0)

	if Input.is_action_pressed("thrust") or Input.is_action_pressed("thrust_alt"):
		velocity += forward_direction * effective_thrust * _get_boost_multiplier() * turn_thrust_scale * delta

	if Input.is_action_pressed("brake") and velocity.length() > 0.001:
		velocity += -velocity.normalized() * effective_thrust * brake_multiplier * delta

	if velocity.length() > 70.0 and steering_angle_error > 0.35:
		var lateral_axis: Vector2 = forward_direction.orthogonal()
		var lateral_speed: float = velocity.dot(lateral_axis)
		var correction_strength: float = clampf((steering_angle_error - 0.35) / 1.5, 0.0, 1.0)
		var correction_step: float = minf(delta * (2.6 + correction_strength * 2.8), 0.5)
		velocity -= lateral_axis * lateral_speed * correction_step

		if (Input.is_action_pressed("thrust") or Input.is_action_pressed("thrust_alt")) and steering_angle_error > 1.0:
			var current_max_speed: float = _get_current_max_speed()
			if velocity.length() > current_max_speed * 0.45:
				var pivot_brake: float = clampf((steering_angle_error - 1.0) / 1.4, 0.0, 1.0)
				velocity += -velocity.normalized() * effective_thrust * 0.2 * pivot_brake * delta

	var current_linear_damp: float = _get_current_linear_damp()
	velocity *= maxf(0.0, 1.0 - (current_linear_damp * delta))


func _apply_hazard_forces(delta: float) -> void:
	for zone_variant in _active_hazard_zones.values():
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.has_method("get_gravity_pull_at"):
			var pull: Vector2 = zone.call("get_gravity_pull_at", global_position)
			velocity += pull * delta


func _apply_soft_speed_limit(delta: float) -> void:
	var current_max_speed: float = _get_current_max_speed()
	var current_speed: float = velocity.length()
	if current_speed <= current_max_speed:
		return

	var target_velocity: Vector2 = velocity.normalized() * current_max_speed
	var correction_force: float = maxf((current_speed - current_max_speed) * 2.0, _get_effective_thrust() * 0.7)
	velocity = velocity.move_toward(target_velocity, correction_force * delta)


func _update_combat_timers(delta: float) -> void:
	if _primary_fire_cooldown_remaining > 0.0:
		_primary_fire_cooldown_remaining = maxf(_primary_fire_cooldown_remaining - delta, 0.0)
	if _secondary_fire_cooldown_remaining > 0.0:
		_secondary_fire_cooldown_remaining = maxf(_secondary_fire_cooldown_remaining - delta, 0.0)
	if _secondary_toast_cooldown > 0.0:
		_secondary_toast_cooldown = maxf(_secondary_toast_cooldown - delta, 0.0)


func _update_weapon_state() -> void:
	if Input.is_action_pressed("fire_primary"):
		_fire_weapon_from_slot(&"primary", false)

	if Input.is_action_just_pressed("fire_secondary"):
		var fired_secondary: bool = _fire_weapon_from_slot(&"secondary", true)
		if not fired_secondary and _secondary_toast_cooldown <= 0.0:
			UIManager.show_toast("No secondary weapon equipped.", &"info")
			_secondary_toast_cooldown = 0.7


func _fire_weapon_from_slot(slot_name: StringName, is_secondary: bool) -> bool:
	if is_secondary:
		if _secondary_fire_cooldown_remaining > 0.0:
			return false
	else:
		if _primary_fire_cooldown_remaining > 0.0:
			return false

	var weapon_data: Dictionary = GameStateManager.get_equipped_weapon_definition(slot_name)
	if weapon_data.is_empty() and slot_name == &"primary":
		weapon_data = ContentDatabase.get_weapon_definition(&"pulse_laser")
	if weapon_data.is_empty():
		return false

	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	if projectile == null:
		return false

	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	projectile.global_position = global_position + forward * 24.0
	get_parent().add_child(projectile)
	projectile.configure({
		"damage": float(weapon_data.get("damage", 8.0)),
		"speed": float(weapon_data.get("projectile_speed", 800.0)),
		"range": float(weapon_data.get("range", 500.0)),
		"is_homing": bool(weapon_data.get("is_homing", false)),
		"owner": "player",
		"source": self,
		"direction": forward,
		"color": weapon_data.get("color", Color(0.7, 0.9, 1.0, 1.0)),
		"scale": float(weapon_data.get("scale", 1.0)),
		"width": 2.5,
	})

	var fire_rate: float = float(weapon_data.get("fire_rate", 0.2))
	if is_secondary:
		_secondary_fire_cooldown_remaining = maxf(fire_rate, 0.05)
	else:
		_primary_fire_cooldown_remaining = maxf(fire_rate, 0.05)

	return true


func _update_targeting() -> void:
	_target_candidates = _collect_target_candidates()
	if _target_candidates.is_empty():
		_clear_target_lock()
		return

	if Input.is_action_just_pressed("cycle_target"):
		_cycle_target_lock()
	else:
		if _current_target == null or not is_instance_valid(_current_target):
			_set_current_target(_target_candidates[0])
		elif not _target_candidates.has(_current_target):
			_set_current_target(_target_candidates[0])

	_update_target_lead_indicator()


func _collect_target_candidates() -> Array[EnemyShip]:
	var collected: Array[Dictionary] = []
	var range_multiplier: float = 1.0
	var steering_noise: float = _get_steering_noise_strength()
	if steering_noise > 0.0:
		range_multiplier = clampf(1.0 - steering_noise * 1.2, 0.6, 1.0)
	var effective_range: float = target_lock_range * range_multiplier

	for enemy_variant in get_tree().get_nodes_in_group("enemy_ship"):
		var enemy: EnemyShip = enemy_variant as EnemyShip
		if enemy == null or not is_instance_valid(enemy):
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance > effective_range:
			continue
		collected.append({
			"enemy": enemy,
			"distance": distance,
		})

	collected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)

	var result: Array[EnemyShip] = []
	for entry in collected:
		result.append(entry["enemy"] as EnemyShip)
	return result


func _cycle_target_lock() -> void:
	if _target_candidates.is_empty():
		_clear_target_lock()
		return

	_target_cycle_index += 1
	if _target_cycle_index >= _target_candidates.size():
		_target_cycle_index = 0
	_set_current_target(_target_candidates[_target_cycle_index])


func _set_current_target(enemy: EnemyShip) -> void:
	if _current_target != null and is_instance_valid(_current_target) and _current_target.has_method("set_targeted"):
		_current_target.call("set_targeted", false)

	_current_target = enemy
	if _current_target != null and is_instance_valid(_current_target) and _current_target.has_method("set_targeted"):
		_current_target.call("set_targeted", true)


func _clear_target_lock() -> void:
	if _current_target != null and is_instance_valid(_current_target) and _current_target.has_method("set_targeted"):
		_current_target.call("set_targeted", false)
	_current_target = null
	_target_cycle_index = -1
	_has_target_lead = false


func _update_target_lead_indicator() -> void:
	_has_target_lead = false
	if _current_target == null or not is_instance_valid(_current_target):
		return

	var weapon_data: Dictionary = GameStateManager.get_equipped_weapon_definition(&"primary")
	if weapon_data.is_empty():
		weapon_data = ContentDatabase.get_weapon_definition(&"pulse_laser")
	var projectile_speed: float = float(weapon_data.get("projectile_speed", 800.0))
	if projectile_speed <= 0.0:
		return

	var target_velocity: Vector2 = Vector2.ZERO
	var target_body: CharacterBody2D = _current_target as CharacterBody2D
	if target_body != null:
		target_velocity = target_body.velocity
	var distance: float = global_position.distance_to(_current_target.global_position)
	var travel_time: float = distance / projectile_speed
	_target_lead_world_position = _current_target.global_position + target_velocity * travel_time

	var target_noise: float = _get_steering_noise_strength()
	if target_noise > 0.0:
		_target_lead_world_position += Vector2(randf_range(-28.0, 28.0), randf_range(-28.0, 28.0)) * target_noise

	_has_target_lead = true


func _update_boost_state(delta: float) -> void:
	if Input.is_action_just_pressed("boost"):
		_try_activate_boost()

	if _boost_time_remaining > 0.0:
		_boost_time_remaining = maxf(_boost_time_remaining - delta, 0.0)

	if _boost_cooldown_remaining > 0.0:
		_boost_cooldown_remaining = maxf(_boost_cooldown_remaining - delta, 0.0)

	if not is_boost_active():
		boost_energy = minf(max_boost_energy, boost_energy + boost_recharge_rate * delta)


func _try_activate_boost() -> void:
	if is_boost_active():
		return
	if _boost_cooldown_remaining > 0.0:
		return
	if boost_energy < boost_cost:
		UIManager.show_toast("Boost energy too low.", &"warning")
		return

	boost_energy -= boost_cost
	_boost_time_remaining = boost_duration
	_boost_cooldown_remaining = boost_cooldown
	add_trauma(0.2)
	boost_activated.emit()


func _update_scanner_state(delta: float) -> void:
	if _scanner_cooldown_remaining > 0.0:
		_scanner_cooldown_remaining = maxf(_scanner_cooldown_remaining - delta, 0.0)

	if _scanner_visual_remaining > 0.0:
		_scanner_visual_remaining = maxf(_scanner_visual_remaining - delta, 0.0)

	if controls_enabled and Input.is_action_just_pressed("scan"):
		_try_activate_scanner()


func _try_activate_scanner() -> void:
	if _scanner_cooldown_remaining > 0.0:
		UIManager.show_toast("Scanner recharging.", &"info")
		return

	var scan_range: float = GameStateManager.get_effective_stat(&"scanner_range")
	if scan_range <= 0.0:
		scan_range = 600.0

	var cooldown: float = GameStateManager.get_effective_stat(&"scanner_cooldown")
	if cooldown <= 0.0:
		cooldown = 8.0

	_scanner_cooldown_remaining = cooldown
	_scanner_visual_remaining = scanner_visual_duration
	_scanner_visual_range = scan_range
	_run_scanner_pulse(scan_range)
	queue_redraw()


func _run_scanner_pulse(scan_range: float) -> void:
	for node_variant in get_tree().get_nodes_in_group("scannable_resource_node"):
		var node: Node2D = node_variant as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if node.global_position.distance_to(global_position) > scan_range:
			continue
		if node.has_method("on_scanned"):
			node.call("on_scanned", 5.0)

	for anomaly_variant in get_tree().get_nodes_in_group("scannable_anomaly"):
		var anomaly: Node2D = anomaly_variant as Node2D
		if anomaly == null or not is_instance_valid(anomaly):
			continue
		if anomaly.global_position.distance_to(global_position) > scan_range:
			continue
		if anomaly.has_method("on_scanned"):
			anomaly.call("on_scanned", 5.0)

	for loot_variant in get_tree().get_nodes_in_group("hidden_loot"):
		var loot: Node2D = loot_variant as Node2D
		if loot == null or not is_instance_valid(loot):
			continue
		if loot.global_position.distance_to(global_position) > scan_range:
			continue
		if loot.has_method("reveal_temporarily"):
			loot.call("reveal_temporarily", 10.0)


func _update_mining(delta: float) -> void:
	if not Input.is_action_pressed("mine"):
		_stop_mining(false)
		return

	var target_node: Node2D = _get_valid_mining_target()
	if target_node == null:
		_stop_mining(true)
		return

	if _active_mining_node == null or _active_mining_node != target_node:
		_switch_mining_target(target_node)

	if _active_mining_node == null:
		return

	_mining_progress_time += delta
	var progress_ratio: float = clampf(_mining_progress_time / maxf(_mining_required_time, 0.01), 0.0, 1.0)
	if _active_mining_node.has_method("set_mining_progress"):
		_active_mining_node.call("set_mining_progress", progress_ratio)

	_update_mining_beam_visual(_active_mining_node)

	if progress_ratio < 1.0:
		return

	var mined_quantity: int = 0
	var mined_resource_name: String = "Resource"
	if _active_mining_node.has_method("get_yield_amount"):
		mined_quantity = int(_active_mining_node.call("get_yield_amount"))
	if _active_mining_node.has_method("get_resource_name"):
		mined_resource_name = String(_active_mining_node.call("get_resource_name"))
	if _active_mining_node.has_method("complete_extraction"):
		_active_mining_node.call("complete_extraction", self)

	UIManager.show_toast("+%d %s" % [max(mined_quantity, 1), mined_resource_name], &"success")
	_stop_mining(false)


func _get_valid_mining_target() -> Node2D:
	var forward_direction: Vector2 = Vector2.RIGHT.rotated(rotation)
	var max_angle: float = deg_to_rad(mining_cone_degrees)
	var mining_range_stat: float = GameStateManager.get_effective_stat(&"mining_range")
	if mining_range_stat <= 0.0:
		mining_range_stat = 200.0

	var best_node: Node2D = null
	var best_distance: float = INF

	for node_variant in get_tree().get_nodes_in_group("resource_node"):
		var node: Node2D = node_variant as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("can_be_mined") or not bool(node.call("can_be_mined")):
			continue

		var to_node: Vector2 = node.global_position - global_position
		var distance: float = to_node.length()
		if distance <= 0.001:
			continue

		var node_range: float = mining_range_stat
		if node.has_method("get_mining_range"):
			node_range = minf(node_range, float(node.call("get_mining_range")))
		if distance > node_range:
			continue

		var alignment: float = forward_direction.angle_to(to_node.normalized())
		if absf(alignment) > max_angle:
			continue

		if distance < best_distance:
			best_distance = distance
			best_node = node

	return best_node


func _switch_mining_target(target_node: Node2D) -> void:
	if _active_mining_node != null and is_instance_valid(_active_mining_node) and _active_mining_node.has_method("clear_mining_progress"):
		_active_mining_node.call("clear_mining_progress")

	_active_mining_node = target_node
	_mining_progress_time = 0.0
	_mining_required_time = 2.0

	if _active_mining_node != null and _active_mining_node.has_method("get_effective_extraction_time"):
		var mining_efficiency: float = GameStateManager.get_effective_stat(&"mining_efficiency")
		if mining_efficiency <= 0.0:
			mining_efficiency = 1.0
		_mining_required_time = float(_active_mining_node.call("get_effective_extraction_time", mining_efficiency))

	_update_mining_beam_visual(target_node)


func _stop_mining(interrupted: bool) -> void:
	if _active_mining_node != null and is_instance_valid(_active_mining_node) and _active_mining_node.has_method("clear_mining_progress"):
		_active_mining_node.call("clear_mining_progress")

	if interrupted and _mining_progress_time > 0.0:
		UIManager.show_toast("Mining Interrupted", &"warning")

	_active_mining_node = null
	_mining_progress_time = 0.0
	_mining_required_time = 0.0
	mining_beam.visible = false
	mining_sparks.emitting = false


func _update_mining_beam_visual(target_node: Node2D) -> void:
	if target_node == null or not is_instance_valid(target_node):
		mining_beam.visible = false
		mining_sparks.emitting = false
		return

	var local_target: Vector2 = to_local(target_node.global_position)
	mining_beam.visible = true
	mining_beam.points = PackedVector2Array([Vector2.ZERO, local_target])

	var beam_color: Color = Color(0.6, 1.0, 0.6, 0.9)
	if target_node.has_method("get_resource_id"):
		var resource_id: StringName = target_node.call("get_resource_id")
		var resource_def: Dictionary = ContentDatabase.get_resource_definition(resource_id)
		beam_color = resource_def.get("family_color", beam_color)
	mining_beam.default_color = beam_color

	mining_sparks.position = local_target
	mining_sparks.modulate = beam_color
	mining_sparks.emitting = true


func _update_shield_recharge(delta: float) -> void:
	if GameStateManager.get_current_hull() <= 0.0:
		return
	var recharge_multiplier: float = _get_shield_recharge_multiplier()
	GameStateManager.recharge_shield(delta, recharge_multiplier)


func _get_effective_thrust() -> float:
	var base_thrust: float = GameStateManager.get_effective_stat(&"thrust")
	if base_thrust <= 0.0:
		base_thrust = thrust_force

	var cargo_weight: float = GameStateManager.get_cargo_weight()
	var cargo_multiplier: float = maxf(0.2, 1.0 - (cargo_weight * 0.005))
	return base_thrust * cargo_multiplier


func _get_boost_multiplier() -> float:
	if not is_boost_active():
		return 1.0

	var stat_boost_multiplier: float = GameStateManager.get_effective_stat(&"boost_strength")
	if stat_boost_multiplier <= 0.0:
		stat_boost_multiplier = boost_multiplier
	return stat_boost_multiplier


func _get_current_max_speed() -> float:
	var base_max_speed: float = GameStateManager.get_effective_stat(&"max_speed")
	if base_max_speed <= 0.0:
		base_max_speed = max_speed

	if is_boost_active():
		base_max_speed *= (1.0 + boost_max_speed_bonus)
	return base_max_speed


func _get_current_linear_damp() -> float:
	var effective_damp: float = linear_damp
	for damp_value_variant in _active_control_zones.values():
		effective_damp = maxf(effective_damp, float(damp_value_variant))
	return effective_damp


func _update_camera(delta: float) -> void:
	var speed: float = velocity.length()
	var lead_offset: Vector2 = Vector2.ZERO
	if speed > 0.001:
		lead_offset = velocity.normalized() * minf(speed * camera_lead_scale, camera_max_lead)

	_trauma = maxf(_trauma - trauma_decay_rate * delta, 0.0)
	var shake_strength: float = _trauma * _trauma
	var shake_offset: Vector2 = Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * max_shake_offset * shake_strength

	ship_camera.offset = lead_offset + shake_offset

	var target_zoom_amount: float = 1.0
	if speed > (_get_current_max_speed() * 0.7):
		target_zoom_amount = high_speed_zoom

	var target_zoom: Vector2 = Vector2.ONE * target_zoom_amount
	ship_camera.zoom = ship_camera.zoom.lerp(target_zoom, clampf(zoom_lerp_speed * delta, 0.0, 1.0))


func _update_interaction_prompt() -> void:
	var area: Area2D = _get_best_interaction_area()
	if area == null:
		_last_interaction_prompt_key = ""
		return

	var prompt_data: Dictionary = _build_prompt_for_area(area)
	if prompt_data.is_empty():
		_last_interaction_prompt_key = ""
		return

	var prompt_key: String = String(prompt_data.get("key", ""))
	if prompt_key.is_empty() or prompt_key == _last_interaction_prompt_key:
		return

	_last_interaction_prompt_key = prompt_key
	UIManager.show_toast(String(prompt_data.get("text", "")), StringName(String(prompt_data.get("category", "info"))))


func _try_interact_with_current_target() -> void:
	var area: Area2D = _get_best_interaction_area()
	if area == null:
		return

	var interaction_type: String = String(area.get_meta("interaction_type", ""))
	match interaction_type:
		"station_dock":
			var station_owner: Node = area.get_meta("interaction_owner", null)
			if station_owner != null and station_owner.has_method("attempt_dock"):
				var dock_successful: bool = bool(station_owner.call("attempt_dock", self))
				if dock_successful:
					station_dock_requested.emit(station_owner)
		"warp_gate":
			var gate_owner: Node = area.get_meta("interaction_owner", null)
			if gate_owner != null and gate_owner.has_method("can_warp"):
				if bool(gate_owner.call("can_warp")):
					var destination_sector_id: StringName = StringName(String(gate_owner.get("destination_sector_id")))
					var source_gate_id: StringName = StringName(String(gate_owner.get("gate_id")))
					warp_gate_requested.emit(destination_sector_id, source_gate_id)
				else:
					var locked_prompt: String = "Warp Gate Locked"
					if gate_owner.has_method("get_interaction_prompt"):
						locked_prompt = String(gate_owner.call("get_interaction_prompt"))
					UIManager.show_toast(locked_prompt, &"warning")
		"anomaly_point":
			var anomaly_owner: Node = area.get_meta("interaction_owner", null)
			if anomaly_owner != null and anomaly_owner.has_method("interact"):
				anomaly_owner.call("interact", self)
		"wreck_beacon":
			var wreck_owner: Node = area.get_meta("interaction_owner", null)
			if wreck_owner != null and wreck_owner.has_method("interact"):
				wreck_owner.call("interact", self)
		"boundary_warning":
			UIManager.show_toast("Sector Boundary - No Gate Here", &"warning")


func _get_best_interaction_area() -> Area2D:
	var best_area: Area2D = null
	var best_priority: int = -99999
	var best_distance: float = INF

	for area in _interaction_areas:
		if area == null or not is_instance_valid(area):
			continue

		var priority: int = int(area.get_meta("interaction_priority", 0))
		var distance: float = global_position.distance_to(area.global_position)

		if priority > best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best_area = area

	return best_area


func _build_prompt_for_area(area: Area2D) -> Dictionary:
	var interaction_type: String = String(area.get_meta("interaction_type", ""))
	if interaction_type.is_empty():
		return {}

	match interaction_type:
		"station_dock":
			var station_owner: Node = area.get_meta("interaction_owner", null)
			if station_owner == null or not station_owner.has_method("get_interaction_prompt"):
				return {}
			var station_prompt: String = String(station_owner.call("get_interaction_prompt", get_current_speed()))
			if station_prompt.is_empty():
				return {}
			return {
				"key": "station_dock:%s" % station_prompt,
				"text": station_prompt,
				"category": "info",
			}
		"warp_gate":
			var gate_owner: Node = area.get_meta("interaction_owner", null)
			if gate_owner == null or not gate_owner.has_method("get_interaction_prompt"):
				return {}
			var gate_prompt: String = String(gate_owner.call("get_interaction_prompt"))
			if gate_prompt.is_empty():
				return {}
			var category: String = "warning" if gate_prompt.begins_with("Requires") else "info"
			return {
				"key": "warp_gate:%s" % gate_prompt,
				"text": gate_prompt,
				"category": category,
			}
		"anomaly_point":
			var anomaly_owner: Node = area.get_meta("interaction_owner", null)
			if anomaly_owner == null or not anomaly_owner.has_method("get_interaction_prompt"):
				return {}
			var anomaly_prompt: String = String(anomaly_owner.call("get_interaction_prompt"))
			if anomaly_prompt.is_empty():
				return {}
			var anomaly_category: String = "info" if anomaly_prompt.begins_with("Press") else "warning"
			return {
				"key": "anomaly:%s" % anomaly_prompt,
				"text": anomaly_prompt,
				"category": anomaly_category,
			}
		"wreck_beacon":
			var wreck_owner: Node = area.get_meta("interaction_owner", null)
			if wreck_owner == null or not wreck_owner.has_method("get_interaction_prompt"):
				return {}
			var wreck_prompt: String = String(wreck_owner.call("get_interaction_prompt"))
			if wreck_prompt.is_empty():
				return {}
			return {
				"key": "wreck:%s" % wreck_prompt,
				"text": wreck_prompt,
				"category": "info",
			}
		"boundary_warning":
			var boundary_prompt: String = String(area.get_meta("interaction_prompt", "Sector Boundary - No Gate Here"))
			return {
				"key": "boundary_warning:%s" % boundary_prompt,
				"text": boundary_prompt,
				"category": "warning",
			}
		_:
			return {}


func _update_active_hazards() -> void:
	var next_hazards: Dictionary = {}
	for zone_variant in get_tree().get_nodes_in_group("hazard_zone"):
		var zone: Node2D = zone_variant as Node2D
		if zone == null or not is_instance_valid(zone):
			continue
		if not zone.has_method("contains_point"):
			continue
		if bool(zone.call("contains_point", global_position)):
			next_hazards[zone.get_instance_id()] = zone
	_active_hazard_zones = next_hazards


func _get_shield_recharge_multiplier() -> float:
	var multiplier: float = 1.0
	for zone_variant in _active_hazard_zones.values():
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.has_method("get_shield_recharge_multiplier"):
			multiplier = minf(multiplier, float(zone.call("get_shield_recharge_multiplier")))
	return multiplier


func _get_steering_noise_strength() -> float:
	var noise_strength: float = 0.0
	for zone_variant in _active_hazard_zones.values():
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.has_method("get_steering_noise_strength"):
			noise_strength = maxf(noise_strength, float(zone.call("get_steering_noise_strength")))
	return noise_strength


func _is_utility_disabled() -> bool:
	for zone_variant in _active_hazard_zones.values():
		var zone: Node = zone_variant
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.has_method("disables_utility_modules") and bool(zone.call("disables_utility_modules")):
			return true
	return false


func _update_debris_contact_timers(delta: float) -> void:
	var expired_ids: Array[int] = []
	for collider_id_variant in _debris_contact_timers.keys():
		var collider_id: int = int(collider_id_variant)
		var remaining: float = float(_debris_contact_timers[collider_id]) - delta
		if remaining <= 0.0:
			expired_ids.append(collider_id)
		else:
			_debris_contact_timers[collider_id] = remaining

	for collider_id in expired_ids:
		_debris_contact_timers.erase(collider_id)


func _handle_slide_hazard_collisions() -> void:
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue
		var collider: Object = collision.get_collider()
		if collider == null:
			continue
		if not (collider is Node):
			continue
		var collider_node: Node = collider
		if not collider_node.is_in_group("debris_piece"):
			continue

		var collider_id: int = collider_node.get_instance_id()
		if _debris_contact_timers.has(collider_id):
			continue

		_debris_contact_timers[collider_id] = 0.45
		apply_external_damage(5.0, "Debris Impact")


func _on_control_zone_area_entered(area: Area2D) -> void:
	if not area.is_in_group("control_zone"):
		return

	var zone_damp: float = control_zone_linear_damp
	if area.has_meta("linear_damp"):
		zone_damp = float(area.get_meta("linear_damp"))
	_active_control_zones[area.get_instance_id()] = zone_damp


func _on_control_zone_area_exited(area: Area2D) -> void:
	if _active_control_zones.has(area.get_instance_id()):
		_active_control_zones.erase(area.get_instance_id())


func _on_interaction_area_entered(area: Area2D) -> void:
	if not area.has_meta("interaction_type"):
		return
	if _interaction_areas.has(area):
		return
	_interaction_areas.append(area)


func _on_interaction_area_exited(area: Area2D) -> void:
	_interaction_areas.erase(area)


func _on_player_damage_applied(shield_damage: float, hull_damage: float) -> void:
	if shield_damage > 0.0:
		_shield_hit_flash_remaining = 0.16
	if hull_damage > 0.0:
		_hull_hit_flash_remaining = 0.12
		add_trauma(clampf(hull_damage / 38.0, 0.1, 0.38))
	_check_for_death()


func _on_player_state_destroyed() -> void:
	_check_for_death()


func _check_for_death() -> void:
	if _death_emitted:
		return
	if GameStateManager.get_current_hull() > 0.0:
		return
	_death_emitted = true
	_stop_mining(false)
	_clear_target_lock()
	player_destroyed.emit(global_position)


func _is_world_position_on_screen(world_position: Vector2) -> bool:
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * world_position
	var viewport_size: Vector2 = get_viewport_rect().size
	return screen_position.x >= 0.0 and screen_position.y >= 0.0 and screen_position.x <= viewport_size.x and screen_position.y <= viewport_size.y
