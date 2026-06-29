extends Node2D
class_name FoodNode
## A gatherable resource node: food bush or wood grove.

var res_kind := "food"   # "food" | "wood"
var amount := 900
var visual_seed := 0
var _sprite: Sprite2D

func harvest(requested: int) -> int:
	if amount <= 0:
		queue_free()
		return 0
	var taken = mini(amount, maxi(0, requested))
	amount -= taken
	if amount <= 0:
		queue_free()
	return taken

func _ready() -> void:
	visual_seed = int(abs(position.x * 17.0 + position.y * 31.0)) % 997
	_sprite = Sprite2D.new()
	if res_kind == "wood":
		var tree_tex := "res://assets/terrain/resource_oak_stand.png" if visual_seed % 2 == 0 else "res://assets/terrain/resource_pine_stand.png"
		_sprite.texture = load(tree_tex)
		_sprite.scale = Vector2.ONE * (0.68 + float(visual_seed % 5) * 0.035)
	else:
		_sprite.texture = load("res://assets/terrain/terrain_detail_brush_leaf.png")
		_sprite.scale = Vector2.ONE * (0.58 + float(visual_seed % 4) * 0.035)
		_sprite.modulate = Color(0.88, 1.0, 0.72, 0.98)
	add_child(_sprite)
	_sync_draw_order()

func _process(_delta: float) -> void:
	_sync_draw_order()

func _sync_draw_order() -> void:
	z_index = 12 + int(position.y / 32.0)

func _draw() -> void:
	if res_kind == "wood":
		draw_set_transform(Vector2(0, 18), 0.0, Vector2(1.55, 0.40))
		draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-5, 4, 10, 14), Color("70451e", 0.85))
	else:
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.45, 0.42))
		draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in range(5):
			var a := float(i) * TAU / 5.0 + float(visual_seed % 9) * 0.11
			var p := Vector2(cos(a), sin(a)) * (5.0 + float((visual_seed + i) % 4))
			draw_circle(p + Vector2(0, -4), 2.0, Color("f0d05a"))
			draw_circle(p + Vector2(0, -4), 1.0, Color("fff0a2"))
