extends Node

const DEFAULT_VARIANCE_MIN: float = 0.9
const DEFAULT_VARIANCE_MAX: float = 1.1
const DEFAULT_STOCK_MIN: int = 8
const DEFAULT_STOCK_MAX: int = 24

var _station_lookup: Dictionary = {}
var _station_goods_stock: Dictionary = {}


func _ready() -> void:
	ContentDatabase.ensure_loaded()
	_rebuild_station_lookup()


func refresh_runtime_data() -> void:
	_rebuild_station_lookup()
	_station_goods_stock.clear()


func get_sell_price(item_id: StringName, station_id: StringName) -> int:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	if item_def.is_empty():
		return 0

	var base_value: int = int(item_def.get("base_sell_value", item_def.get("base_value", 0)))
	if base_value <= 0:
		return 0

	var station_data: Dictionary = _get_station_data(station_id)
	var economy_type: StringName = StringName(String(station_data.get("economy_type", "")))
	var economy_multiplier: float = _get_economy_multiplier(item_def, economy_type)
	var station_variance: float = _get_station_variance(station_id, item_id)
	var final_price: int = int(round(float(base_value) * economy_multiplier * station_variance))
	return max(final_price, 1)


func get_buy_price(commodity_id: StringName, station_id: StringName) -> int:
	var item_def: Dictionary = ContentDatabase.get_item_definition(commodity_id)
	if item_def.is_empty():
		return 0

	var base_buy: int = int(item_def.get("base_buy_value", item_def.get("base_value", 0)))
	if base_buy <= 0:
		return 0

	var station_data: Dictionary = _get_station_data(station_id)
	var economy_type: StringName = StringName(String(station_data.get("economy_type", "")))
	var economy_multiplier: float = _get_economy_multiplier(item_def, economy_type)
	var station_variance: float = _get_station_variance(station_id, commodity_id)
	var final_price: int = int(round(float(base_buy) * economy_multiplier * station_variance))
	return max(final_price, 1)


func sell_cargo(item_id: StringName, quantity: int, station_id: StringName) -> int:
	if quantity <= 0:
		return 0

	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if not item_def.is_empty() and not bool(item_def.get("tradeable", true)):
		UIManager.show_toast("%s cannot be sold." % String(item_def.get("name", String(item_id))), &"warning")
		return 0

	var available: int = _get_cargo_quantity(item_id)
	if available <= 0:
		return 0
	var amount_to_sell: int = min(quantity, available)
	var unit_price: int = get_sell_price(item_id, station_id)
	if unit_price <= 0:
		return 0
	if not GameStateManager.remove_cargo(item_id, amount_to_sell):
		return 0

	var earned: int = unit_price * amount_to_sell
	GameStateManager.credits += earned
	AudioManager.play_sfx(&"market_sell", Vector2.ZERO)
	return earned


func buy_commodity(commodity_id: StringName, quantity: int, station_id: StringName) -> bool:
	if quantity <= 0:
		return false
	var station_key: String = String(station_id)
	if station_key.is_empty():
		return false

	var stock: Dictionary = _ensure_station_stock(station_id)
	if not stock.has(String(commodity_id)):
		UIManager.show_toast("This station does not stock that commodity.", &"warning")
		return false

	var available: int = int(stock.get(String(commodity_id), 0))
	if available <= 0:
		UIManager.show_toast("Out of stock.", &"warning")
		return false

	var amount_to_buy: int = min(quantity, available)
	var unit_price: int = get_buy_price(commodity_id, station_id)
	if unit_price <= 0:
		return false

	var max_affordable: int = int(GameStateManager.credits / unit_price)
	amount_to_buy = min(amount_to_buy, max_affordable)
	if amount_to_buy <= 0:
		UIManager.show_toast("Not enough credits.", &"warning")
		return false

	var added: int = GameStateManager.add_cargo(commodity_id, amount_to_buy)
	if added <= 0:
		return false

	var total_cost: int = unit_price * added
	GameStateManager.credits = max(GameStateManager.credits - total_cost, 0)
	stock[String(commodity_id)] = max(available - added, 0)
	_station_goods_stock[station_key] = stock

	var commodity_def: Dictionary = ContentDatabase.get_item_definition(commodity_id)
	var commodity_name: String = String(commodity_def.get("name", commodity_id))
	UIManager.show_toast("Purchased %d %s (-%d cr)" % [added, commodity_name, total_cost], &"success")
	if added < quantity:
		UIManager.show_toast("Partial purchase due to stock, credits, or cargo space.", &"info")

	AudioManager.play_sfx(&"market_buy", Vector2.ZERO)
	return true


func get_station_commodity_offers(station_id: StringName) -> Array[Dictionary]:
	var station_data: Dictionary = _get_station_data(station_id)
	if station_data.is_empty():
		return []

	var economy_type: String = String(station_data.get("economy_type", ""))
	var profile: Dictionary = ContentDatabase.get_market_profile_data()
	var commodity_by_type: Dictionary = profile.get("commodity_availability", {})
	var available_ids: Array = commodity_by_type.get(economy_type, [])
	var stock: Dictionary = _ensure_station_stock(station_id)

	var offers: Array[Dictionary] = []
	for commodity_variant in available_ids:
		var commodity_id: StringName = StringName(String(commodity_variant))
		var item_def: Dictionary = ContentDatabase.get_item_definition(commodity_id)
		if item_def.is_empty():
			continue

		var available_quantity: int = int(stock.get(String(commodity_id), 0))
		offers.append({
			"item_id": String(commodity_id),
			"name": String(item_def.get("name", commodity_id)),
			"available_quantity": available_quantity,
			"buy_price": get_buy_price(commodity_id, station_id),
			"icon_color": item_def.get("icon_color", Color(0.85, 0.85, 0.9, 1.0)),
		})

	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return offers


func get_station_data(station_id: StringName) -> Dictionary:
	return _get_station_data(station_id)


func get_station_services(station_id: StringName) -> Array[String]:
	var station_data: Dictionary = _get_station_data(station_id)
	if station_data.is_empty():
		return []

	var result: Array[String] = []
	for service_variant in station_data.get("services", []):
		result.append(String(service_variant))
	return result


func get_price(item_id: StringName, station_economy_type: StringName = &"") -> int:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	if item_def.is_empty():
		return 0

	var base_value: int = int(item_def.get("base_sell_value", item_def.get("base_value", 0)))
	if base_value <= 0:
		return 0

	var multiplier: float = _get_economy_multiplier(item_def, station_economy_type)
	return max(int(round(float(base_value) * multiplier)), 1)


func can_afford(cost: int) -> bool:
	return GameStateManager.credits >= cost


func apply_transaction(delta_credits: int) -> void:
	GameStateManager.credits += delta_credits


func _rebuild_station_lookup() -> void:
	_station_lookup.clear()
	for sector_variant in ContentDatabase.get_all_sectors().values():
		var sector_data: Dictionary = sector_variant
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			continue
		var station_id: String = String(station_data.get("id", ""))
		if station_id.is_empty():
			continue
		_station_lookup[station_id] = station_data.duplicate(true)


func _get_station_data(station_id: StringName) -> Dictionary:
	var key: String = String(station_id)
	if key.is_empty():
		return {}
	if _station_lookup.is_empty():
		_rebuild_station_lookup()
	if not _station_lookup.has(key):
		return {}
	return (_station_lookup[key] as Dictionary).duplicate(true)


func _get_economy_multiplier(item_def: Dictionary, economy_type: StringName) -> float:
	var profile: Dictionary = ContentDatabase.get_market_profile_data()
	var type_modifiers: Dictionary = profile.get("station_type_modifiers", {})
	var economy_key: String = String(economy_type)
	if economy_key.is_empty() or not type_modifiers.has(economy_key):
		return 1.0

	var modifiers: Dictionary = type_modifiers.get(economy_key, {})
	var best_multiplier: float = 1.0
	var best_delta: float = 0.0
	for tag_variant in item_def.get("tags", []):
		var tag: String = String(tag_variant)
		if not modifiers.has(tag):
			continue
		var candidate: float = float(modifiers.get(tag, 1.0))
		var delta: float = absf(candidate - 1.0)
		if delta > best_delta:
			best_delta = delta
			best_multiplier = candidate
	return best_multiplier


func _get_station_variance(station_id: StringName, item_id: StringName) -> float:
	var station_key: String = String(station_id)
	if station_key.is_empty():
		return 1.0

	var profile: Dictionary = ContentDatabase.get_market_profile_data()
	var min_variance: float = float(profile.get("station_price_variance_min", DEFAULT_VARIANCE_MIN))
	var max_variance: float = float(profile.get("station_price_variance_max", DEFAULT_VARIANCE_MAX))
	if max_variance < min_variance:
		var temp: float = min_variance
		min_variance = max_variance
		max_variance = temp

	var hashed: int = abs(hash("%s|%s|price" % [station_key, String(item_id)]))
	var t: float = float(hashed % 10000) / 9999.0
	return lerpf(min_variance, max_variance, t)


func _ensure_station_stock(station_id: StringName) -> Dictionary:
	var station_key: String = String(station_id)
	if station_key.is_empty():
		return {}
	if _station_goods_stock.has(station_key):
		return (_station_goods_stock[station_key] as Dictionary).duplicate(true)

	var station_data: Dictionary = _get_station_data(station_id)
	if station_data.is_empty():
		return {}

	var economy_type: String = String(station_data.get("economy_type", ""))
	var profile: Dictionary = ContentDatabase.get_market_profile_data()
	var commodity_by_type: Dictionary = profile.get("commodity_availability", {})
	var commodity_ids: Array = commodity_by_type.get(economy_type, [])

	var stock_min: int = int(profile.get("commodity_stock_min", DEFAULT_STOCK_MIN))
	var stock_max: int = int(profile.get("commodity_stock_max", DEFAULT_STOCK_MAX))
	if stock_max < stock_min:
		stock_max = stock_min

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = abs(hash("stock|%s" % station_key))

	var stock: Dictionary = {}
	for commodity_variant in commodity_ids:
		var commodity_id: String = String(commodity_variant)
		if commodity_id.is_empty():
			continue
		stock[commodity_id] = rng.randi_range(stock_min, stock_max)

	_station_goods_stock[station_key] = stock
	return stock.duplicate(true)


func _get_cargo_quantity(item_id: StringName) -> int:
	for entry_variant in GameStateManager.get_cargo_manifest():
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("resource_id", "")) == String(item_id):
			return int(entry.get("quantity", 0))
	return 0
