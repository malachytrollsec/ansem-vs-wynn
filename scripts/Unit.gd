extends Node2D
class_name Unit
## RTS unit (villager / swordsman / archer): move, gather, auto-combat.

var king := "doge"
var kind := "villager"
var team := 0          # 0 = player, 1 = rival
var speed := 92.0
var hp := 40.0
var max_hp := 40.0
var atk := 4.0
var atk_range := 34.0
var atk_interval := 0.7
var aggro := 210.0
var selected := false
var target: Vector2
var gather_target: Node2D = null
var attack_target: Node2D = null
var player_ordered := false   # explicit player order overrides auto-acquire

# --- multiplayer ---
var net_id := 0
var puppet := false           # joiner-side: pose driven by host snapshots, no local sim
var net_pos: Vector2

var _sprite: Sprite2D
var _anim_t := 0.0
var _frame := 0
var _facing_row := 0
var _work_t := 0.0
var _cd := 0.0

func setup(p_king: String, p_kind: String, p_team: int) -> void:
	king = p_king
	kind = p_kind
	team = p_team
	match kind:
		"swordsman":
			hp = 80.0; max_hp = 80.0; speed = 82.0; atk = 10.0; atk_range = 34.0; atk_interval = 0.65
		"archer":
			hp = 48.0; max_hp = 48.0; speed = 88.0; atk = 8.0; atk_range = 150.0; atk_interval = 0.85
		"lancer":
			hp = 66.0; max_hp = 66.0; speed = 120.0; atk = 13.0; atk_range = 36.0; atk_interval = 0.7
		"siege":
			hp = 175.0; max_hp = 175.0; speed = 52.0; atk = 26.0; atk_range = 44.0; atk_interval = 1.3
		_:
			hp = 60.0; max_hp = 60.0; speed = 96.0; atk = 4.0; atk_range = 30.0; atk_interval = 0.9
	hp *= Game.king_bonus(king, "hp")
	max_hp = hp
	speed *= Game.king_bonus(king, "speed")
	atk *= Game.king_bonus(king, "atk")

func _ready() -> void:
	target = position
	_sprite = Sprite2D.new()
	_sprite.texture = load(Game.unit_sheet(king, kind))
	_sprite.hframes = 4
	_sprite.vframes = 4
	_set_sprite_frame(0)
	var s := _sprite_scale()
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0, 13.0 - 24.0 * s)
	add_child(_sprite)
	_sync_draw_order()

func _sprite_scale() -> float:
	if kind == "siege":
		return 1.62
	if kind == "lancer":
		return 1.82
	if kind == "villager":
		return 1.64
	return 1.72

func click_radius() -> float:
	if kind == "siege":
		return 33.0
	if kind == "lancer":
		return 30.0
	return 28.0

func _selection_radius() -> float:
	if kind == "siege":
		return 30.0
	if kind == "lancer":
		return 28.0
	return 26.0

func _health_bar_y() -> float:
	if kind == "siege":
		return -46.0
	if kind == "lancer":
		return -45.0
	return -42.0

func order_move(p: Vector2) -> void:
	target = p
	gather_target = null
	attack_target = null
	player_ordered = true

func order_gather(node: Node2D) -> void:
	gather_target = node
	attack_target = null
	target = node.position
	player_ordered = true

func order_attack(node: Node2D) -> void:
	attack_target = node
	gather_target = null
	player_ordered = true

func is_busy() -> bool:
	return is_instance_valid(gather_target) or is_instance_valid(attack_target)

func _process(delta: float) -> void:
	if puppet:
		_puppet_proc(delta)
		return
	_cd = maxf(0.0, _cd - delta)

	if is_instance_valid(attack_target):
		_combat(delta)
	elif is_instance_valid(gather_target):
		_gather(delta)
	else:
		_march(delta)
	_sync_draw_order()
	queue_redraw()

func _puppet_proc(delta: float) -> void:
	# smoothly chase the networked pose; animate while moving
	var to := net_pos - position
	var dist := to.length()
	if dist > 1.0:
		position += to * minf(1.0, delta * 12.0)
		_face_dir(to / dist)
		_anim_t += delta
		if _anim_t >= 0.11:
			_anim_t = 0.0
			_frame = (_frame + 1) % 4
			_set_sprite_frame(_frame)
	else:
		_set_sprite_frame(0)
	_sync_draw_order()
	queue_redraw()

func _sync_draw_order() -> void:
	z_index = 24 + int(position.y / 32.0)

func _combat(delta: float) -> void:
	var to: Vector2 = attack_target.position - position
	var dist := to.length()
	if dist > atk_range:
		_step(to / maxf(dist, 0.001), delta)
	else:
		_face_dir(to / maxf(dist, 0.001))
		_set_sprite_frame(0)
		if _cd <= 0.0:
			_cd = atk_interval
			if ["archer", "siege"].has(kind) and get_parent().has_method("spawn_projectile"):
				get_parent().spawn_projectile(position, attack_target.position, "stone" if kind == "siege" else "arrow")
			if attack_target.has_method("take_damage"):
				var dmg: float = atk + get_parent().team_atk_bonus(team)
				attack_target.take_damage(dmg)

func _gather(delta: float) -> void:
	if kind != "villager":
		gather_target = null
		return
	var to: Vector2 = gather_target.position - position
	var dist := to.length()
	if dist > 32.0:
		_step(to / maxf(dist, 0.001), delta)
	else:
		_face_dir(to / maxf(dist, 0.001))
		_set_sprite_frame(0)
		_work_t += delta
		if _work_t >= 1.0:
			_work_t = 0.0
			var g: float = Game.king_bonus(king, "gather") * get_parent().team_eco_bonus(team)
			if is_instance_valid(gather_target) and gather_target.get("res_kind") == "wood":
				var wood: int = gather_target.harvest(int(round(8 * g))) if gather_target.has_method("harvest") else int(round(8 * g))
				if wood > 0:
					get_parent().credit_resource(team, "timber", wood)
			else:
				var food: int = gather_target.harvest(int(round(10 * g))) if is_instance_valid(gather_target) and gather_target.has_method("harvest") else int(round(10 * g))
				if food > 0:
					get_parent().credit_resource(team, "food", food)

func _march(delta: float) -> void:
	var to := target - position
	var dist := to.length()
	if dist > 4.0:
		_step(to / dist, delta)
	else:
		_set_sprite_frame(0)
		player_ordered = false

func _step(dir: Vector2, delta: float) -> void:
	position += dir * speed * delta
	_face_dir(dir)
	_anim_t += delta
	if _anim_t >= 0.11:
		_anim_t = 0.0
		_frame = (_frame + 1) % 4
		_set_sprite_frame(_frame)

func _face_dir(dir: Vector2) -> void:
	if dir.length_squared() <= 0.0001:
		return
	var n := dir.normalized()
	var ax := absf(n.x)
	if n.y < -0.35:
		_facing_row = 3 if ax > 0.28 else 2
	elif ax > 0.42:
		_facing_row = 1
	else:
		_facing_row = 0
	if ax > 0.05:
		_sprite.flip_h = n.x < 0

func _set_sprite_frame(col: int) -> void:
	if not is_instance_valid(_sprite):
		return
	var max_frame := maxi(0, _sprite.hframes * _sprite.vframes - 1)
	_sprite.frame = clampi(_facing_row * _sprite.hframes + clampi(col, 0, _sprite.hframes - 1), 0, max_frame)

func take_damage(d: float) -> void:
	d = maxf(1.0, d - get_parent().team_armor_bonus(team))
	hp -= d
	if hp <= 0.0:
		_die()

func _die() -> void:
	get_parent().on_unit_death(team)
	queue_free()

func _draw() -> void:
	# team marker under the feet (cyan = you, red = rival)
	var tc := Game.COL_ACCENT if team == 0 else Game.COL_ENEMY
	var shadow_alpha := 0.30 if kind == "siege" else 0.23
	var shadow_radius := 15.0 if kind == "siege" else 11.5
	draw_set_transform(Vector2(0, 15), 0.0, Vector2(1.65, 0.48))
	draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, shadow_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var marker_radius := 10.0 if kind == "siege" else 9.0
	draw_circle(Vector2(0, 13), marker_radius, Color(tc, 0.30))
	draw_arc(Vector2(0, 13), marker_radius, 0.0, TAU, 18, tc, 1.5, true)
	if selected:
		draw_arc(Vector2.ZERO, _selection_radius(), 0.0, TAU, 26, Game.COL_ACCENT_BRIGHT, 2.0, true)
	if hp < max_hp:
		var w := 26.0
		var bar_y := _health_bar_y()
		draw_rect(Rect2(-w * 0.5, bar_y, w, 4.0), Game.COL_EDGE)
		var c := Color("43c865") if team == 0 else Game.COL_ENEMY
		draw_rect(Rect2(-w * 0.5, bar_y, w * (hp / max_hp), 4.0), c)
