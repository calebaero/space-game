extends StaticBody2D
class_name ResourceNode

const LOOT_CRATE_SCENE: PackedScene = preload("res://scenes/world/LootCrate.tscn")

@export var node_id: StringName = &""
@export var resource_id: StringName = &"common_ore"
@export var tier: int = 1
@export var yield_amount: int = 0
@export var extraction_time: float = 0.0
@export var is_unstable: bool = false
@export var mining_range: float = 200.0

@onready var body_collision_shape: CollisionShape2D = %BodyCollisionShape
@onready var mining_range_area: Area2D = %MiningRangeArea
@onready var mining_range_shape: CollisionShape2D = %MiningRangeShape
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var reveal_label: Label = %RevealLabel

var _resource_def: Dictionary = {}
var _scan_highlight_time: float = 0.0
var _unstable_pulse_time: float = 0.0
var _depleted: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("resource_node")
	add_to_group("scannable_resource_node")

	progress_bar.visible = false
	progress_bar.value = 0.0
	_rng.seed = hash("%s|%s" % [String(node_id), String(resource_id)])

	_apply_node_data()
	set_process(true)
	queue_redraw()


func configure(data: Dictionary) -> void:
	node_id = StringName(String(data.get("id", node_id)))
	resource_id = StringName(String(data.get("resource_id", resource_id)))
	tier = int(data.get("tier", tier))
	yield_amount = int(data.get("yield_amount", yield_amount))
	extraction_time = float(data.get("extraction_time", extraction_time))
	mining_range = float(data.get("mining_range", mining_range))

	var tier_data: Dictionary = ContentDatabase.get_node_tier_definition(tier)
	var unstable_default: bool = bool(tier_data.get("unstable", false))
	is_unstable = bool(data.get("is_unstable", unstable_default))

	_rng.seed = hash("%s|%s|%s" % [String(node_id), String(resource_id), str(data.get("position", Vector2.ZERO))])

	if is_inside_tree():
		_apply_node_data()
		queue_redraw()


func get_mining_range() -> float:
	return mining_range


func get_resource_id() -> StringName:
	return resource_id


func get_resource_name() -> String:
	if _resource_def.is_empty():
		_resource_def = ContentDatabase.get_resource_definition(resource_id)
	return String(_resource_def.get("name", String(resource_id)))


func get_tier() -> int:
	return tier


func get_yield_amount() -> int:
	return yield_amount


func can_be_mined() -> bool:
	return not _depleted


func get_effective_extraction_time(mining_efficiency: float) -> float:
	var efficiency: float = maxf(mining_efficiency, 0.1)
	return maxf(0.25, extraction_time / efficiency)


func set_mining_progress(progress_ratio: float) -> void:
	if _depleted:
		return

	progress_bar.visible = true
	progress_bar.value = clampf(progress_ratio * 100.0, 0.0, 100.0)


func clear_mining_progress() -> void:
	progress_bar.visible = false
	progress_bar.value = 0.0


func on_scanned(duration: float = 5.0) -> void:
	if _depleted:
		return

	_scan_highlight_time = maxf(_scan_highlight_time, duration)
	reveal_label.visible = true
	queue_redraw()


func complete_extraction(miner: Node2D) -> bool:
	if _depleted:
		return false

	_depleted = true
	clear_mining_progress()
	_spawn_loot_crate()

	if is_unstable and randf() < 0.35:
		_emit_unstable_burst(miner)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 0.12, 0.16)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.16)
	tween.finished.connect(queue_free)
	return true


func _process(delta: float) -> void:
	if _scan_highlight_time > 0.0:
		_scan_highlight_time = maxf(_scan_highlight_time - delta, 0.0)
		reveal_label.visible = _scan_highlight_time > 0.0

	if is_unstable and not _depleted:
		_unstable_pulse_time += delta

	if _scan_highlight_time > 0.0 or is_unstable:
		queue_redraw()


func _apply_node_data() -> void:
	_resource_def = ContentDatabase.get_resource_definition(resource_id)
	var tier_data: Dictionary = ContentDatabase.get_node_tier_definition(tier)

	if extraction_time <= 0.0:
		extraction_time = float(tier_data.get("extraction_time", 2.0))

	if yield_amount <= 0:
		var min_yield: int = int(tier_data.get("yield_min", 2))
		var max_yield: int = int(tier_data.get("yield_max", 4))
		yield_amount = _rng.randi_range(min_yield, max_yield)

	if mining_range <= 0.0:
		mining_range = 200.0

	var visual_radius: float = _get_visual_radius()
	var body_circle: CircleShape2D = body_collision_shape.shape as CircleShape2D
	if body_circle == null:
		body_circle = CircleShape2D.new()
		body_collision_shape.shape = body_circle
	body_circle.radius = visual_radius * 0.7

	var mining_circle: CircleShape2D = mining_range_shape.shape as CircleShape2D
	if mining_circle == null:
		mining_circle = CircleShape2D.new()
		mining_range_shape.shape = mining_circle
	mining_circle.radius = mining_range

	mining_range_area.monitoring = false
	mining_range_area.monitorable = true

	var resource_name: String = get_resource_name()
	reveal_label.text = "%s T%d" % [_abbreviate_resource_name(resource_name), tier]
	reveal_label.visible = false


func _spawn_loot_crate() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var loot_crate: Area2D = LOOT_CRATE_SCENE.instantiate() as Area2D
	if loot_crate == null:
		return

	loot_crate.global_position = global_position
	parent_node.add_child(loot_crate)
	if loot_crate.has_method("configure"):
		loot_crate.call("configure", {
			"contents": [{
				"item_type": "resource",
				"item_id": String(resource_id),
				"quantity": yield_amount,
			}],
		})


func _emit_unstable_burst(miner: Node2D) -> void:
	UIManager.show_toast("Unstable node burst!", &"warning")
	if miner != null and is_instance_valid(miner) and miner.has_method("apply_external_damage"):
		miner.call("apply_external_damage", 8.0, "Unstable Burst")


func _get_visual_radius() -> float:
	match tier:
		1:
			return 18.0
		2:
			return 24.0
		_:
			return 30.0


func _abbreviate_resource_name(full_name: String) -> String:
	var parts: PackedStringArray = full_name.split(" ", false)
	if parts.size() <= 1:
		return full_name
	var short_name: String = ""
	for part in parts:
		if part.is_empty():
			continue
		short_name += part.substr(0, 1)
	return short_name


func _draw() -> void:
	if _depleted:
		return

	var base_color: Color = _resource_def.get("family_color", Color(0.7, 0.7, 0.75, 1.0))
	var shape_name: String = String(_resource_def.get("shape", "pentagon"))
	var radius: float = _get_visual_radius()

	_draw_resource_shape(shape_name, radius, base_color)

	if _scan_highlight_time > 0.0:
		var glow_alpha: float = 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.01)
		draw_circle(Vector2.ZERO, radius + 8.0, Color(base_color.r, base_color.g, base_color.b, clampf(glow_alpha, 0.2, 0.7)))

	if is_unstable:
		var pulse: float = 0.5 + 0.5 * sin(_unstable_pulse_time * 6.0)
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 40, Color(1.0, 0.2, 0.2, 0.4 + pulse * 0.5), 3.0)


func _draw_resource_shape(shape_name: String, radius: float, color: Color) -> void:
	match shape_name:
		"diamond":
			_draw_polygon_shape(_build_regular_polygon_points(4, radius), color)
		"cloud":
			draw_circle(Vector2(-radius * 0.35, 0.0), radius * 0.5, color)
			draw_circle(Vector2(radius * 0.08, -radius * 0.16), radius * 0.62, color)
			draw_circle(Vector2(radius * 0.5, 0.08 * radius), radius * 0.45, color)
		"hexagon":
			_draw_polygon_shape(_build_regular_polygon_points(6, radius), color)
		"triangle":
			_draw_polygon_shape(_build_regular_polygon_points(3, radius), color)
		"star":
			_draw_polygon_shape(_build_star_points(radius, radius * 0.45), color)
		_:
			_draw_polygon_shape(_build_regular_polygon_points(5, radius), color)


func _draw_polygon_shape(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	if points.is_empty():
		return
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	draw_polyline(outline_points, Color(1.0, 1.0, 1.0, 0.7), 2.0, true)


func _build_regular_polygon_points(point_count: int, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count) - PI * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _build_star_points(outer_radius: float, inner_radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 10:
		var angle: float = TAU * float(i) / 10.0 - PI * 0.5
		var radius: float = outer_radius if i % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
