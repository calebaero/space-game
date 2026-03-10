extends Node

# TODO(phase-later): route to audio buses, support crossfades, and persistence.


func play_sfx(_sfx_id: StringName, _position: Vector2 = Vector2.ZERO) -> void:
	pass


func play_music(_track_id: StringName) -> void:
	pass


func stop_music() -> void:
	pass


func set_volume(_bus_name: StringName, _linear_value: float) -> void:
	pass
