extends StaticBody2D
class_name Planet

@export var radius: float = 220.0
@export var fill_color: Color = Color(0.18, 0.36, 0.58, 1.0)
@export var rim_color: Color = Color(0.6, 0.8, 0.95, 1.0)
@export var orbit_zone_padding: float = 150.0
@export var control_zone_padding: float = 230.0
@export var control_zone_damp: float = 0.5

@onready var collision_shape: CollisionShape2D = %BodyCollisionShape
@onready var orbit_zone: Area2D = %OrbitZone
@onready var orbit_zone_shape: CollisionShape2D = %OrbitZoneShape
@onready var control_zone: Area2D = %ControlZone
@onready var control_zone_shape: CollisionShape2D = %ControlZoneShape
@onready var planet_type_label: Label = %PlanetTypeLabel


func _ready() -> void:
	_apply_configuration()
	queue_redraw()


func configure(planet_data: Dictionary) -> void:
	radius = float(planet_data.get("radius", radius))
	fill_color = planet_data.get("color", fill_color)
	var planet_type: String = String(planet_data.get("type", "planet"))
	planet_type_label.text = planet_type.capitalize()

	if is_inside_tree():
		_apply_configuration()
		queue_redraw()


func _apply_configuration() -> void:
	var body_circle: CircleShape2D = collision_shape.shape as CircleShape2D
	if body_circle == null:
		body_circle = CircleShape2D.new()
		collision_shape.shape = body_circle
	body_circle.radius = radius

	var orbit_circle: CircleShape2D = orbit_zone_shape.shape as CircleShape2D
	if orbit_circle == null:
		orbit_circle = CircleShape2D.new()
		orbit_zone_shape.shape = orbit_circle
	orbit_circle.radius = radius + orbit_zone_padding

	var control_circle: CircleShape2D = control_zone_shape.shape as CircleShape2D
	if control_circle == null:
		control_circle = CircleShape2D.new()
		control_zone_shape.shape = control_circle
	control_circle.radius = radius + control_zone_padding

	control_zone.monitoring = false
	control_zone.monitorable = true
	control_zone.set_meta("linear_damp", control_zone_damp)
	if not control_zone.is_in_group("control_zone"):
		control_zone.add_to_group("control_zone")


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, rim_color, 6.0)
	draw_arc(Vector2(-radius * 0.2, -radius * 0.14), radius * 0.4, 0.1, PI * 1.1, 40, Color(0.9, 0.95, 1.0, 0.45), 4.0)
