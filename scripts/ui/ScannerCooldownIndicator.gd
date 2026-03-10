extends Control

var _cooldown_ratio: float = 1.0


func _ready() -> void:
	queue_redraw()


func set_cooldown_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _cooldown_ratio):
		return
	_cooldown_ratio = clamped
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = max(minf(size.x, size.y) * 0.5 - 2.0, 2.0)

	draw_circle(center, radius, Color(0.04, 0.06, 0.1, 0.9))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.32, 0.56, 0.8, 0.7), 2.0)

	if _cooldown_ratio < 1.0:
		var remaining_ratio: float = 1.0 - _cooldown_ratio
		var segments: int = 36
		var wedge: PackedVector2Array = PackedVector2Array([center])
		for i in segments + 1:
			var t: float = float(i) / float(segments)
			var angle: float = -PI * 0.5 + TAU * remaining_ratio * t
			wedge.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(wedge, Color(0.36, 0.84, 1.0, 0.45))

	var ready_color: Color = Color(0.45, 0.95, 0.45, 0.95)
	if _cooldown_ratio < 1.0:
		ready_color = Color(0.96, 0.84, 0.28, 0.95)
	draw_circle(center, 2.8, ready_color)
