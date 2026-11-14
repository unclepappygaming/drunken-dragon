# =====================================================================
# cook.gd  —  one cook. Attached to scenes/cook.tscn.
#
# Cooks work in the kitchen (see tavern_grid.gd): each claims a Hearth
# and stands in the aisle behind it, facing the room. When a dish is
# done they carry it along the aisle to the pass (expo counter), set it
# down for a waiter, and walk back. If the pass is full, they wait.
#
#   IDLE -> TO_HEARTH -> AT_HEARTH -> TO_PASS -> AT_PASS -> TO_HEARTH ...
#     ^                                 (their Hearth sold: back to IDLE)
#
# A cook with no Hearth of their own is a RUNNER: when another cook's
# dish is done, they carry it to the pass (IDLE -> TO_PASS -> AT_PASS
# -> IDLE), so the Hearth's cook can start the next dish at once.
#
# Cooks always face the camera (always_front), so food and faces stay
# visible. LEAVING is used when the player lets them go.
#
# Each cook has a profile (see staff_profiles.gd): their name, looks and
# type. The type's trait changes how they cook (cook_speed, portion_bonus).
# =====================================================================
class_name Cook
extends Walker

enum State { IDLE, TO_HEARTH, AT_HEARTH, TO_PASS, AT_PASS, LEAVING }

const WALK_SPEED: float = 200.0

var state: State = State.IDLE
var hearth_cell: Vector2i = TavernGrid.NO_CELL
var profile: Dictionary = {}
var _dish: Customer = null   # the guest whose plate we're carrying


func setup(tavern_grid: TavernGrid, start_pos: Vector2, who: Dictionary) -> void:
	_setup_walker(tavern_grid, start_pos)
	profile = who
	speed = WALK_SPEED * StaffProfiles.level_bonus(profile)
	sprite_sheet = StaffProfiles.SHEETS[profile["type"]]
	material = StaffProfiles.material_for(profile)
	# Pixel art stays crisp instead of blurry when scaled up.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	always_front = true
	_facing = "front"
	add_to_group("cooks")


# How fast this cook works on a dish (1.0 = normal). Traits:
#   Trained (Classic Chef): everything 25% faster
#   Roast Master (Dwarf Cook): roasts 40% faster
func cook_speed(order: Dictionary) -> float:
	var trait_speed: float = 1.0
	match profile["type"]:
		"chef":
			trait_speed = 1.25
		"dwarf_cook":
			if StaffProfiles.ROAST_DISHES.has(order.get("id", "")):
				trait_speed = 1.4
	return trait_speed * StaffProfiles.level_bonus(profile)   # and faster with every level


# Experience for a job done; at a new level they get quicker.
func gain_xp(amount: int = 1) -> void:
	if StaffProfiles.add_xp(profile, amount):
		speed = WALK_SPEED * StaffProfiles.level_bonus(profile)
		GameManager.staff_levelled.emit(profile)


# Extra share of the price for dishes this cook makes.
# Hearty Portions (Tavern Cook): +15%.
func portion_bonus() -> float:
	return 0.15 if profile["type"] == "tavern_cook" else 0.0


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			# Look for a Hearth that has no cook. (Cheap, so every frame is fine.)
			var cell: Vector2i = grid.claim_hearth(self)
			if cell != TavernGrid.NO_CELL:
				end_standby()
				hearth_cell = cell
				_go_to_hearth()
			else:
				idle_standby(delta)   # no free Hearth: wait in the aisle

		State.TO_HEARTH:
			if _walk(delta):
				state = State.AT_HEARTH

		State.AT_HEARTH:
			pass   # the grid sees we're here and cooks

		State.TO_PASS:
			if not _dish_wanted():
				_dish = null
				_back_to_work()   # the guest left; the dish is binned
			elif _walk(delta):
				state = State.AT_PASS

		State.AT_PASS:
			if not _dish_wanted():
				_dish = null
				_back_to_work()
			elif grid.expo_has_room():
				grid.put_on_expo(_dish)
				gain_xp(2)   # a whole dish: worth an order, a serve and a clear-up
				_dish = null
				_back_to_work()
			# Otherwise the pass is full: wait for a waiter to clear it.

		State.LEAVING:
			if _walk(delta):
				queue_free()

	queue_redraw()


func is_at_hearth() -> bool:
	return state == State.AT_HEARTH


# Called by the grid when a dish is done: carry it to the pass.
func take_dish(guest: Customer) -> void:
	end_standby()
	_dish = guest
	go_to_cell(grid.expo_back())
	state = State.TO_PASS


# Called by the grid when our Hearth is sold or the kitchen moves.
# Find a Hearth again (a dish in our hands still goes to the pass first).
func release_hearth() -> void:
	if state == State.LEAVING:
		return
	hearth_cell = TavernGrid.NO_CELL
	if state == State.TO_PASS or state == State.AT_PASS:
		if state == State.TO_PASS:
			go_to_cell(grid.expo_back())   # the kitchen may have moved
		return
	stop()
	state = State.IDLE


# Called by main.gd when the player lets this cook go.
func leave() -> void:
	grid.release_hearth(self)
	# Leave the group right away so the staff count updates now,
	# not when we finally walk out of the door.
	remove_from_group("cooks")
	state = State.LEAVING
	go_out_door()


func _go_to_hearth() -> void:
	go_to_cell(grid.access_cell(hearth_cell, position, self))
	state = State.TO_HEARTH


func _back_to_work() -> void:
	if hearth_cell == TavernGrid.NO_CELL:
		state = State.IDLE
	else:
		_go_to_hearth()


# is_instance_valid: the guest may already be deleted, and touching a
# deleted node crashes.
func _dish_wanted() -> bool:
	return is_instance_valid(_dish) and _dish.state == Customer.State.WAITING_FOR_FOOD


func _draw() -> void:
	draw_sprite()
	if is_instance_valid(_dish):
		# The dish, held out in front.
		grid.draw_dish(self, Vector2(0, -8), _dish.order.get("id", "plate"), 0.75)
