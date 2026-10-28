# =====================================================================
# walker.gd  —  shared walking code for everyone who moves around.
#
# Customer, Cook and Waiter all say "extends Walker". That's
# INHERITANCE: each of them starts with everything in this file, then
# adds its own job on top. Fix walking here and all three get the fix.
#
# Walking uses the grid's pathfinder, so nobody walks through furniture.
# If the player builds or sells something while someone is walking,
# they plan a new route (see _on_layout_changed).
#
# Walkers with a sprite_sheet are drawn as animated pixel art facing the
# way they walk (see draw_sprite). Guests still use simple shapes.
# =====================================================================
class_name Walker
extends Node2D

var speed: float = 170.0        # pixels per second; subclasses change it
var grid: TavernGrid

# The grid square we're heading to (or standing on, once we've arrived).
# The grid won't let the player build on it while we need it.
var destination: Vector2i = TavernGrid.NO_CELL

# Points still to walk to, in Main's space. Empty = standing still.
var _path: Array[Vector2] = []
var _leaving_by_door: bool = false
# Set when walking to a spot outside the floor (the waiting line), where
# there's no furniture and so no pathfinding.
var _outside_target: Vector2
var _going_outside: bool = false
# True when no route exists right now. We try again on the next layout change.
var _stuck: bool = false

# --- Sprite drawing ---
const WALK_FPS: float = 6.0       # walk-cycle frames per second
const SPRITE_SCALE: float = 2.0   # sheet pixels -> world pixels
var sprite_sheet: Texture2D       # null = no sprite
var _facing: String = "front"     # "front", "back", "left" or "right"
var _anim_time: float = 0.0
var _last_moved_frame: int = -10


# Subclasses call this from their own setup().
func _setup_walker(tavern_grid: TavernGrid, start_pos: Vector2) -> void:
	grid = tavern_grid
	position = start_pos
	# The grid looks through this group to see which squares people need.
	add_to_group("walkers")
	grid.layout_changed.connect(_on_layout_changed)


# Walk to a square inside the tavern.
func go_to_cell(cell: Vector2i) -> void:
	destination = cell
	_leaving_by_door = false
	_going_outside = false
	_plan_route()


# Walk to a spot outside the tavern, like a place in the waiting line.
func go_to_outside_spot(point: Vector2) -> void:
	destination = TavernGrid.NO_CELL
	_leaving_by_door = false
	_going_outside = true
	_outside_target = point
	_plan_route()


# Walk out through the front door.
func go_out_door() -> void:
	destination = TavernGrid.NO_CELL
	_leaving_by_door = true
	_going_outside = false
	_plan_route()


# Stop right here (used when a job is cancelled halfway).
func stop() -> void:
	_path.clear()
	destination = TavernGrid.NO_CELL
	_stuck = false


# The square we're on now, or NO_CELL if we're outside the door.
func current_cell() -> Vector2i:
	return grid.cell_at_world(position)


# Moves a step along the route. Returns true once we've arrived.
func _walk(delta: float) -> bool:
	if _stuck:
		return false
	var start_pos: Vector2 = position
	var step: float = speed * delta
	# A loop, so a fast step can pass a corner and keep going.
	while not _path.is_empty() and step > 0.0:
		var next_point: Vector2 = _path[0]
		var distance: float = position.distance_to(next_point)
		if distance <= step:
			position = next_point
			step -= distance
			_path.pop_front()
		else:
			position = position.move_toward(next_point, step)
			step = 0.0
	_note_movement(position - start_pos, delta)
	return _path.is_empty()


# Remembers which way we're heading, for the sprite.
func _note_movement(moved: Vector2, delta: float) -> void:
	if moved.length() < 0.01:
		return
	_last_moved_frame = Engine.get_process_frames()
	_anim_time += delta
	if absf(moved.x) > absf(moved.y):
		_facing = "right" if moved.x > 0 else "left"
	else:
		_facing = "front" if moved.y > 0 else "back"


func is_moving() -> bool:
	return Engine.get_process_frames() - _last_moved_frame <= 1


# Draws the current frame of sprite_sheet. Call it from _draw().
# Sheet columns: front x3, side x3 (facing right), back x3; each set is
# [standing, walk 1, walk 2]. Row 1 is the same poses carrying a dish.
func draw_sprite(carrying: bool = false) -> void:
	if sprite_sheet == null:
		return
	var frame: Vector2 = Vector2(StaffProfiles.FRAME_SIZE)
	var column: int = {"front": 0, "right": 3, "left": 3, "back": 6}[_facing]
	if is_moving():
		column += 1 + int(_anim_time * WALK_FPS) % 2
	var source := Rect2(Vector2(column * frame.x, (1 if carrying else 0) * frame.y), frame)
	var size: Vector2 = frame * SPRITE_SCALE
	# The feet are near the bottom of the frame; stand them a little
	# below our position, so we look like we're standing in our square.
	var spot := Rect2(Vector2(-size.x / 2.0, 18.0 - size.y), size)
	if _facing == "left":
		# The sheet only faces right; mirror it to face left.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	draw_texture_rect_region(sprite_sheet, spot, source)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _plan_route() -> void:
	_path.clear()
	_stuck = false
	if _going_outside:
		_path.append(_outside_target)
		return
	var start: Vector2i = current_cell()
	if start == TavernGrid.NO_CELL:
		# Outside: step in front of the door first, so we don't walk
		# through the wall, then come in through the door.
		_path.append(grid.door_position())
		start = grid.door_cell
	var goal: Vector2i = grid.door_cell if _leaving_by_door else destination
	if goal == TavernGrid.NO_CELL:
		return

	# find_path gives a list of squares; we walk to the middle of each.
	var cells: Array[Vector2i] = grid.find_path(start, goal)
	if cells.is_empty():
		_stuck = true
		return
	for cell in cells:
		_path.append(grid.cell_center(cell))
	if _leaving_by_door:
		_path.append(grid.door_position())


func _on_layout_changed() -> void:
	# Only people who are on the move need a new route.
	if not _path.is_empty() or _stuck:
		_plan_route()
