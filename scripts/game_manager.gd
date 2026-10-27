# =====================================================================
# game_manager.gd  —  AUTOLOAD (registered in project.godot)
#
# Holds everything that's "global" about the tavern: gold, fame, the
# day/clock, the menu, furniture prices, and the queue of food orders.
#
# Other scripts never change gold directly — they call try_spend() or
# earn(). That way this script can EMIT A SIGNAL every time gold changes,
# and the HUD just listens for it instead of checking every frame.
# =====================================================================
extends Node

# ---------------------------------------------------------------------
# SIGNALS
# A signal is a "broadcast". This script shouts "gold changed!" and any
# script that connected to it (like the HUD) runs its own function.
# The sender doesn't need to know who's listening.
# ---------------------------------------------------------------------
signal gold_changed(new_amount: int)
signal fame_changed(new_amount: int)
signal clock_changed(hour: int, minute: int)
signal shop_opened(day: int)
signal shop_closed(day: int)

# ---------------------------------------------------------------------
# TUNING CONSTANTS — tweak these to change how the game feels.
# ---------------------------------------------------------------------
const OPEN_HOUR: int = 9
const CLOSE_HOUR: int = 21
# 6 game-minutes per real second -> a 12-hour day lasts 2 real minutes.
const GAME_MINUTES_PER_SECOND: float = 6.0
const STARTING_GOLD: int = 200

# Everything the player can build. The key ("table") is the ID the
# other scripts use; the inner Dictionary holds its details.
const FURNITURE: Dictionary = {
	"table": {"name": "Table", "cost": 50, "color": Color(0.55, 0.36, 0.2)},
	"kitchen": {"name": "Hearth", "cost": 120, "color": Color(0.7, 0.25, 0.15)},
}

# The menu. Milestone 3 replaces this with recipes you research.
const MENU: Array = [
	{"name": "Dragon Ale", "price": 12, "cook_time": 2.5},
	{"name": "Mushroom Stew", "price": 18, "cook_time": 4.0},
	{"name": "Roast Boar", "price": 28, "cook_time": 6.0},
]

# ---------------------------------------------------------------------
# GAME STATE
# ---------------------------------------------------------------------
var gold: int = STARTING_GOLD
var fame: int = 0
var day: int = 0          # becomes 1 when the first day opens
var is_open: bool = false
var minutes_since_open: float = 0.0
var _last_minute_shown: int = -1

# Stats for the end-of-day summary (reset every morning).
var today_income: int = 0
var today_served: int = 0
var today_walkouts: int = 0

# Customers who have ordered and are waiting for a free Hearth to cook.
# Array[Customer] is a TYPED array: Godot will refuse anything that
# isn't a Customer. "Customer" works as a type because customer.gd
# declares `class_name Customer`.
var order_queue: Array[Customer] = []


# _process runs once every frame. delta = seconds since the last frame
# (about 0.016 at 60 FPS). Multiplying by delta keeps the clock speed
# the same on fast and slow phones.
func _process(delta: float) -> void:
	if not is_open:
		return

	minutes_since_open += delta * GAME_MINUTES_PER_SECOND
	var total_minutes: int = OPEN_HOUR * 60 + int(minutes_since_open)

	# Only broadcast when the displayed minute actually changes.
	if total_minutes != _last_minute_shown:
		_last_minute_shown = total_minutes
		clock_changed.emit(floori(total_minutes / 60.0), total_minutes % 60)

	if total_minutes >= CLOSE_HOUR * 60:
		is_open = false
		shop_closed.emit(day)


func open_shop() -> void:
	day += 1
	is_open = true
	minutes_since_open = 0.0
	_last_minute_shown = -1
	today_income = 0
	today_served = 0
	today_walkouts = 0
	shop_opened.emit(day)


# Returns true and deducts gold if the player can afford it.
func try_spend(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func earn(amount: int) -> void:
	gold += amount
	today_income += amount
	gold_changed.emit(gold)


func change_fame(amount: int) -> void:
	fame = max(0, fame + amount)   # fame never goes below zero
	fame_changed.emit(fame)


# More fame = guests arrive more often (6 seconds at 0 fame, down to 1.5).
func get_spawn_interval() -> float:
	return max(1.5, 6.0 - fame * 0.1)
