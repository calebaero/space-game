extends StaticBody2D
class_name SpaceStation

const DOCK_SPEED_THRESHOLD: float = 50.0
const DOCK_SPEED_QOL_LIMIT: float = DOCK_SPEED_THRESHOLD * 1.2

@export var radius: float = 60.0
@export var fill_color: Color = Color(0.75, 0.75, 0.82, 1.0)
@export var outline_color: Color = Color(0.95, 0.98, 1.0, 1.0)
@export var docking_zone_radius: float = 200.0
@export var control_zone_radius: float = 320.0
@export var control_zone_damp: float = 0.5

@onready var collision_polygon: CollisionPolygon2D = %BodyCollisionPolygon
@onready var docking_zone: Area2D = %DockingZone
@onready var docking_shape: CollisionShape2D = %DockingZoneShape
@onready var control_zone: Area2D = %ControlZone
@onready var control_shape: CollisionShape2D = %ControlZoneShape
@onready var station_name_label: Label = %StationNameLabel
@onready var station_type_label: Label = %StationTypeLabel

var station_data: Dictionary = {}
var is_dockable: bool = true


func _ready() -> void:
	_apply_shapes()
	_register_zone_metadata()
	queue_redraw()


func configure(data: Dictionary) -> void:
	station_data = data.duplicate(true)
	is_dockable = bool(station_data.get("dockable", true))

	station_name_label.text = String(station_data.get("name", "Station"))
	station_type_label.text = String(station_data.get("type", "Unknown")).capitalize()
	if not is_dockable:
		station_type_label.text = "%s (No Dock)" % station_type_label.text

	if is_inside_tree():
		_apply_shapes()
		_register_zone_metadata()
		queue_redraw()


func get_station_data() -> Dictionary:
	return station_data.duplicate(true)


func get_station_id() -> StringName:
	return StringName(String(station_data.get("id", "")))


func get_interaction_prompt(player_speed: float) -> String:
	if not is_dockable:
		return "Outpost Stub - No Docking Services"

	if player_speed < DOCK_SPEED_THRESHOLD:
		return "Press E to Dock"
	return "Reduce Speed to Dock"


func attempt_dock(player_ship: CharacterBody2D) -> bool:
	if not is_dockable:
		UIManager.show_toast("This outpost has no docking services.", &"warning")
		return false

	if player_ship == null:
		return false

	var speed: float = player_ship.velocity.length()
	if speed <= DOCK_SPEED_THRESHOLD:
		return true

	if speed <= DOCK_SPEED_QOL_LIMIT:
		player_ship.velocity = player_ship.velocity.move_toward(Vector2.ZERO, speed)
		return true

	UIManager.show_toast("Reduce speed to dock.", &"warning")
	return false


func get_undock_spawn_position() -> Vector2:
	# Spawn slightly below station center for clear separation on undock.
	return global_position + Vector2(0.0, docking_zone_radius * 0.75)


func _apply_shapes() -> void:
	var hex_points: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		hex_points.append(Vector2(cos(angle), sin(angle)) * radius)
	collision_polygon.polygon = hex_points

	var dock_circle: CircleShape2D = docking_shape.shape as CircleShape2D
	if dock_circle == null:
		dock_circle = CircleShape2D.new()
		docking_shape.shape = dock_circle
	dock_circle.radius = docking_zone_radius

	var control_circle: CircleShape2D = control_shape.shape as CircleShape2D
	if control_circle == null:
		control_circle = CircleShape2D.new()
		control_shape.shape = control_circle
	control_circle.radius = control_zone_radius

	docking_shape.disabled = not is_dockable


func _register_zone_metadata() -> void:
	docking_zone.monitoring = false
	docking_zone.monitorable = true
	docking_zone.set_meta("interaction_owner", self)
	docking_zone.set_meta("interaction_type", "station_dock")
	docking_zone.set_meta("interaction_priority", 90)

	control_zone.monitoring = false
	control_zone.monitorable = true
	control_zone.set_meta("linear_damp", control_zone_damp)
	if not control_zone.is_in_group("control_zone"):
		control_zone.add_to_group("control_zone")


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 - PI * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	var closed_points: PackedVector2Array = points.duplicate()
	closed_points.append(points[0])

	draw_colored_polygon(points, fill_color)
	draw_polyline(closed_points, outline_color, 6.0, true)
	draw_arc(Vector2.ZERO, radius * 1.24, 0.0, TAU, 96, Color(0.45, 0.65, 1.0, 0.55), 3.0)
