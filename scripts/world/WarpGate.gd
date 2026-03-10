extends Area2D
class_name WarpGate

@export var gate_id: StringName = &""
@export var destination_sector_id: StringName = &""
@export var is_locked: bool = false
@export var unlock_requirement: StringName = &""

@onready var left_rail: Line2D = %LeftRail
@onready var right_rail: Line2D = %RightRail
@onready var center_glow: ColorRect = %CenterGlow
@onready var lock_label: Label = %LockLabel
@onready var destination_label: Label = %DestinationLabel

var _destination_sector_name: String = "Unknown"
var _pulse_timer: float = 0.0


func _ready() -> void:
	monitoring = true
	monitorable = true
	set_meta("interaction_owner", self)
	set_meta("interaction_type", "warp_gate")
	set_meta("interaction_priority", 80)
	set_process(true)
	_update_visual_state(0.0)
	queue_redraw()


func configure(gate_data: Dictionary) -> void:
	gate_id = StringName(String(gate_data.get("id", "")))
	destination_sector_id = StringName(String(gate_data.get("destination_sector_id", "")))
	unlock_requirement = StringName(String(gate_data.get("unlock_requirement", "")))

	var locked_from_data: bool = bool(gate_data.get("locked", false))
	if unlock_requirement != &"":
		is_locked = not GalaxyManager.is_galaxy_unlocked(unlock_requirement)
	else:
		is_locked = locked_from_data

	var destination_data: Dictionary = ContentDatabase.get_sector(destination_sector_id)
	_destination_sector_name = String(destination_data.get("name", "Unknown Sector"))
	destination_label.text = _destination_sector_name

	if is_inside_tree():
		_update_visual_state(0.0)
		queue_redraw()


func get_destination_sector_name() -> String:
	return _destination_sector_name


func get_interaction_prompt() -> String:
	if is_locked:
		if unlock_requirement != &"":
			return "Requires %s" % String(unlock_requirement)
		return "Warp Gate Locked"
	return "Press E to Warp to %s" % _destination_sector_name


func can_warp() -> bool:
	return not is_locked


func _process(delta: float) -> void:
	_pulse_timer += delta
	_update_visual_state(delta)


func _update_visual_state(_delta: float) -> void:
	if is_locked:
		left_rail.default_color = Color(0.45, 0.45, 0.52, 0.7)
		right_rail.default_color = Color(0.45, 0.45, 0.52, 0.7)
		center_glow.color = Color(0.2, 0.2, 0.24, 0.45)
		lock_label.visible = true
		lock_label.text = "LOCK"
		queue_redraw()
		return

	var pulse: float = 0.5 + (sin(_pulse_timer * 3.8) * 0.5)
	left_rail.default_color = Color(0.4, 0.78, 1.0, 0.8 + pulse * 0.2)
	right_rail.default_color = Color(0.4, 0.78, 1.0, 0.8 + pulse * 0.2)
	center_glow.color = Color(0.5, 0.85, 1.0, 0.35 + pulse * 0.35)
	lock_label.visible = false
	queue_redraw()


func _draw() -> void:
	if not is_locked:
		return

	# Simple vector padlock icon overlay for locked gate readability.
	var shackle_center: Vector2 = Vector2(0.0, -10.0)
	var shackle_radius: float = 11.0
	var body_rect: Rect2 = Rect2(Vector2(-12.0, -2.0), Vector2(24.0, 22.0))
	draw_arc(shackle_center, shackle_radius, PI, TAU, 24, Color(1.0, 0.88, 0.4, 0.95), 2.5)
	draw_rect(body_rect, Color(0.16, 0.16, 0.2, 0.95), true)
	draw_rect(body_rect, Color(1.0, 0.88, 0.4, 0.95), false, 2.0, true)
