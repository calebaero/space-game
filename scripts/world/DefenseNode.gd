extends StaticBody2D
class_name DefenseNode

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/world/Projectile.tscn")

signal destroyed(node: DefenseNode)

@onready var damageable: Damageable = %Damageable
@onready var hull_polygon: Polygon2D = %HullPolygon

var display_name: String = "Defense Node"
var faction: StringName = &"alien"
var damage: float = 10.0
var projectile_speed: float = 780.0
var projectile_range: float = 900.0
var fire_rate: float = 0.9

var _player_ship: Node2D = null
var _fire_cooldown_remaining: float = 0.0


func _ready() -> void:
	add_to_group("enemy_ship")
	add_to_group("defense_node")
	damageable.configure_from_values(100.0, 0.0, 3.0, 0.0)
	if not damageable.destroyed.is_connected(_on_destroyed):
		damageable.destroyed.connect(_on_destroyed)
	set_physics_process(true)


func configure(data: Dictionary) -> void:
	display_name = String(data.get("display_name", display_name))
	faction = StringName(String(data.get("faction", faction)))
	damage = float(data.get("damage", damage))
	projectile_range = float(data.get("range", projectile_range))
	var hull_value: float = float(data.get("hull", 100.0))
	damageable.configure_from_values(hull_value, 0.0, 3.0, 0.0)


func set_player_ship(player_ship: Node2D) -> void:
	_player_ship = player_ship


func apply_projectile_damage(amount: float, _projectile: Node = null) -> void:
	damageable.take_damage(amount)


func apply_emp_disable(_duration: float) -> void:
	# Defense nodes do not use shields currently.
	pass


func get_display_name() -> String:
	return display_name


func get_faction_name() -> String:
	return String(faction).capitalize()


func get_current_hull() -> float:
	return damageable.current_hull


func get_max_hull() -> float:
	return damageable.max_hull


func get_current_shield() -> float:
	return 0.0


func get_max_shield() -> float:
	return 0.0


func _physics_process(delta: float) -> void:
	if _player_ship == null or not is_instance_valid(_player_ship):
		_player_ship = get_tree().get_first_node_in_group("player_ship") as Node2D
		if _player_ship == null:
			return

	if _fire_cooldown_remaining > 0.0:
		_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)

	var to_player: Vector2 = _player_ship.global_position - global_position
	if to_player.length() > projectile_range:
		return
	rotation = to_player.angle()
	if _fire_cooldown_remaining > 0.0:
		return
	_fire_cooldown_remaining = fire_rate
	_fire_at_player(to_player.normalized())


func _fire_at_player(direction: Vector2) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	if projectile == null:
		return
	projectile.global_position = global_position + direction * 24.0
	get_parent().add_child(projectile)
	projectile.configure({
		"damage": damage,
		"speed": projectile_speed,
		"range": projectile_range,
		"owner": "enemy",
		"source": self,
		"direction": direction,
		"color": Color(1.0, 0.64, 0.34, 1.0),
		"scale": 1.1,
	})
	if _player_ship != null and is_instance_valid(_player_ship) and _player_ship.has_method("register_incoming_fire"):
		_player_ship.call("register_incoming_fire", global_position)


func _on_destroyed() -> void:
	MissionManager.report_enemy_destroyed(&"ancient_defense_node", faction, GameStateManager.current_sector_id, false, &"", &"")
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.global_position = global_position
	particles.amount = 22
	particles.one_shot = true
	particles.lifetime = 0.4
	particles.explosiveness = 0.94
	particles.spread = 180.0
	particles.direction = Vector2.ZERO
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 65.0
	particles.initial_velocity_max = 150.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	particles.color = Color(1.0, 0.58, 0.34, 0.95)
	get_parent().add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	destroyed.emit(self)
	queue_free()
