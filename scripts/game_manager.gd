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
# version 6 named staff with types and looks. Older saves still load.
const SAVE_VERSION: int = 6

# Everything the player can build. The key ("table") is the ID the
# other scripts use; the inner Dictionary holds its details.
const FURNITURE: Dictionary = {
	"table": {"name": "Table", "cost": 50, "color": Color(0.55, 0.36, 0.2)},
	"kitchen": {"name": "Hearth", "cost": 120, "color": Color(0.7, 0.25, 0.15)},
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
const RECIPES: Dictionary = {
	"ale":     {"name": "Dragon Ale",       "price": 12, "cook_time": 2.5,  "tier": 1},
	"stew":    {"name": "Mushroom Stew",    "price": 18, "cook_time": 4.0,  "tier": 1},
	"mead":    {"name": "Honey Mead",       "price": 16, "cook_time": 3.0,  "tier": 1,
			"unlock": {"by": "patron", "stat": "served", "goal": 20,
				"task": "A regular may share it once you've served 20 guests",
				"who": "A regular"}},
	"boar":    {"name": "Roast Boar",       "price": 28, "cook_time": 6.0,  "tier": 2},
	"cheese":  {"name": "Troll Cheese",     "price": 24, "cook_time": 4.0,  "tier": 2,
			"unlock": {"by": "quest", "stat": "dish:stew", "goal": 12,
				"title": "The Bridge Troll", "task": "Serve 12 Mushroom Stews"}},
	"wings":   {"name": "Wyvern Wings",     "price": 34, "cook_time": 6.5,  "tier": 2,
			"unlock": {"by": "quest", "stat": "perfect_days", "goal": 1,
				"title": "Hunter's Challenge", "task": "Finish a day with no walk-outs and 20+ guests served"}},
	"wine":    {"name": "Elven Wine",       "price": 45, "cook_time": 5.0,  "tier": 3,
			"unlock": {"by": "patron", "stat": "best_fame", "goal": 25,
				"task": "A noble's steward may share it when your fame reaches 25",
				"who": "A noble's steward"}},
	"phoenix": {"name": "Phoenix Roast",    "price": 60, "cook_time": 9.0,  "tier": 3,
			"unlock": {"by": "quest", "stat": "nobles", "goal": 8,
				"title": "Noble Approval", "task": "Serve 8 nobles"}},
	"feast":   {"name": "Dragonfire Feast", "price": 85, "cook_time": 12.0, "tier": 3,
			"unlock": {"by": "quest", "stat": "dish:phoenix", "goal": 10,
				"title": "A Feast for a Dragon", "task": "Serve 10 Phoenix Roasts"}},
}
const STARTER_RECIPES: Array[String] = ["ale", "stew", "boar"]
const MAX_MENU: int = 4          # dishes on the menu at once
# NOBLE BANQUETS: nobles only come when invited. At NOBLE_FAME you can
# host a banquet (from the Open Day button): pay BANQUET_COST and a party
# of nobles arrives between BANQUET_START and BANQUET_END (24h clock).
const NOBLE_FAME: int = 25
const BANQUET_COST: int = 150
const BANQUET_EVERY: int = 3     # days between banquets
const BANQUET_START: int = 12
const BANQUET_END: int = 15
const NOBLE_TIP: float = 0.5        # nobles pay 50% on top
const PERFECT_DAY_GUESTS: int = 20   # guests needed for a "perfect day"

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
	{"cols": 10, "rows": 10, "cost": 300, "stat": "served", "goal": 60,
		"title": "Room to Grow", "task": "Serve 60 guests"},
	{"cols": 10, "rows": 12, "cost": 500, "stat": "best_fame", "goal": 30,
		"title": "Talk of the Town", "task": "Reach 30 fame"},
	{"cols": 12, "rows": 12, "cost": 800, "stat": "nobles", "goal": 15,
		"title": "Fit for Nobles", "task": "Serve 15 nobles"},
	{"cols": 12, "rows": 14, "cost": 1200, "stat": "perfect_days", "goal": 2,
		"title": "The Grand Hall", "task": "Have 2 perfect days (no walk-outs, 20+ guests)"},
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

# Recipe IDs you know, and the ones on today's menu (always some of
# the known ones). .duplicate() makes a copy so the constant stays as-is.
var known_recipes: Array[String] = STARTER_RECIPES.duplicate()
var menu: Array[String] = STARTER_RECIPES.duplicate()

# Lifetime counters that quests and patron ideas check, e.g.
# {"served": 41, "nobles": 3, "dish:stew": 9, "perfect_days": 1, "best_fame": 27}
var stats: Dictionary = {}

var expansions_built: int = 0

# Today's job applicants: role ("cook"/"waiter") -> Array of profiles.
# New faces every day.
var _applicants: Dictionary = {}
var _applicants_day: int = -1

# Stats for the end-of-day summary (reset every morning).
var today_income: int = 0
var today_served: int = 0
var today_walkouts: int = 0
var today_turned_away: int = 0   # arrived but found no free table
var today_nobles_served: int = 0
var today_disappointed: int = 0   # left because nothing on the menu suited them
var today_unlocked: Array[String] = []   # recipes earned today
var today_news: Array[String] = []       # other news for the day summary
var banquet_today: bool = false
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

	if total_minutes >= CLOSE_HOUR * 60:
		is_open = false
		shop_closed.emit(day)


func open_shop(banquet: bool = false) -> void:
	day += 1
	banquet_today = banquet
	today_banquet_nobles = 0
	if banquet:
		stats["last_banquet_day"] = day
	is_open = true
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
func save_game(layout: Array, door: Array, staff: Array) -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"day": day,
		"gold": gold,
		"fame": fame,
		"furniture": layout,
		"door": door,
		"expansions": expansions_built,
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
	# Saves from before expansions: the original floor.
	expansions_built = clampi(int(parsed.get("expansions", 0)), 0, EXPANSIONS.size())
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
		for job in ["cook", "waiter"]:
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


# Called when a guest pays and leaves happy.
func record_served(order_id: String, noble: bool) -> void:
	add_stat("served")
	add_stat("dish:" + order_id)
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
# The floor size for the expansions built so far.
func floor_size() -> Vector2i:
	if expansions_built == 0:
		return Vector2i(TavernGrid.START_COLS, TavernGrid.START_ROWS)
	var last: Dictionary = EXPANSIONS[expansions_built - 1]
	return Vector2i(last["cols"], last["rows"])


# The next expansion, or {} once the tavern is as big as it gets.
func next_expansion() -> Dictionary:
	if expansions_built >= EXPANSIONS.size():
		return {}
	return EXPANSIONS[expansions_built]


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
	return not pick_order(noble).is_empty()


# A guest chooses a dish from today's menu. Nobles only order tier 3
# dishes; common folk only order tier 1-2. Empty if nothing suits them.
func pick_order(noble: bool) -> Dictionary:
	var choices: Array = []
	for id in menu:
		var recipe: Dictionary = RECIPES[id]
		if (recipe["tier"] == 3) == noble:
			# Add the ID so the guest can report which dish they ate.
			choices.append(recipe.merged({"id": id}))
	if choices.is_empty():
		return {}
	return choices.pick_random()


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


# More fame = guests arrive more often (6 seconds at 0 fame, down to 1.5
# at 90). Turning guests away spoils the daily review, so build more
# Tables as fame grows.
func get_spawn_interval() -> float:
	return max(1.5, 6.0 - fame * 0.05)


# ---------------------------------------------------------------------
# REVIEWS, MILESTONES AND RANKS
# ---------------------------------------------------------------------
# Today's review: {"happy": share of happy guests (0-1), "fame": change,
# "name": "Glowing" etc.}. Everyone who left unhappy or never got a seat
# counts against it.
func daily_review() -> Dictionary:
	var unhappy: int = today_walkouts + today_disappointed + today_turned_away
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
