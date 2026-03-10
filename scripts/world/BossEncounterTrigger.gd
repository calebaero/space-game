extends Area2D
class_name BossEncounterTrigger

signal boss_encounter_triggered(boss_name: String, boss_max_health: float, total_phases: int)

@export var boss_name: String = "PIRATE GUNSHIP CAPTAIN"
@export var boss_max_health: float = 200.0
@export var total_phases: int = 3
@export var required_story_flag: StringName = &""

var _triggered: bool = false


func _ready() -> void:
	add_to_group("boss_encounter_trigger")
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)


func reset_trigger() -> void:
	_triggered = false


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if body == null or not body.is_in_group("player_ship"):
		return

	if required_story_flag != &"":
		var key: String = String(required_story_flag)
		if not MissionManager.story_flags.has(key):
			return

	_triggered = true
	boss_encounter_triggered.emit(boss_name, boss_max_health, max(total_phases, 1))
