extends Control
## Bottom-corner minimap: keeps, units, and the camera viewport rect.

var main: Node = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if main == null or not is_instance_valid(main):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var world := _local_to_world(get_local_mouse_position())
			if main.has_method("minimap_click"):
				main.minimap_click(world, event.button_index)
			elif event.button_index == MOUSE_BUTTON_LEFT and main.has_method("center_camera_on"):
				main.center_camera_on(world)

func _local_to_world(local: Vector2) -> Vector2:
	var w: Vector2 = main.get_world()
	return Vector2(
		clampf(local.x / maxf(size.x, 1.0), 0.0, 1.0) * w.x,
		clampf(local.y / maxf(size.y, 1.0), 0.0, 1.0) * w.y
	)

func _draw() -> void:
	var bg := Color(String(Game.arena_cfg().get("ground", "65a844")))
	draw_rect(Rect2(Vector2.ZERO, size), bg.darkened(0.28))
	for i in range(0, int(size.x), 12):
		draw_line(Vector2(i, 0), Vector2(i + 18, size.y), Color(bg.lightened(0.18), 0.08), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Game.COL_EDGE, false, 2.0)
	if main == null or not is_instance_valid(main):
		return
	var w: Vector2 = main.get_world()
	var sx := size.x / w.x
	var sy := size.y / w.y

	for s in main.structures:
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var c := Game.COL_ACCENT if s.team == 0 else Game.COL_ENEMY
		var p := Vector2(s.position.x * sx, s.position.y * sy)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Game.COL_EDGE)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), c)

	for f in main.food_nodes:
		if not is_instance_valid(f) or f.is_queued_for_deletion():
			continue
		var rc := Color("7fca4d") if f.res_kind == "food" else Color("4c8f35")
		draw_circle(Vector2(f.position.x * sx, f.position.y * sy), 1.5, Color(rc, 0.65))

	for u in main.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		var c := Game.COL_ACCENT_BRIGHT if u.team == 0 else Game.COL_ENEMY
		draw_circle(Vector2(u.position.x * sx, u.position.y * sy), 1.7, c)

	for ping in main.alert_pings:
		var pos: Vector2 = ping.get("pos", Vector2.ZERO)
		var age := float(ping.get("age", 0.0))
		var duration := maxf(float(ping.get("duration", 1.0)), 0.01)
		var t := clampf(age / duration, 0.0, 1.0)
		var col: Color = main.alert_ping_color(String(ping.get("kind", "danger"))) if main.has_method("alert_ping_color") else Color("ff665a")
		var p := Vector2(pos.x * sx, pos.y * sy)
		draw_circle(p, 8.0 + 9.0 * t, Color(col, 0.42 * (1.0 - t)))
		draw_arc(p, 5.0 + 12.0 * t, 0.0, TAU, 24, Color(col, 0.95 * (1.0 - t)), 1.6, true)

	if main.rally_point != Vector2.ZERO:
		var rp := Vector2(main.rally_point.x * sx, main.rally_point.y * sy)
		draw_circle(rp, 3.0, Game.COL_ACCENT_BRIGHT)
		draw_circle(rp, 1.5, Game.COL_EDGE)

	# camera viewport rectangle
	if is_instance_valid(main.camera):
		var vp: Vector2 = get_viewport().get_visible_rect().size / main.zoom_level
		var tl: Vector2 = main.camera.position - vp * 0.5
		draw_rect(Rect2(tl.x * sx, tl.y * sy, vp.x * sx, vp.y * sy), Game.COL_BONE, false, 1.4)
