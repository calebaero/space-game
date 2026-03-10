extends Area2D
class_name LootCrate

@export var despawn_time: float = 60.0
@export var hidden_until_scanned: bool = false
@export var drift_speed_min: float = 1.0
@export var drift_speed_max: float = 2.0

var contents: Array[Dictionary] = []

var _lifetime_remaining: float = 60.0
var _reveal_time_remaining: float = 0.0
var _drift_velocity: Vector2 = Vector2.ZERO
var _spin_speed: float = 0.0
var _base_color: Color = Color(0.96, 0.88, 0.24, 1.0)


func _ready() -> void:
	add_to_group("loot_crate")
	if hidden_until_scanned and not is_in_group("hidden_loot"):
		add_to_group("hidden_loot")

	body_entered.connect(_on_body_entered)
	_lifetime_remaining = despawn_time
	_seed_motion()
	_refresh_visibility_state()
	set_process(true)
	queue_redraw()


func configure(data: Dictionary) -> void:
	hidden_until_scanned = bool(data.get("hidden_until_scanned", hidden_until_scanned))
	if data.has("contents"):
		_set_contents(data.get("contents", []))

	if data.has("color"):
		_base_color = data.get("color", _base_color)
	else:
		_update_color_from_contents()

	if is_inside_tree():
		if hidden_until_scanned and not is_in_group("hidden_loot"):
			add_to_group("hidden_loot")
		_refresh_visibility_state()
		queue_redraw()


func set_contents(new_contents: Array) -> void:
	_set_contents(new_contents)
	_update_color_from_contents()
	queue_redraw()


func reveal_temporarily(duration: float = 10.0) -> void:
	if not hidden_until_scanned:
		return

	_reveal_time_remaining = maxf(_reveal_time_remaining, duration)
	_refresh_visibility_state()


func get_contents() -> Array[Dictionary]:
	return contents.duplicate(true)


func _process(delta: float) -> void:
	if hidden_until_scanned and _reveal_time_remaining > 0.0:
		_reveal_time_remaining = maxf(_reveal_time_remaining - delta, 0.0)
		if _reveal_time_remaining <= 0.0:
			_refresh_visibility_state()

	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()
		return

	if visible:
		position += _drift_velocity * delta
		rotation += _spin_speed * delta


func _on_body_entered(body: Node) -> void:
	if not visible:
		return
	if body == null:
		return
	if not body.is_in_group("player_ship"):
		return

	var collected_anything: bool = _apply_contents()
	if collected_anything:
		AudioManager.play_sfx(&"loot_pickup", global_position)
	queue_free()


func _apply_contents() -> bool:
	var collected_anything: bool = false

	for content_variant in contents:
		if content_variant is not Dictionary:
			continue
		var entry: Dictionary = content_variant
		var item_type: String = String(entry.get("item_type", ""))
		var item_id: String = String(entry.get("item_id", ""))
		var quantity: int = max(int(entry.get("quantity", 0)), 0)
		if quantity <= 0:
			continue

		match item_type:
			"resource":
				var added: int = GameStateManager.add_cargo(StringName(item_id), quantity)
				if added > 0:
					collected_anything = true
					var item_def: Dictionary = ContentDatabase.get_item_definition(StringName(item_id))
					var resource_name: String = String(item_def.get("name", item_id))
					UIManager.show_toast("+%d %s" % [added, resource_name], &"success")
			"credits":
				GameStateManager.credits += quantity
				UIManager.show_toast("+%d Credits" % quantity, &"success")
				collected_anything = true
			"commodity", "material":
				var added_trade: int = GameStateManager.add_cargo(StringName(item_id), quantity)
				if added_trade > 0:
					var item_data: Dictionary = ContentDatabase.get_item_definition(StringName(item_id))
					var item_name: String = String(item_data.get("name", item_id))
					UIManager.show_toast("+%d %s" % [added_trade, item_name], &"success")
					collected_anything = true
			"mission_item":
				var mission_item_def: Dictionary = ContentDatabase.get_item_definition(StringName(item_id))
				if bool(mission_item_def.get("store_in_relic_inventory", false)):
					GameStateManager.add_relic(StringName(item_id), quantity)
					UIManager.show_toast("Recovered %s x%d" % [String(mission_item_def.get("name", item_id)), quantity], &"success")
					collected_anything = true
				else:
					var added_mission: int = GameStateManager.add_cargo(StringName(item_id), quantity)
					if added_mission > 0:
						UIManager.show_toast("+%d %s" % [added_mission, String(mission_item_def.get("name", item_id))], &"success")
						collected_anything = true
			_:
				continue

	return collected_anything


func _seed_motion() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%s|%s" % [str(global_position), str(Time.get_ticks_msec())])
	var direction: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
	var speed: float = rng.randf_range(drift_speed_min, drift_speed_max)
	_drift_velocity = direction * speed
	_spin_speed = rng.randf_range(-0.8, 0.8)


func _refresh_visibility_state() -> void:
	if hidden_until_scanned and _reveal_time_remaining <= 0.0:
		visible = false
		monitoring = false
	else:
		visible = true
		monitoring = true


func _set_contents(new_contents: Array) -> void:
	contents.clear()
	for item_variant in new_contents:
		if item_variant is not Dictionary:
			continue
		contents.append((item_variant as Dictionary).duplicate(true))


func _update_color_from_contents() -> void:
	if contents.is_empty():
		return
	var first_entry: Dictionary = contents[0]
	var resource_id: StringName = StringName(String(first_entry.get("item_id", "")))
	var resource_def: Dictionary = ContentDatabase.get_item_definition(resource_id)
	if resource_def.is_empty():
		resource_def = ContentDatabase.get_resource_definition(resource_id)
	if resource_def.is_empty():
		return
	_base_color = resource_def.get("icon_color", resource_def.get("family_color", _base_color))


func _draw() -> void:
	if not visible:
		return

	var size: float = 16.0
	var rect: Rect2 = Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size))
	draw_rect(rect, _base_color, true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.85), false, 2.0, true)
	draw_line(Vector2(-size * 0.5, 0.0), Vector2(size * 0.5, 0.0), Color(1.0, 1.0, 1.0, 0.35), 1.0)
	draw_line(Vector2(0.0, -size * 0.5), Vector2(0.0, size * 0.5), Color(1.0, 1.0, 1.0, 0.35), 1.0)
