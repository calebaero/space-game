extends Node

# TODO(phase-later): implement full save slot serialization and metadata handling.


func save_game(slot_id: int = 0) -> bool:
	push_warning("SaveManager.save_game() is a stub. slot_id=%d" % slot_id)
	return false


func load_game(slot_id: int = 0) -> bool:
	push_warning("SaveManager.load_game() is a stub. slot_id=%d" % slot_id)
	return false


func autosave() -> bool:
	push_warning("SaveManager.autosave() is a stub.")
	return false
