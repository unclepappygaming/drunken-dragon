# =====================================================================
# game_manager.gd  —  AUTOLOAD (registered in project.godot)
#
# Holds everything that's "global" about the tavern: gold, fame, the
# day/clock, the menu, furniture prices, staff wages, the two lines
# guests wait in (for a waiter, then for a cook), and saving/loading.
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

# "user://" is a folder Godot gives every game for its own files. On a
# phone it's private app storage; in a web browser it's browser storage.
const SAVE_PATH: String = "user://save.json"
# Bump this if the save format ever changes, so old saves can be handled.
const SAVE_VERSION: int = 1

# Everything the player can build. The key ("table") is the ID the
# other scripts use; the inner Dictionary holds its details.
const FURNITURE: Dictionary = {
	"table": {"name": "Table", "cost": 50, "color": Color(0.55, 0.36, 0.2)},
	"kitchen": {"name": "Hearth", "cost": 120, "color": Color(0.7, 0.25, 0.15)},
}

# Staff you can hire. Wages are paid at the end of each day.
const STAFF: Dictionary = {
	"cook": {"name": "Cook", "wage": 25},
	"waiter": {"name": "Waiter", "wage": 20},
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
var today_turned_away: int = 0   # arrived but found no free table

# Customers waiting for a Waiter to come and take their order.
# Array[Customer] is a TYPED array: Godot will refuse anything that
# isn't a Customer. "Customer" works as a type because customer.gd
# declares `class_name Customer`.
var order_requests: Array[Customer] = []
# Customers whose order was taken, waiting for a Hearth to cook it.
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
	today_turned_away = 0
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


# Put everything back to a brand-new game (used by "New Game").
# Autoloads survive scene reloads, so this has to be done by hand.
func reset() -> void:
	gold = STARTING_GOLD
	fame = 0
	day = 0
	is_open = false
	minutes_since_open = 0.0
	_last_minute_shown = -1
	today_income = 0
	today_served = 0
	today_walkouts = 0
	today_turned_away = 0
	order_requests.clear()
	order_queue.clear()


# ---------------------------------------------------------------------
# SAVING
# The game saves between days only. Quitting mid-day means replaying
# that day from the start, which keeps saves simple: no half-cooked
# dishes or guests mid-walk to store.
#
# The save is a JSON text file, so you can open it and read it.
# main.gd supplies the furniture and staff; we add gold, fame and day.
# ---------------------------------------------------------------------
func save_game(layout: Array, cooks: int, waiters: int) -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"day": day,
		"gold": gold,
		"fame": fame,
		"furniture": layout,
		"cooks": cooks,
		"waiters": waiters,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		# Saving can fail (full storage, private browsing). The game keeps
		# working; it just won't remember this session.
		push_warning("Could not save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	# The file is closed and written when `file` goes out of scope.


# Returns the saved data, or an empty Dictionary if there's no usable save.
# Also restores gold, fame and day.
func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	# A damaged or unknown file is ignored rather than crashing the game.
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("version") != SAVE_VERSION:
		push_warning("Save file unreadable, starting a new game.")
		return {}
	# JSON stores every number as a decimal, so turn them back into ints.
	day = int(parsed.get("day", 0))
	gold = int(parsed.get("gold", STARTING_GOLD))
	fame = int(parsed.get("fame", 0))
	gold_changed.emit(gold)
	fame_changed.emit(fame)
	return parsed


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# Money back from selling furniture. Not counted in today's income,
# so the end-of-day summary only shows what guests paid.
func refund(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


# Wages always get paid, even if that takes gold below zero. While in
# debt, try_spend() fails, so you can't build until you earn it back.
func pay_wages(amount: int) -> void:
	gold -= amount
	gold_changed.emit(gold)


func daily_wages(cooks: int, waiters: int) -> int:
	return cooks * STAFF["cook"]["wage"] + waiters * STAFF["waiter"]["wage"]


# A Waiter asks for the next guest who wants to order (or null).
func next_order_request() -> Customer:
	while not order_requests.is_empty():
		var c: Customer = order_requests.pop_front()
		if is_instance_valid(c) and c.state == Customer.State.WAITING_FOR_WAITER:
			return c
	return null


func change_fame(amount: int) -> void:
	fame = max(0, fame + amount)   # fame never goes below zero
	fame_changed.emit(fame)


# More fame = guests arrive more often (6 seconds at 0 fame, down to 1.5).
# Guests you turn away cost fame, so fame settles at whatever your
# tavern can actually seat. Build more Tables to grow it further.
func get_spawn_interval() -> float:
	return max(1.5, 6.0 - fame * 0.1)
