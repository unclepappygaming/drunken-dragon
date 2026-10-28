# =====================================================================
# tavern_camera.gd  —  lets the player look around the tavern.
# Attached to the Camera node in main.tscn.
#
#   * one finger (or the mouse) drags the view around
#   * two fingers pinch to zoom (mouse wheel or trackpad on a computer)
#   * a quick tap that didn't drag is passed on as `tapped`, which the
#     grid uses for building
#
# A Camera2D shows the part of the world around its `position`. The HUD
# lives on a CanvasLayer, so it stays put while the camera moves.
# =====================================================================
class_name TavernCamera
extends Camera2D

# A tap (not a drag) at this point in the world.
signal tapped(world_pos: Vector2)

# Godot zoom: 2.0 = everything twice as big, 0.5 = half size.
const MIN_ZOOM: float = 0.7
const MAX_ZOOM: float = 2.0
const WHEEL_STEP: float = 1.1
# A finger has to move this many pixels before a tap becomes a drag,
# so a slightly shaky tap still builds.
const DRAG_THRESHOLD: float = 14.0

# The camera's center never leaves this area, so the floor stays in view.
var bounds: Rect2 = Rect2(0, 0, 720, 1280)

var _pressed: bool = false
var _dragging: bool = false
var _press_pos: Vector2
# Fingers currently on the screen: finger number -> screen position.
var _touches: Dictionary = {}
var _pinch_distance: float = 0.0


# Godot calls _unhandled_input with every tap, click and drag that the
# HUD buttons didn't already use.
func _unhandled_input(event: InputEvent) -> void:
	# --- Real touch events, needed for two-finger pinch ---
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			_pinch_distance = _finger_distance()
			_dragging = true   # a pinch is never a tap
		return

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var distance: float = _finger_distance()
			if _pinch_distance > 0.0:
				_zoom_at(_finger_center(), distance / _pinch_distance)
			_pinch_distance = distance
			get_viewport().set_input_as_handled()
		return

	# --- Mouse events. Phones also send these for the first finger,
	# so they handle one-finger drags and taps everywhere. ---
	if event is InputEventMouseButton:
		match event.button_index:
			# Each wheel click sends a press and a release; zoom on the press only.
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, WHEEL_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1.0 / WHEEL_STEP)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pressed = true
					_dragging = false
					_press_pos = event.position
				elif _pressed:
					_pressed = false
					if not _dragging:
						tapped.emit(screen_to_world(event.position))
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _pressed:
		# While pinching, the copied mouse only follows one finger; ignore it.
		if _touches.size() >= 2:
			return
		if not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			# Dividing by zoom makes the floor follow the finger exactly,
			# whether zoomed in or out.
			position -= event.relative / zoom
			_keep_in_bounds()
		get_viewport().set_input_as_handled()
		return

	# Trackpad pinch on a laptop.
	if event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		get_viewport().set_input_as_handled()


# Converts a point on the screen to a point in the tavern world.
# The camera's position is the world point at the middle of the screen.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2.0) / zoom


# Zooms while keeping the world point under the fingers (or the mouse)
# in the same place on screen, which is what makes pinching feel natural.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world_before: Vector2 = screen_to_world(screen_pos)
	var new_zoom: float = clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	position += world_before - screen_to_world(screen_pos)
	_keep_in_bounds()


func _keep_in_bounds() -> void:
	position = position.clamp(bounds.position, bounds.end)


func _finger_distance() -> float:
	var points: Array = _touches.values()
	return points[0].distance_to(points[1])


func _finger_center() -> Vector2:
	var points: Array = _touches.values()
	return (points[0] + points[1]) / 2.0
