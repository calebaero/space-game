extends Resource
class_name EconomyCatalog

@export var station_type_modifiers: Dictionary = {}
@export var commodity_availability: Dictionary = {}
@export var station_price_variance_min: float = 0.9
@export var station_price_variance_max: float = 1.1
@export var commodity_stock_min: int = 8
@export var commodity_stock_max: int = 28
