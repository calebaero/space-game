extends CanvasLayer
class_name TutorialOverlay

signal tutorial_completed
signal tutorial_skipped
signal tutorial_step_changed(step_index: int)

@onready var instruction_panel: PanelContainer = %InstructionPanel
@onready var instruction_label: RichTextLabel = %InstructionLabel
@onready var step_label: Label = %StepLabel
@onready var skip_label: Label = %SkipLabel

const STEP_COUNT: int = 10
const STEP_TEXTS: PackedStringArray = [
	"Use [b]Mouse[/b] to aim and hold [b]Left Click[/b] to thrust.",
	"Press [b]S[/b] to brake until nearly stopped.",
	"Press [b]Space[/b] to trigger boost.",
	"Fly to the tutorial beacon.",
	"Press [b]Q[/b] to scan the area.",
	"Hold [b]F[/b] near a resource node to begin mining.",
	"Collect the dropped loot crate.",
	"Return to Anchor Station and press [b]E[/b] to dock.",
	"Open [b]Market[/b] and sell your cargo.",
	"Tutorial complete. You're ready for the frontier.",
]

var _player_ship: PlayerShip = null
var _active: bool = false
var _current_step_index: int = 0
var _beacon_position: Vector2 = Vector2.ZERO
var _dock_station_id: StringName = &"station_anchor_prime"
var _boost_seen: bool = false
var _scan_seen: bool = false
var _mining_started_seen: bool = false
var _cargo_used_step_start: int = 0
var _sold_cargo_seen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	instruction_label.bbcode_enabled = true
	skip_label.text = "Press Esc to skip tutorial"
	set_process(true)


func set_player_ship(player_ship: PlayerShip) -> void:
	if _player_ship != null and is_instance_valid(_player_ship):
		_disconnect_player_ship(_player_ship)
	_player_ship = player_ship
	if _active and _player_ship != null and is_instance_valid(_player_ship):
		_connect_player_ship(_player_ship)


func start_tutorial(player_ship: PlayerShip, beacon_position: Vector2, station_id: StringName = &"station_anchor_prime") -> void:
	if GameStateManager.has_progression_flag(&"tutorial_completed"):
		return
	_beacon_position = beacon_position
	_dock_station_id = station_id
	set_player_ship(player_ship)
	if _active:
		return

	_active = true
	visible = true
	if _player_ship != null and is_instance_valid(_player_ship):
		_connect_player_ship(_player_ship)
	_boost_seen = false
	_scan_seen = false
	_mining_started_seen = false
	_sold_cargo_seen = false
	_cargo_used_step_start = GameStateManager.get_cargo_used()
	_go_to_step(0)


func is_active() -> bool:
	return _active


func report_cargo_sold(total_quantity: int, _credits_earned: int) -> void:
	if not _active:
		return
	if total_quantity <= 0:
		return
	_sold_cargo_seen = true


func skip_tutorial() -> void:
	if not _active:
		return
	_finish_tutorial(true)


func _process(_delta: float) -> void:
	if not _active:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		return

	match _current_step_index:
		0:
			if _player_ship.get_current_speed() > 100.0:
				_go_to_step(1)
		1:
			if _player_ship.get_current_speed() < 10.0:
				_go_to_step(2)
		2:
			if _boost_seen:
				_go_to_step(3)
		3:
			if _player_ship.global_position.distance_to(_beacon_position) <= 180.0:
				_go_to_step(4)
		4:
			if _scan_seen:
				_go_to_step(5)
		5:
			if _mining_started_seen:
				_cargo_used_step_start = GameStateManager.get_cargo_used()
				_go_to_step(6)
		6:
			if GameStateManager.get_cargo_used() > _cargo_used_step_start:
				_go_to_step(7)
		7:
			if GameStateManager.is_docked and GameStateManager.docked_station_id == _dock_station_id:
				_go_to_step(8)
		8:
			if _sold_cargo_seen:
				_go_to_step(9)
		9:
			_finish_tutorial(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		skip_tutorial()


func _go_to_step(step_index: int) -> void:
	_current_step_index = clampi(step_index, 0, STEP_COUNT - 1)
	step_label.text = "Tutorial %d/%d" % [_current_step_index + 1, STEP_COUNT]
	instruction_label.text = STEP_TEXTS[_current_step_index]
	tutorial_step_changed.emit(_current_step_index)


func _finish_tutorial(skipped: bool) -> void:
	if not _active:
		return
	if _player_ship != null and is_instance_valid(_player_ship):
		_disconnect_player_ship(_player_ship)
	_active = false
	visible = false
	GameStateManager.set_progression_flag(&"tutorial_completed", true)
	if skipped:
		UIManager.show_toast("Tutorial skipped.", &"info")
		tutorial_skipped.emit()
	else:
		UIManager.show_toast("Tutorial complete!", &"success")
		tutorial_completed.emit()
	SaveManager.autosave()


func _connect_player_ship(player_ship: PlayerShip) -> void:
	if not player_ship.boost_activated.is_connected(_on_boost_activated):
		player_ship.boost_activated.connect(_on_boost_activated)
	if not player_ship.scanner_pulsed.is_connected(_on_scanner_pulsed):
		player_ship.scanner_pulsed.connect(_on_scanner_pulsed)
	if not player_ship.mining_started.is_connected(_on_mining_started):
		player_ship.mining_started.connect(_on_mining_started)


func _disconnect_player_ship(player_ship: PlayerShip) -> void:
	if player_ship.boost_activated.is_connected(_on_boost_activated):
		player_ship.boost_activated.disconnect(_on_boost_activated)
	if player_ship.scanner_pulsed.is_connected(_on_scanner_pulsed):
		player_ship.scanner_pulsed.disconnect(_on_scanner_pulsed)
	if player_ship.mining_started.is_connected(_on_mining_started):
		player_ship.mining_started.disconnect(_on_mining_started)


func _on_boost_activated() -> void:
	_boost_seen = true


func _on_scanner_pulsed(_range: float) -> void:
	_scan_seen = true


func _on_mining_started(_node: Node2D) -> void:
	_mining_started_seen = true
