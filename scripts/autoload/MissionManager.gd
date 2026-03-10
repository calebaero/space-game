extends Node

# TODO(phase-later): contract generation, story mission state, and objective tracking.

var active_missions: Array = []
var completed_missions: Array = []
var story_flags: Dictionary = {}


func reset_for_new_game() -> void:
	active_missions.clear()
	completed_missions.clear()
	story_flags.clear()
