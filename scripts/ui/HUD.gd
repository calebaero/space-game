extends CanvasLayer

@onready var hull_bar: ProgressBar = %HullBar
@onready var shield_bar: ProgressBar = %ShieldBar
@onready var boost_bar: ProgressBar = %BoostBar
@onready var speed_label: Label = %SpeedLabel
@onready var cargo_label: Label = %CargoLabel
@onready var credits_label: Label = %CreditsLabel
@onready var mission_label: Label = %MissionLabel
@onready var target_info_panel: Panel = %TargetInfoPanel
@onready var toast_label: Label = %ToastLabel
@onready var velocity_indicator: Node2D = %VelocityVectorIndicator
@onready var velocity_line: Line2D = %VelocityVectorLine
@onready var lead_indicator_label: Label = %LeadIndicatorLabel
@onready var incoming_warning_label: Label = %IncomingWarningLabel
@onready var target_name_label: Label = %TargetNameLabel
@onready var target_faction_label: Label = %TargetFactionLabel
@onready var target_distance_label: Label = %TargetDistanceLabel
@onready var target_hull_bar: ProgressBar = %TargetHullBar
@onready var target_shield_bar: ProgressBar = %TargetShieldBar
@onready var damage_flash: ColorRect = %DamageFlash
@onready var minimap_panel: Control = %MiniMapPanel
@onready var scanner_cooldown_indicator: Control = %ScannerCooldownIndicator
@onready var in_flight_cargo_panel: CargoPanel = %InFlightCargoPanel

var _player_ship: CharacterBody2D = null
var _hull_flash_timer: float = 0.0
var _screen_flash_decay_rate: float = 6.5

const TOAST_COLORS: Dictionary = {
	"warning": Color(1.0, 0.66, 0.22, 1.0),
	"info": Color(1.0, 1.0, 1.0, 1.0),
	"success": Color(0.45, 0.95, 0.45, 1.0),
	"danger": Color(1.0, 0.34, 0.34, 1.0),
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	target_info_panel.visible = false
	mission_label.text = "No active mission"
	toast_label.text = ""
	toast_label.visible = false
	velocity_indicator.visible = false
	lead_indicator_label.visible = false
	incoming_warning_label.visible = false
	damage_flash.color.a = 0.0
	if in_flight_cargo_panel != null:
		in_flight_cargo_panel.set_title("Cargo Hold")

	if not UIManager.toast_state_changed.is_connected(_on_toast_state_changed):
		UIManager.toast_state_changed.connect(_on_toast_state_changed)
	if UIManager.has_signal("screen_flash_requested") and not UIManager.screen_flash_requested.is_connected(_on_screen_flash_requested):
		UIManager.screen_flash_requested.connect(_on_screen_flash_requested)
	if not GameStateManager.player_damage_applied.is_connected(_on_player_damage_applied):
		GameStateManager.player_damage_applied.connect(_on_player_damage_applied)


func set_player_ship(player_ship: CharacterBody2D) -> void:
	_player_ship = player_ship
	if minimap_panel.has_method("set_player_ship"):
		minimap_panel.call("set_player_ship", _player_ship)


func _process(_delta: float) -> void:
	_update_status_bars()
	_update_player_metrics()
	_update_economy_readout()
	_update_target_panel()
	_update_target_lead_indicator()
	_update_incoming_warning()
	_update_damage_flash()


func _update_status_bars() -> void:
	var max_hull: float = maxf(GameStateManager.get_max_hull(), 1.0)
	var max_shield: float = maxf(GameStateManager.get_max_shield(), 1.0)

	hull_bar.max_value = max_hull
	hull_bar.value = clampf(GameStateManager.get_current_hull(), 0.0, max_hull)
	shield_bar.max_value = max_shield
	shield_bar.value = clampf(GameStateManager.get_current_shield(), 0.0, max_shield)

	var hull_ratio: float = hull_bar.value / max_hull
	if hull_ratio <= 0.25:
		_hull_flash_timer += get_process_delta_time() * 6.0
		var pulse: float = 0.45 + absf(sin(_hull_flash_timer)) * 0.55
		hull_bar.modulate = Color(1.0, 0.24 + pulse * 0.28, 0.24 + pulse * 0.2, 1.0)
	else:
		hull_bar.modulate = Color(1.0, 0.36, 0.36, 1.0)


func _update_player_metrics() -> void:
	var speed: float = 0.0
	var boost_ratio: float = 1.0
	var scanner_ratio: float = 1.0
	var velocity_vector: Vector2 = Vector2.ZERO

	if is_instance_valid(_player_ship):
		if _player_ship.has_method("get_current_speed"):
			speed = float(_player_ship.call("get_current_speed"))
		if _player_ship.has_method("get_boost_energy_ratio"):
			boost_ratio = float(_player_ship.call("get_boost_energy_ratio"))
		if _player_ship.has_method("get_scanner_cooldown_ratio"):
			scanner_ratio = float(_player_ship.call("get_scanner_cooldown_ratio"))
		if _player_ship.has_method("get_velocity_vector"):
			velocity_vector = _player_ship.call("get_velocity_vector")

	boost_bar.value = clampf(boost_ratio * 100.0, 0.0, 100.0)
	if scanner_cooldown_indicator.has_method("set_cooldown_ratio"):
		scanner_cooldown_indicator.call("set_cooldown_ratio", scanner_ratio)
	speed_label.text = "Speed: %d px/s" % int(round(speed))
	_update_velocity_indicator(velocity_vector)


func _update_economy_readout() -> void:
	var cargo_used: int = GameStateManager.get_cargo_used()
	var cargo_capacity: int = int(max(GameStateManager.get_cargo_capacity(), 1))
	cargo_label.text = "Cargo: %d/%d" % [cargo_used, cargo_capacity]
	credits_label.text = "Credits: %d" % GameStateManager.credits


func _update_velocity_indicator(velocity_vector: Vector2) -> void:
	if not is_instance_valid(_player_ship):
		velocity_indicator.visible = false
		return

	var speed: float = velocity_vector.length()
	if speed < 6.0:
		velocity_indicator.visible = false
		return

	velocity_indicator.visible = true
	velocity_indicator.position = get_viewport().get_canvas_transform() * _player_ship.global_position
	velocity_indicator.rotation = velocity_vector.angle()

	var line_length: float = clampf(speed * 0.22, 24.0, 84.0)
	velocity_line.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(line_length, 0.0),
	])


func _update_target_panel() -> void:
	if not is_instance_valid(_player_ship):
		target_info_panel.visible = false
		return
	if not _player_ship.has_method("get_current_target_info"):
		target_info_panel.visible = false
		return

	var info: Dictionary = _player_ship.call("get_current_target_info")
	if info.is_empty():
		target_info_panel.visible = false
		return

	target_info_panel.visible = true
	target_name_label.text = String(info.get("name", "Target"))
	target_faction_label.text = "Faction: %s" % String(info.get("faction", "Unknown"))
	target_distance_label.text = "Distance: %d" % int(round(float(info.get("distance", 0.0))))

	var max_hull: float = maxf(float(info.get("max_hull", 1.0)), 1.0)
	var max_shield: float = maxf(float(info.get("max_shield", 1.0)), 1.0)
	target_hull_bar.max_value = max_hull
	target_hull_bar.value = clampf(float(info.get("hull", 0.0)), 0.0, max_hull)
	target_shield_bar.max_value = max_shield
	target_shield_bar.value = clampf(float(info.get("shield", 0.0)), 0.0, max_shield)


func _update_target_lead_indicator() -> void:
	if not is_instance_valid(_player_ship):
		lead_indicator_label.visible = false
		return
	if not _player_ship.has_method("has_target_lead_indicator") or not bool(_player_ship.call("has_target_lead_indicator")):
		lead_indicator_label.visible = false
		return
	if not _player_ship.has_method("get_target_lead_world_position"):
		lead_indicator_label.visible = false
		return

	var lead_world_position: Vector2 = _player_ship.call("get_target_lead_world_position")
	var lead_screen_position: Vector2 = get_viewport().get_canvas_transform() * lead_world_position
	lead_indicator_label.visible = true
	lead_indicator_label.position = lead_screen_position - Vector2(10.0, 12.0)


func _update_incoming_warning() -> void:
	if not is_instance_valid(_player_ship):
		incoming_warning_label.visible = false
		return
	if not _player_ship.has_method("get_incoming_warning_data"):
		incoming_warning_label.visible = false
		return

	var warning_data: Dictionary = _player_ship.call("get_incoming_warning_data")
	if not bool(warning_data.get("active", false)):
		incoming_warning_label.visible = false
		return

	var direction: Vector2 = warning_data.get("direction", Vector2.RIGHT)
	var angle_degrees: int = int(round(rad_to_deg(direction.angle())))
	incoming_warning_label.visible = true
	incoming_warning_label.text = "INCOMING FIRE %d°" % angle_degrees
	incoming_warning_label.modulate.a = clampf(float(warning_data.get("strength", 1.0)), 0.35, 1.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = viewport_size * 0.5
	var edge_offset: Vector2 = Vector2(direction.x * (viewport_size.x * 0.42), direction.y * (viewport_size.y * 0.42))
	incoming_warning_label.position = center + edge_offset - Vector2(120.0, 14.0)


func _update_damage_flash() -> void:
	if damage_flash.color.a <= 0.0:
		return
	var decay_rate: float = _screen_flash_decay_rate
	if decay_rate <= 0.0:
		decay_rate = 6.5
	damage_flash.color.a = maxf(damage_flash.color.a - get_process_delta_time() * decay_rate, 0.0)
	if damage_flash.color.a <= 0.0:
		_screen_flash_decay_rate = 6.5


func _on_toast_state_changed(message: String, category: StringName, alpha: float, visible: bool) -> void:
	if not visible:
		toast_label.visible = false
		return

	toast_label.visible = true
	toast_label.text = message
	var key: String = String(category)
	toast_label.modulate = TOAST_COLORS.get(key, TOAST_COLORS["info"])
	toast_label.modulate.a = alpha


func _on_player_damage_applied(_shield_damage: float, hull_damage: float) -> void:
	if hull_damage <= 0.0:
		return
	damage_flash.color = Color(1.0, 0.2, 0.2, minf(damage_flash.color.a + clampf(hull_damage / 40.0, 0.16, 0.4), 0.5))
	_screen_flash_decay_rate = 6.5


func _on_screen_flash_requested(color: Color, duration: float, max_alpha: float) -> void:
	if duration <= 0.0 or max_alpha <= 0.0:
		return
	damage_flash.color = Color(color.r, color.g, color.b, maxf(damage_flash.color.a, max_alpha))
	_screen_flash_decay_rate = max_alpha / duration
