extends CanvasLayer
class_name BossHealthBar

@onready var root: Control = %Root
@onready var boss_name_label: Label = %BossNameLabel
@onready var boss_health_bar: ProgressBar = %BossHealthBar
@onready var phase_label: Label = %PhaseLabel
@onready var intro_label: Label = %IntroLabel

var _max_health: float = 1.0
var _total_phases: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	intro_label.visible = false


func begin_encounter(boss_name: String, max_health: float, total_phases: int = 1) -> void:
	_max_health = maxf(max_health, 1.0)
	_total_phases = max(total_phases, 1)

	boss_name_label.text = boss_name
	boss_health_bar.max_value = _max_health
	boss_health_bar.value = _max_health
	phase_label.text = "Phase 1/%d" % _total_phases
	root.visible = true

	intro_label.text = boss_name.to_upper()
	intro_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	intro_label.visible = true

	var tween: Tween = create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(intro_label, "modulate:a", 0.0, 0.9)
	tween.finished.connect(func() -> void:
		intro_label.visible = false
	)


func update_encounter(current_health: float, phase_index: int = 1) -> void:
	if not root.visible:
		return
	boss_health_bar.value = clampf(current_health, 0.0, _max_health)
	phase_label.text = "Phase %d/%d" % [clampi(phase_index, 1, _total_phases), _total_phases]


func end_encounter() -> void:
	root.visible = false
	intro_label.visible = false
