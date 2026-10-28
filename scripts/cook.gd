# =====================================================================
# cook.gd  —  one cook. Attached to scenes/cook.tscn.
#
# A Hearth only cooks while a Cook is standing at it. Each cook claims
# a Hearth that has nobody working it, walks over, and stays there.
# The cooking itself is timed by tavern_grid.gd.
#
#   IDLE -> WALKING_TO_HEARTH -> AT_HEARTH
#     ^                              |
#     +----- their Hearth is sold ---+
#
# LEAVING is used when the player lets them go.
#
# Each cook has a profile (see staff_profiles.gd): their name, looks and
# type. The type's trait changes how they cook (cook_speed, portion_bonus).
# =====================================================================
class_name Cook
extends Walker

enum State { IDLE, WALKING_TO_HEARTH, AT_HEARTH, LEAVING }

const WALK_SPEED: float = 200.0

var state: State = State.IDLE
var hearth_cell: Vector2i = TavernGrid.NO_CELL
var profile: Dictionary = {}


func setup(tavern_grid: TavernGrid, start_pos: Vector2, who: Dictionary) -> void:
	_setup_walker(tavern_grid, start_pos)
	speed = WALK_SPEED
	profile = who
	sprite_sheet = StaffProfiles.SHEETS[profile["type"]]
	material = StaffProfiles.material_for(profile)
	# Pixel art stays crisp instead of blurry when scaled up.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("cooks")


# How fast this cook works on a dish (1.0 = normal). Traits:
#   Trained (Classic Chef): everything 25% faster
#   Roast Master (Dwarf Cook): roasts 40% faster
func cook_speed(order: Dictionary) -> float:
	match profile["type"]:
		"chef":
			return 1.25
		"dwarf_cook":
			if StaffProfiles.ROAST_DISHES.has(order.get("id", "")):
				return 1.4
	return 1.0


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
				hearth_cell = cell
				go_to_cell(grid.access_cell(cell, position, self))
				state = State.WALKING_TO_HEARTH

		State.WALKING_TO_HEARTH:
			if _walk(delta):
				state = State.AT_HEARTH

		State.AT_HEARTH:
			pass   # the grid sees we're here and cooks

		State.LEAVING:
			if _walk(delta):
				queue_free()

	queue_redraw()


func is_at_hearth() -> bool:
	return state == State.AT_HEARTH


# Called by the grid when our Hearth is sold. Go find another one.
func release_hearth() -> void:
	if state == State.LEAVING:
		return
	hearth_cell = TavernGrid.NO_CELL
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


func _draw() -> void:
	draw_sprite()
