extends Control

@export var line_count: int = 48
@export var inner_radius: float = 40.0
@export var outer_radius: float = 900.0
@export var line_width: float = 2.0

var _active: bool = false
var _time: float = 0.0


func _ready() -> void:
	set_process(true)
	visible = false


func start_effect() -> void:
	_active = true
	visible = true


func stop_effect() -> void:
	_active = false
	visible = false
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not _active:
		return

	var center: Vector2 = size * 0.5
	for i in line_count:
		var angle: float = (TAU * float(i) / float(line_count)) + (_time * 0.8)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var pulse: float = 0.6 + 0.4 * sin(_time * 9.0 + float(i) * 0.4)
		var start: Vector2 = center + direction * (inner_radius + pulse * 25.0)
		var finish: Vector2 = center + direction * (outer_radius * (0.45 + pulse * 0.55))
		draw_line(start, finish, Color(1.0, 1.0, 1.0, 0.18 + pulse * 0.55), line_width)
