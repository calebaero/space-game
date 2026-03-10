extends Node

# TODO(phase-later): implement market profiles, seeded modifiers, and transaction logic.


func get_price(_item_id: StringName, _station_economy_type: StringName = &"") -> int:
	return 0


func can_afford(cost: int) -> bool:
	return GameStateManager.credits >= cost


func apply_transaction(delta_credits: int) -> void:
	GameStateManager.credits += delta_credits
