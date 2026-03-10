extends Control

@export var star_count: int = 260
@export var drift_speed_min: float = 4.0
@export var drift_speed_max: float = 16.0

var _stars: Array[Dictionary] = []


func _ready() -> void:
	set_process(true)
	_regenerate_stars()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_regenerate_stars()


func _process(delta: float) -> void:
	for star_data in _stars:
		star_data["position"].y += star_data["speed"] * delta
		if star_data["position"].y > size.y + 4.0:
			star_data["position"].y = -4.0
			star_data["position"].x = randf_range(0.0, size.x)
	queue_redraw()


func _draw() -> void:
	for star_data in _stars:
		var position: Vector2 = star_data["position"]
		var radius: float = star_data["radius"]
		var alpha: float = star_data["alpha"]
		draw_circle(position, radius, Color(1.0, 1.0, 1.0, alpha))


func _regenerate_stars() -> void:
	_stars.clear()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i in star_count:
		_stars.append({
			"position": Vector2(
				rng.randf_range(0.0, max(size.x, 1.0)),
				rng.randf_range(0.0, max(size.y, 1.0))
			),
			"radius": rng.randf_range(0.8, 1.8),
			"alpha": rng.randf_range(0.2, 0.9),
			"speed": rng.randf_range(drift_speed_min, drift_speed_max),
		})

	queue_redraw()
