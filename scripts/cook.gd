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
# =====================================================================
class_name Cook
extends Walker

enum State { IDLE, WALKING_TO_HEARTH, AT_HEARTH, LEAVING }

const WALK_SPEED: float = 200.0

var state: State = State.IDLE
var hearth_cell: Vector2i = TavernGrid.NO_CELL


func setup(tavern_grid: TavernGrid, start_pos: Vector2) -> void:
	_setup_walker(tavern_grid, start_pos)
	speed = WALK_SPEED
	add_to_group("cooks")


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
	draw_circle(Vector2(0, 0), 18.0, Color(0.95, 0.95, 0.95))   # white jacket
	draw_circle(Vector2(0, -26), 11.0, Color(1.0, 0.85, 0.7))   # head
	draw_rect(Rect2(-10, -50, 20, 14), Color.WHITE)             # chef's hat
