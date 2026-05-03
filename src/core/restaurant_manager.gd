extends Node

signal money_changed(amount: float)
signal time_changed(current_time: float)
signal day_changed(current_day: int)
signal open_state_changed(is_open: bool)
signal menu_prices_changed()

@export var starting_money: float = 1000.0
@export var day_duration_seconds: float = 360.0
@export var start_time_of_day: float = 8.0 # 8:00 AM
@export var end_time_of_day: float = 22.0 # 10:00 PM
@export var burger_price: float = 5.0:
	set(value):
		burger_price = maxf(value, 0.0)
		menu_prices_changed.emit()
@export var fries_price: float = 2.0:
	set(value):
		fries_price = maxf(value, 0.0)
		menu_prices_changed.emit()
@export var soda_price: float = 1.0:
	set(value):
		soda_price = maxf(value, 0.0)
		menu_prices_changed.emit()

var money: float = 0.0
var time_of_day: float = 0.0 # Range: start_time_of_day to end_time_of_day
var current_day: int = 1
var is_open: bool = false
var _time_accumulator: float = 0.0
var _orders_placed_this_day := 0
var _orders_delivered_this_day := 0
var _total_order_to_delivery_seconds := 0.0

func _ready() -> void:
	money = starting_money
	time_of_day = start_time_of_day
	emit_signal("money_changed", money)
	emit_signal("time_changed", time_of_day)
	emit_signal("day_changed", current_day)
	emit_signal("open_state_changed", is_open)

func _process(delta: float) -> void:
	if not is_open:
		return

	_time_accumulator += delta
	var time_fraction = _time_accumulator / day_duration_seconds
	time_of_day = start_time_of_day + (end_time_of_day - start_time_of_day) * time_fraction

	emit_signal("time_changed", time_of_day)

	if time_of_day >= end_time_of_day:
		close_restaurant()
		_end_of_day_processing()

func open_restaurant() -> void:
	if is_open: return
	
	is_open = true
	time_of_day = start_time_of_day
	_time_accumulator = 0.0
	_orders_placed_this_day = 0
	_orders_delivered_this_day = 0
	_total_order_to_delivery_seconds = 0.0
	emit_signal("open_state_changed", is_open)
	emit_signal("time_changed", time_of_day)

func close_restaurant() -> void:
	if not is_open: return
	
	is_open = false
	emit_signal("open_state_changed", is_open)

func _end_of_day_processing() -> void:
	# Calculate end of day expenses here (wages, etc) in the future
	current_day += 1
	emit_signal("day_changed", current_day)

func add_money(amount: float) -> void:
	if amount <= 0: return
	money += amount
	emit_signal("money_changed", money)

func spend_money(amount: float) -> bool:
	if amount <= 0: return true
	if money >= amount:
		money -= amount
		emit_signal("money_changed", money)
		return true
	return false

func set_food_price(food_type: String, price: float) -> void:
	match food_type.to_lower():
		"burger":
			burger_price = price
		"fries":
			fries_price = price
		"soda":
			soda_price = price

func get_food_price(food_type: String) -> float:
	match food_type.to_lower():
		"burger":
			return burger_price
		"fries":
			return fries_price
		"soda":
			return soda_price
	return 0.0

func get_menu_items() -> Array[Dictionary]:
	return [
		{"id": "burger", "label": "BURGER", "price": burger_price},
		{"id": "fries", "label": "FRIES", "price": fries_price},
		{"id": "soda", "label": "SODA", "price": soda_price},
	]

func record_order_placed() -> void:
	_orders_placed_this_day += 1

func record_order_delivered(order_to_delivery_seconds: float) -> void:
	_orders_delivered_this_day += 1
	_total_order_to_delivery_seconds += maxf(0.0, order_to_delivery_seconds)

func get_service_metrics() -> Dictionary:
	var elapsed_real_seconds := maxf(1.0, _time_accumulator)
	var elapsed_game_hours := maxf(0.01, time_of_day - start_time_of_day)
	return {
		"orders_placed": _orders_placed_this_day,
		"orders_delivered": _orders_delivered_this_day,
		"orders_per_real_minute": float(_orders_placed_this_day) / (elapsed_real_seconds / 60.0),
		"orders_per_ingame_hour": float(_orders_placed_this_day) / elapsed_game_hours,
		"avg_order_to_delivery_seconds": _total_order_to_delivery_seconds / float(maxi(1, _orders_delivered_this_day)),
	}

func get_time_string() -> String:
	var hours = floori(time_of_day)
	var minutes = floori((time_of_day - hours) * 60.0)
	var am_pm = "AM" if hours < 12 else "PM"
	var display_hours = hours
	if display_hours > 12:
		display_hours -= 12
	elif display_hours == 0:
		display_hours = 12
	
	return "%02d:%02d %s" % [display_hours, minutes, am_pm]
