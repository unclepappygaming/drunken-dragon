# =====================================================================
# game_manager.gd  —  AUTOLOAD (registered in project.godot)
#
# Holds everything that's "global" about the tavern: gold, fame, the
# day/clock, recipes and today's menu, furniture prices, staff wages, the two lines
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
signal recipes_changed   # a recipe was unlocked or the menu changed
signal rush_changed(rush_name: String)   # a rush began ("" = it ended)

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
# Version 2 added recipes and the menu, version 3 lifetime stats (for
# quests), version 4 expansions and the door, version 5 fame milestones,
# version 6 named staff with types and looks, version 7 the kitchen zone,
# version 8 the location (the tavern or the Grand Hall), version 9 tables
# with chairs (older one-square tables become 3 x 1 tables on loading),
# version 10 decorations.
# Older saves still load.
const SAVE_VERSION: int = 10

# Everything the player can build. The key ("table") is the ID the
# other scripts use; the inner Dictionary holds its details.
const FURNITURE: Dictionary = {
	# A Table is 3 x 1 (chair, table, chair) and seats 2; a Long Table is
	# 3 x 2 and seats 4. Each group of guests takes a whole table.
	"table": {"name": "Table", "cost": 100, "color": Color(0.55, 0.36, 0.2)},
	"long_table": {"name": "Long Table", "cost": 220, "color": Color(0.55, 0.36, 0.2)},
	# A Bar: a bartender stands behind it (the -y side) and pours drinks.
	"bar": {"name": "Bar", "cost": 300, "color": Color(0.4, 0.25, 0.15)},
	"kitchen": {"name": "Hearth", "cost": 250, "color": Color(0.7, 0.25, 0.15)},
}

# DECORATIONS are just for looks. Floor pieces are bought ("cost"); a
# few need a rank first ("fame"). size 2 = it covers 2 x 2 squares.
# walk = people can walk over it (the rug). frames > 1 = it's animated.
# Wall pieces hang on the back walls and are never bought: each one is
# earned by an achievement ("stat" reaching "goal"; "task" describes it).
const DECOR: Dictionary = {
	"fern":      {"name": "Potted Fern", "where": "floor", "cost": 60},
	"barrels":   {"name": "Ale Barrels", "where": "floor", "cost": 90},
	"rug":       {"name": "Rug", "where": "floor", "cost": 120, "walk": true},
	"armour":    {"name": "Suit of Armour", "where": "floor", "cost": 250},
	"bookshelf": {"name": "Bookshelf", "where": "floor", "cost": 250},
	"fireplace": {"name": "Fireplace", "where": "floor", "cost": 400, "frames": 3},
	"dragon":    {"name": "Dragon Statue", "where": "floor", "cost": 1500, "size": 2, "fame": 140},
	"painting":  {"name": "Painting", "where": "wall", "stat": "best_fame", "goal": 10, "task": "Reach Local Haunt"},
	"shield":    {"name": "Shield & Swords", "where": "wall", "stat": "guest:guard", "goal": 25, "task": "Serve 25 Town Guards"},
	"antlers":   {"name": "Antlers", "where": "wall", "stat": "dish:boar", "goal": 100, "task": "Serve 100 Roast Boars"},
	"lantern":   {"name": "Faerie Lantern", "where": "wall", "stat": "days", "goal": 20, "task": "Open the tavern for 20 days", "frames": 4},
	"wreath":    {"name": "Moonflower Wreath", "where": "wall", "stat": "dish:mead", "goal": 50, "task": "Serve 50 Honey Meads"},
	"glowcap":   {"name": "Glowcap Shelf", "where": "wall", "stat": "dish:stew", "goal": 100, "task": "Serve 100 Mushroom Stews"},
	"wings":     {"name": "Gossamer Wings", "where": "wall", "stat": "fae_nights", "goal": 1, "task": "Delight the fae on a Fae Night"},
	"mirror":    {"name": "Fae Mirror", "where": "wall", "stat": "triumphs", "goal": 3, "task": "Host 3 triumphant banquets"},
	"crown":     {"name": "Faerie Crown", "where": "wall", "stat": "recipes_learned", "goal": 6, "task": "Learn every recipe"},
	"wyvern":    {"name": "Wyvern Head", "where": "wall", "stat": "dish:wings", "goal": 30, "task": "Serve 30 Wyvern Wings", "frames": 4},
	"centaur":   {"name": "Centaur Head", "where": "wall", "stat": "guest:adventurer", "goal": 50, "task": "Serve 50 adventurers", "frames": 4},
	"griffon":   {"name": "Griffon Head", "where": "wall", "stat": "best_fame", "goal": 90, "task": "Reach Famed Hall", "frames": 4},
	"unicorn":   {"name": "Unicorn Head", "where": "wall", "stat": "nobles", "goal": 25, "task": "Serve 25 nobles", "frames": 4},
	"minotaur":  {"name": "Minotaur Head", "where": "wall", "stat": "served", "goal": 500, "task": "Serve 500 guests", "frames": 4},
	"kraken":    {"name": "Kraken Tentacles", "where": "wall", "stat": "moved", "goal": 1, "task": "Move to the Grand Hall", "frames": 4},
}

# Staff types, traits and wages live in staff_profiles.gd. Each day a few
# people apply for each job; you pick who to hire.
const APPLICANTS_PER_ROLE: int = 3

# Every dish the tavern could ever serve. The key ("ale") is the ID.
#   tier 1-2: what common folk order
#   tier 3:   fancy dishes only nobles order
#   unlock:   how you earn it (starter recipes have none). It finishes
#             when the lifetime stat `stat` reaches `goal`:
#               "patron" = a guest shares the idea
#               "quest"  = a named task shown in the recipe book
# Pricier dishes earn more per guest but keep a Hearth busy longer.
# cost: what the ingredients cost, paid every night for each dish cooked
# (even ones the guest left before eating).
const RECIPES: Dictionary = {
	"ale":     {"name": "Dragon Ale",       "price": 10, "cost": 4, "cook_time": 2.33,  "tier": 1},
	"stew":    {"name": "Mushroom Stew",    "price": 15, "cost": 6, "cook_time": 3.72,  "tier": 1},
	"mead":    {"name": "Honey Mead",       "price": 13, "cost": 5, "cook_time": 2.79,  "tier": 1,
			"unlock": {"by": "patron", "stat": "served", "goal": 20,
				"task": "A regular may share it once you've served 20 guests",
				"who": "A regular"}},
	"boar":    {"name": "Roast Boar",       "price": 23, "cost": 9, "cook_time": 5.58,  "tier": 2},
	"cheese":  {"name": "Troll Cheese",     "price": 20, "cost": 7, "cook_time": 3.72,  "tier": 2,
			"unlock": {"by": "quest", "stat": "dish:stew", "goal": 12,
				"title": "The Bridge Troll", "task": "Serve 12 Mushroom Stews"}},
	"wings":   {"name": "Wyvern Wings",     "price": 28, "cost": 10, "cook_time": 6.04,  "tier": 2,
			"unlock": {"by": "quest", "stat": "perfect_days", "goal": 1,
				"title": "Hunter's Challenge", "task": "Finish a day with no walk-outs and 20+ guests served"}},
	"wine":    {"name": "Elven Wine",       "price": 38, "cost": 13, "cook_time": 4.65,  "tier": 3,
			"unlock": {"by": "patron", "stat": "best_fame", "goal": 25,
				"task": "A noble's steward may share it when your fame reaches 25",
				"who": "A noble's steward"}},
	"phoenix": {"name": "Phoenix Roast",    "price": 50, "cost": 16, "cook_time": 8.37,  "tier": 3,
			"unlock": {"by": "quest", "stat": "nobles", "goal": 8,
				"title": "Noble Approval", "task": "Serve 8 nobles"}},
	"feast":   {"name": "Dragonfire Feast", "price": 70, "cost": 22, "cook_time": 11.16, "tier": 3,
			"unlock": {"by": "quest", "stat": "dish:phoenix", "goal": 10,
				"title": "A Feast for a Dragon", "task": "Serve 10 Phoenix Roasts"}},
}
const STARTER_RECIPES: Array[String] = ["ale", "stew", "boar"]
const MAX_MENU: int = 4          # dishes on the menu at once
# NOBLE BANQUETS: nobles only come when invited. At NOBLE_FAME you can
# host a banquet (from the Open Day button): pay BANQUET_COST and a party
# of nobles arrives between BANQUET_START and BANQUET_END (24h clock).
const NOBLE_FAME: int = 25
const BANQUET_COST: int = 250
const BANQUET_EVERY: int = 3     # days between banquets
const BANQUET_START: int = 12
const BANQUET_END: int = 15
const NOBLE_TIP: float = 0.5        # nobles pay 50% on top
const PERFECT_DAY_GUESTS: int = 20   # guests needed for a "perfect day"

# RUSH HOURS: guests arrive `busy` times as often between `start` and
# `end` (24h clock). Mornings before QUIET_UNTIL are quieter than usual.
const RUSHES: Array = [
	{"name": "Lunch rush", "start": 12, "end": 14, "busy": 1.7},
	{"name": "Dinner rush", "start": 18, "end": 20, "busy": 2.0},
]
const QUIET_UNTIL: int = 11
const QUIET_BUSY: float = 0.7

# SPECIAL EVENTS: from day 3, each ordinary (non-banquet) day has
# EVENT_CHANCE of one, picked by weight among those your fame allows.
#   festival   guests come twice as often and tip 25% more
#   rain       30% fewer guests, but 30% more patient; rain outside
#   critic     a food critic visits: serve them well and quickly for fame
#   fae_night  from dusk, fae guests arrive; delight them all for a trophy
const EVENT_CHANCE: float = 0.4
const EVENTS: Dictionary = {
	"festival": {"name": "Festival Day", "weight": 12, "fame": 0,
		"text": "Festival Day! Twice the guests, and everyone tips 25% more."},
	"rain": {"name": "Rainy Day", "weight": 12, "fame": 0,
		"text": "A rainy day: fewer guests, but they're in no hurry to leave."},
	"critic": {"name": "Food Critic", "weight": 10, "fame": 10,
		"text": "A food critic is in town! Serve them well and quickly."},
	"fae_night": {"name": "Fae Night", "weight": 6, "fame": 25,
		"text": "The fae are abroad tonight! From dusk, fae folk will visit."},
}
const FESTIVAL_TIP: float = 0.25
const RAIN_BUSY: float = 0.7
const RAIN_PATIENCE: float = 1.3
const CRITIC_FAME: Dictionary = {"glowing": 3, "fair": 1, "scathing": -3}
const FAE_FROM_HOUR: int = 18       # the fae arrive from dusk
const FAE_GUESTS: int = 6           # how many come
const FAE_NIGHT_FAME: int = 2       # for delighting every one of them

# ---------------------------------------------------------------------
# FAME
# Fame doesn't come from single guests. It comes from:
#   * the daily review: what share of the day's guests left happy
#   * one-time milestones
#   * banquet results
# ---------------------------------------------------------------------
# [share of happy guests needed, fame, review name]. The first row that
# matches is used. Fame-earning reviews also need REVIEW_MIN_SERVED
# guests, so a tiny day can't earn them.
const REVIEWS: Array = [
	[0.9, 2, "Glowing"],
	[0.75, 1, "Good"],
	[0.5, 0, "Mixed"],
	[0.25, -1, "Poor"],
	[0.0, -2, "Terrible"],
]
const REVIEW_MIN_SERVED: int = 8

# Banquet result: everyone happy / at least half / fewer than half.
const BANQUET_FAME: Dictionary = {"triumph": 3, "good": 1, "poor": -2}

# Each one awards fame once, the first time `stat` reaches `goal`.
const MILESTONES: Array = [
	{"id": "served_25", "stat": "served", "goal": 25, "fame": 1, "text": "Serve 25 guests"},
	{"id": "served_100", "stat": "served", "goal": 100, "fame": 3, "text": "Serve 100 guests"},
	{"id": "served_250", "stat": "served", "goal": 250, "fame": 5, "text": "Serve 250 guests"},
	{"id": "served_500", "stat": "served", "goal": 500, "fame": 5, "text": "Serve 500 guests"},
	{"id": "perfect_1", "stat": "perfect_days", "goal": 1, "fame": 2, "text": "Have a perfect day"},
	{"id": "perfect_10", "stat": "perfect_days", "goal": 10, "fame": 5, "text": "Have 10 perfect days"},
	{"id": "recipes_3", "stat": "recipes_learned", "goal": 3, "fame": 2, "text": "Learn 3 new recipes"},
	{"id": "recipes_6", "stat": "recipes_learned", "goal": 6, "fame": 4, "text": "Learn every recipe"},
	{"id": "expand_1", "stat": "expansions", "goal": 1, "fame": 3, "text": "Expand the tavern"},
	{"id": "expand_4", "stat": "expansions", "goal": 4, "fame": 5, "text": "Build the full-size tavern"},
	{"id": "triumph_1", "stat": "triumphs", "goal": 1, "fame": 3, "text": "Host a triumphant banquet"},
	{"id": "grand_hall", "stat": "moved", "goal": 1, "fame": 5, "text": "Move to the Grand Hall"},
]

# [fame needed, title]. Your rank is the last one you've reached.
const RANKS: Array = [
	[0, "Unknown"],
	[10, "Local Haunt"],
	[25, "Town Favorite"],
	[55, "Talk of the Realm"],
	[90, "Famed Hall"],
	[140, "Legendary"],
]

# Making the tavern bigger, one step at a time. Each step's quest has to
# be done before you can pay for it. cols/rows = floor size afterwards.
const EXPANSIONS: Array = [
	{"cols": 10, "rows": 10, "cost": 800, "stat": "served", "goal": 60,
		"title": "Room to Grow", "task": "Serve 60 guests"},
	{"cols": 10, "rows": 12, "cost": 1800, "stat": "best_fame", "goal": 30,
		"title": "Talk of the Town", "task": "Reach 30 fame"},
	{"cols": 12, "rows": 12, "cost": 3000, "stat": "nobles", "goal": 15,
		"title": "Fit for Nobles", "task": "Serve 15 nobles"},
	{"cols": 12, "rows": 14, "cost": 4500, "stat": "perfect_days", "goal": 2,
		"title": "The Grand Hall", "task": "Have 2 perfect days (no walk-outs, 20+ guests)"},
]

# THE GRAND HALL: once the tavern is Legendary and fully expanded, the
# Dragon can move to a grand hall in the capital. Fame, recipes, stats
# and staff come along; the furniture stays behind. The hall starts at
# cols x rows and has expansions of its own (HALL_EXPANSIONS). Their
# quests count only what happens in the hall ("hall_served" etc.).
const GRAND_HALL: Dictionary = {"cost": 15000, "fame": 140, "cols": 16, "rows": 16}
const HALL_PRICE_BONUS: float = 0.25   # city guests pay 25% more
const HALL_EXPANSIONS: Array = [
	{"cols": 18, "rows": 18, "cost": 6000, "stat": "hall_served", "goal": 300,
		"title": "A Packed House", "task": "Serve 300 guests in the Grand Hall"},
	{"cols": 20, "rows": 20, "cost": 9000, "stat": "hall_nobles", "goal": 20,
		"title": "The Court's Favorite", "task": "Serve 20 nobles in the Grand Hall"},
	{"cols": 22, "rows": 22, "cost": 13000, "stat": "hall_perfect_days", "goal": 3,
		"title": "Flawless Service", "task": "Have 3 perfect days in the Grand Hall"},
	{"cols": 24, "rows": 24, "cost": 18000, "stat": "hall_served", "goal": 1500,
		"title": "Talk of the Capital", "task": "Serve 1500 guests in the Grand Hall"},
]
# Stats that also get a "hall_" count while you're in the Grand Hall.
const HALL_STATS: Array[String] = ["served", "nobles", "perfect_days"]

# ---------------------------------------------------------------------
# GAME STATE
# ---------------------------------------------------------------------
var gold: int = STARTING_GOLD
var fame: int = 0
var day: int = 0          # becomes 1 when the first day opens
var is_open: bool = false
var minutes_since_open: float = 0.0
var _last_minute_shown: int = -1
var _rush_name: String = ""

# Recipe IDs you know, and the ones on today's menu (always some of
# the known ones). .duplicate() makes a copy so the constant stays as-is.
var known_recipes: Array[String] = STARTER_RECIPES.duplicate()
var menu: Array[String] = STARTER_RECIPES.duplicate()

# Lifetime counters that quests and patron ideas check, e.g.
# {"served": 41, "nobles": 3, "dish:stew": 9, "perfect_days": 1, "best_fame": 27}
var stats: Dictionary = {}

var expansions_built: int = 0   # in the current location
var location: String = "tavern"   # "tavern" or "grand_hall"

# Today's job applicants: role ("cook"/"waiter") -> Array of profiles.
# New faces every day.
var _applicants: Dictionary = {}
var _applicants_day: int = -1

# Stats for the end-of-day summary (reset every morning).
var today_income: int = 0
var today_ingredients: int = 0   # gold owed tonight for dishes cooked today
var today_served: int = 0
var today_walkouts: int = 0
var today_turned_away: int = 0   # arrived but found no free table
var today_nobles_served: int = 0
var today_disappointed: int = 0   # left because nothing on the menu suited them
var today_unlocked: Array[String] = []   # recipes earned today
var today_news: Array[String] = []       # other news for the day summary
var banquet_today: bool = false
var today_event: String = ""             # "" or a key of EVENTS
var force_event: String = ""             # for testing: the next day's event
var today_fae: int = 0                   # fae guests who came tonight
var today_fae_happy: int = 0             # ...and left happy
var today_banquet_nobles: int = 0       # nobles who came to today's banquet

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

	var rush: String = current_rush().get("name", "")
	if rush != _rush_name:
		_rush_name = rush
		rush_changed.emit(rush)

	if total_minutes >= CLOSE_HOUR * 60:
		is_open = false
		if _rush_name != "":
			_rush_name = ""
			rush_changed.emit("")
		shop_closed.emit(day)


func open_shop(banquet: bool = false) -> void:
	day += 1
	banquet_today = banquet
	today_banquet_nobles = 0
	if banquet:
		stats["last_banquet_day"] = day
	is_open = true
	add_stat("days")
	minutes_since_open = 0.0
	_last_minute_shown = -1
	today_income = 0
	today_ingredients = 0
	today_served = 0
	today_walkouts = 0
	today_turned_away = 0
	today_nobles_served = 0
	today_disappointed = 0
	today_unlocked.clear()
	today_news.clear()
	today_fae = 0
	today_fae_happy = 0
	today_event = _roll_event(banquet)
	shop_opened.emit(day)


# Today's special event, or "" (never on the first two days or a banquet day).
func _roll_event(banquet: bool) -> String:
	if force_event != "":
		var forced: String = force_event
		force_event = ""
		return forced
	if banquet or day < 3 or randf() >= EVENT_CHANCE:
		return ""
	var total: int = 0
	for id in EVENTS:
		if fame >= EVENTS[id]["fame"]:
			total += EVENTS[id]["weight"]
	var roll: int = randi() % total
	for id in EVENTS:
		if fame >= EVENTS[id]["fame"]:
			roll -= EVENTS[id]["weight"]
			if roll < 0:
				return id
	return ""


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
	today_nobles_served = 0
	today_disappointed = 0
	today_unlocked.clear()
	today_news.clear()
	banquet_today = false
	today_banquet_nobles = 0
	known_recipes = STARTER_RECIPES.duplicate()
	menu = STARTER_RECIPES.duplicate()
	stats = {}
	expansions_built = 0
	location = "tavern"
	_applicants_day = -1
	order_requests.clear()
	order_queue.clear()


# ---------------------------------------------------------------------
# SAVING
# The game saves between days only. Quitting mid-day means replaying
# that day from the start, which keeps saves simple: no half-cooked
# dishes or guests mid-walk to store.
#
# The save is a JSON text file, so you can open it and read it.
# main.gd supplies the furniture, door and staff (a list of profiles);
# we add gold, fame, day, recipes, stats and expansions.
# ---------------------------------------------------------------------
func save_game(layout: Array, door: Array, kitchen: Array, staff: Array, decor: Dictionary = {}) -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"day": day,
		"gold": gold,
		"fame": fame,
		"furniture": layout,
		"door": door,
		"kitchen": kitchen,
		"expansions": expansions_built,
		"location": location,
		"decor": decor,
		"staff": staff,
		"recipes": known_recipes,
		"menu": menu,
		"stats": stats,
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
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting a new game.")
		return {}
	# JSON stores every number as a decimal, so turn them back into ints.
	var version: int = int(parsed.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		push_warning("Save file from an unknown version, starting a new game.")
		return {}
	day = int(parsed.get("day", 0))
	gold = int(parsed.get("gold", STARTING_GOLD))
	fame = int(parsed.get("fame", 0))
	# Version 1 saves have no recipes, so they get the starter ones.
	_load_recipes(parsed.get("recipes", []), parsed.get("menu", []))
	var saved_stats = parsed.get("stats", {})
	stats = saved_stats if typeof(saved_stats) == TYPE_DICTIONARY else {}
	# Saves from before stats existed: count the fame they already have.
	stats["best_fame"] = maxi(stat("best_fame"), fame)
	# Saves from before the "days" count (a trophy needs it).
	stats["days"] = maxi(stat("days"), day)
	# Saves from before the Grand Hall are in the tavern.
	location = "grand_hall" if parsed.get("location", "") == "grand_hall" else "tavern"
	# Saves from before expansions: the original floor.
	expansions_built = clampi(int(parsed.get("expansions", 0)), 0, expansion_list().size())
	if version < 5:
		# Older saves already earned fame the old way, so milestones they've
		# passed are marked done without paying out again.
		stats["recipes_learned"] = known_recipes.size() - STARTER_RECIPES.size()
		stats["expansions"] = expansions_built
		for milestone in MILESTONES:
			if stat(milestone["stat"]) >= milestone["goal"]:
				stats["m:" + milestone["id"]] = 1
		stats["best_rank"] = rank_index(fame)
	gold_changed.emit(gold)
	fame_changed.emit(fame)
	return parsed


# Only accept recipe IDs that really exist, in case the file was edited.
func _load_recipes(saved_known: Array, saved_menu: Array) -> void:
	known_recipes = STARTER_RECIPES.duplicate()
	for id in saved_known:
		if RECIPES.has(id) and not known_recipes.has(id):
			known_recipes.append(id)
	menu.clear()
	for id in saved_menu:
		if known_recipes.has(id) and not menu.has(id) and menu.size() < MAX_MENU:
			menu.append(id)
	if menu.is_empty():
		menu = STARTER_RECIPES.duplicate()


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
# A Hearth started cooking this dish.
func buy_ingredients(order: Dictionary) -> void:
	today_ingredients += order.get("cost", 0)


func pay_wages(amount: int) -> void:
	gold -= amount
	gold_changed.emit(gold)


func daily_wages(staff: Array) -> int:
	var total: int = 0
	for profile in staff:
		total += StaffProfiles.wage(profile)
	return total


# ---------------------------------------------------------------------
# HIRING
# ---------------------------------------------------------------------
# Today's applicants for a role. A fresh set each day.
func applicants(role: String) -> Array:
	if _applicants_day != day:
		_applicants_day = day
		_applicants = {}
		for job in StaffProfiles.ROLES:
			var people: Array = []
			for i in APPLICANTS_PER_ROLE:
				people.append(StaffProfiles.random_profile(job))
			_applicants[job] = people
	return _applicants[role]


# Hires an applicant: they leave the list and get an ID of their own.
func take_applicant(role: String, index: int) -> Dictionary:
	var people: Array = applicants(role)
	if index < 0 or index >= people.size():
		return {}
	var profile: Dictionary = people.pop_at(index)
	profile["uid"] = new_staff_uid()
	return profile


# A number no other staff member has, so you can pick who to let go.
func new_staff_uid() -> int:
	add_stat("staff_uid")
	return stat("staff_uid")


# A Waiter asks for the next guest who wants to order (or null).
func next_order_request() -> Customer:
	while not order_requests.is_empty():
		var c: Customer = order_requests.pop_front()
		if is_instance_valid(c) and c.state == Customer.State.WAITING_FOR_WAITER:
			return c
	return null


# ---------------------------------------------------------------------
# STATS, QUESTS AND PATRON IDEAS
# Recipes can't be bought. Each locked recipe has an "unlock" goal on a
# lifetime stat; check_unlocks() hands out every recipe whose goal is met.
# ---------------------------------------------------------------------
func stat(key: String) -> int:
	return int(stats.get(key, 0))   # int() because JSON loads numbers as decimals


func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = stat(key) + amount
	if in_hall() and key in HALL_STATS:
		stats["hall_" + key] = stat("hall_" + key) + amount


# Called when a guest pays and leaves happy.
func record_served(order_id: String, noble: bool, guest_type: String = "") -> void:
	add_stat("served")
	add_stat("dish:" + order_id)
	if guest_type != "":
		add_stat("guest:" + guest_type)
	if noble:
		add_stat("nobles")


# Called once the last guest has left for the night.
func finish_day() -> void:
	if today_walkouts == 0 and today_served >= PERFECT_DAY_GUESTS:
		add_stat("perfect_days")


# How far along a locked recipe's quest or patron idea is (capped at its goal).
func unlock_progress(id: String) -> int:
	var unlock: Dictionary = RECIPES[id]["unlock"]
	return mini(stat(unlock["stat"]), unlock["goal"])


# Unlocks every recipe whose goal has been reached. Returns their IDs so
# main.gd can announce them.
# Wall decorations earned so far (marked once in stats, so a trophy stays
# earned). Returns the ones just earned, so main.gd can announce them.
func check_trophies() -> Array[String]:
	var earned: Array[String] = []
	for id in DECOR:
		var info: Dictionary = DECOR[id]
		if info["where"] != "wall" or stat("trophy:" + id) > 0:
			continue
		if stat(info["stat"]) >= info["goal"]:
			stats["trophy:" + id] = 1
			earned.append(id)
	return earned


func has_trophy(id: String) -> bool:
	return stat("trophy:" + id) > 0


# Can this decoration be placed? Floor pieces may need a rank first.
func decor_available(id: String) -> bool:
	var info: Dictionary = DECOR[id]
	if info["where"] == "wall":
		return has_trophy(id)
	return stat("best_fame") >= info.get("fame", 0)


func check_unlocks() -> Array[String]:
	var unlocked: Array[String] = []
	for id in RECIPES:
		var recipe: Dictionary = RECIPES[id]
		if known_recipes.has(id) or not recipe.has("unlock"):
			continue
		if stat(recipe["unlock"]["stat"]) >= recipe["unlock"]["goal"]:
			known_recipes.append(id)
			# Straight onto the menu if there's a free slot.
			if menu.size() < MAX_MENU:
				menu.append(id)
			unlocked.append(id)
			today_unlocked.append(id)
			add_stat("recipes_learned")
	if not unlocked.is_empty():
		recipes_changed.emit()
	return unlocked


# ---------------------------------------------------------------------
# EXPANSIONS
# ---------------------------------------------------------------------
func in_hall() -> bool:
	return location == "grand_hall"


# This location's expansions.
func expansion_list() -> Array:
	return HALL_EXPANSIONS if in_hall() else EXPANSIONS


# The floor size for the expansions built so far.
func floor_size() -> Vector2i:
	if expansions_built == 0:
		if in_hall():
			return Vector2i(GRAND_HALL["cols"], GRAND_HALL["rows"])
		return Vector2i(TavernGrid.START_COLS, TavernGrid.START_ROWS)
	var last: Dictionary = expansion_list()[expansions_built - 1]
	return Vector2i(last["cols"], last["rows"])


# The next expansion, or {} once this place is as big as it gets.
func next_expansion() -> Dictionary:
	if expansions_built >= expansion_list().size():
		return {}
	return expansion_list()[expansions_built]


# The Grand Hall is offered once the tavern can't grow any more.
func move_offered() -> bool:
	return not in_hall() and expansions_built >= EXPANSIONS.size()


# Why you can't move yet ("" if you can).
func move_blocker() -> String:
	if fame < GRAND_HALL["fame"]:
		return "You need to be Legendary (%d fame) first." % GRAND_HALL["fame"]
	if gold < GRAND_HALL["cost"]:
		return "Not enough gold (%dg)." % GRAND_HALL["cost"]
	return ""


# Pays for the Grand Hall and moves in. main.gd sets up the new floor.
func move_to_hall() -> bool:
	if not move_offered() or move_blocker() != "" or not try_spend(GRAND_HALL["cost"]):
		return false
	location = "grand_hall"
	expansions_built = 0
	add_stat("moved")
	return true


func expansion_progress() -> int:
	var next: Dictionary = next_expansion()
	if next.is_empty():
		return 0
	return mini(stat(next["stat"]), next["goal"])


func expansion_quest_done() -> bool:
	var next: Dictionary = next_expansion()
	return not next.is_empty() and stat(next["stat"]) >= next["goal"]


# Returns the quest title the first time the next expansion's quest is
# done (so it's announced once), otherwise "".
func check_expansion_ready() -> String:
	if not expansion_quest_done() or stat("expansion_announced") > expansions_built:
		return ""
	stats["expansion_announced"] = expansions_built + 1
	return next_expansion()["title"]


# ---------------------------------------------------------------------
# THE MENU
# Returns a message for the HUD to show ("" = nothing to say).
# ---------------------------------------------------------------------
func toggle_menu(id: String) -> String:
	if menu.has(id):
		if menu.size() <= 1:
			return "Keep at least one dish on the menu."
		menu.erase(id)
	else:
		if menu.size() >= MAX_MENU:
			return "The menu is full. Take a dish off first."
		menu.append(id)
	recipes_changed.emit()
	return ""


# Does today's menu have anything for this kind of guest?
func menu_suits(noble: bool) -> bool:
	return not pick_order("noble" if noble else "farmer").is_empty()


# A guest chooses a dish from today's menu, depending on their type
# (see guest_types.gd). Empty if nothing suits them.
#   noble       tier 3 only
#   merchant    tier 2 only
#   guard       Dragon Ale if it's on, otherwise anything common
#   regular     their favorite dish, or nothing
#   others      any tier 1-2 dish
func pick_order(guest_type: String) -> Dictionary:
	var choices: Array[String] = []
	for id in menu:
		var tier: int = RECIPES[id]["tier"]
		match guest_type:
			"noble":
				if tier == 3: choices.append(id)
			"merchant":
				if tier == 2: choices.append(id)
			"regular":
				if id == regular_favorite(): choices.append(id)
			"elf":
				if id == "wine": choices.append(id)
			"fae":
				if tier < 3 or id == "wine": choices.append(id)
			_:
				if tier < 3: choices.append(id)
	if guest_type == "guard" and choices.has("ale"):
		choices = ["ale"]
	if guest_type == "fae" and choices.has("mead"):
		choices.append_array(["mead", "mead"])   # the fae love honey mead
	if choices.is_empty():
		return {}
	var pick: String = choices.pick_random()
	# Add the ID so the guest can report which dish they ate.
	return RECIPES[pick].merged({"id": pick})


# The Old Regular's favorite: chosen on their first visit from the common
# dishes you know, then remembered forever (it's saved with the stats).
func regular_favorite() -> String:
	if not stats.has("regular_favorite"):
		var common: Array = known_recipes.filter(func(id): return RECIPES[id]["tier"] < 3)
		stats["regular_favorite"] = common.pick_random()
	return str(stats["regular_favorite"])


# ---------------------------------------------------------------------
# NOBLE BANQUETS
# ---------------------------------------------------------------------
# Unlocked for good once you've ever reached NOBLE_FAME.
func banquet_unlocked() -> bool:
	return stat("best_fame") >= NOBLE_FAME


# The first day you can host the next banquet.
func next_banquet_day() -> int:
	if stat("last_banquet_day") == 0:
		return 1
	return stat("last_banquet_day") + BANQUET_EVERY


# Why you can't host a banquet tomorrow, or "" if you can.
func banquet_blocker() -> String:
	if not banquet_unlocked():
		return "Reach %d fame to invite nobles" % NOBLE_FAME
	if day + 1 < next_banquet_day():
		return "Next banquet: Day %d" % next_banquet_day()
	if gold < BANQUET_COST:
		return "Not enough gold (%dg)" % BANQUET_COST
	return ""


# 3 nobles at 25 fame, one more for every 15 fame after that, up to 8.
func banquet_party_size() -> int:
	return mini(8, 3 + floori(maxi(0, fame - NOBLE_FAME) / 15.0))


# Returns true the first time banquets become available (to announce it once).
func check_banquet_unlock() -> bool:
	if not banquet_unlocked() or stat("banquet_announced") > 0:
		return false
	stats["banquet_announced"] = 1
	return true


func change_fame(amount: int) -> void:
	fame = max(0, fame + amount)   # fame never goes below zero
	stats["best_fame"] = maxi(stat("best_fame"), fame)
	fame_changed.emit(fame)


# The rush happening right now, or {} if none.
func current_rush() -> Dictionary:
	var hour: float = OPEN_HOUR + minutes_since_open / 60.0
	for rush in RUSHES:
		if hour >= rush["start"] and hour < rush["end"]:
			return rush
	return {}


# How busy it is right now: 1 is normal, 2 means guests come twice as often.
func busyness() -> float:
	var busy: float = 1.0
	var rush: Dictionary = current_rush()
	if not rush.is_empty():
		busy = rush["busy"]
	elif OPEN_HOUR + minutes_since_open / 60.0 < QUIET_UNTIL:
		busy = QUIET_BUSY
	match today_event:
		"festival": busy *= 2.0
		"rain": busy *= RAIN_BUSY
	return busy


# More fame = guests arrive more often (6.5 seconds at 0 fame, down to
# 2.5 at 100), and more often still during rushes. Turning guests away spoils
# the daily review, so build more Tables and hire more staff as fame grows.
# In the Grand Hall the crowds grow with the hall instead: every
# expansion brings guests faster, down to about one a second.
func get_spawn_interval() -> float:
	if in_hall():
		return max(1.0, 2.6 - 0.35 * expansions_built) / busyness()
	return max(2.5, 6.5 - fame * 0.04) / busyness()


# ---------------------------------------------------------------------
# REVIEWS, MILESTONES AND RANKS
# ---------------------------------------------------------------------
# Today's review: {"happy": share of happy guests (0-1), "fame": change,
# "name": "Glowing" etc.}. Everyone who left unhappy or never got a seat
# counts against it.
func daily_review() -> Dictionary:
	var unhappy: int = today_walkouts + today_disappointed + today_turned_away
	if today_event == "festival":
		unhappy -= today_turned_away   # festival crowds just move on to the next stall
	var total: int = today_served + unhappy
	if total == 0:
		return {"happy": 0.0, "fame": 0, "name": "No"}
	var happy: float = float(today_served) / total
	for row in REVIEWS:
		if happy >= row[0]:
			# A tiny day can't earn a glowing or good review.
			if row[1] > 0 and today_served < REVIEW_MIN_SERVED:
				continue
			return {"happy": happy, "fame": row[1], "name": row[2]}
	return {"happy": happy, "fame": -2, "name": "Terrible"}


# Awards every milestone just reached. Returns them so main.gd can
# announce them.
func check_milestones() -> Array:
	var reached: Array = []
	for milestone in MILESTONES:
		if stat("m:" + milestone["id"]) > 0 or stat(milestone["stat"]) < milestone["goal"]:
			continue
		stats["m:" + milestone["id"]] = 1
		change_fame(milestone["fame"])
		reached.append(milestone)
	return reached


func milestone_done(milestone: Dictionary) -> bool:
	return stat("m:" + milestone["id"]) > 0


# Position in RANKS for a fame value.
func rank_index(value: int) -> int:
	var index: int = 0
	for i in RANKS.size():
		if value >= RANKS[i][0]:
			index = i
	return index


func rank_name() -> String:
	return RANKS[rank_index(fame)][1]


# Returns the new rank's title the first time you reach it, otherwise "".
func check_rank_up() -> String:
	var index: int = rank_index(fame)
	if index <= stat("best_rank"):
		return ""
	stats["best_rank"] = index
	return RANKS[index][1]
