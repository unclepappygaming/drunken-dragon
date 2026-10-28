# =====================================================================
# main.gd  —  the "director". Attached to the root Main node.
#
# It doesn't do much itself; it wires the other pieces together:
#   * spawns guests on a timer, seating them or lining them up outside
#   * moves the waiting line along whenever a table frees up
#   * hires and lets go of staff (only between days)
#   * tells the grid which build tool the HUD selected
#   * runs Noble Banquets: invited nobles arrive at midday
#   * frees tables and records stats when guests leave
#   * gives fame for the daily review, banquets and milestones
#   * announces recipes, expansions, milestones and new ranks
#   * builds expansions and keeps the camera fitted to the floor
#   * shows the end-of-day summary once the last guest is gone
#   * loads the saved game at startup and saves between days
# =====================================================================
extends Node2D

# preload() loads the customer scene once, when the game starts.
# A PackedScene is a "blueprint"; instantiate() stamps out a new copy.
const CUSTOMER_SCENE: PackedScene = preload("res://scenes/customer.tscn")
const COOK_SCENE: PackedScene = preload("res://scenes/cook.tscn")
const WAITER_SCENE: PackedScene = preload("res://scenes/waiter.tscn")
const MAX_STAFF: int = 6   # per role
const MAX_LINE: int = 5    # guests who will wait outside for a table
const LINE_GAP: float = 46.0   # pixels between people in the line

# @onready waits until this node and its children exist, then fills in
# the variable. Without it, $TavernGrid would be looked up too early
# (before the children are ready) and come back empty.
# $TavernGrid is shorthand for get_node("TavernGrid") — a child by name.
@onready var grid: TavernGrid = $TavernGrid
@onready var customers_node: Node2D = $Customers
@onready var staff_node: Node2D = $Staff
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hud: TavernHUD = $HUD
@onready var camera: TavernCamera = $Camera

var _waiting_for_last_guests: bool = false
# Guests waiting outside for a table, first in line first.
var _line: Array[Customer] = []
# On a banquet day: when each noble arrives, in game minutes after opening.
var _noble_arrivals: Array[float] = []


func _ready() -> void:
	hud.build_selected.connect(_on_build_selected)
	hud.day_start_requested.connect(_on_day_start_requested)
	hud.hire_requested.connect(_on_hire_requested)
	hud.fire_requested.connect(_on_fire_requested)
	hud.staff_list_requested.connect(_show_staff_list)
	hud.new_game_requested.connect(_on_new_game_requested)
	hud.expand_requested.connect(_on_expand_requested)
	# You can connect a signal straight to another node's function.
	grid.build_message.connect(hud.show_message)
	camera.tapped.connect(grid.handle_tap)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.shop_closed.connect(_on_shop_closed)
	# Building or selling between days changes the save, so save again.
	grid.layout_changed.connect(_save_if_closed)
	GameManager.recipes_changed.connect(_save_if_closed)
	# A newly built table can seat whoever is first in line.
	grid.layout_changed.connect(_seat_from_line)

	var save: Dictionary = GameManager.load_game()
	if save.is_empty():
		# New game: one cook and one waiter. They walk in through the door.
		_hire(StaffProfiles.random_profile("cook"))
		_hire(StaffProfiles.random_profile("waiter"))
		hud.show_summary(
			"Welcome to\nThe Drunken Dragon!\n\nGuests sit at Tables. Waiters take orders and carry food; Cooks work the Hearths. Staff get paid every night.\n\nHappy patrons share recipe ideas, and quests teach you more. See Recipes.\n\nDrag to look around and pinch to zoom.")
	else:
		# Size and door first, so the furniture lands on the right floor.
		var size: Vector2i = GameManager.floor_size()
		grid.resize(size.x, size.y, false)
		var door = save.get("door", [])
		if typeof(door) == TYPE_ARRAY and door.size() == 2:
			grid.set_door(str(door[0]), int(door[1]))
		grid.load_layout(save.get("furniture", []))
		# clampi keeps a number within limits, in case the file was edited.
		_load_staff(save)
		# Day 0 means they built or hired before ever opening.
		var progress: String = "Day %d is done." % GameManager.day if GameManager.day > 0 \
				else "Your tavern is ready for its first day."
		hud.show_summary(
			"Welcome back to\nThe Drunken Dragon!\n\n%s\nGold: %d\nFame: %d" % [progress, GameManager.gold, GameManager.fame],
			true)
	_update_staff_display()
	_fit_camera()
	hud.set_day_button("Open\nDay %d" % (GameManager.day + 1), true)


func _fit_camera() -> void:
	camera.bounds = grid.floor_rect()
	# grow() leaves room around the walls for the doorstep and the line.
	camera.frame(grid.play_rect().grow(45), TavernHUD.TOP_HEIGHT, TavernHUD.BAR_HEIGHT)


func _process(_delta: float) -> void:
	# Banquet nobles arrive on their own schedule, separate from the
	# spawn timer that brings everyone else.
	if GameManager.is_open and not _noble_arrivals.is_empty() \
			and GameManager.minutes_since_open >= _noble_arrivals[0]:
		_noble_arrivals.pop_front()
		_noble_arrives()

	# After closing, wait until every guest has walked out the door.
	# get_nodes_in_group asks for every node tagged "customers".
	if _waiting_for_last_guests and get_tree().get_nodes_in_group("customers").is_empty():
		_waiting_for_last_guests = false
		_show_day_summary()


func _on_day_start_requested(banquet: bool) -> void:
	if GameManager.is_open or _waiting_for_last_guests:
		return
	if banquet:
		var blocker: String = GameManager.banquet_blocker()
		if blocker != "" or not GameManager.try_spend(GameManager.BANQUET_COST):
			hud.show_message(blocker if blocker != "" else "Not enough gold!")
			return
	GameManager.open_shop(banquet)
	hud.set_day_button("Open", false)
	spawn_timer.start(2.0)   # first guest arrives 2 seconds after opening
	_noble_arrivals.clear()
	if banquet:
		# Spread the party evenly between BANQUET_START and BANQUET_END.
		var party: int = GameManager.banquet_party_size()
		var start: float = (GameManager.BANQUET_START - GameManager.OPEN_HOUR) * 60.0
		var length: float = (GameManager.BANQUET_END - GameManager.BANQUET_START) * 60.0
		for i in party:
			_noble_arrivals.append(start + length * i / party)
		hud.show_message("Banquet day! %d nobles will arrive from %d:00." % [party, GameManager.BANQUET_START], 4.0)


func _on_build_selected(type: String) -> void:
	grid.build_type = type


# ---------------------------------------------------------------------
# Guests and the waiting line
# ---------------------------------------------------------------------
func _on_spawn_timer_timeout() -> void:
	var noble: bool = false   # nobles only come to banquets
	var cell: Vector2i = grid.find_free_table()
	# Nobody jumps the line: a free table goes to the line first.
	if cell != TavernGrid.NO_CELL and _line.is_empty():
		var customer: Customer = _spawn_customer(noble)
		_seat(customer, cell)
	elif _line.size() < MAX_LINE:
		var customer: Customer = _spawn_customer(noble)
		_line.append(customer)
		customer.wait_in_line(_line_spot(_line.size() - 1))
	else:
		# Turned-away guests count against today's review, so more fame
		# alone can't outgrow your seating.
		GameManager.today_turned_away += 1
		hud.show_message("The line is full! A guest went elsewhere.")
	# Restart with a fresh interval — higher fame means shorter waits.
	spawn_timer.start(GameManager.get_spawn_interval())


func _spawn_customer(noble: bool) -> Customer:
	# instantiate() creates a brand-new guest from the blueprint...
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	# ...but it isn't in the game until it's added to the scene tree.
	customers_node.add_child(customer)
	customer.setup(grid, noble)
	customer.left_tavern.connect(_on_customer_left)
	return customer


func _seat(customer: Customer, cell: Vector2i) -> void:
	grid.reserve_table(cell, customer)
	customer.take_table(cell)


# An invited noble. Nobles don't queue: they get the next free table,
# and go to the front of the line if there isn't one.
func _noble_arrives() -> void:
	if GameManager.today_banquet_nobles == 0:
		hud.show_message("The nobles are arriving!", 3.0)
	GameManager.today_banquet_nobles += 1
	var noble: Customer = _spawn_customer(true)
	var cell: Vector2i = grid.find_free_table()
	if cell != TavernGrid.NO_CELL:
		_seat(noble, cell)
	else:
		_line.insert(0, noble)
		noble.wait_in_line(_line_spot(0))
		_seat_from_line()   # moves everyone else back a place


# The line runs along the outside wall, starting beside the door.
func _line_spot(place: int) -> Vector2:
	return grid.door_position() + grid.line_direction() * (60.0 + place * LINE_GAP)


# Give free tables to the front of the line, then shuffle everyone up.
func _seat_from_line() -> void:
	while not _line.is_empty():
		var cell: Vector2i = grid.find_free_table()
		if cell == TavernGrid.NO_CELL:
			break
		_seat(_line.pop_front(), cell)
	for i in _line.size():
		_line[i].move_up_in_line(_line_spot(i))


func _on_customer_left(customer: Customer, _happy: bool) -> void:
	grid.release_table(customer.table_cell)
	_line.erase(customer)

	# Single guests don't change fame; they all count toward tonight's
	# review (and nobles toward the banquet result).
	match customer.leave_reason:
		"served":
			GameManager.today_served += 1
			if customer.is_noble:
				GameManager.today_nobles_served += 1
			GameManager.record_served(customer.order["id"], customer.is_noble)
		"impatient":
			GameManager.today_walkouts += 1
		"no_dish":
			GameManager.today_disappointed += 1
		"gave_up_line":
			GameManager.today_turned_away += 1
		# "closed": sent home at closing time, it doesn't count.

	_announce_unlocks(GameManager.check_unlocks(), customer)
	_seat_from_line()


# Tells the player about recipes they just earned. A regular who shares
# an idea says it out loud on the way out.
func _announce_unlocks(ids: Array[String], speaker: Customer) -> void:
	for id in ids:
		var recipe: Dictionary = GameManager.RECIPES[id]
		var unlock: Dictionary = recipe["unlock"]
		if unlock["by"] == "patron":
			hud.show_message("%s shared a recipe: %s!" % [unlock["who"], recipe["name"]], 5.0)
			if speaker != null and unlock["stat"] == "served":
				speaker.say("Try %s!" % recipe["name"])
		else:
			hud.show_message("Quest done: %s! New recipe: %s." % [unlock["title"], recipe["name"]], 5.0)
	var expansion_quest: String = GameManager.check_expansion_ready()
	if expansion_quest != "":
		hud.show_message("Quest done: %s! You can expand the tavern (Build > Expand)." % expansion_quest, 6.0)
		GameManager.today_news.append("You can expand the tavern (Build > Expand).")
	_announce_fame()


# Milestones reached and new ranks. Milestones can give fame, which can
# reach a new rank, which can unlock banquets, so check in that order.
func _announce_fame() -> void:
	for milestone in GameManager.check_milestones():
		hud.show_message("Milestone: %s! +%d fame" % [milestone["text"], milestone["fame"]], 5.0)
		GameManager.today_news.append("Milestone: %s (+%d fame)" % [milestone["text"], milestone["fame"]])
	var rank: String = GameManager.check_rank_up()
	if rank != "":
		hud.show_message("Your tavern is now known as a %s!" % rank, 6.0)
		GameManager.today_news.append("New rank: %s!" % rank)
	if GameManager.check_banquet_unlock():
		hud.show_message("Nobles have heard of you! Host a Noble Banquet from Open Day.", 6.0)
		GameManager.today_news.append("Nobles have heard of you! You can now host Noble Banquets.")


func _on_expand_requested() -> void:
	if GameManager.is_open or _waiting_for_last_guests:
		hud.show_message("Expand the tavern after closing time.")
		return
	var next: Dictionary = GameManager.next_expansion()
	if next.is_empty() or not GameManager.expansion_quest_done():
		return
	if not GameManager.try_spend(next["cost"]):
		hud.show_message("Not enough gold (%dg)." % next["cost"])
		return
	GameManager.expansions_built += 1
	GameManager.add_stat("expansions")
	hud.show_message("The tavern grew to %d x %d!" % [next["cols"], next["rows"]], 4.0)
	_announce_fame()
	grid.resize(next["cols"], next["rows"])   # also saves, via layout_changed
	_fit_camera()
	hud.close_expand_panel()


func _on_shop_closed(_day: int) -> void:
	spawn_timer.stop()
	hud.show_message("Closing time! Finishing last orders...")
	# Nobody new gets in, so the line goes home.
	for customer in _line.duplicate():
		customer.send_home()
	_line.clear()
	_waiting_for_last_guests = true


# ---------------------------------------------------------------------
# Staff
# ---------------------------------------------------------------------
# Changing staff mid-shift would leave orders half-done, so hiring and
# letting people go only happen while the tavern is closed.
func _staff_changes_allowed() -> bool:
	if GameManager.is_open or _waiting_for_last_guests:
		hud.show_message("Hire or let staff go after closing time.")
		return false
	return true


# Hire one of today's applicants (index into GameManager.applicants).
func _on_hire_requested(role: String, index: int) -> void:
	if not _staff_changes_allowed():
		return
	if get_tree().get_nodes_in_group(role + "s").size() >= MAX_STAFF:
		hud.show_message("That's plenty of %ss!" % role)
		return
	var profile: Dictionary = GameManager.take_applicant(role, index)
	if profile.is_empty():
		return
	_hire(profile)
	var info: Dictionary = StaffProfiles.TYPES[profile["type"]]
	hud.show_message("Hired %s the %s (%dg/day)." % [profile["name"], info["title"], info["wage"]])
	_update_staff_display()
	_save_if_closed()


func _on_fire_requested(uid: int) -> void:
	if not _staff_changes_allowed():
		return
	for person in _all_staff():
		if person.profile["uid"] != uid:
			continue
		var role: String = StaffProfiles.role_of(person.profile)
		# Without at least one of each, nobody could ever be served.
		if get_tree().get_nodes_in_group(role + "s").size() <= 1:
			hud.show_message("You need at least one %s." % role)
			return
		person.leave()
		hud.show_message("%s has left the tavern." % person.profile["name"])
		break
	_update_staff_display()
	_save_if_closed()
	_show_staff_list()


func _hire(profile: Dictionary) -> void:
	if not profile.has("uid") or int(profile["uid"]) <= 0:
		profile["uid"] = GameManager.new_staff_uid()
	var role: String = StaffProfiles.role_of(profile)
	var scene: PackedScene = COOK_SCENE if role == "cook" else WAITER_SCENE
	var person: Walker = scene.instantiate()
	staff_node.add_child(person)
	person.setup(grid, grid.door_position(), profile)


# Staff from the save file. Saves from before named staff only stored
# how many of each there were, so those get random new faces.
func _load_staff(save: Dictionary) -> void:
	var saved = save.get("staff", null)
	if typeof(saved) == TYPE_ARRAY:
		for entry in saved:
			for role in ["cook", "waiter"]:
				var profile: Dictionary = StaffProfiles.clean(entry, role)
				if not profile.is_empty() and get_tree().get_nodes_in_group(role + "s").size() < MAX_STAFF:
					_hire(profile)
	else:
		for i in clampi(int(save.get("cooks", 1)), 1, MAX_STAFF):
			_hire(StaffProfiles.random_profile("cook"))
		for i in clampi(int(save.get("waiters", 1)), 1, MAX_STAFF):
			_hire(StaffProfiles.random_profile("waiter"))
	# Everyone needs at least one of each.
	for role in ["cook", "waiter"]:
		if get_tree().get_nodes_in_group(role + "s").is_empty():
			_hire(StaffProfiles.random_profile(role))


# Everyone on staff (not counting anyone already walking out).
func _all_staff() -> Array:
	return get_tree().get_nodes_in_group("cooks") + get_tree().get_nodes_in_group("waiters")


func _staff_profiles() -> Array:
	return _all_staff().map(func(person): return person.profile)


func _show_staff_list() -> void:
	hud.show_staff_list(_staff_profiles())


func _update_staff_display() -> void:
	var cooks: int = get_tree().get_nodes_in_group("cooks").size()
	var waiters: int = get_tree().get_nodes_in_group("waiters").size()
	hud.set_staff(cooks, waiters, GameManager.daily_wages(_staff_profiles()))


# ---------------------------------------------------------------------
# Saving, new game, end of day
# ---------------------------------------------------------------------
func _on_new_game_requested() -> void:
	GameManager.delete_save()
	GameManager.reset()
	# Throw away the whole scene and build it fresh, like starting the game.
	get_tree().reload_current_scene()


func _save_if_closed() -> void:
	# Mid-day changes are saved at the end of the day instead.
	if GameManager.is_open or _waiting_for_last_guests:
		return
	GameManager.save_game(grid.get_layout(), grid.get_door(), _staff_profiles())


func _show_day_summary() -> void:
	var wages: int = GameManager.daily_wages(_staff_profiles())
	GameManager.pay_wages(wages)
	GameManager.finish_day()

	# Tonight's fame: the review first, then the banquet result.
	var review: Dictionary = GameManager.daily_review()
	GameManager.change_fame(review["fame"])
	var banquet_line: String = ""
	if GameManager.banquet_today:
		var guests: int = GameManager.today_banquet_nobles
		var happy: int = GameManager.today_nobles_served
		var result: String = "poor"
		if guests > 0 and happy == guests:
			result = "triumph"
			GameManager.add_stat("triumphs")
		elif happy * 2 >= guests:
			result = "good"
		var change: int = GameManager.BANQUET_FAME[result]
		GameManager.change_fame(change)
		var title: String = {"triumph": "A triumphant banquet!", "good": "A pleasant banquet.", "poor": "The nobles were not impressed."}[result]
		banquet_line = "%s %d of %d nobles left happy (%+d fame)." % [title, happy, guests, change]
	_announce_unlocks(GameManager.check_unlocks(), null)
	_save_if_closed()

	var text := "Day %d complete!\n\nIncome: %dg\nWages: -%dg\nProfit: %dg\n\nGuests served: %d (nobles: %d)\nWalk-outs: %d\nTurned away: %d" % [
		GameManager.day,
		GameManager.today_income,
		wages,
		GameManager.today_income - wages,
		GameManager.today_served,
		GameManager.today_nobles_served,
		GameManager.today_walkouts,
		GameManager.today_turned_away,
	]
	if GameManager.today_disappointed > 0:
		text += "\nNothing they liked: %d" % GameManager.today_disappointed
	if review["name"] != "No":
		text += "\n\n%s reviews: %d%% happy (%+d fame)" % [review["name"], roundi(review["happy"] * 100), review["fame"]]
	if banquet_line != "":
		text += "\n" + banquet_line
	text += "\n\nFame: %d (%s)\nGold: %d" % [GameManager.fame, GameManager.rank_name(), GameManager.gold]
	if not GameManager.today_unlocked.is_empty():
		var names: Array[String] = []
		for id in GameManager.today_unlocked:
			names.append(GameManager.RECIPES[id]["name"])
		text += "\n\nNew recipes: %s" % ", ".join(names)
	for line in GameManager.today_news:
		text += "\n\n" + line
	hud.show_summary(text, true)
	hud.set_day_button("Open\nDay %d" % (GameManager.day + 1), true)
