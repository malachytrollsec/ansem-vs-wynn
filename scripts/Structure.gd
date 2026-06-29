extends Node2D
class_name Structure
## Keep / house / forge building.

var kind := "keep"
var team := 0
var hp := 1200.0
var max_hp := 1200.0
var net_id := 0
var _sprite: Sprite2D

# Pixel-size standards:
# - units occupy roughly 64-80 px of visual height
# - village buildings occupy roughly 130-150 px
# - keeps/castles occupy roughly 200 px and define base footprint
static func visual_scale_for(p_kind: String) -> float:
	match p_kind:
		"keep":
			return 1.55
		"tower":
			return 1.50
		"forge", "market":
			return 1.42
		"house":
			return 1.34
		_:
			return 1.34

static func footprint_radius_for(p_kind: String) -> float:
	match p_kind:
		"keep":
			return 122.0
		"tower":
			return 70.0
		"forge", "market":
			return 78.0
		"house":
			return 72.0
		_:
			return 72.0

static func base_y_for(p_kind: String) -> float:
	return 55.0 if p_kind == "keep" else 42.0

func setup(p_kind: String, p_team: int) -> void:
	kind = p_kind
	team = p_team
	if kind == "house":
		hp = 400.0; max_hp = 400.0
	elif kind == "forge":
		hp = 600.0; max_hp = 600.0
	elif kind == "tower":
		hp = 700.0; max_hp = 700.0
	elif kind == "market":
		hp = 650.0; max_hp = 650.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	var tex := ""
	match kind:
		"keep":
			tex = "res://assets/structures/keep_blue.png" if team == 0 else "res://assets/structures/keep_red.png"
		"house":
			tex = "res://assets/structures/house_asset.png"
		"forge":
			tex = "res://assets/structures/forge_asset.png"
		"tower":
			tex = "res://assets/structures/tower_asset.png"
		"market":
			tex = "res://assets/structures/market_asset.png"
		_:
			tex = "res://assets/structures/house_asset.png"
	_sprite.texture = load(tex)
	var visual_scale := visual_scale_for(kind)
	_sprite.scale = Vector2(visual_scale, visual_scale)
	add_child(_sprite)
	_sync_draw_order()

func _process(_delta: float) -> void:
	_sync_draw_order()

func _sync_draw_order() -> void:
	z_index = 18 + int(position.y / 32.0)

func take_damage(d: float) -> void:
	hp -= d
	queue_redraw()
	if hp <= 0.0:
		queue_free()

func _draw() -> void:
	var base_y := base_y_for(kind)
	var base_r := footprint_radius_for(kind) * 0.48
	draw_set_transform(Vector2(0, base_y), 0.0, Vector2(1.55, 0.40))
	draw_circle(Vector2.ZERO, base_r, Color(0, 0, 0, 0.26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tc := Game.COL_ACCENT if team == 0 else Game.COL_ENEMY
	draw_arc(Vector2(0, base_y), base_r * 0.72, 0.0, TAU, 32, Color(tc, 0.45), 2.0, true)
	if hp < max_hp:
		var w := 84.0 if kind == "keep" else 64.0
		var y := -98.0 if kind == "keep" else -70.0
		draw_rect(Rect2(-w * 0.5, y, w, 6.0), Game.COL_EDGE)
		var c := Game.COL_ACCENT if team == 0 else Game.COL_ENEMY
		draw_rect(Rect2(-w * 0.5, y, w * (hp / max_hp), 6.0), c)
