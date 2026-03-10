extends Node2D

@export var area_size: Vector2 = Vector2(9000.0, 9000.0)
@export var star_count: int = 180
@export var min_radius: float = 0.8
@export var max_radius: float = 2.0
@export var brightness: float = 0.9
@export var seed_value: int = 1

var _stars: Array[Dictionary] = []


func _ready() -> void:
	_generate_stars()
	queue_redraw()


func _draw() -> void:
	for star_data in _stars:
		var star_position: Vector2 = star_data["position"]
		var star_radius: float = star_data["radius"]
		var alpha: float = star_data["alpha"]
		draw_circle(star_position, star_radius, Color(brightness, brightness, brightness, alpha))


func _generate_stars() -> void:
	_stars.clear()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	var half_size: Vector2 = area_size * 0.5
	for i in star_count:
		_stars.append({
			"position": Vector2(
				rng.randf_range(-half_size.x, half_size.x),
				rng.randf_range(-half_size.y, half_size.y)
			),
			"radius": rng.randf_range(min_radius, max_radius),
			"alpha": rng.randf_range(0.2, 0.9),
		})
