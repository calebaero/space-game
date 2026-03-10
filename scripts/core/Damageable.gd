extends Node
class_name Damageable

signal damaged(shield_damage: float, hull_damage: float)
signal shield_depleted
signal destroyed

@export var max_hull: float = 100.0
@export var max_shield: float = 0.0
@export var shield_recharge_delay: float = 3.0
@export var shield_recharge_rate: float = 5.0

var current_hull: float = 0.0
var current_shield: float = 0.0

var _recharge_delay_remaining: float = 0.0
var _is_destroyed: bool = false
var _shield_disable_remaining: float = 0.0


func _ready() -> void:
	reset_to_full()


func configure_from_values(new_max_hull: float, new_max_shield: float, recharge_delay: float, recharge_rate: float) -> void:
	max_hull = maxf(new_max_hull, 1.0)
	max_shield = maxf(new_max_shield, 0.0)
	shield_recharge_delay = maxf(recharge_delay, 0.0)
	shield_recharge_rate = maxf(recharge_rate, 0.0)
	reset_to_full()


func reset_to_full() -> void:
	current_hull = maxf(max_hull, 1.0)
	current_shield = maxf(max_shield, 0.0)
	_recharge_delay_remaining = 0.0
	_shield_disable_remaining = 0.0
	_is_destroyed = false


func take_damage(amount: float) -> Dictionary:
	if amount <= 0.0 or _is_destroyed:
		return {"shield_damage": 0.0, "hull_damage": 0.0, "destroyed": _is_destroyed, "shield_depleted": false}

	var remaining: float = amount
	var shield_damage: float = 0.0
	var hull_damage: float = 0.0
	var depleted_this_hit: bool = false
	var shield_before: float = current_shield

	if current_shield > 0.0:
		shield_damage = minf(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		if shield_before > 0.0 and current_shield <= 0.0:
			depleted_this_hit = true
			shield_depleted.emit()

	if remaining > 0.0:
		hull_damage = minf(current_hull, remaining)
		current_hull -= hull_damage
		remaining -= hull_damage

	_recharge_delay_remaining = shield_recharge_delay
	damaged.emit(shield_damage, hull_damage)

	if current_hull <= 0.0 and not _is_destroyed:
		_is_destroyed = true
		destroyed.emit()

	return {
		"shield_damage": shield_damage,
		"hull_damage": hull_damage,
		"destroyed": _is_destroyed,
		"shield_depleted": depleted_this_hit,
	}


func process_recharge(delta: float, multiplier: float = 1.0) -> void:
	if _is_destroyed:
		return
	if max_shield <= 0.0 or current_shield >= max_shield:
		return
	if multiplier <= 0.0:
		return
	if _shield_disable_remaining > 0.0:
		_shield_disable_remaining = maxf(_shield_disable_remaining - delta, 0.0)
		return

	if _recharge_delay_remaining > 0.0:
		_recharge_delay_remaining = maxf(_recharge_delay_remaining - delta, 0.0)
		return

	current_shield = minf(max_shield, current_shield + shield_recharge_rate * multiplier * delta)


func disable_shield(duration: float) -> void:
	if duration <= 0.0:
		return
	current_shield = 0.0
	_shield_disable_remaining = maxf(_shield_disable_remaining, duration)
	_recharge_delay_remaining = maxf(_recharge_delay_remaining, duration)
	shield_depleted.emit()


func get_shield_disable_remaining() -> float:
	return _shield_disable_remaining


func is_destroyed() -> bool:
	return _is_destroyed


func get_hull_ratio() -> float:
	return current_hull / maxf(max_hull, 1.0)


func get_shield_ratio() -> float:
	if max_shield <= 0.0:
		return 0.0
	return current_shield / max_shield
