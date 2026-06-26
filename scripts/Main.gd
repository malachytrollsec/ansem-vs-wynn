extends Node2D
## Battlefield: world, RTS camera, selection, orders, train/build.

const WORLD := Vector2(1900, 1300)
const CAMERA_KEY_SPEED := 540.0
const EDGE_PAN_MARGIN := 18.0
const EDGE_PAN_SPEED := 500.0
const CAMERA_ZOOM_MIN := 0.6
const CAMERA_ZOOM_MAX := 1.8
const CAMERA_ZOOM_STEP := 0.12
const AI_FREE_SPAWN_START := 30.0
const FIRST_WAVE_START := 24.0
const ENEMY_ATTACK_GRACE := 36.0
const BATTLEFIELD_GRASS_PATH := "res://assets/terrain/terrain_grass_battlefield.png"
const BATTLEFIELD_SAND_PATH := "res://assets/terrain/terrain_sand_battlefield.png"
const GRASS_VARIATION_PATHS := [
	"res://assets/terrain/terrain_grass_tile.png",
	"res://assets/terrain/terrain_grass_variation_01.png",
	"res://assets/terrain/terrain_grass_variation_02.png",
	"res://assets/terrain/terrain_grass_variation_03.png",
]
const SAND_VARIATION_PATHS := [
	"res://assets/terrain/terrain_sand_tile.png",
	"res://assets/terrain/terrain_sand_variation_01.png",
	"res://assets/terrain/terrain_sand_variation_02.png",
	"res://assets/terrain/terrain_sand_variation_03.png",
]
const COMMAND_MARKER_PATHS := {
	"attack": "res://assets/fx/command_attack_marker.png",
	"gather": "res://assets/fx/command_gather_marker.png",
	"move": "res://assets/fx/command_move_marker.png",
	"rally": "res://assets/fx/command_rally_marker.png",
	"select": "res://assets/fx/command_select_ring.png",
	"target": "res://assets/fx/command_target_bracket.png",
}

func get_world() -> Vector2:
	return WORLD

func center_camera_on(world_pos: Vector2) -> void:
	if not is_instance_valid(camera):
		return
	camera.position = world_pos
	_clamp_camera()

func minimap_click(world_pos: Vector2, button_index: int) -> void:
	if rally_set:
		_set_local_rally(world_pos)
		return
	if button_index == MOUSE_BUTTON_LEFT:
		center_camera_on(world_pos)
	elif button_index == MOUSE_BUTTON_RIGHT:
		if build_mode != "":
			_cancel_build()
		else:
			_issue_order(world_pos)

var camera: Camera2D
var units: Array[Unit] = []
var food_nodes: Array[FoodNode] = []
var structures: Array[Structure] = []
var player_keep: Structure
var rival_keep: Structure

var selecting := false
var sel_start := Vector2.ZERO
var sel_now := Vector2.ZERO
var sel_double_click := false
var zoom_level := 1.0
var _acquire_t := 0.0
var _ai_t := 0.0
var _tower_t := 0.0
var _match_t := 0.0
var _wave_t := 0.0
var _over := false
var _match_result := ""
var _remote_over_shown := false
var build_mode := ""
var build_ghost: Sprite2D = null
var towers: Array[Structure] = []
var markets: Array[Structure] = []
var _market_t := 0.0
var rally_point := Vector2.ZERO
var rally_set := false
var train_queue: Array = []
var queued_pop := 0
var power_cd := 0.0
var threat := false
var _next_net_id := 1
var _snapshot_t := 0.0
var _snapshot_log_t := -1
var _snapshots_sent := 0
var _snapshots_applied := 0
var _intents_sent := 0
var _intents_received := 0
var _intent_results := 0
var _last_intent_sent := {}
var _units_by_net_id := {}
var _structures_by_net_id := {}
var _rival_food := Game.START_FOOD
var _rival_timber := Game.START_TIMBER
var _rival_memp := Game.START_MEMP
var _rival_pop := 0
var _rival_pop_cap := Game.START_POP_CAP
var _rival_atk_bonus := 0.0
var _rival_armor_bonus := 0.0
var _rival_eco_bonus := 1.0
var _rival_has_forge := false
var _rival_rally_point := Vector2.ZERO
var _player_rally_custom := false
var _rival_rally_custom := false
var battlefield_grass: Texture2D = null
var battlefield_sand: Texture2D = null
var command_markers := {}
var _projectile_debug_counts := {}
var alert_pings: Array = []
var _alert_debug_counts := {}
var control_groups := {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	battlefield_grass = load(BATTLEFIELD_GRASS_PATH)
	battlefield_sand = load(BATTLEFIELD_SAND_PATH)
	_load_command_markers()
	Game.reset()
	_reset_rival_state()
	if "--multiplayer-setup-smoke" in OS.get_cmdline_args() or "--multiplayer-setup-smoke" in OS.get_cmdline_user_args():
		Game.net_mode = "host"
		Game.my_team = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arena="):
			Game.arena = a.split("=")[1]
	_scatter_decals()
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_sync_camera_zoom)
	_sync_camera_zoom()

	player_keep = _add_structure("keep", 0, Vector2(300, WORLD.y - 300))
	rival_keep = _add_structure("keep", 1, Vector2(WORLD.x - 300, 320))
	towers.append(player_keep)
	towers.append(rival_keep)
	rally_point = player_keep.position + Vector2(40, 150)
	_rival_rally_point = rival_keep.position + Vector2(-40, -150)

	for i in range(5):
		_add_food(Vector2(470 + i * 64, WORLD.y - 410))
	for i in range(3):
		_add_resource(Vector2(360 + i * 78, WORLD.y - 560), "wood")

	for i in range(4):
		_spawn_unit(Game.player_king, "villager", 0, Vector2(380 + i * 42, WORLD.y - 400))
	_spawn_starting_defenders(0)
	if _human_multiplayer():
		for i in range(5):
			_add_food(Vector2(WORLD.x - 470 - i * 64, 410))
		for i in range(3):
			_add_resource(Vector2(WORLD.x - 360 - i * 78, 560), "wood")
		for i in range(4):
			_spawn_unit(Game.rival_king, "villager", 1, Vector2(WORLD.x - 380 - i * 42, 400), 0, false)
			_add_team_pop(1, 1)
		_spawn_starting_defenders(1)
	else:
		# a couple of rival defenders to fight toward once the opening breathes.
		for i in range(2):
			var guard := _spawn_unit(Game.rival_king, "swordsman", 1, Vector2(WORLD.x - 420 - i * 42, 420), 0, false)
			guard.order_move(_defensive_point_for_team(1) + Vector2(-i * 28, i * 18))

	camera.position = player_keep.position + Vector2(120, -120)
	_clamp_camera()

	var hud := preload("res://scripts/Hud.gd").new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	if not Net.got_message.is_connected(_on_net_message):
		Net.got_message.connect(_on_net_message)

	Game.log_event("%s vs %s — %s" % [Game.KINGS[Game.player_king]["name"], Game.KINGS[Game.rival_king]["name"], String(Game.arena_cfg()["label"])])
	if Game.wager_stake > 0:
		var ticket_unit := "SOL" if Wallet.verified else "ticket"
		Game.log_event("%s live: stake %d, tax %d, win pays %d." % [ticket_unit.capitalize(), Game.wager_stake, Game.wager_tax(), Game.wager_payout(true)])
	else:
		Game.log_event("No wager ticket locked.")
	if Game.net_mode == "host":
		Game.log_event("Hosting room %s — publishing snapshots." % Net.room)
	elif Game.net_mode == "join":
		Game.log_event("Joined room %s — commanding rival side." % Net.room)
	_publish_web_match_state()

	if "--shot" in OS.get_cmdline_args() or "--shot" in OS.get_cmdline_user_args():
		_capture()
	if "--result-smoke" in OS.get_cmdline_args() or "--result-smoke" in OS.get_cmdline_user_args():
		call_deferred("_result_smoke")
	if "--remote-result-smoke" in OS.get_cmdline_args() or "--remote-result-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_result_smoke")
	if _truthy(_web_query_params().get("webResultSmoke", "")):
		call_deferred("_web_result_smoke")
	if _truthy(_web_query_params().get("memeSpritePreview", "")):
		call_deferred("_web_meme_sprite_preview")
	if _truthy(_web_query_params().get("selectionSummaryPreview", "")):
		call_deferred("_web_selection_summary_preview")
	if "--tower-target-smoke" in OS.get_cmdline_args() or "--tower-target-smoke" in OS.get_cmdline_user_args():
		call_deferred("_tower_target_smoke")
	if "--build-placement-smoke" in OS.get_cmdline_args() or "--build-placement-smoke" in OS.get_cmdline_user_args():
		call_deferred("_build_placement_smoke")
	if "--build-ghost-smoke" in OS.get_cmdline_args() or "--build-ghost-smoke" in OS.get_cmdline_user_args():
		call_deferred("_build_ghost_smoke")
	if "--resource-depletion-smoke" in OS.get_cmdline_args() or "--resource-depletion-smoke" in OS.get_cmdline_user_args():
		call_deferred("_resource_depletion_smoke")
	if "--destroyed-entity-smoke" in OS.get_cmdline_args() or "--destroyed-entity-smoke" in OS.get_cmdline_user_args():
		call_deferred("_destroyed_entity_smoke")
	if "--structure-stats-smoke" in OS.get_cmdline_args() or "--structure-stats-smoke" in OS.get_cmdline_user_args():
		call_deferred("_structure_stats_smoke")
	if "--remote-economy-smoke" in OS.get_cmdline_args() or "--remote-economy-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_economy_smoke")
	if "--remote-authority-smoke" in OS.get_cmdline_args() or "--remote-authority-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_authority_smoke")
	if "--remote-order-smoke" in OS.get_cmdline_args() or "--remote-order-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_order_smoke")
	if "--remote-order-target-smoke" in OS.get_cmdline_args() or "--remote-order-target-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_order_target_smoke")
	if "--multiplayer-setup-smoke" in OS.get_cmdline_args() or "--multiplayer-setup-smoke" in OS.get_cmdline_user_args():
		call_deferred("_multiplayer_setup_smoke")
	if "--remote-concede-smoke" in OS.get_cmdline_args() or "--remote-concede-smoke" in OS.get_cmdline_user_args():
		call_deferred("_remote_concede_smoke")
	if "--net-leave-smoke" in OS.get_cmdline_args() or "--net-leave-smoke" in OS.get_cmdline_user_args():
		call_deferred("_net_leave_smoke")
	if "--hud-team-smoke" in OS.get_cmdline_args() or "--hud-team-smoke" in OS.get_cmdline_user_args():
		call_deferred("_hud_team_smoke")
	if "--tech-status-smoke" in OS.get_cmdline_args() or "--tech-status-smoke" in OS.get_cmdline_user_args():
		call_deferred("_tech_status_smoke")
	if "--selection-summary-smoke" in OS.get_cmdline_args() or "--selection-summary-smoke" in OS.get_cmdline_user_args():
		call_deferred("_selection_summary_smoke")
	if "--projectile-fx-smoke" in OS.get_cmdline_args() or "--projectile-fx-smoke" in OS.get_cmdline_user_args():
		call_deferred("_projectile_fx_smoke")
	if "--alert-ping-smoke" in OS.get_cmdline_args() or "--alert-ping-smoke" in OS.get_cmdline_user_args():
		call_deferred("_alert_ping_smoke")
	if "--input-flow-smoke" in OS.get_cmdline_args() or "--input-flow-smoke" in OS.get_cmdline_user_args():
		call_deferred("_input_flow_smoke")
	if "--mouse-input-smoke" in OS.get_cmdline_args() or "--mouse-input-smoke" in OS.get_cmdline_user_args():
		call_deferred("_mouse_input_smoke")
	if "--camera-zoom-smoke" in OS.get_cmdline_args() or "--camera-zoom-smoke" in OS.get_cmdline_user_args():
		call_deferred("_camera_zoom_smoke")
	if "--double-click-select-smoke" in OS.get_cmdline_args() or "--double-click-select-smoke" in OS.get_cmdline_user_args():
		call_deferred("_double_click_select_smoke")
	if "--minimap-command-smoke" in OS.get_cmdline_args() or "--minimap-command-smoke" in OS.get_cmdline_user_args():
		call_deferred("_minimap_command_smoke")
	if "--queue-status-smoke" in OS.get_cmdline_args() or "--queue-status-smoke" in OS.get_cmdline_user_args():
		call_deferred("_queue_status_smoke")
	if "--order-indicator-smoke" in OS.get_cmdline_args() or "--order-indicator-smoke" in OS.get_cmdline_user_args():
		call_deferred("_order_indicator_smoke")
	if "--intent-preflight-smoke" in OS.get_cmdline_args() or "--intent-preflight-smoke" in OS.get_cmdline_user_args():
		call_deferred("_intent_preflight_smoke")
	if "--faction-sprite-smoke" in OS.get_cmdline_args() or "--faction-sprite-smoke" in OS.get_cmdline_user_args():
		call_deferred("_faction_sprite_smoke")
	if "--unit-scale-smoke" in OS.get_cmdline_args() or "--unit-scale-smoke" in OS.get_cmdline_user_args():
		call_deferred("_unit_scale_smoke")
	if "--opening-balance-smoke" in OS.get_cmdline_args() or "--opening-balance-smoke" in OS.get_cmdline_user_args():
		call_deferred("_opening_balance_smoke")
	if "--control-group-smoke" in OS.get_cmdline_args() or "--control-group-smoke" in OS.get_cmdline_user_args():
		call_deferred("_control_group_smoke")
	if "--ready-defender-smoke" in OS.get_cmdline_args() or "--ready-defender-smoke" in OS.get_cmdline_user_args():
		call_deferred("_ready_defender_smoke")
	if "--command-marker-smoke" in OS.get_cmdline_args() or "--command-marker-smoke" in OS.get_cmdline_user_args():
		call_deferred("_command_marker_smoke")

func _reset_rival_state() -> void:
	_rival_food = Game.START_FOOD
	_rival_timber = Game.START_TIMBER
	_rival_memp = Game.START_MEMP
	_rival_pop = 0
	_rival_pop_cap = Game.START_POP_CAP
	_rival_atk_bonus = 0.0
	_rival_armor_bonus = 0.0
	_rival_eco_bonus = 1.0
	_rival_has_forge = false
	_rival_rally_point = Vector2.ZERO
	_player_rally_custom = false
	_rival_rally_custom = false

func _load_command_markers() -> void:
	command_markers.clear()
	for key in COMMAND_MARKER_PATHS.keys():
		var tex: Texture2D = load(String(COMMAND_MARKER_PATHS[key]))
		if tex != null:
			command_markers[key] = tex

func _result_smoke() -> void:
	_match_result = "won"
	_over = true
	_show_banner("VICTORY", Color("43c865"))
	await get_tree().create_timer(0.2).timeout
	var found_play := _tree_has_button_text(self, "PLAY AGAIN")
	var found_menu := _tree_has_button_text(self, "MAIN MENU")
	print("RESULT_SMOKE play_again=%s main_menu=%s" % [str(found_play).to_lower(), str(found_menu).to_lower()])
	get_tree().quit(0 if found_play and found_menu else 1)

func _web_result_smoke() -> void:
	if not OS.has_feature("web"):
		return
	await get_tree().create_timer(0.4).timeout
	_finish_by_concede(1)
	_publish_web_match_state({"webResultSmoke": true, "matchOver": _over, "matchResult": _match_result})

func _web_meme_sprite_preview() -> void:
	if not OS.has_feature("web"):
		return
	await get_tree().process_frame
	Game.player_king = "doge"
	camera.position = player_keep.position + Vector2(260, -360)
	_sync_camera_zoom()
	for u in units:
		if _node_alive(u):
			u.visible = false
			u.selected = false
	var placements := [
		{"king": "doge", "kind": "villager", "pos": player_keep.position + Vector2(80, -470), "dir": Vector2.DOWN},
		{"king": "doge", "kind": "swordsman", "pos": player_keep.position + Vector2(142, -478), "dir": Vector2.RIGHT},
		{"king": "doge", "kind": "archer", "pos": player_keep.position + Vector2(204, -486), "dir": Vector2.UP},
		{"king": "doge", "kind": "lancer", "pos": player_keep.position + Vector2(284, -500), "dir": Vector2.RIGHT},
		{"king": "doge", "kind": "siege", "pos": player_keep.position + Vector2(382, -508), "dir": Vector2.LEFT},
		{"king": "pepe", "kind": "villager", "pos": player_keep.position + Vector2(80, -352), "dir": Vector2.DOWN},
		{"king": "pepe", "kind": "swordsman", "pos": player_keep.position + Vector2(142, -360), "dir": Vector2.RIGHT},
		{"king": "pepe", "kind": "archer", "pos": player_keep.position + Vector2(204, -368), "dir": Vector2.UP},
		{"king": "pepe", "kind": "lancer", "pos": player_keep.position + Vector2(292, -382), "dir": Vector2.RIGHT},
		{"king": "pepe", "kind": "siege", "pos": player_keep.position + Vector2(392, -390), "dir": Vector2.LEFT},
	]
	var kinds := []
	var kings := []
	for p in placements:
		var king := String(p["king"])
		var kind := String(p["kind"])
		var u := _spawn_unit(king, kind, 0, p["pos"], 0, false)
		u.selected = true
		u._face_dir(p["dir"])
		u._set_sprite_frame(1)
		kinds.append(kind)
		if not kings.has(king):
			kings.append(king)
	Game.selection_changed.emit(kinds.size())
	Game.log_event("Israel and Palestine unit sprite preview staged.")
	_publish_web_match_state({
		"memeSpritePreview": true,
		"memeSpriteKings": kings,
		"memeSpriteKinds": kinds,
		"memeSpriteUnits": placements.size(),
	})

func _web_selection_summary_preview() -> void:
	if not OS.has_feature("web"):
		return
	await get_tree().create_timer(0.2).timeout
	var summary := _prepare_selection_summary_preview()
	_publish_web_match_state({
		"selectionSummaryPreview": true,
		"selectionSummaryCount": int(summary.get("count", 0)),
		"selectionSummaryComposition": String(summary.get("composition", "")),
		"selectionSummaryOrder": String(summary.get("order", "")),
	})

func _remote_result_smoke() -> void:
	Game.suppress_result_persistence = true
	Game.net_mode = "join"
	Game.my_team = 1
	Game.player_king = "doge"
	Game.rival_king = "pepe"
	var before_wins := int(Game.board.get("pepe", {}).get("wins", 0))
	_apply_snapshot({
		"over": true,
		"result": "lost",
		"seconds": 37,
		"wave": 2,
		"kills": 4,
		"resources": {"food": Game.food, "timber": Game.timber, "memp": Game.memp},
		"pop": {"live": Game.pop, "queued": queued_pop, "cap": Game.pop_cap},
		"units": [],
		"structures": [],
	})
	await get_tree().create_timer(0.2).timeout
	var after_wins := int(Game.board.get("pepe", {}).get("wins", 0))
	var ok := _remote_over_shown and _match_result == "won" and after_wins == before_wins + 1 and _tree_has_button_text(self, "PLAY AGAIN") and _tree_has_button_text(self, "MAIN MENU")
	print("REMOTE_RESULT_SMOKE local_result=%s king=%s recorded=%s" % [_match_result, Game.rival_king, str(after_wins == before_wins + 1).to_lower()])
	get_tree().quit(0 if ok else 1)

func _tower_target_smoke() -> void:
	var rival_tower := _add_structure("tower", 1, Vector2(820, 720))
	var player_unit := _spawn_unit(Game.player_king, "swordsman", 0, rival_tower.position + Vector2(42, 0), 0, false)
	var rival_unit := _spawn_unit(Game.rival_king, "swordsman", 1, rival_tower.position + Vector2(18, 0), 0, false)
	var target = _nearest_enemy_unit_for_team(rival_tower.position, 240.0, rival_tower.team)
	var ok: bool = target == player_unit and target != rival_unit
	print("TOWER_TARGET_SMOKE target_team=%s ok=%s" % [str(target.team if target != null else -1), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _build_placement_smoke() -> void:
	var before_timber := Game.timber
	var before_pop_cap := Game.pop_cap
	var before_count := structures.size()
	build_mode = "house"
	_place_build(player_keep.position)
	var rejected := Game.timber == before_timber and Game.pop_cap == before_pop_cap and structures.size() == before_count and build_mode == "house"
	_place_build(player_keep.position + Vector2(225, 0))
	var accepted := Game.timber < before_timber and Game.pop_cap == before_pop_cap + 6 and structures.size() == before_count + 1 and build_mode == ""
	print("BUILD_PLACEMENT_SMOKE rejected=%s accepted=%s" % [str(rejected).to_lower(), str(accepted).to_lower()])
	get_tree().quit(0 if rejected and accepted else 1)

func _build_ghost_smoke() -> void:
	begin_build("house")
	var started := build_mode == "house" and is_instance_valid(build_ghost)
	_update_build_ghost_at(player_keep.position)
	var invalid_red := is_instance_valid(build_ghost) and build_ghost.modulate.r > build_ghost.modulate.g
	_update_build_ghost_at(player_keep.position + Vector2(225, 0))
	var valid_blue := is_instance_valid(build_ghost) and build_ghost.modulate.g >= build_ghost.modulate.r and build_ghost.modulate.b >= build_ghost.modulate.r
	_cancel_build()
	var ok := started and invalid_red and valid_blue and build_mode == ""
	print("BUILD_GHOST_SMOKE started=%s invalid=%s valid=%s ok=%s" % [str(started).to_lower(), str(invalid_red).to_lower(), str(valid_blue).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _resource_depletion_smoke() -> void:
	var node := _add_resource(player_keep.position + Vector2(140, 0), "food")
	node.amount = 5
	var vill := _spawn_unit(Game.player_king, "villager", 0, node.position + Vector2(8, 0), 0, false)
	var before_food := Game.food
	vill.order_gather(node)
	vill._gather(1.0)
	var depleted := node.amount == 0 and node.is_queued_for_deletion()
	await get_tree().process_frame
	var gained := Game.food - before_food
	var ok := gained == 5 and depleted
	print("RESOURCE_DEPLETION_SMOKE gained=%d depleted=%s" % [gained, str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _destroyed_entity_smoke() -> void:
	Game.suppress_result_persistence = true
	var doomed := _spawn_unit(Game.rival_king, "swordsman", 1, player_keep.position + Vector2(60, 0), 0, false)
	doomed.take_damage(9999.0)
	rival_keep.take_damage(99999.0)
	_check_win()
	var snap := _room_snapshot()
	var unit_gone := true
	for d in snap.get("units", []):
		if int(d.get("id", 0)) == doomed.net_id:
			unit_gone = false
	var rival_keep_gone := true
	for d in snap.get("structures", []):
		if int(d.get("id", 0)) == rival_keep.net_id:
			rival_keep_gone = false
	var ok := _over and _match_result == "won" and unit_gone and rival_keep_gone
	print("DESTROYED_ENTITY_SMOKE result=%s unit_gone=%s keep_gone=%s" % [_match_result, str(unit_gone).to_lower(), str(rival_keep_gone).to_lower()])
	get_tree().quit(0 if ok else 1)

func _structure_stats_smoke() -> void:
	var house := _add_structure("house", 0, player_keep.position + Vector2(245, 0))
	var forge := _add_structure("forge", 0, player_keep.position + Vector2(405, 0))
	var tower := _add_structure("tower", 0, player_keep.position + Vector2(570, 0))
	var market := _add_structure("market", 0, player_keep.position + Vector2(735, 0))
	var stats_ok := player_keep.max_hp == 1200.0 and house.max_hp == 400.0 and forge.max_hp == 600.0 and tower.max_hp == 700.0 and market.max_hp == 650.0
	var art_ok := _structure_sprite_path(house).ends_with("house_asset.png") and _structure_sprite_path(forge).ends_with("forge_asset.png") and _structure_sprite_path(tower).ends_with("tower_asset.png") and _structure_sprite_path(market).ends_with("market_asset.png")
	var scale_ok := _structure_sprite_scale(player_keep) >= 1.5 and _structure_sprite_scale(house) >= 1.3 and _structure_radius("keep") > _structure_radius("house")
	var ok := stats_ok and art_ok and scale_ok
	print("STRUCTURE_STATS_SMOKE keep=%d house=%d forge=%d tower=%d market=%d art=%s scale=%s ok=%s" % [int(player_keep.max_hp), int(house.max_hp), int(forge.max_hp), int(tower.max_hp), int(market.max_hp), str(art_ok).to_lower(), str(scale_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _structure_sprite_path(st: Structure) -> String:
	if not _node_alive(st):
		return ""
	for child in st.get_children():
		if child is Sprite2D:
			var tex: Texture2D = (child as Sprite2D).texture
			return tex.resource_path if tex != null else ""
	return ""

func _structure_sprite_scale(st: Structure) -> float:
	if not _node_alive(st):
		return 0.0
	for child in st.get_children():
		if child is Sprite2D:
			return (child as Sprite2D).scale.x
	return 0.0

func _remote_economy_smoke() -> void:
	_rival_food = 260
	_rival_timber = 230
	_rival_memp = 100
	var build_forge := _apply_remote_intent({"intent": {"id": "forge", "action": "build", "side": "rival", "structure": "forge"}})
	var research_atk := _apply_remote_intent({"intent": {"id": "atk", "action": "research", "side": "rival", "structure": "upgrade_atk"}})
	var build_market := _apply_remote_intent({"intent": {"id": "market", "action": "build", "side": "rival", "structure": "market"}})
	_market_income()
	var train_siege := _apply_remote_intent({"intent": {"id": "siege", "action": "train", "side": "rival", "unit": "siege"}})
	var snap := _room_snapshot()
	var rival_resources: Dictionary = snap.get("rivalResources", {})
	var rival_pop: Dictionary = snap.get("rivalPop", {})
	var ok := bool(build_forge.get("accepted", false)) \
		and bool(research_atk.get("accepted", false)) \
		and not bool(train_siege.get("accepted", true)) \
		and bool(build_market.get("accepted", false)) \
		and _rival_has_forge \
		and _rival_atk_bonus == 3.0 \
		and _rival_timber == 23 \
		and _rival_memp == 11 \
		and int(rival_resources.get("timber", 0)) == _rival_timber \
		and int(rival_pop.get("cap", 0)) == _rival_pop_cap
	print("REMOTE_ECONOMY_SMOKE forge=%s research=%s siege=%s market=%s timber=%d memp=%d atk=%d ok=%s" % [str(bool(build_forge.get("accepted", false))).to_lower(), str(bool(research_atk.get("accepted", false))).to_lower(), str(bool(train_siege.get("accepted", false))).to_lower(), str(bool(build_market.get("accepted", false))).to_lower(), _rival_timber, _rival_memp, int(_rival_atk_bonus), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _remote_authority_smoke() -> void:
	_rival_food = 500
	_rival_timber = 500
	_rival_memp = 500
	var rally_before := _rival_rally_point
	var rally_result := _apply_remote_intent({"intent": {"id": "rally", "action": "rally", "side": "rival"}})
	var expected_rally := _default_rally_for_team(1)
	var rally_ok := bool(rally_result.get("accepted", false)) and _rival_rally_point == expected_rally and _rival_rally_point != rally_before
	var unit_count := units.size()
	var train_result := _apply_remote_intent({"intent": {"id": "train", "action": "train", "side": "rival", "unit": "swordsman"}})
	var trained: Unit = units[units.size() - 1] if units.size() > unit_count else null
	var train_ok := bool(train_result.get("accepted", false)) and _node_alive(trained) and trained.team == 1 and trained.target.distance_to(_rival_rally_point) < 40.0
	var structure_count := structures.size()
	var timber_before_build := _rival_timber
	var build_result := _apply_remote_intent({"intent": {"id": "build", "action": "build", "side": "rival", "structure": "tower"}})
	var built: Structure = structures[structures.size() - 1] if structures.size() > structure_count else null
	var build_ok := bool(build_result.get("accepted", false)) and _node_alive(built) and built.team == 1 and built.kind == "tower" and built.position.distance_to(rival_keep.position) >= _structure_radius("tower") + _structure_radius("keep")
	var build_paid := _rival_timber == timber_before_build - int(Game.COSTS["tower"].get("timber", 0))
	for i in range(40):
		var spot := _find_build_spot(rival_keep.position, "house", 1)
		if not spot.is_finite():
			break
		_add_structure("house", 1, spot)
	var timber_before_reject := _rival_timber
	var blocked_result := _apply_remote_intent({"intent": {"id": "blocked", "action": "build", "side": "rival", "structure": "house"}})
	var blocked_ok := not bool(blocked_result.get("accepted", true)) and String(blocked_result.get("reason", "")) == "no build space" and _rival_timber == timber_before_reject
	var ok := rally_ok and train_ok and build_ok and build_paid and blocked_ok
	print("REMOTE_AUTHORITY_SMOKE rally=%s train=%s build=%s paid=%s blocked=%s ok=%s" % [str(rally_ok).to_lower(), str(train_ok).to_lower(), str(build_ok).to_lower(), str(build_paid).to_lower(), str(blocked_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _remote_order_smoke() -> void:
	Game.net_mode = "join"
	Game.my_team = 1
	Net.connected = true
	_intents_sent = 0
	_last_intent_sent = {}
	var target := Vector2(WORLD.x * 0.58, WORLD.y * 0.35)
	_issue_order(target)
	var order_payload: Dictionary = _last_intent_sent
	cmd_rally()
	_set_local_rally(target + Vector2(44, 28))
	var rally_payload: Dictionary = _last_intent_sent
	var sent_ok := _intents_sent == 2 \
		and String(order_payload.get("action", "")) == "order" \
		and order_payload.has("x") and order_payload.has("y") \
		and String(rally_payload.get("action", "")) == "rally" \
		and rally_payload.has("x") and rally_payload.has("y")
	Game.net_mode = "host"
	Game.my_team = 0
	_spawn_unit(Game.rival_king, "swordsman", 1, rival_keep.position + Vector2(0, 70), 0, false)
	var apply_result := _apply_remote_intent({"intent": {"id": "order-1", "action": "order", "side": "rival", "x": int(target.x), "y": int(target.y)}})
	var ordered_units := 0
	for u in _team_units(1):
		if u.target.distance_to(target) < 120.0:
			ordered_units += 1
	var host_ok := bool(apply_result.get("accepted", false)) and ordered_units > 0
	var ok := sent_ok and host_ok
	print("REMOTE_ORDER_SMOKE sent=%s host=%s x=%d y=%d ok=%s" % [str(sent_ok).to_lower(), str(host_ok).to_lower(), int(order_payload.get("x", -1)), int(order_payload.get("y", -1)), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _remote_order_target_smoke() -> void:
	Game.net_mode = "host"
	Game.my_team = 0
	var soldier := _spawn_unit(Game.rival_king, "swordsman", 1, rival_keep.position + Vector2(0, 86), 0, false)
	var vill := _spawn_unit(Game.rival_king, "villager", 1, rival_keep.position + Vector2(34, 86), 0, false)
	var attack_result := _apply_remote_intent({"intent": {"id": "atk-point", "action": "order", "side": "rival", "x": int(player_keep.position.x), "y": int(player_keep.position.y)}})
	var attack_ok := bool(attack_result.get("accepted", false)) and soldier.attack_target == player_keep
	var food := food_nodes[0]
	var gather_result := _apply_remote_intent({"intent": {"id": "gather-point", "action": "order", "side": "rival", "x": int(food.position.x), "y": int(food.position.y)}})
	var gather_ok := bool(gather_result.get("accepted", false)) and vill.gather_target == food
	var ok := attack_ok and gather_ok
	print("REMOTE_ORDER_TARGET_SMOKE attack=%s gather=%s ok=%s" % [str(attack_ok).to_lower(), str(gather_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _multiplayer_setup_smoke() -> void:
	var rival_villagers := 0
	for u in units:
		if _node_alive(u) and u.team == 1 and u.kind == "villager":
			rival_villagers += 1
	var rival_resources := 0
	for node in food_nodes:
		if _node_alive(node) and node.position.distance_to(rival_keep.position) < 380.0:
			rival_resources += 1
	var before_units := units.size()
	var before_wave := Game.wave
	_match_t = 11.0
	_ai_t = 3.0
	_wave_t = _wave_interval()
	_process(0.1)
	var no_free_ai := units.size() == before_units and Game.wave == before_wave
	var ok := Game.net_mode == "host" and rival_villagers == 4 and _rival_pop == 6 and rival_resources >= 6 and no_free_ai
	print("MULTIPLAYER_SETUP_SMOKE rival_vills=%d rival_pop=%d rival_resources=%d no_free_ai=%s ok=%s" % [rival_villagers, _rival_pop, rival_resources, str(no_free_ai).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _remote_concede_smoke() -> void:
	Game.suppress_result_persistence = true
	Game.net_mode = "host"
	Game.my_team = 0
	var result := _apply_remote_intent({"intent": {"id": "gg", "action": "concede", "side": "rival"}})
	var snap := _room_snapshot()
	var ok := bool(result.get("accepted", false)) \
		and _over \
		and _match_result == "won" \
		and bool(snap.get("over", false)) \
		and String(snap.get("result", "")) == "won" \
		and String(result.get("reason", "")) == "concede accepted"
	print("REMOTE_CONCEDE_SMOKE accepted=%s result=%s over=%s snap=%s ok=%s" % [str(bool(result.get("accepted", false))).to_lower(), _match_result, str(_over).to_lower(), String(snap.get("result", "")), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _net_leave_smoke() -> void:
	Net.room = "STALE"
	Net.role = "host"
	Net.connected = true
	Net.roster = [{"from": "join", "role": "join"}]
	Net.leave()
	var ok := Net.room == "" and Net.role == "" and not Net.connected and Net.roster.is_empty()
	print("NET_LEAVE_SMOKE room_empty=%s role_empty=%s disconnected=%s roster_empty=%s ok=%s" % [str(Net.room == "").to_lower(), str(Net.role == "").to_lower(), str(not Net.connected).to_lower(), str(Net.roster.is_empty()).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _hud_team_smoke() -> void:
	Game.net_mode = "host"
	Game.my_team = 0
	Game.food = 401
	Game.pop = 6
	Game.has_forge = true
	_rival_food = 123
	_rival_pop = 2
	_rival_has_forge = false
	var host_ok := hud_food() == 401 and hud_pop() == 6 and hud_has_forge() and hud_can_afford("villager")
	rival_keep.take_damage(99999.0)
	var host_enemy_done := hud_enemy_keep_destroyed()
	Game.net_mode = "join"
	Game.my_team = 1
	var join_ok := hud_food() == 123 and hud_pop() == 2 and not hud_has_forge() and not hud_can_afford("upgrade_atk")
	player_keep.take_damage(99999.0)
	var join_enemy_done := hud_enemy_keep_destroyed()
	var ok := host_ok and host_enemy_done and join_ok and join_enemy_done
	print("HUD_TEAM_SMOKE host=%s host_enemy=%s join=%s join_enemy=%s ok=%s" % [str(host_ok).to_lower(), str(host_enemy_done).to_lower(), str(join_ok).to_lower(), str(join_enemy_done).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _tech_status_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	Game.atk_bonus = 3.0
	Game.armor_bonus = 2.0
	Game.eco_bonus = 1.25
	Game.has_forge = true
	var player_summary := hud_tech_summary()
	var player_ok := int(player_summary.get("atk", 0)) == 3 \
		and int(player_summary.get("armor", 0)) == 2 \
		and int(player_summary.get("ecoPct", 0)) == 125 \
		and bool(player_summary.get("forge", false))
	Game.net_mode = "join"
	Game.my_team = 1
	_rival_atk_bonus = 6.0
	_rival_armor_bonus = 4.0
	_rival_eco_bonus = 1.5
	_rival_has_forge = true
	var join_summary := hud_tech_summary()
	var join_ok := int(join_summary.get("atk", 0)) == 6 \
		and int(join_summary.get("armor", 0)) == 4 \
		and int(join_summary.get("ecoPct", 0)) == 150 \
		and bool(join_summary.get("forge", false))
	var ok := player_ok and join_ok
	print("TECH_STATUS_SMOKE player=%s join=%s atk=%d armor=%d eco=%d ok=%s" % [str(player_ok).to_lower(), str(join_ok).to_lower(), int(join_summary.get("atk", 0)), int(join_summary.get("armor", 0)), int(join_summary.get("ecoPct", 0)), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _selection_summary_smoke() -> void:
	var summary := _prepare_selection_summary_preview()
	var composition := String(summary.get("composition", ""))
	var ok := int(summary.get("count", 0)) == 2 \
		and composition.contains("ISR WORK") \
		and composition.contains("ISR INF") \
		and int(summary.get("avgHp", 100)) < 100 \
		and String(summary.get("order", "")) == "MIXED"
	print("SELECTION_SUMMARY_SMOKE count=%d composition=%s hp=%d order=%s ok=%s" % [int(summary.get("count", 0)), composition, int(summary.get("avgHp", 0)), String(summary.get("order", "")), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _prepare_selection_summary_preview() -> Dictionary:
	for u in units:
		if _node_alive(u):
			u.selected = false
	var vill: Unit = units[0]
	var sword := _spawn_unit(Game.player_king, "swordsman", 0, player_keep.position + Vector2(96, -48), 0, false)
	vill.selected = true
	sword.selected = true
	sword.hp = sword.max_hp * 0.5
	sword.order_attack(rival_keep)
	var summary := hud_selection_summary()
	Game.selection_changed.emit(int(summary.get("count", 0)))
	return summary

func _projectile_fx_smoke() -> void:
	_projectile_debug_counts.clear()
	spawn_projectile(player_keep.position, player_keep.position + Vector2(80, -20), "arrow")
	spawn_projectile(player_keep.position, player_keep.position + Vector2(80, 0), "bolt")
	spawn_projectile(player_keep.position, player_keep.position + Vector2(80, 20), "stone")
	await get_tree().process_frame
	var arrow_ok := int(_projectile_debug_counts.get("arrow", 0)) == 1
	var bolt_ok := int(_projectile_debug_counts.get("bolt", 0)) == 1
	var stone_ok := int(_projectile_debug_counts.get("stone", 0)) == 1
	var assets_ok := load(_projectile_texture_path("arrow")) != null \
		and load(_projectile_texture_path("bolt")) != null \
		and load(_projectile_texture_path("stone")) != null \
		and load(_projectile_texture_path("impact")) != null
	var ok := arrow_ok and bolt_ok and stone_ok and assets_ok
	print("PROJECTILE_FX_SMOKE arrow=%s bolt=%s stone=%s assets=%s ok=%s" % [str(arrow_ok).to_lower(), str(bolt_ok).to_lower(), str(stone_ok).to_lower(), str(assets_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _alert_ping_smoke() -> void:
	alert_pings.clear()
	_alert_debug_counts.clear()
	add_alert_ping(player_keep.position, "danger")
	add_alert_ping(player_keep.position + Vector2(72, 0), "build")
	add_alert_ping(rally_point, "rally")
	await get_tree().process_frame
	var danger_ok := int(_alert_debug_counts.get("danger", 0)) == 1
	var build_ok := int(_alert_debug_counts.get("build", 0)) == 1
	var rally_ok := int(_alert_debug_counts.get("rally", 0)) == 1
	var visible_ok := alert_pings.size() == 3 and alert_ping_color("danger").a > 0.0 and alert_ping_color("build").a > 0.0
	var ok := danger_ok and build_ok and rally_ok and visible_ok
	print("ALERT_PING_SMOKE danger=%s build=%s rally=%s visible=%s ok=%s" % [str(danger_ok).to_lower(), str(build_ok).to_lower(), str(rally_ok).to_lower(), str(visible_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _input_flow_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	train_unit("villager")
	var train_ok := train_queue.size() == 1 and queued_pop == 1
	begin_build("house")
	var build_started := build_mode == "house" and is_instance_valid(build_ghost)
	_cancel_build()
	var build_cancelled := build_mode == "" and not is_instance_valid(build_ghost)
	for u in units:
		u.selected = false
	sel_start = units[0].position
	sel_now = units[0].position
	_finish_selection()
	var select_ok := _selected().size() == 1
	sel_start = units[1].position
	sel_now = units[1].position
	_finish_selection(true)
	var additive_ok := _selected().size() == 2
	var selected_units := _selected()
	var selected: Unit = selected_units[0] if not selected_units.is_empty() else null
	var before_target := selected.target if selected != null else Vector2.INF
	if selected != null:
		_issue_order(player_keep.position + Vector2(210, -120))
	var order_ok := selected != null and selected.target.distance_to(before_target) > 20.0
	var edge_constants_ok := EDGE_PAN_MARGIN > 0.0 and EDGE_PAN_SPEED > 0.0
	var ok := train_ok and build_started and build_cancelled and select_ok and additive_ok and order_ok and edge_constants_ok
	print("INPUT_FLOW_SMOKE train=%s build=%s cancel=%s select=%s additive=%s order=%s edge=%s ok=%s" % [str(train_ok).to_lower(), str(build_started).to_lower(), str(build_cancelled).to_lower(), str(select_ok).to_lower(), str(additive_ok).to_lower(), str(order_ok).to_lower(), str(edge_constants_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _mouse_input_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	for u in units:
		if _node_alive(u):
			u.selected = false
	var clicked: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0:
			clicked = u
			break
	if clicked == null:
		print("MOUSE_INPUT_SMOKE select=false zoom=false order=false ok=false")
		get_tree().quit(1)
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _world_to_screen(clicked.position)
	_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = _world_to_screen(clicked.position)
	_input(release)
	var select_ok := clicked.selected and _selected().size() == 1
	var before_zoom := zoom_level
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = _world_to_screen(clicked.position)
	_input(wheel)
	var zoom_ok := zoom_level > before_zoom
	var before_target := clicked.target
	var order_pos := clicked.position + Vector2(180, -90)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = _world_to_screen(order_pos)
	_input(right)
	var order_ok := clicked.target.distance_to(before_target) > 20.0
	var ok := select_ok and zoom_ok and order_ok
	print("MOUSE_INPUT_SMOKE select=%s zoom=%s order=%s ok=%s" % [str(select_ok).to_lower(), str(zoom_ok).to_lower(), str(order_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _camera_zoom_smoke() -> void:
	var before := zoom_level
	cmd_zoom_in()
	var in_ok := zoom_level > before and is_equal_approx(camera.zoom.x, maxf(zoom_level, _min_camera_zoom_for_viewport()))
	cmd_zoom_out()
	cmd_zoom_out()
	var out_ok := zoom_level < before and is_equal_approx(camera.zoom.x, maxf(zoom_level, _min_camera_zoom_for_viewport()))
	cmd_zoom_reset()
	var reset_ok := is_equal_approx(zoom_level, 1.0) and is_equal_approx(camera.zoom.x, maxf(1.0, _min_camera_zoom_for_viewport()))
	var ok := in_ok and out_ok and reset_ok
	print("CAMERA_ZOOM_SMOKE in=%s out=%s reset=%s ok=%s" % [str(in_ok).to_lower(), str(out_ok).to_lower(), str(reset_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _double_click_select_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	camera.position = player_keep.position + Vector2(120, -120)
	_clamp_camera()
	for u in units:
		if _node_alive(u):
			u.selected = false
	var clicked: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "villager":
			clicked = u
			break
	if clicked == null:
		print("DOUBLE_CLICK_SELECT_SMOKE target=false selected=0 expected=0 additive=false ok=false")
		get_tree().quit(1)
		return
	sel_start = clicked.position
	sel_now = clicked.position
	_finish_selection(false, true)
	var expected := 0
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == clicked.kind and _visible_world_rect().grow(80.0).has_point(u.position):
			expected += 1
	var selected_after_double := _selected().size()
	var base_ok := selected_after_double == expected and expected >= 2
	var soldier: Unit = null
	var visible := _visible_world_rect().grow(80.0)
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "swordsman" and visible.has_point(u.position):
			soldier = u
			break
	if soldier == null:
		soldier = _spawn_unit(Game.player_king, "swordsman", 0, camera.position + Vector2(34, 0), 0, false)
		visible = _visible_world_rect().grow(80.0)
	if soldier != null:
		sel_start = soldier.position
		sel_now = soldier.position
		_finish_selection(true, true)
	var expected_additive := expected
	if soldier != null:
		for u in units:
			if _node_alive(u) and u.team == 0 and u.kind == soldier.kind and visible.has_point(u.position):
				expected_additive += 1
	var selected_after_additive := _selected().size()
	var additive_ok := soldier != null and soldier.selected and selected_after_additive == expected_additive
	var ok := base_ok and additive_ok
	print("DOUBLE_CLICK_SELECT_SMOKE target=true selected=%d expected=%d selectedAdditive=%d expectedAdditive=%d soldier=%s additive=%s ok=%s" % [selected_after_double, expected, selected_after_additive, expected_additive, str(soldier != null and soldier.selected).to_lower(), str(additive_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _minimap_command_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	var center_pos := WORLD * 0.5
	minimap_click(center_pos, MOUSE_BUTTON_LEFT)
	var centered := is_instance_valid(camera) and camera.position.distance_to(center_pos) < 2.0
	for u in units:
		if _node_alive(u):
			u.selected = false
	var selected_unit: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0:
			selected_unit = u
			u.selected = true
			break
	var order_pos := Vector2(WORLD.x * 0.46, WORLD.y * 0.36)
	minimap_click(order_pos, MOUSE_BUTTON_RIGHT)
	var ordered := selected_unit != null and selected_unit.target.distance_to(order_pos + Vector2(-39, 0)) < 2.0
	var rally_pos := Vector2(WORLD.x * 0.38, WORLD.y * 0.66)
	rally_set = true
	minimap_click(rally_pos, MOUSE_BUTTON_LEFT)
	var rally_ok := not rally_set and rally_point.distance_to(rally_pos) < 2.0
	var ok := centered and ordered and rally_ok
	print("MINIMAP_COMMAND_SMOKE center=%s order=%s rally=%s ok=%s" % [str(centered).to_lower(), str(ordered).to_lower(), str(rally_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _queue_status_smoke() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	Game.food = 260
	Game.timber = 230
	Game.memp = 60
	train_queue.clear()
	queued_pop = 0
	train_unit("archer")
	var start_summary := hud_queue_summary()
	var archer_time := _train_time("archer")
	train_queue[0]["t"] = archer_time * 0.5
	var half_summary := hud_queue_summary()
	var count_ok := int(start_summary.get("count", 0)) == 1 and int(half_summary.get("count", 0)) == 1
	var name_ok := String(half_summary.get("name", "")) == Game.unit_label("archer", Game.player_king)
	var pct_ok := int(half_summary.get("pct", 0)) == 50
	var seconds_ok := int(half_summary.get("seconds", 0)) == int(ceil(archer_time * 0.5))
	var ok := count_ok and name_ok and pct_ok and seconds_ok
	print("QUEUE_STATUS_SMOKE count=%s name=%s pct=%d seconds=%d ok=%s" % [str(count_ok).to_lower(), str(name_ok).to_lower(), int(half_summary.get("pct", 0)), int(half_summary.get("seconds", 0)), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _order_indicator_smoke() -> void:
	for u in units:
		if _node_alive(u):
			u.selected = false
	var unit: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0:
			unit = u
			unit.selected = true
			break
	if unit == null:
		print("ORDER_INDICATOR_SMOKE move=false gather=false attack=false ok=false")
		get_tree().quit(1)
		return
	unit.order_move(unit.position + Vector2(180, -45))
	var move_ok := int(selected_order_indicator_count().get("move", 0)) == 1
	unit.order_gather(food_nodes[0])
	var gather_ok := int(selected_order_indicator_count().get("gather", 0)) == 1
	unit.order_attack(rival_keep)
	var attack_ok := int(selected_order_indicator_count().get("attack", 0)) == 1
	var ok := move_ok and gather_ok and attack_ok
	print("ORDER_INDICATOR_SMOKE move=%s gather=%s attack=%s ok=%s" % [str(move_ok).to_lower(), str(gather_ok).to_lower(), str(attack_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _intent_preflight_smoke() -> void:
	Game.net_mode = "join"
	Game.my_team = 1
	Net.connected = true
	_rival_food = 0
	_rival_timber = 0
	_rival_memp = 0
	_rival_pop = 0
	_rival_pop_cap = 20
	_rival_has_forge = false
	_intents_sent = 0
	train_unit("villager")
	var train_blocked := _intents_sent == 0
	begin_build("house")
	var build_blocked := _intents_sent == 0
	do_research("upgrade_atk")
	var research_blocked := _intents_sent == 0
	_rival_food = 60
	train_unit("villager")
	var train_sent := _intents_sent == 1
	var ok := train_blocked and build_blocked and research_blocked and train_sent
	print("INTENT_PREFLIGHT_SMOKE train_blocked=%s build_blocked=%s research_blocked=%s train_sent=%s ok=%s" % [str(train_blocked).to_lower(), str(build_blocked).to_lower(), str(research_blocked).to_lower(), str(train_sent).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _faction_sprite_smoke() -> void:
	var kinds := ["villager", "swordsman", "archer", "lancer", "siege"]
	var loaded := true
	var transparent := true
	var spawned := true
	var directional := true
	var readable_scale := true
	var frames_populated := true
	var role_distinct := true
	var signatures := {}
	var spawn_i := 0
	for king in Game.KING_ORDER:
		for kind in kinds:
			var tex: Texture2D = load(Game.unit_sheet(king, kind))
			loaded = loaded and tex != null and tex.get_width() == 192 and tex.get_height() == 192
			if tex != null:
				var img := tex.get_image()
				transparent = transparent and img.get_pixel(0, 0).a < 0.01 and img.get_pixel(191, 191).a < 0.01
				var first_signature := 0
				for row in range(4):
					for col in range(4):
						var visible_pixels := 0
						for y in range(row * 48, row * 48 + 48):
							for x in range(col * 48, col * 48 + 48):
								var px := img.get_pixel(x, y)
								if px.a > 0.05:
									visible_pixels += 1
									if row == 0 and col == 0:
										first_signature = (first_signature + int(px.r * 255.0) * 3 + int(px.g * 255.0) * 5 + int(px.b * 255.0) * 7 + x * 11 + y * 13) % 1000000007
						frames_populated = frames_populated and visible_pixels > 180
				var sig_key := "%s:%d" % [king, first_signature]
				role_distinct = role_distinct and not signatures.has(sig_key)
				signatures[sig_key] = true
			var u := _spawn_unit(king, kind, 0, player_keep.position + Vector2(160 + spawn_i * 34, -40), 0, false)
			spawn_i += 1
			spawned = spawned and _node_alive(u) and u.king == king and u.kind == kind and u._sprite.texture != null
			readable_scale = readable_scale and u._sprite.scale.x >= 1.5 and u._sprite.position.y < -15.0
			u._face_dir(Vector2.RIGHT)
			u._set_sprite_frame(1)
			var side_frame: int = u._sprite.frame
			u._face_dir(Vector2.UP)
			u._set_sprite_frame(2)
			var up_frame: int = u._sprite.frame
			directional = directional and side_frame >= 4 and side_frame < 8 and up_frame >= 8
	var ok := loaded and transparent and spawned and directional and readable_scale and frames_populated and role_distinct
	print("FACTION_SPRITE_SMOKE loaded=%s transparent=%s spawned=%s directional=%s readable_scale=%s frames=%s distinct=%s ok=%s" % [str(loaded).to_lower(), str(transparent).to_lower(), str(spawned).to_lower(), str(directional).to_lower(), str(readable_scale).to_lower(), str(frames_populated).to_lower(), str(role_distinct).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _opening_balance_smoke() -> void:
	var player_villagers := 0
	var player_army := 0
	var rival_army := 0
	for u in units:
		if not _node_alive(u):
			continue
		if u.team == 0 and u.kind == "villager":
			player_villagers += 1
		elif u.team == 0:
			player_army += 1
		elif u.team == 1 and u.kind != "villager":
			rival_army += 1
	var resources_ok := Game.food >= 400 and Game.timber >= 340 and Game.memp >= 80 and Game.pop_cap >= 24
	var defenders_ok := player_villagers >= 4 and player_army >= 2 and rival_army >= 2
	var keep_fire_ok := towers.has(player_keep) and towers.has(rival_keep)
	var timing_ok := AI_FREE_SPAWN_START >= 30.0 and FIRST_WAVE_START >= 24.0 and ENEMY_ATTACK_GRACE >= 36.0 and _wave_interval() >= 28.0
	var villager_ok := false
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "villager":
			villager_ok = u.max_hp >= 60.0
			break
	var scale_ok := Structure.visual_scale_for("keep") > Structure.visual_scale_for("house") and Structure.footprint_radius_for("keep") > Structure.footprint_radius_for("house")
	var ok := resources_ok and defenders_ok and keep_fire_ok and timing_ok and villager_ok and scale_ok
	print("OPENING_BALANCE_SMOKE resources=%s defenders=%s keep_fire=%s timing=%s villager=%s scale=%s ok=%s" % [str(resources_ok).to_lower(), str(defenders_ok).to_lower(), str(keep_fire_ok).to_lower(), str(timing_ok).to_lower(), str(villager_ok).to_lower(), str(scale_ok).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _control_group_smoke() -> void:
	var army := []
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind != "villager":
			army.append(u)
	_select_units(army)
	cmd_assign_control_group(1)
	for u in units:
		if _node_alive(u):
			u.selected = false
	cmd_recall_control_group(1)
	var recalled := _selected().size() == army.size() and army.size() >= 2
	var defend_point := _defensive_point_for_team(0)
	cmd_defend_base()
	var defending := true
	for item in army:
		var u := item as Unit
		defending = defending and _node_alive(u) and u.target.distance_to(defend_point) < 80.0 and not _node_alive(u.attack_target)
	var counts: Dictionary = hud_control_group_counts()
	var counted := int(counts.get(1, 0)) == army.size()
	var ok := recalled and defending and counted
	print("CONTROL_GROUP_SMOKE recalled=%s defending=%s counted=%s ok=%s" % [str(recalled).to_lower(), str(defending).to_lower(), str(counted).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _ready_defender_smoke() -> void:
	train_queue.clear()
	queued_pop = 0
	_player_rally_custom = false
	var before_id := _next_net_id
	train_queue.append({"kind": "swordsman", "t": 0.0})
	queued_pop = 1
	_process_queue(0.1)
	var defender: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "swordsman" and u.net_id >= before_id:
			if defender == null or u.net_id > defender.net_id:
				defender = u
	var defend_point := _defensive_point_for_team(0)
	var guard_ready := _node_alive(defender) and defender.target.distance_to(defend_point) < 90.0 and defender.player_ordered == false

	before_id = _next_net_id
	train_queue.append({"kind": "villager", "t": 0.0})
	queued_pop = 1
	_process_queue(0.1)
	var worker: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "villager" and u.net_id >= before_id:
			worker = u
	var worker_ready := _node_alive(worker) and _node_alive(worker.gather_target)

	_player_rally_custom = true
	rally_point = player_keep.position + Vector2(240, -64)
	before_id = _next_net_id
	train_queue.append({"kind": "archer", "t": 0.0})
	queued_pop = 1
	_process_queue(0.1)
	var rallied: Unit = null
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind == "archer" and u.net_id >= before_id:
			rallied = u
	var custom_rally := _node_alive(rallied) and rallied.target.distance_to(rally_point) < 70.0 and rallied.player_ordered
	var ok := guard_ready and worker_ready and custom_rally
	print("READY_DEFENDER_SMOKE guard=%s worker=%s rally=%s ok=%s" % [str(guard_ready).to_lower(), str(worker_ready).to_lower(), str(custom_rally).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _command_marker_smoke() -> void:
	var loaded := true
	for key in COMMAND_MARKER_PATHS.keys():
		loaded = loaded and command_markers.has(key) and command_markers[key] != null
	var army := []
	for u in units:
		if _node_alive(u) and u.team == 0 and u.kind != "villager":
			army.append(u)
	if not army.is_empty():
		_select_units(army)
	cmd_attack_move()
	var order_counts := selected_order_indicator_count()
	var indicators := int(order_counts.get("move", 0)) + int(order_counts.get("attack", 0)) + int(order_counts.get("gather", 0)) > 0
	var ok := loaded and indicators
	print("COMMAND_MARKER_SMOKE loaded=%s indicators=%s ok=%s" % [str(loaded).to_lower(), str(indicators).to_lower(), str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _unit_scale_smoke() -> void:
	var loaded := true
	var scale_ok := true
	var click_area := true
	var spawned := 0
	for king in Game.KING_ORDER:
		for kind in Game.UNIT_KINDS:
			var tex: Texture2D = load(Game.unit_sheet(king, kind))
			loaded = loaded and tex != null and tex.get_width() == 192 and tex.get_height() == 192
			var u := _spawn_unit(king, kind, 0, player_keep.position + Vector2(140 + spawned * 6, -130 + spawned * 3), 0, false)
			spawned += 1
			scale_ok = scale_ok and u._sprite.scale.x >= 1.5
			click_area = click_area and u.click_radius() >= (31.0 if kind == "siege" else 26.0)
	var ok := loaded and scale_ok and click_area and spawned == Game.KING_ORDER.size() * Game.UNIT_KINDS.size()
	print("UNIT_SCALE_SMOKE loaded=%s scale=%s click=%s spawned=%d ok=%s" % [str(loaded).to_lower(), str(scale_ok).to_lower(), str(click_area).to_lower(), spawned, str(ok).to_lower()])
	get_tree().quit(0 if ok else 1)

func _tree_has_button_text(node: Node, text: String) -> bool:
	if node is Button and String((node as Button).text) == text:
		return true
	for child in node.get_children():
		if _tree_has_button_text(child, text):
			return true
	return false

func _capture() -> void:
	# stage a skirmish at center so combat + projectiles show in the shot
	camera.position = WORLD * 0.5
	_clamp_camera()
	var mid := WORLD * 0.5
	for i in range(4):
		_spawn_unit(Game.player_king, "swordsman", 0, mid + Vector2(-130, -50 + i * 26))
	for i in range(4):
		_spawn_unit(Game.rival_king, "swordsman", 1, mid + Vector2(130, -50 + i * 26))
	_spawn_unit(Game.player_king, "archer", 0, mid + Vector2(-180, 60))
	_spawn_unit(Game.rival_king, "archer", 1, mid + Vector2(180, 60))
	_spawn_unit(Game.player_king, "lancer", 0, mid + Vector2(-150, -90))
	_spawn_unit(Game.rival_king, "lancer", 1, mid + Vector2(150, -90))
	_spawn_unit(Game.player_king, "siege", 0, mid + Vector2(-210, 0))
	var t := _add_structure("tower", 0, mid + Vector2(-260, -10))
	towers.append(t)
	if units.size() > 0:
		units[0].selected = true
	Game.selection_changed.emit(1)
	await get_tree().create_timer(1.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_preview.png")
	print("SHOT_SAVED")
	get_tree().quit()

# ---------- world building ----------

func _scatter_decals() -> void:
	var cfg := Game.arena_cfg()
	var biome := String(cfg.get("biome", "grass"))
	var decals := [
		"res://assets/terrain/terrain_detail_grass_clump.png",
		"res://assets/terrain/terrain_detail_brush_leaf.png",
		"res://assets/terrain/terrain_detail_field_stubble.png",
	]
	if biome == "sand":
		decals = [
			"res://assets/terrain/terrain_detail_sand_rock.png",
			"res://assets/terrain/terrain_detail_dry_scrub.png",
			"res://assets/terrain/terrain_detail_road_rut.png",
		]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260620
	for i in range(int(cfg.decor)):
		var s := Sprite2D.new()
		s.texture = load(decals[rng.randi() % decals.size()])
		s.position = Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y)
		s.scale = Vector2.ONE * ((0.3 + rng.randf() * 0.45) if biome == "sand" else (0.4 + rng.randf() * 0.5))
		s.modulate = Color(1, 1, 1, 0.58 if biome == "sand" else 0.66)
		s.z_index = -8
		add_child(s)
	if String(cfg.feature) == "forest" or String(cfg.feature) == "olive":
		var trees := ["res://assets/terrain/resource_oak_stand.png", "res://assets/terrain/resource_pine_stand.png"]
		for i in range(38 if String(cfg.feature) == "olive" else 44):
			var t := Sprite2D.new()
			t.texture = load(trees[rng.randi() % trees.size()])
			t.position = Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y)
			t.scale = Vector2.ONE * (0.48 + rng.randf() * 0.28)
			t.modulate = Color("b6c37c", 0.82) if String(cfg.feature) == "olive" else Color(1, 1, 1, 0.88)
			t.z_index = 4 + int(t.position.y / 48.0)
			add_child(t)

func _spawn_unit(king: String, kind: String, team: int, pos: Vector2, desired_net_id := 0, count_pop := true) -> Unit:
	var u := Unit.new()
	u.position = pos
	u.setup(king, kind, team)
	add_child(u)
	if desired_net_id > 0:
		u.net_id = desired_net_id
		_next_net_id = maxi(_next_net_id, desired_net_id + 1)
	else:
		u.net_id = _next_net_id
		_next_net_id += 1
	u.puppet = Game.net_mode == "join"
	u.net_pos = pos
	units.append(u)
	_units_by_net_id[u.net_id] = u
	if team == 0 and count_pop:
		Game.pop += 1
		Game.resources_changed.emit()
	return u

func _add_structure(kind: String, team: int, pos: Vector2, desired_net_id := 0) -> Structure:
	var st := Structure.new()
	st.position = pos
	st.setup(kind, team)
	add_child(st)
	if desired_net_id > 0:
		st.net_id = desired_net_id
		_next_net_id = maxi(_next_net_id, desired_net_id + 1)
	else:
		st.net_id = _next_net_id
		_next_net_id += 1
	structures.append(st)
	_structures_by_net_id[st.net_id] = st
	return st

func _add_food(pos: Vector2) -> FoodNode:
	return _add_resource(pos, "food")

func _add_resource(pos: Vector2, res_kind: String) -> FoodNode:
	var f := FoodNode.new()
	f.res_kind = res_kind
	f.position = pos
	add_child(f)
	food_nodes.append(f)
	return f

func _defensive_point_for_team(team: int) -> Vector2:
	var base := player_keep if team == 0 else rival_keep
	if not _node_alive(base):
		return Vector2.ZERO
	return base.position + (Vector2(82, 118) if team == 0 else Vector2(-82, -118))

func _spawn_starting_defenders(team: int) -> void:
	var king := Game.player_king if team == 0 else Game.rival_king
	var base := player_keep if team == 0 else rival_keep
	if not _node_alive(base):
		return
	var sign := 1.0 if team == 0 else -1.0
	var specs := [
		{"kind": "swordsman", "offset": Vector2(82.0 * sign, 92.0 * sign)},
		{"kind": "archer", "offset": Vector2(132.0 * sign, 122.0 * sign)},
	]
	for spec in specs:
		var offset: Vector2 = spec["offset"]
		var u := _spawn_unit(king, String(spec["kind"]), team, base.position + offset, 0, team == 0)
		if team == 1:
			_add_team_pop(1, 1)
		u.order_move(_defensive_point_for_team(team) + Vector2(randf_range(-20, 20), randf_range(-16, 16)))

# ---------- HUD actions ----------

func train_unit(kind: String) -> void:
	if _is_joiner():
		if not _preflight_controlled_cost(kind):
			return
		_send_intent("train", kind)
		return
	if Game.pop + queued_pop >= Game.pop_cap:
		return
	if not Game.pay(kind):
		return
	queued_pop += 1
	train_queue.append({"kind": kind, "t": _train_time(kind)})

func _train_time(kind: String) -> float:
	match kind:
		"siege": return 5.0
		"lancer": return 3.0
		"swordsman", "archer": return 2.4
		_: return 1.6

func _process_queue(delta: float) -> void:
	if train_queue.is_empty():
		return
	train_queue[0]["t"] -= delta
	if train_queue[0]["t"] <= 0.0:
		var kind: String = train_queue[0]["kind"]
		train_queue.pop_front()
		queued_pop = max(0, queued_pop - 1)
		var u := _spawn_unit(Game.player_king, kind, 0, player_keep.position + Vector2(randf_range(-40, 40), 70))
		_apply_new_unit_default_order(u, 0)
		Game.log_event("%s ready" % Game.unit_label(kind, Game.player_king))

func _apply_new_unit_default_order(u: Unit, team: int) -> void:
	if not _node_alive(u):
		return
	var rally := _team_rally_point(team)
	var custom_rally := _team_rally_custom(team)
	if u.kind == "villager" and not custom_rally:
		var node = _nearest(food_nodes, u.position, 1.0e9)
		if node:
			u.order_gather(node)
			return
	if u.kind != "villager" and not custom_rally:
		_order_units_defend_point([u], _defensive_point_for_team(team))
		return
	u.order_move(rally + Vector2(randf_range(-30, 30), randf_range(-20, 20)))

# ---------- RTS control commands ----------

func _set_selection_pred(want_villager: bool) -> void:
	var n := 0
	for u in units:
		if not _node_alive(u):
			continue
		var sel := u.team == _controlled_team() and ((u.kind == "villager") == want_villager)
		u.selected = sel
		u.queue_redraw()
		if sel:
			n += 1
	Game.selection_changed.emit(n)

func cmd_select_army() -> void:
	_set_selection_pred(false)

func cmd_select_villagers() -> void:
	_set_selection_pred(true)

func cmd_assign_control_group(slot: int) -> void:
	var picked := []
	for item in _selected():
		var u := item as Unit
		if _node_alive(u) and u.team == _controlled_team():
			picked.append(u)
	if picked.is_empty():
		Game.log_event("No units selected for group %d." % slot)
		return
	control_groups[slot] = picked
	Game.log_event("Group %d set: %d units." % [slot, picked.size()])

func cmd_recall_control_group(slot: int) -> void:
	var group := _live_control_group(slot)
	if group.is_empty():
		control_groups.erase(slot)
		Game.log_event("Group %d empty." % slot)
		return
	_select_units(group)
	center_camera_on(_unit_group_center(group))
	Game.log_event("Group %d ready." % slot)

func hud_control_group_counts() -> Dictionary:
	var out := {}
	for slot in range(1, 6):
		out[slot] = _live_control_group(slot).size()
	return out

func cmd_defend_base() -> void:
	if _is_joiner():
		_send_intent("defend")
		return
	var selected := _selected()
	if selected.is_empty():
		cmd_select_army()
		selected = _selected()
	var army := []
	for item in selected:
		var u := item as Unit
		if _node_alive(u) and u.kind != "villager" and u.team == _controlled_team():
			army.append(u)
	if army.is_empty():
		return
	var point := _defensive_point_for_team(_controlled_team())
	_order_units_defend_point(army, point)
	add_alert_ping(point, "rally")
	_publish_selection_state()
	queue_redraw()

func cmd_gather() -> void:
	if _is_joiner():
		_send_intent("gather")
		return
	for u in _selected():
		if u.kind == "villager":
			var node = _nearest(food_nodes, u.position, 1.0e9)
			if node:
				u.order_gather(node)

func cmd_attack_move() -> void:
	if _is_joiner():
		_send_intent("attack")
		return
	for u in _selected():
		u.gather_target = null
		u.attack_target = null
		u.player_ordered = false
		if _node_alive(rival_keep):
			u.target = rival_keep.position

func cmd_hold() -> void:
	if _is_joiner():
		_send_intent("hold")
		return
	for u in _selected():
		u.target = u.position
		u.gather_target = null
		u.attack_target = null
		u.player_ordered = false

func cmd_rally() -> void:
	rally_set = true

func _set_local_rally(pos: Vector2) -> void:
	if _is_joiner():
		_send_intent("rally", "", "", pos)
		rally_set = false
		return
	rally_point = pos
	_player_rally_custom = true
	add_alert_ping(rally_point, "rally")
	rally_set = false

func cmd_pause() -> void:
	get_tree().paused = not get_tree().paused

func cmd_speed() -> float:
	if Engine.time_scale >= 2.9:
		Engine.time_scale = 1.0
	elif Engine.time_scale >= 1.9:
		Engine.time_scale = 3.0
	else:
		Engine.time_scale = 2.0
	return Engine.time_scale

func cmd_power() -> void:
	if _is_joiner():
		_send_intent("power")
		return
	if power_cd > 0.0:
		return
	power_cd = 45.0
	Game.log_event("Power unleashed — army restored!")
	for u in units:
		if _node_alive(u) and u.team == 0:
			u.hp = u.max_hp
			u.queue_redraw()

func cmd_concede() -> void:
	if _over:
		return
	if _is_joiner():
		_send_intent("concede")
		Game.log_event("Concede sent to host.")
		return
	_over = true
	_match_result = "lost"
	Game.record_result(_local_result_king(), false, _result_meta())
	Game.log_event("CONCEDED")
	_send_final_snapshot()
	_show_banner("DEFEAT", Game.COL_ENEMY)

func cmd_zoom_in() -> void:
	_set_camera_zoom(zoom_level + CAMERA_ZOOM_STEP)

func cmd_zoom_out() -> void:
	_set_camera_zoom(zoom_level - CAMERA_ZOOM_STEP)

func cmd_zoom_reset() -> void:
	_set_camera_zoom(1.0)

func hud_zoom_label() -> String:
	return "%d" % int(round(zoom_level * 100.0))

func _detect_threat() -> void:
	var was_threat := threat
	threat = false
	if _node_alive(player_keep):
		for u in units:
			if _node_alive(u) and u.team == 1 and u.position.distance_to(player_keep.position) < 270.0:
				threat = true
				break
	if threat and not was_threat:
		add_alert_ping(player_keep.position, "danger")

func begin_build(kind: String) -> void:
	if _is_joiner():
		if not _preflight_controlled_cost(kind):
			return
		_send_intent("build", "", kind)
		return
	if not Game.can_afford(kind):
		return
	build_mode = kind
	if is_instance_valid(build_ghost):
		build_ghost.queue_free()
	build_ghost = Sprite2D.new()
	var tex := "res://assets/structures/house_asset.png"
	match kind:
		"forge":
			tex = "res://assets/structures/forge_asset.png"
		"tower":
			tex = "res://assets/structures/tower_asset.png"
		"market":
			tex = "res://assets/structures/market_asset.png"
	build_ghost.texture = load(tex)
	var ghost_scale := Structure.visual_scale_for(kind)
	build_ghost.scale = Vector2(ghost_scale, ghost_scale)
	build_ghost.modulate = Color(0.5, 0.9, 1.0, 0.55)
	build_ghost.z_index = 20
	add_child(build_ghost)
	_update_build_ghost_at(get_global_mouse_position())

func _update_build_ghost_at(pos: Vector2) -> void:
	if not is_instance_valid(build_ghost):
		return
	build_ghost.position = pos
	var legal := build_mode != "" and _can_place_structure(pos, build_mode)
	build_ghost.modulate = Color(0.5, 0.95, 1.0, 0.62) if legal else Color(1.0, 0.28, 0.22, 0.58)

func _place_build(pos: Vector2) -> void:
	if build_mode == "":
		_cancel_build()
		return
	if not _can_place_structure(pos, build_mode):
		Game.log_event("Cannot build there.")
		return
	if not Game.pay(build_mode):
		_cancel_build()
		return
	var st := _add_structure(build_mode, 0, pos)
	match build_mode:
		"house":
			_add_team_pop_cap(0, 6)
		"forge":
			_set_team_has_forge(0, true)
		"tower":
			towers.append(st)
		"market":
			markets.append(st)
	Game.log_event("%s built" % build_mode.to_upper())
	add_alert_ping(pos, "build")
	Game.resources_changed.emit()
	_cancel_build()

func _can_place_structure(pos: Vector2, kind: String) -> bool:
	var radius := _structure_radius(kind)
	if pos.x < radius or pos.y < radius or pos.x > WORLD.x - radius or pos.y > WORLD.y - radius:
		return false
	for st in structures:
		if _node_alive(st) and st.position.distance_to(pos) < radius + _structure_radius(st.kind):
			return false
	for node in food_nodes:
		if _node_alive(node) and node.position.distance_to(pos) < radius + 26.0:
			return false
	return true

func _structure_radius(kind: String) -> float:
	return Structure.footprint_radius_for(kind)

func _find_build_spot(base: Vector2, kind: String, team: int) -> Vector2:
	var y_dir := 1.0 if team == 0 else -1.0
	var x_offsets := [0.0, -125.0, 125.0, -240.0, 240.0, -355.0, 355.0]
	var y_offsets := [190.0, 300.0, 410.0, 520.0]
	for y in y_offsets:
		for x in x_offsets:
			var pos := base + Vector2(float(x), float(y) * y_dir)
			if _can_place_structure(pos, kind):
				return pos
	return Vector2.INF

func _cancel_build() -> void:
	build_mode = ""
	if is_instance_valid(build_ghost):
		build_ghost.queue_free()
	build_ghost = null

func do_research(kind: String) -> void:
	if _is_joiner():
		if not _preflight_controlled_cost(kind):
			return
		_send_intent("research", "", kind)
		return
	var result := _research_for_team(0, kind)
	if bool(result.get("accepted", false)):
		Game.log_event(String(result.get("reason", "research complete")))
	Game.resources_changed.emit()

func _market_income() -> void:
	var any := false
	for m in markets:
		if _node_alive(m):
			credit_resource(m.team, "food", 4)
			credit_resource(m.team, "timber", 3)
			credit_resource(m.team, "memp", 1)
			any = true
	if any:
		Game.resources_changed.emit()

func _tower_fire() -> void:
	for t in towers:
		if not _node_alive(t):
			continue
		var range := 285.0 if t.kind == "keep" else 240.0
		var damage := 16.0 if t.kind == "keep" else 12.0
		var origin_y := -58.0 if t.kind == "keep" else -30.0
		var foe = _nearest_enemy_unit_for_team(t.position, range, t.team)
		if foe:
			spawn_projectile(t.position + Vector2(0, origin_y), foe.position, "bolt")
			if foe.has_method("take_damage"):
				foe.take_damage(damage)

# ---------- camera ----------

func _process(delta: float) -> void:
	_prune_dead_entities()
	_process_alert_pings(delta)
	var mv := _camera_pan_vector()
	if mv != Vector2.ZERO:
		camera.position += mv.normalized() * CAMERA_KEY_SPEED * delta / maxf(camera.zoom.x, 0.01)
		_clamp_camera()
	if selecting:
		sel_now = get_global_mouse_position()
		queue_redraw()
	elif not _selected().is_empty():
		for u in _selected():
			if _unit_order_kind(u) != "":
				queue_redraw()
				break

	if is_instance_valid(build_ghost):
		_update_build_ghost_at(get_global_mouse_position())

	power_cd = max(0.0, power_cd - delta)
	if Game.net_mode == "join":
		return
	if _over:
		return
	_process_queue(delta)
	_detect_threat()
	_separate()
	_tower_t += delta
	if _tower_t >= 0.5:
		_tower_t = 0.0
		_tower_fire()
	_acquire_t += delta
	if _acquire_t >= 0.25:
		_acquire_t = 0.0
		_acquire_targets()
	_match_t += delta
	if not _human_multiplayer():
		_ai_t += delta
		if _match_t >= AI_FREE_SPAWN_START and _ai_t >= 3.4:
			_ai_t = 0.0
			_enemy_ai()
		if _match_t >= FIRST_WAVE_START:
			_wave_t += delta
			if _wave_t >= _wave_interval():
				_wave_t = 0.0
				_spawn_wave()
	_market_t += delta
	if _market_t >= 4.0:
		_market_t = 0.0
		_market_income()
	_check_win()
	if Game.net_mode == "host" and Net.connected:
		_snapshot_t += delta
		if _snapshot_t >= 0.35:
			_snapshot_t = 0.0
			_snapshots_sent += 1
			Net.send_msg({"type": "snapshot", "snapshot": _room_snapshot()})
			_publish_web_match_state({"snapshotsSent": _snapshots_sent})

func _wave_interval() -> float:
	match Game.pressure:
		"rush": return 28.0
		"siege": return 38.0
		_: return 40.0

func _spawn_wave() -> void:
	if not _node_alive(rival_keep):
		return
	Game.wave += 1
	Game.log_event("Wave %d incoming!" % Game.wave)
	add_alert_ping(rival_keep.position, "danger")
	Game.resources_changed.emit()
	var size := 2 + Game.wave + (1 if Game.pressure == "siege" else 0)
	var pool := ["swordsman", "archer", "lancer"]
	if Game.pressure == "siege" and Game.wave >= 2:
		pool.append("siege")
	for i in range(mini(size, 8)):
		var k: String = pool[randi() % pool.size()]
		var u := _spawn_unit(Game.rival_king, k, 1, rival_keep.position + Vector2(randf_range(-70, 70), 90))
		if _node_alive(player_keep):
			u.target = player_keep.position

# ---------- crowd separation so armies spread out ----------

func _separate() -> void:
	var n := units.size()
	for i in range(n):
		var a := units[i]
		if not _node_alive(a):
			continue
		for j in range(i + 1, n):
			var b := units[j]
			if not _node_alive(b):
				continue
			var d := a.position - b.position
			var dist := d.length()
			if dist < 17.0 and dist > 0.01:
				var push := d / dist * (17.0 - dist) * 0.5
				a.position += push
				b.position -= push

# ---------- combat acquisition + enemy AI ----------

func _acquire_targets() -> void:
	for u in units:
		if not _node_alive(u):
			continue
		if u.player_ordered:
			continue
		if u.kind == "villager" and u.team == 0:
			continue
		if _node_alive(u.attack_target):
			continue
		var foe := _nearest_foe(u)
		if foe:
			u.attack_target = foe
		elif u.team == 1 and _match_t >= ENEMY_ATTACK_GRACE and _node_alive(player_keep):
			u.target = player_keep.position

func _nearest_foe(u: Unit) -> Node2D:
	var best: Node2D = null
	var bd := u.aggro
	for o in units:
		if not _node_alive(o) or o.team == u.team:
			continue
		var d := o.position.distance_to(u.position)
		if d < bd:
			bd = d
			best = o
	for s in structures:
		if not _node_alive(s) or s.team == u.team:
			continue
		var d := s.position.distance_to(u.position)
		if d < bd + 40.0:
			bd = d
			best = s
	return best

func _enemy_ai() -> void:
	if not _node_alive(rival_keep):
		return
	var rivals := 0
	for u in units:
		if _node_alive(u) and u.team == 1:
			rivals += 1
	if rivals < 7:
		var pool := ["swordsman", "archer", "lancer"]
		var kind: String = pool[randi() % pool.size()]
		var u := _spawn_unit(Game.rival_king, kind, 1, rival_keep.position + Vector2(randf_range(-50, 50), 80))
		if Game.wave > 0 and _node_alive(player_keep):
			u.target = player_keep.position
		else:
			u.order_move(_defensive_point_for_team(1) + Vector2(randf_range(-30, 30), randf_range(-20, 20)))

func _projectile_texture_path(kind: String) -> String:
	match kind:
		"bolt":
			return "res://assets/fx/projectile_bolt.png"
		"stone":
			return "res://assets/fx/projectile_stone.png"
		"fire", "impact":
			return "res://assets/fx/projectile_fire.png"
		_:
			return "res://assets/fx/projectile_arrow.png"

func spawn_projectile(from: Vector2, to: Vector2, kind := "arrow") -> void:
	_projectile_debug_counts[kind] = int(_projectile_debug_counts.get(kind, 0)) + 1
	var p := Sprite2D.new()
	p.texture = load(_projectile_texture_path(kind))
	var s := 0.62 if kind == "stone" else 0.5
	p.scale = Vector2(s, s)
	p.position = from
	p.rotation = (to - from).angle()
	p.z_index = 28
	add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "position", to, 0.22 if kind == "stone" else 0.16)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free()
		_spawn_projectile_impact(to, kind)
	)

func _spawn_projectile_impact(pos: Vector2, kind := "arrow") -> void:
	var flash := Sprite2D.new()
	flash.texture = load(_projectile_texture_path("impact" if kind == "stone" else "bolt"))
	flash.position = pos
	flash.scale = Vector2(0.34, 0.34) if kind == "stone" else Vector2(0.22, 0.22)
	flash.z_index = 29
	flash.modulate = Color(1, 1, 1, 0.72)
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "scale", flash.scale * 1.7, 0.16)
	tw.parallel().tween_property(flash, "modulate", Color(1, 1, 1, 0.0), 0.16)
	tw.tween_callback(flash.queue_free)

func add_alert_ping(pos: Vector2, kind := "danger") -> void:
	_alert_debug_counts[kind] = int(_alert_debug_counts.get(kind, 0)) + 1
	alert_pings.append({
		"pos": pos.clamp(Vector2.ZERO, WORLD),
		"kind": kind,
		"age": 0.0,
		"duration": 2.4 if kind == "danger" else 1.8,
	})
	if alert_pings.size() > 18:
		alert_pings.pop_front()
	queue_redraw()

func _process_alert_pings(delta: float) -> void:
	for ping in alert_pings:
		ping["age"] = float(ping.get("age", 0.0)) + delta
	alert_pings = alert_pings.filter(func(ping): return float(ping.get("age", 0.0)) < float(ping.get("duration", 1.0)))
	if not alert_pings.is_empty():
		queue_redraw()

func alert_ping_color(kind: String) -> Color:
	match kind:
		"build":
			return Color("ffd15c")
		"rally":
			return Game.COL_ACCENT_BRIGHT
		_:
			return Color("ff665a")

func _check_win() -> void:
	if _over:
		return
	if not _node_alive(rival_keep):
		_over = true
		_match_result = "won"
		Game.record_result(_local_result_king(), true, _result_meta())
		Game.log_event("VICTORY!")
		_send_final_snapshot()
		_show_banner("VICTORY", Color("43c865"))
	elif not _node_alive(player_keep):
		_over = true
		_match_result = "lost"
		Game.record_result(_local_result_king(), false, _result_meta())
		Game.log_event("DEFEAT")
		_send_final_snapshot()
		_show_banner("DEFEAT", Game.COL_ENEMY)

func _send_final_snapshot() -> void:
	if Game.net_mode == "host" and Net.connected:
		_snapshots_sent += 1
		Net.send_msg({"type": "snapshot", "snapshot": _room_snapshot()})
		_publish_web_match_state({"snapshotsSent": _snapshots_sent, "matchResult": _match_result})

func _finish_by_concede(team: int) -> Dictionary:
	if _over:
		return {"accepted": false, "reason": "match already over"}
	var local_won := team != 0
	_over = true
	_match_result = "won" if local_won else "lost"
	Game.record_result(_local_result_king(), local_won, _result_meta())
	Game.log_event("%s conceded." % ("Rival" if team == 1 else "Player"))
	_send_final_snapshot()
	_show_banner("VICTORY" if local_won else "DEFEAT", Color("43c865") if local_won else Game.COL_ENEMY)
	return {"accepted": true, "reason": "concede accepted"}

func _web_query_params() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw = JavaScriptBridge.eval("window.location.search || ''", true)
	var qs := String(raw)
	if qs.begins_with("?"):
		qs = qs.substr(1)
	var out := {}
	for pair in qs.split("&", false):
		var eq := pair.find("=")
		var key := pair.substr(0, eq if eq >= 0 else pair.length()).uri_decode()
		var val := "1" if eq < 0 else pair.substr(eq + 1).uri_decode()
		if key != "":
			out[key] = val
	return out

func _truthy(v) -> bool:
	var s := String(v).strip_edges().to_lower()
	return ["1", "true", "yes", "on"].has(s)

func _result_meta() -> Dictionary:
	return {
		"seconds": int(_match_t),
		"wave": Game.wave,
		"kills": Game.kills,
		"arena": Game.arena,
		"pressure": Game.pressure,
		"rivalId": _local_result_rival(),
	}

func _local_result_king() -> String:
	return Game.rival_king if Game.net_mode == "join" else Game.player_king

func _local_result_rival() -> String:
	return Game.player_king if Game.net_mode == "join" else Game.rival_king

func _show_banner(text: String, col: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Game.COL_PANEL
	sb.border_color = col
	sb.set_border_width_all(4)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load("res://assets/fonts/press-start-2p.ttf"))
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var ticket := Label.new()
	var won := text.to_lower() == "victory"
	var ticket_unit := "SOL" if Wallet.verified else "TICKET"
	ticket.text = "%s %d | TAX %d | PAYOUT %d" % [ticket_unit, Game.wager_stake, Game.wager_tax(), Game.wager_payout(won)]
	ticket.add_theme_font_override("font", load("res://assets/fonts/silkscreen.ttf"))
	ticket.add_theme_font_size_override("font_size", 14)
	ticket.add_theme_color_override("font_color", Game.COL_BONE)
	ticket.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ticket)
	var again := Button.new()
	again.text = "PLAY AGAIN"
	again.add_theme_font_override("font", load("res://assets/fonts/silkscreen.ttf"))
	again.add_theme_font_size_override("font_size", 14)
	again.add_theme_color_override("font_color", Game.COL_BONE)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Game.COL_ACCENT
	bsb.border_color = Game.COL_EDGE
	bsb.set_border_width_all(2)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 10
	bsb.content_margin_bottom = 10
	again.add_theme_stylebox_override("normal", bsb)
	again.add_theme_stylebox_override("hover", bsb)
	again.add_theme_stylebox_override("pressed", bsb)
	again.pressed.connect(func():
		Game.reset()
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())
	vb.add_child(again)
	var menu := Button.new()
	menu.text = "MAIN MENU"
	menu.add_theme_font_override("font", load("res://assets/fonts/silkscreen.ttf"))
	menu.add_theme_font_size_override("font_size", 14)
	menu.add_theme_color_override("font_color", Game.COL_BONE)
	menu.add_theme_stylebox_override("normal", bsb)
	menu.add_theme_stylebox_override("hover", bsb)
	menu.add_theme_stylebox_override("pressed", bsb)
	menu.pressed.connect(_return_to_menu)
	vb.add_child(menu)

func _return_to_menu() -> void:
	Net.leave()
	Game.net_mode = ""
	Game.my_team = 0
	Game.reset()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")

func _clamp_camera() -> void:
	if not is_instance_valid(camera):
		return
	var half := get_viewport_rect().size * 0.5 / maxf(camera.zoom.x, 0.01)
	var min_x := half.x
	var max_x := WORLD.x - half.x
	var min_y := half.y
	var max_y := WORLD.y - half.y
	camera.position.x = WORLD.x * 0.5 if min_x > max_x else clampf(camera.position.x, min_x, max_x)
	camera.position.y = WORLD.y * 0.5 if min_y > max_y else clampf(camera.position.y, min_y, max_y)

func _min_camera_zoom_for_viewport() -> float:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 1.0
	return maxf(CAMERA_ZOOM_MIN, maxf(vp.x / WORLD.x, vp.y / WORLD.y))

func _set_camera_zoom(value: float) -> void:
	zoom_level = clampf(value, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	_sync_camera_zoom()

func _sync_camera_zoom() -> void:
	if not is_instance_valid(camera):
		return
	var effective_zoom := maxf(zoom_level, _min_camera_zoom_for_viewport())
	camera.zoom = Vector2(effective_zoom, effective_zoom)
	_clamp_camera()

func _camera_pan_vector() -> Vector2:
	var mv := Vector2.ZERO
	mv.x = Input.get_action_strength("pan_right") - Input.get_action_strength("pan_left")
	mv.y = Input.get_action_strength("pan_down") - Input.get_action_strength("pan_up")
	if selecting or build_mode != "" or rally_set:
		return mv
	if get_viewport().gui_get_hovered_control() != null:
		return mv
	var vp := get_viewport_rect().size
	var mp := get_viewport().get_mouse_position()
	if mp.x < 0.0 or mp.y < 0.0 or mp.x > vp.x or mp.y > vp.y:
		return mv
	if mp.x <= EDGE_PAN_MARGIN:
		mv.x -= EDGE_PAN_SPEED / CAMERA_KEY_SPEED
	elif mp.x >= vp.x - EDGE_PAN_MARGIN:
		mv.x += EDGE_PAN_SPEED / CAMERA_KEY_SPEED
	if mp.y <= EDGE_PAN_MARGIN:
		mv.y -= EDGE_PAN_SPEED / CAMERA_KEY_SPEED
	elif mp.y >= vp.y - EDGE_PAN_MARGIN:
		mv.y += EDGE_PAN_SPEED / CAMERA_KEY_SPEED
	return mv

# ---------- input: selection + orders ----------

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var mouse := event as InputEventMouseButton
	if _handle_pointer_button(mouse):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_build()
		rally_set = false
		return
	if rally_set:
		if event is InputEventMouseButton and event.pressed:
			var rally_mouse := event as InputEventMouseButton
			if event.button_index == MOUSE_BUTTON_LEFT:
				_set_local_rally(_screen_to_world(rally_mouse.position))
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				rally_set = false
				return
		return
	if build_mode != "":
		if event is InputEventMouseButton and event.pressed:
			var build_mouse := event as InputEventMouseButton
			if event.button_index == MOUSE_BUTTON_LEFT:
				_place_build(_screen_to_world(build_mouse.position))
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_build()
				return
		return
	if event is InputEventKey and event.pressed:
		if _handle_command_key(event):
			return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		_handle_pointer_button(mouse)

func _handle_pointer_button(mouse: InputEventMouseButton) -> bool:
	if rally_set:
		if mouse.pressed:
			if mouse.button_index == MOUSE_BUTTON_LEFT:
				_set_local_rally(_screen_to_world(mouse.position))
				return true
			if mouse.button_index == MOUSE_BUTTON_RIGHT:
				rally_set = false
				return true
		return false
	if build_mode != "":
		if mouse.pressed:
			if mouse.button_index == MOUSE_BUTTON_LEFT:
				_place_build(_screen_to_world(mouse.position))
				return true
			if mouse.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_build()
				return true
		return false
	return _handle_mouse_button(mouse.button_index, mouse.pressed, mouse.double_click, mouse.shift_pressed, _screen_to_world(mouse.position))

func _handle_mouse_button(button_index: int, pressed: bool, double_click := false, shift_pressed := false, world_pos := Vector2.INF) -> bool:
	var pos := world_pos if world_pos.is_finite() else get_global_mouse_position()
	if button_index == MOUSE_BUTTON_WHEEL_UP and pressed:
		cmd_zoom_in()
		return true
	if button_index == MOUSE_BUTTON_WHEEL_DOWN and pressed:
		cmd_zoom_out()
		return true
	if button_index == MOUSE_BUTTON_LEFT:
		if pressed:
			selecting = true
			sel_double_click = double_click
			sel_start = pos
			sel_now = sel_start
		else:
			selecting = false
			sel_now = pos
			_finish_selection(shift_pressed, sel_double_click)
			sel_double_click = false
			queue_redraw()
		return true
	if button_index == MOUSE_BUTTON_RIGHT and pressed:
		_issue_order(pos)
		return true
	return false

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if not is_instance_valid(camera):
		return screen_pos
	return camera.position + (screen_pos - get_viewport_rect().size * 0.5) / maxf(camera.zoom.x, 0.01)

func _world_to_screen(world_pos: Vector2) -> Vector2:
	if not is_instance_valid(camera):
		return world_pos
	return (world_pos - camera.position) * maxf(camera.zoom.x, 0.01) + get_viewport_rect().size * 0.5

func _handle_command_key(event: InputEventKey) -> bool:
	if event.echo or _over:
		return false
	var slot := _control_group_slot_for_key(event.keycode)
	if slot > 0:
		if event.ctrl_pressed or event.meta_pressed:
			cmd_assign_control_group(slot)
			return true
		if _live_control_group(slot).size() > 0:
			cmd_recall_control_group(slot)
			return true
	match event.keycode:
		KEY_1:
			train_unit("villager")
		KEY_2:
			train_unit("swordsman")
		KEY_3:
			train_unit("archer")
		KEY_4:
			train_unit("lancer")
		KEY_5:
			train_unit("siege")
		KEY_B:
			begin_build("house")
		KEY_F:
			begin_build("forge")
		KEY_T:
			begin_build("tower")
		KEY_M:
			begin_build("market")
		KEY_C:
			cmd_select_army()
		KEY_V:
			cmd_select_villagers()
		KEY_G:
			cmd_gather()
		KEY_X:
			cmd_attack_move()
		KEY_H:
			cmd_hold()
		KEY_D:
			cmd_defend_base()
		KEY_R:
			cmd_rally()
		KEY_P:
			cmd_pause()
		KEY_EQUAL, KEY_PLUS:
			cmd_speed()
		KEY_BRACKETLEFT, KEY_MINUS:
			cmd_zoom_out()
		KEY_BRACKETRIGHT:
			cmd_zoom_in()
		KEY_0:
			cmd_zoom_reset()
		KEY_SPACE:
			cmd_power()
		_:
			return false
	return true

func _control_group_slot_for_key(keycode: int) -> int:
	match keycode:
		KEY_1: return 1
		KEY_2: return 2
		KEY_3: return 3
		KEY_4: return 4
		KEY_5: return 5
		_: return 0

func _finish_selection(additive := false, double_click := false) -> void:
	var rect := Rect2(sel_start, sel_now - sel_start).abs()
	var click := rect.size.length() < 8.0
	var team := _controlled_team()
	if click and double_click:
		var picked_unit := _unit_at(sel_now, team)
		if picked_unit != null:
				_select_visible_kind(picked_unit.kind, team, additive)
				Game.selection_changed.emit(_selected().size())
				_publish_selection_state()
				return
	var picked := false
	for u in units:
		if not _node_alive(u) or u.team != team:
			continue
		var hit := false
		if click:
			var pick_radius := u.click_radius() if u.has_method("click_radius") else 22.0
			hit = u.position.distance_to(sel_now) < pick_radius
		else:
			hit = rect.has_point(u.position)
		if click and picked:
			hit = false  # single-select: only first
		u.selected = (u.selected or hit) if additive else hit
		u.queue_redraw()
		if hit:
			picked = true
	Game.selection_changed.emit(_selected().size())
	_publish_selection_state()

func _unit_at(world_pos: Vector2, team: int) -> Unit:
	var best: Unit = null
	var best_dist := 1.0e9
	for u in units:
		if not _node_alive(u) or u.team != team:
			continue
		var pick_radius := u.click_radius() if u.has_method("click_radius") else 22.0
		var d := u.position.distance_to(world_pos)
		if d <= pick_radius and d < best_dist:
			best_dist = d
			best = u
	return best

func _visible_world_rect() -> Rect2:
	if not is_instance_valid(camera):
		return Rect2(Vector2.ZERO, WORLD)
	var half := get_viewport_rect().size * 0.5 / maxf(camera.zoom.x, 0.01)
	return Rect2(camera.position - half, half * 2.0)

func _select_visible_kind(kind: String, team: int, additive: bool) -> void:
	var visible := _visible_world_rect().grow(80.0)
	for u in units:
		if not _node_alive(u) or u.team != team:
			continue
		var hit := u.kind == kind and visible.has_point(u.position)
		u.selected = (u.selected or hit) if additive else hit
		u.queue_redraw()

func _selected() -> Array:
	var out := []
	for u in units:
		if _node_alive(u) and u.selected:
			out.append(u)
	return out

func _live_control_group(slot: int) -> Array:
	var out := []
	var group: Array = control_groups.get(slot, [])
	for item in group:
		var u := item as Unit
		if _node_alive(u) and u.team == _controlled_team():
			out.append(u)
	control_groups[slot] = out
	return out

func _select_units(target_units: Array) -> void:
	var n := 0
	var team := _controlled_team()
	for u in units:
		if not _node_alive(u) or u.team != team:
			continue
		var sel := target_units.has(u)
		u.selected = sel
		u.queue_redraw()
		if sel:
			n += 1
	Game.selection_changed.emit(n)
	_publish_selection_state()

func _unit_group_center(target_units: Array) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for item in target_units:
		var u := item as Unit
		if _node_alive(u):
			sum += u.position
			count += 1
	return sum / maxf(float(count), 1.0)

func _issue_order(world_pos: Vector2) -> void:
	if _is_joiner():
		_send_intent("order", "", "", world_pos)
		return
	var sel := _selected()
	if sel.is_empty():
		return
	_apply_order_to_units(sel, _controlled_team(), world_pos)
	_publish_selection_state()
	queue_redraw()

func _publish_selection_state() -> void:
	Game.publish_web_state({
		"selectedCount": _selected().size(),
		"selectedOrderCounts": selected_order_indicator_count(),
	})

func _unit_order_kind(u: Unit) -> String:
	if _node_alive(u.attack_target):
		return "attack"
	if _node_alive(u.gather_target):
		return "gather"
	if u.target.distance_to(u.position) > 8.0:
		return "move"
	return ""

func _unit_order_point(u: Unit) -> Vector2:
	if _node_alive(u.attack_target):
		return u.attack_target.position
	if _node_alive(u.gather_target):
		return u.gather_target.position
	return u.target

func selected_order_indicator_count() -> Dictionary:
	var out := {"move": 0, "gather": 0, "attack": 0}
	for item in _selected():
		var u := item as Unit
		var kind := _unit_order_kind(u)
		if out.has(kind):
			out[kind] = int(out[kind]) + 1
	return out

func _nearest(arr: Array, p: Vector2, r: float):
	var best = null
	var bd := r
	for n in arr:
		if not _node_alive(n):
			continue
		var node := n as Node2D
		var d := node.position.distance_to(p)
		if d < bd:
			bd = d
			best = node
	return best

func _nearest_enemy_structure(p: Vector2, r: float):
	return _nearest_enemy_structure_for_team(p, r, _controlled_team())

func _nearest_enemy_structure_for_team(p: Vector2, r: float, team: int):
	var best = null
	var bd := r
	for s in structures:
		if _node_alive(s) and s.team != team and s.position.distance_to(p) < bd:
			bd = s.position.distance_to(p); best = s
	return best

func _nearest_enemy_unit(p: Vector2, r: float):
	return _nearest_enemy_unit_for_team(p, r, _controlled_team())

func _nearest_enemy_unit_for_team(p: Vector2, r: float, team: int):
	var best = null
	var bd := r
	for u in units:
		if _node_alive(u) and u.team != team and u.position.distance_to(p) < bd:
			bd = u.position.distance_to(p); best = u
	return best

# ---------- team helpers + multiplayer authority ----------

func _controlled_team() -> int:
	return Game.my_team if Game.net_mode != "" else 0

func _controlled_king() -> String:
	return Game.rival_king if _controlled_team() == 1 else Game.player_king

func _is_joiner() -> bool:
	return Game.net_mode == "join"

func _human_multiplayer() -> bool:
	return Game.net_mode == "host" or Game.net_mode == "join"

func team_atk_bonus(team: int) -> float:
	return Game.atk_bonus if team == 0 else _rival_atk_bonus

func team_armor_bonus(team: int) -> float:
	return Game.armor_bonus if team == 0 else _rival_armor_bonus

func team_eco_bonus(team: int) -> float:
	return Game.eco_bonus if team == 0 else _rival_eco_bonus

func _team_has_forge(team: int) -> bool:
	return Game.has_forge if team == 0 else _rival_has_forge

func hud_food() -> int:
	return Game.food if _controlled_team() == 0 else _rival_food

func hud_timber() -> int:
	return Game.timber if _controlled_team() == 0 else _rival_timber

func hud_memp() -> int:
	return Game.memp if _controlled_team() == 0 else _rival_memp

func hud_pop() -> int:
	return _team_pop(_controlled_team())

func hud_pop_cap() -> int:
	return _team_pop_cap(_controlled_team())

func hud_has_forge() -> bool:
	return _team_has_forge(_controlled_team())

func hud_tech_summary() -> Dictionary:
	var team := _controlled_team()
	return {
		"atk": int(round(team_atk_bonus(team))),
		"armor": int(round(team_armor_bonus(team))),
		"ecoPct": int(round(team_eco_bonus(team) * 100.0)),
		"forge": _team_has_forge(team),
	}

func hud_queue_summary() -> Dictionary:
	var count := queued_pop
	if not train_queue.is_empty():
		count = train_queue.size()
		var current: Dictionary = train_queue[0]
		var kind := String(current.get("kind", "villager"))
		var total := maxf(_train_time(kind), 0.01)
		var left := clampf(float(current.get("t", total)), 0.0, total)
		var pct := int(round((1.0 - left / total) * 100.0))
		return {
			"count": count,
			"kind": kind,
			"name": Game.unit_label(kind, _controlled_king()),
			"pct": clampi(pct, 0, 100),
			"seconds": int(ceil(left)),
		}
	return {"count": count, "kind": "", "name": "", "pct": 0, "seconds": 0}

func hud_can_afford(kind: String) -> bool:
	var team := _controlled_team()
	if kind.begins_with("upgrade_") and not _team_has_forge(team):
		return false
	return _team_can_afford(team, kind)

func _preflight_controlled_cost(kind: String) -> bool:
	var team := _controlled_team()
	if Game.UNIT_KINDS.has(kind) and _team_pop(team) >= _team_pop_cap(team):
		Game.log_event("Population capped.")
		return false
	if kind.begins_with("upgrade_") and not _team_has_forge(team):
		Game.log_event("Forge required.")
		return false
	if not _team_can_afford(team, kind):
		Game.log_event("Not enough resources.")
		return false
	return true

func hud_enemy_keep_destroyed() -> bool:
	var enemy := rival_keep if _controlled_team() == 0 else player_keep
	return not _node_alive(enemy)

func hud_selection_summary() -> Dictionary:
	var selected := _selected()
	var counts := {}
	var hp_now := 0.0
	var hp_max := 0.0
	var attacking := 0
	var gathering := 0
	var moving := 0
	var idle := 0
	var count := 0
	for item in selected:
		var u := item as Unit
		if not _node_alive(u):
			continue
		count += 1
		counts[u.kind] = int(counts.get(u.kind, 0)) + 1
		hp_now += maxf(0.0, u.hp)
		hp_max += maxf(1.0, u.max_hp)
		if _node_alive(u.attack_target):
			attacking += 1
		elif _node_alive(u.gather_target):
			gathering += 1
		elif u.target.distance_to(u.position) > 6.0:
			moving += 1
		else:
			idle += 1
	if count <= 0:
		return {"count": 0, "composition": "NO UNITS", "avgHp": 0, "order": "IDLE"}
	var parts: Array[String] = []
	for kind in Game.UNIT_KINDS:
		var n := int(counts.get(kind, 0))
		if n > 0:
			parts.append("%d %s" % [n, Game.unit_label(kind, _controlled_king())])
	var active_orders := 0
	active_orders += 1 if attacking > 0 else 0
	active_orders += 1 if gathering > 0 else 0
	active_orders += 1 if moving > 0 else 0
	active_orders += 1 if idle > 0 else 0
	var order := "MIXED"
	if active_orders == 1:
		if attacking > 0:
			order = "ATTACKING"
		elif gathering > 0:
			order = "GATHERING"
		elif moving > 0:
			order = "MOVING"
		else:
			order = "IDLE"
	return {
		"count": count,
		"composition": " ".join(parts),
		"avgHp": int(round(clampf(hp_now / maxf(hp_max, 1.0), 0.0, 1.0) * 100.0)),
		"order": order,
	}

func _set_team_has_forge(team: int, value: bool) -> void:
	if team == 0:
		Game.has_forge = value
	else:
		_rival_has_forge = value

func _team_pop(team: int) -> int:
	return Game.pop if team == 0 else _rival_pop

func _team_pop_cap(team: int) -> int:
	return Game.pop_cap if team == 0 else _rival_pop_cap

func _add_team_pop_cap(team: int, amount: int) -> void:
	if team == 0:
		Game.pop_cap += amount
	else:
		_rival_pop_cap += amount

func _add_team_pop(team: int, amount: int) -> void:
	if team == 0:
		Game.pop = maxi(0, Game.pop + amount)
	else:
		_rival_pop = maxi(0, _rival_pop + amount)

func _team_can_afford(team: int, kind: String) -> bool:
	if team == 0:
		return Game.can_afford(kind)
	var c: Dictionary = Game.COSTS.get(kind, {})
	return _rival_food >= int(c.get("food", 0)) and _rival_timber >= int(c.get("timber", 0)) and _rival_memp >= int(c.get("memp", 0))

func _team_pay(team: int, kind: String) -> bool:
	if team == 0:
		return Game.pay(kind)
	if not _team_can_afford(team, kind):
		return false
	var c: Dictionary = Game.COSTS.get(kind, {})
	_rival_food -= int(c.get("food", 0))
	_rival_timber -= int(c.get("timber", 0))
	_rival_memp -= int(c.get("memp", 0))
	Game.resources_changed.emit()
	return true

func _research_for_team(team: int, kind: String) -> Dictionary:
	var upgrade := kind if ["upgrade_atk", "upgrade_armor", "upgrade_eco"].has(kind) else "upgrade_atk"
	if not _team_has_forge(team):
		return {"accepted": false, "reason": "forge required"}
	if not _team_pay(team, upgrade):
		return {"accepted": false, "reason": "not enough resources"}
	match upgrade:
		"upgrade_atk":
			if team == 0:
				Game.atk_bonus += 3.0
			else:
				_rival_atk_bonus += 3.0
			return {"accepted": true, "reason": "attack upgraded"}
		"upgrade_armor":
			if team == 0:
				Game.armor_bonus += 2.0
			else:
				_rival_armor_bonus += 2.0
			return {"accepted": true, "reason": "armor upgraded"}
		"upgrade_eco":
			if team == 0:
				Game.eco_bonus += 0.25
			else:
				_rival_eco_bonus += 0.25
			return {"accepted": true, "reason": "economy upgraded"}
	return {"accepted": false, "reason": "unknown research"}

func credit_resource(team: int, kind: String, amount: int) -> void:
	if team == 0:
		match kind:
			"timber":
				Game.timber += amount
			"memp":
				Game.memp += amount
			_:
				Game.food += amount
	else:
		match kind:
			"timber":
				_rival_timber += amount
			"memp":
				_rival_memp += amount
			_:
				_rival_food += amount
	Game.resources_changed.emit()

func on_unit_death(team: int) -> void:
	if team == 1:
		Game.kills += 1
		_add_team_pop(1, -1)
	else:
		_add_team_pop(0, -1)
	Game.resources_changed.emit()

func _send_intent(action: String, unit := "", structure := "", world_pos := Vector2.INF) -> void:
	if not Net.connected:
		Game.log_event("No room relay for %s." % action.to_upper())
		return
	_intents_sent += 1
	var intent := {
		"id": "godot-%d" % Time.get_ticks_msec(),
		"action": action,
		"side": "rival" if Game.my_team == 1 else "player",
	}
	if unit != "":
		intent["unit"] = unit
	if structure != "":
		intent["structure"] = structure
	if world_pos.is_finite():
		intent["x"] = int(round(world_pos.x))
		intent["y"] = int(round(world_pos.y))
	_last_intent_sent = intent.duplicate(true)
	Net.send_msg({"type": "intent", "side": intent["side"], "intent": intent})
	_publish_web_match_state({"intentsSent": _intents_sent, "lastIntent": action})
	Game.log_event("Sent %s command to host." % action.to_upper())

func _on_net_message(msg: Dictionary) -> void:
	var typ := String(msg.get("type", ""))
	if typ == "snapshot" and Game.net_mode == "join":
		var snap = msg.get("snapshot", {})
		if typeof(snap) == TYPE_DICTIONARY:
			_snapshots_applied += 1
			_apply_snapshot(snap)
	elif typ == "intent" and Game.net_mode == "host":
		_intents_received += 1
		var result := _apply_remote_intent(msg)
		Net.send_msg({
			"type": "intent-result",
			"intentId": result.get("intentId", ""),
			"accepted": result.get("accepted", false),
			"action": result.get("action", ""),
			"side": result.get("side", ""),
			"reason": result.get("reason", ""),
		})
		_publish_web_match_state({"intentsReceived": _intents_received, "lastIntentAccepted": bool(result.get("accepted", false)), "lastIntentAction": String(result.get("action", ""))})
	elif typ == "intent-result":
		_intent_results += 1
		var action := String(msg.get("action", "command")).to_upper()
		var reason := String(msg.get("reason", ""))
		_publish_web_match_state({"intentResults": _intent_results, "lastIntentAccepted": bool(msg.get("accepted", false)), "lastIntentAction": action.to_lower()})
		Game.log_event("%s %s" % [action, "accepted" if bool(msg.get("accepted", false)) else "rejected: " + reason])

func _apply_remote_intent(msg: Dictionary) -> Dictionary:
	var intent: Dictionary = msg.get("intent", {}) if typeof(msg.get("intent")) == TYPE_DICTIONARY else {}
	var action := String(intent.get("action", "")).to_lower()
	var side := String(intent.get("side", msg.get("side", "rival"))).to_lower()
	var team := 1 if side == "rival" else 0
	var accepted := true
	var reason := "accepted"
	match action:
		"train":
			var unit := _valid_unit(String(intent.get("unit", "swordsman")))
			var train_result := _train_for_team(team, unit)
			accepted = bool(train_result.get("accepted", false))
			reason = String(train_result.get("reason", "train rejected"))
		"build":
			var structure := _valid_structure(String(intent.get("structure", "house")))
			var build_result := _build_for_team(team, structure)
			accepted = bool(build_result.get("accepted", false))
			reason = String(build_result.get("reason", "build rejected"))
		"research":
			var research := _valid_research(String(intent.get("structure", intent.get("research", "upgrade_atk"))))
			var research_result := _research_for_team(team, research)
			accepted = bool(research_result.get("accepted", false))
			reason = String(research_result.get("reason", "research rejected"))
		"power":
			for u in units:
				if _node_alive(u) and u.team == team:
					u.hp = u.max_hp
					u.queue_redraw()
			reason = "power healed army"
		"attack":
			_order_team_attack(team)
			reason = "attack move"
		"gather":
			_order_team_gather(team)
			reason = "villagers gathering"
		"hold":
			_order_team_hold(team)
			reason = "holding"
		"defend":
			_order_team_defend(team)
			reason = "defending base"
		"order":
			var order_pos := _default_rally_for_team(team)
			if intent.has("x") and intent.has("y"):
				order_pos = Vector2(float(intent.get("x", order_pos.x)), float(intent.get("y", order_pos.y)))
			_order_team_to_point(team, order_pos)
			reason = "ordered to point"
		"rally":
			var rally_pos := _default_rally_for_team(team)
			if intent.has("x") and intent.has("y"):
				rally_pos = Vector2(float(intent.get("x", rally_pos.x)), float(intent.get("y", rally_pos.y)))
			_set_team_rally_point(team, rally_pos)
			reason = "rally set"
		"concede":
			var concede_result := _finish_by_concede(team)
			accepted = bool(concede_result.get("accepted", false))
			reason = String(concede_result.get("reason", "concede rejected"))
		_:
			accepted = false
			reason = "unknown action"
	if accepted:
		Game.log_event("%s command: %s." % ["Rival" if team == 1 else "Player", reason])
	return {
		"intentId": String(intent.get("id", "")),
		"accepted": accepted,
		"action": action,
		"side": side,
		"reason": reason,
	}

func _valid_unit(kind: String) -> String:
	return kind if Game.UNIT_KINDS.has(kind) else "swordsman"

func _valid_structure(kind: String) -> String:
	return kind if ["house", "forge", "tower", "market"].has(kind) else "house"

func _valid_research(kind: String) -> String:
	return kind if ["upgrade_atk", "upgrade_armor", "upgrade_eco"].has(kind) else "upgrade_atk"

func _train_for_team(team: int, kind: String) -> Dictionary:
	if _team_pop(team) >= _team_pop_cap(team):
		return {"accepted": false, "reason": "population capped"}
	if not _team_pay(team, kind):
		return {"accepted": false, "reason": "not enough resources"}
	_spawn_for_team(team, kind)
	return {"accepted": true, "reason": "%s trained" % kind}

func _spawn_for_team(team: int, kind: String) -> void:
	var base := player_keep if team == 0 else rival_keep
	if not _node_alive(base):
		return
	var king := Game.player_king if team == 0 else Game.rival_king
	var u := _spawn_unit(king, kind, team, base.position + Vector2(randf_range(-45, 45), 80), 0, team == 0)
	if team == 1:
		_add_team_pop(1, 1)
	_apply_new_unit_default_order(u, team)

func _build_for_team(team: int, kind: String) -> Dictionary:
	var base := player_keep if team == 0 else rival_keep
	if not _node_alive(base):
		return {"accepted": false, "reason": "base destroyed"}
	var spot := _find_build_spot(base.position, kind, team)
	if not spot.is_finite():
		return {"accepted": false, "reason": "no build space"}
	if not _team_pay(team, kind):
		return {"accepted": false, "reason": "not enough resources"}
	var st := _add_structure(kind, team, spot)
	if kind == "tower":
		towers.append(st)
	elif kind == "market":
		markets.append(st)
	elif kind == "house":
		_add_team_pop_cap(team, 6)
	elif kind == "forge":
		_set_team_has_forge(team, true)
	Game.resources_changed.emit()
	return {"accepted": true, "reason": "%s built" % kind}

func _team_units(team: int) -> Array:
	var out := []
	for u in units:
		if _node_alive(u) and u.team == team:
			out.append(u)
	return out

func _team_rally_point(team: int) -> Vector2:
	return rally_point if team == 0 else _rival_rally_point

func _team_rally_custom(team: int) -> bool:
	return _player_rally_custom if team == 0 else _rival_rally_custom

func _set_team_rally_point(team: int, pos: Vector2) -> void:
	if team == 0:
		rally_point = pos
		_player_rally_custom = true
	else:
		_rival_rally_point = pos
		_rival_rally_custom = true
	add_alert_ping(pos, "rally")

func _default_rally_for_team(team: int) -> Vector2:
	var base := player_keep if team == 0 else rival_keep
	if not _node_alive(base):
		return Vector2.ZERO
	return base.position + (Vector2(70, 150) if team == 0 else Vector2(-70, -150))

func _order_team_attack(team: int) -> void:
	var target_keep := rival_keep if team == 0 else player_keep
	for u in _team_units(team):
		u.gather_target = null
		u.attack_target = null
		u.player_ordered = false
		if _node_alive(target_keep):
			u.target = target_keep.position

func _order_team_hold(team: int) -> void:
	for u in _team_units(team):
		u.target = u.position
		u.gather_target = null
		u.attack_target = null
		u.player_ordered = false

func _order_team_defend(team: int) -> void:
	var army := []
	for item in _team_units(team):
		var u := item as Unit
		if _node_alive(u) and u.kind != "villager":
			army.append(u)
	_order_units_defend_point(army, _defensive_point_for_team(team))

func _order_units_defend_point(target_units: Array, point: Vector2) -> void:
	var i := 0
	for item in target_units:
		var u := item as Unit
		if not _node_alive(u):
			continue
		var spread := Vector2(float(i % 4) * 24 - 36, float(i / 4) * 24)
		u.target = point + spread
		u.gather_target = null
		u.attack_target = null
		u.player_ordered = false
		i += 1

func _order_team_to_point(team: int, pos: Vector2) -> void:
	_apply_order_to_units(_team_units(team), team, pos)
	add_alert_ping(pos, "rally")

func _apply_order_to_units(target_units: Array, team: int, pos: Vector2) -> void:
	# target priority mirrors ordinary RTS right-click: resource, enemy building, enemy unit, ground.
	var food = _nearest(food_nodes, pos, 40.0)
	var enemy_struct = _nearest_enemy_structure_for_team(pos, 70.0, team)
	var enemy_unit = _nearest_enemy_unit_for_team(pos, 30.0, team)
	var i := 0
	for item in target_units:
		var u := item as Unit
		if not _node_alive(u):
			continue
		var spread := Vector2(float(i % 4) * 26 - 39, float(i / 4) * 26)
		if food and u.kind == "villager":
			u.order_gather(food)
		elif enemy_struct:
			u.order_attack(enemy_struct)
		elif enemy_unit:
			u.order_attack(enemy_unit)
		else:
			u.order_move(pos + spread)
		i += 1

func _order_team_gather(team: int) -> void:
	for u in _team_units(team):
		if u.kind == "villager":
			var node = _nearest(food_nodes, u.position, 1.0e9)
			if node:
				u.order_gather(node)

func _room_snapshot() -> Dictionary:
	_prune_dead_entities()
	var live_units := []
	for u in units:
		if not _node_alive(u):
			continue
		live_units.append({
			"id": u.net_id,
			"king": u.king,
			"kind": u.kind,
			"team": u.team,
			"x": roundi(u.position.x),
			"y": roundi(u.position.y),
			"hp": roundi(u.hp),
			"maxHp": roundi(u.max_hp),
		})
	var live_structures := []
	for s in structures:
		if not _node_alive(s):
			continue
		live_structures.append({
			"id": s.net_id,
			"kind": s.kind,
			"team": s.team,
			"x": roundi(s.position.x),
			"y": roundi(s.position.y),
			"hp": roundi(s.hp),
			"maxHp": roundi(s.max_hp),
		})
	return {
		"version": "memepires-godot-snapshot-v1",
		"started": true,
		"over": _over,
		"result": _match_result,
		"player": String(Game.KINGS[Game.player_king]["name"]),
		"playerId": Game.player_king,
		"rival": String(Game.KINGS[Game.rival_king]["name"]),
		"rivalId": Game.rival_king,
		"seconds": int(_match_t),
		"time": "%02d:%02d" % [int(_match_t) / 60, int(_match_t) % 60],
		"wave": Game.wave,
		"kills": Game.kills,
		"resources": {"food": Game.food, "timber": Game.timber, "memp": Game.memp},
		"rivalResources": {"food": _rival_food, "timber": _rival_timber, "memp": _rival_memp},
		"pop": {"live": Game.pop, "queued": queued_pop, "cap": Game.pop_cap},
		"rivalPop": {"live": _rival_pop, "queued": 0, "cap": _rival_pop_cap},
		"upgrades": {"atk": Game.atk_bonus, "armor": Game.armor_bonus, "eco": Game.eco_bonus, "forge": Game.has_forge},
		"rivalUpgrades": {"atk": _rival_atk_bonus, "armor": _rival_armor_bonus, "eco": _rival_eco_bonus, "forge": _rival_has_forge},
		"wager": {
			"unit": "SOL" if Wallet.verified else "ticket",
			"wagerUnit": "SOL" if Wallet.verified else "ticket",
			"ticketMode": "sol" if Wallet.verified else "ticket",
			"verified": Wallet.verified,
			"wallet": Wallet.address if Wallet.verified else "",
			"walletLabel": Wallet.short() if Wallet.verified else "Ticket mode",
			"stake": Game.wager_stake,
			"tax": Game.wager_tax(),
			"net": Game.wager_net(),
			"winPayout": Game.wager_payout(true),
		},
		"units": live_units,
		"structures": live_structures,
		"battlefield": {
			"world": {"width": int(WORLD.x), "height": int(WORLD.y)},
			"camera": {"x": roundi(camera.position.x), "y": roundi(camera.position.y), "zoom": zoom_level},
		},
	}

func _apply_snapshot(snap: Dictionary) -> void:
	var resource_key := "rivalResources" if Game.my_team == 1 and typeof(snap.get("rivalResources")) == TYPE_DICTIONARY else "resources"
	var pop_key := "rivalPop" if Game.my_team == 1 and typeof(snap.get("rivalPop")) == TYPE_DICTIONARY else "pop"
	var upgrade_key := "rivalUpgrades" if Game.my_team == 1 and typeof(snap.get("rivalUpgrades")) == TYPE_DICTIONARY else "upgrades"
	var resources: Dictionary = snap.get(resource_key, {}) if typeof(snap.get(resource_key)) == TYPE_DICTIONARY else {}
	Game.food = int(resources.get("food", Game.food))
	Game.timber = int(resources.get("timber", Game.timber))
	Game.memp = int(resources.get("memp", Game.memp))
	var pop: Dictionary = snap.get(pop_key, {}) if typeof(snap.get(pop_key)) == TYPE_DICTIONARY else {}
	Game.pop = int(pop.get("live", Game.pop))
	queued_pop = int(pop.get("queued", queued_pop))
	Game.pop_cap = int(pop.get("cap", Game.pop_cap))
	var upgrades: Dictionary = snap.get(upgrade_key, {}) if typeof(snap.get(upgrade_key)) == TYPE_DICTIONARY else {}
	Game.atk_bonus = float(upgrades.get("atk", Game.atk_bonus))
	Game.armor_bonus = float(upgrades.get("armor", Game.armor_bonus))
	Game.eco_bonus = float(upgrades.get("eco", Game.eco_bonus))
	Game.has_forge = bool(upgrades.get("forge", Game.has_forge))
	Game.wave = int(snap.get("wave", Game.wave))
	Game.kills = int(snap.get("kills", Game.kills))
	Game.resources_changed.emit()

	var seen_units := {}
	for d in snap.get("units", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id := int(d.get("id", 0))
		if id <= 0:
			continue
		seen_units[id] = true
		var u: Unit = _units_by_net_id.get(id, null)
		if not _node_alive(u):
			u = _spawn_unit(String(d.get("king", "doge")), String(d.get("kind", "villager")), int(d.get("team", 0)), Vector2(float(d.get("x", 0)), float(d.get("y", 0))), id, false)
		u.king = String(d.get("king", u.king))
		u.kind = String(d.get("kind", u.kind))
		u.team = int(d.get("team", u.team))
		u.hp = float(d.get("hp", u.hp))
		u.max_hp = float(d.get("maxHp", u.max_hp))
		u.puppet = true
		u.net_pos = Vector2(float(d.get("x", u.position.x)), float(d.get("y", u.position.y)))
		u.selected = u.team == Game.my_team and u.selected
		u.queue_redraw()
	for id in _units_by_net_id.keys():
		if not seen_units.has(id):
			var stale: Unit = _units_by_net_id[id]
			if _node_alive(stale):
				stale.queue_free()
			_units_by_net_id.erase(id)
	units = units.filter(func(u): return _node_alive(u))

	var seen_structures := {}
	for d in snap.get("structures", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id := int(d.get("id", 0))
		if id <= 0:
			continue
		seen_structures[id] = true
		var st: Structure = _structures_by_net_id.get(id, null)
		if not _node_alive(st):
			st = _add_structure(String(d.get("kind", "house")), int(d.get("team", 0)), Vector2(float(d.get("x", 0)), float(d.get("y", 0))), id)
		st.kind = String(d.get("kind", st.kind))
		st.team = int(d.get("team", st.team))
		st.position = Vector2(float(d.get("x", st.position.x)), float(d.get("y", st.position.y)))
		st.hp = float(d.get("hp", st.hp))
		st.max_hp = float(d.get("maxHp", st.max_hp))
		st.queue_redraw()
	for id in _structures_by_net_id.keys():
		if not seen_structures.has(id):
			var stale: Structure = _structures_by_net_id[id]
			if _node_alive(stale):
				stale.queue_free()
			_structures_by_net_id.erase(id)
	structures = structures.filter(func(s): return _node_alive(s))

	var seconds := int(snap.get("seconds", 0))
	_match_t = float(seconds)
	if _snapshot_log_t < 0 or seconds - _snapshot_log_t >= 10:
		_snapshot_log_t = seconds
		Game.log_event("Host snapshot %s wave %d." % [String(snap.get("time", "00:00")), Game.wave])
	if bool(snap.get("over", false)) and not _remote_over_shown:
		_remote_over_shown = true
		_over = true
		var result := String(snap.get("result", ""))
		var won := result == "lost"
		_match_result = "won" if won else "lost"
		Game.record_result(_local_result_king(), won, _result_meta())
		Game.log_event("Host result: %s." % result.to_upper())
		_show_banner("VICTORY" if won else "DEFEAT", Color("43c865") if won else Game.COL_ENEMY)
	_publish_web_match_state({"snapshotsApplied": _snapshots_applied, "hostSeconds": seconds, "matchOver": _over, "matchResult": _match_result, "hostResult": String(snap.get("result", ""))})

func _publish_web_match_state(extra := {}) -> void:
	_prune_dead_entities()
	var controlled_units := []
	for u in units:
		if _node_alive(u) and u.team == _controlled_team():
			var screen_pos := u.get_global_transform_with_canvas().origin
			controlled_units.append({
				"id": u.net_id,
				"kind": u.kind,
				"x": u.position.x,
				"y": u.position.y,
				"screenX": screen_pos.x,
				"screenY": screen_pos.y,
				"selected": u.selected,
			})
	var camera_pos := camera.position if is_instance_valid(camera) else Vector2.ZERO
	var camera_zoom := camera.zoom.x if is_instance_valid(camera) else 1.0
	var state := {
		"scene": "main",
		"netMode": Game.net_mode,
		"myTeam": Game.my_team,
		"room": Net.room,
		"netConnected": Net.connected,
		"playerKing": Game.player_king,
		"rivalKing": Game.rival_king,
		"units": units.size(),
		"controlledUnits": controlled_units,
		"selectedCount": _selected().size(),
		"selectedOrderCounts": selected_order_indicator_count(),
		"cameraX": camera_pos.x,
		"cameraY": camera_pos.y,
		"cameraZoom": camera_zoom,
		"structures": structures.size(),
		"food": Game.food,
		"timber": Game.timber,
		"memp": Game.memp,
		"pop": Game.pop,
		"popCap": Game.pop_cap,
		"rivalFood": _rival_food,
		"rivalTimber": _rival_timber,
		"rivalMemp": _rival_memp,
		"rivalPop": _rival_pop,
		"rivalPopCap": _rival_pop_cap,
		"playerAtkBonus": Game.atk_bonus,
		"playerArmorBonus": Game.armor_bonus,
		"playerEcoBonus": Game.eco_bonus,
		"rivalAtkBonus": _rival_atk_bonus,
		"rivalArmorBonus": _rival_armor_bonus,
		"rivalEcoBonus": _rival_eco_bonus,
		"wagerStake": Game.wager_stake,
		"wagerTax": Game.wager_tax(),
		"wagerNet": Game.wager_net(),
		"wagerWinPayout": Game.wager_payout(true),
		"wave": Game.wave,
		"snapshotsSent": _snapshots_sent,
		"snapshotsApplied": _snapshots_applied,
		"intentsSent": _intents_sent,
		"intentsReceived": _intents_received,
		"intentResults": _intent_results,
	}
	for k in extra:
		state[k] = extra[k]
	Game.publish_web_state(state)

func _node_alive(node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()

func _prune_dead_entities() -> void:
	units = units.filter(func(u): return _node_alive(u))
	structures = structures.filter(func(s): return _node_alive(s))
	towers = towers.filter(func(t): return _node_alive(t))
	markets = markets.filter(func(m): return _node_alive(m))
	food_nodes = food_nodes.filter(func(f): return _node_alive(f))
	for id in _units_by_net_id.keys():
		if not _node_alive(_units_by_net_id[id]):
			_units_by_net_id.erase(id)
	for id in _structures_by_net_id.keys():
		if not _node_alive(_structures_by_net_id[id]):
			_structures_by_net_id.erase(id)

func _draw_feature(feature: String, rng: RandomNumberGenerator) -> void:
	match feature:
		"river":
			var pts := PackedVector2Array()
			var yy := 0
			while yy <= int(WORLD.y):
				var t := float(yy) / WORLD.y
				pts.append(Vector2(WORLD.x * 0.55 + sin(t * TAU) * 130.0, float(yy)))
				yy += 50
			var river_edge := Color("0e4f65", 0.70)
			draw_polyline(pts, river_edge, 106.0, true)
			draw_polyline(pts, Color(Game.COL_RIVER, 0.92), 78.0, true)
			draw_polyline(pts, Color(Game.COL_BONE, 0.16), 5.0, true)
		"pond":
			draw_circle(WORLD * 0.5, 262.0, Color("0e4f65", 0.48))
			draw_circle(WORLD * 0.5, 232.0, Color(Game.COL_RIVER, 0.90))
			draw_arc(WORLD * 0.5, 232.0, 0.0, TAU, 48, Color(Game.COL_BONE, 0.18), 3.0, true)
		"cross":
			var road_edge := Color("3c2717", 0.36)
			var road_main := Color(Game.COL_DIRT, 0.78)
			draw_rect(Rect2(WORLD.x * 0.5 - 60.0, 0.0, 120.0, WORLD.y), road_edge)
			draw_rect(Rect2(0.0, WORLD.y * 0.5 - 60.0, WORLD.x, 120.0), road_edge)
			draw_rect(Rect2(WORLD.x * 0.5 - 41.0, 0.0, 82.0, WORLD.y), road_main)
			draw_rect(Rect2(0.0, WORLD.y * 0.5 - 41.0, WORLD.x, 82.0), road_main)
			for off in [-26.0, 26.0]:
				draw_line(Vector2(WORLD.x * 0.5 + off, 0), Vector2(WORLD.x * 0.5 + off, WORLD.y), Color("2f1c10", 0.16), 2.0)
				draw_line(Vector2(0, WORLD.y * 0.5 + off), Vector2(WORLD.x, WORLD.y * 0.5 + off), Color("2f1c10", 0.16), 2.0)
		"checkpoint":
			var road_edge := Color("4a3320", 0.34)
			var road_main := Color("8f7148", 0.62)
			draw_rect(Rect2(0.0, WORLD.y * 0.48 - 54.0, WORLD.x, 108.0), road_edge)
			draw_rect(Rect2(0.0, WORLD.y * 0.48 - 36.0, WORLD.x, 72.0), road_main)
			draw_rect(Rect2(WORLD.x * 0.5 - 110.0, WORLD.y * 0.48 - 94.0, 220.0, 188.0), Color("2d2117", 0.20))
			for x in [WORLD.x * 0.5 - 76.0, WORLD.x * 0.5 + 76.0]:
				draw_rect(Rect2(x - 9.0, WORLD.y * 0.48 - 90.0, 18.0, 180.0), Color("d8c28b", 0.68))
				draw_rect(Rect2(x - 5.0, WORLD.y * 0.48 - 90.0, 10.0, 180.0), Color("4f3a23", 0.58))
			draw_line(Vector2(WORLD.x * 0.5 - 140.0, WORLD.y * 0.48), Vector2(WORLD.x * 0.5 + 140.0, WORLD.y * 0.48), Color("e9d9a7", 0.68), 4.0)
		"wadi":
			var pts := PackedVector2Array()
			var xx := 0
			while xx <= int(WORLD.x):
				var t := float(xx) / WORLD.x
				pts.append(Vector2(float(xx), WORLD.y * 0.56 + sin(t * TAU * 1.45) * 88.0))
				xx += 48
			draw_polyline(pts, Color("7a5633", 0.36), 112.0, true)
			draw_polyline(pts, Color("b98f57", 0.50), 80.0, true)
			draw_polyline(pts, Color("ead39b", 0.34), 7.0, true)
		"urban":
			for i in range(18):
				var p := Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y)
				var s := Vector2(58.0 + rng.randf() * 92.0, 36.0 + rng.randf() * 64.0)
				draw_rect(Rect2(p - s * 0.5, s), Color("5a4a3d", 0.16))
				draw_rect(Rect2(p - s * 0.42, s * 0.84), Color("c1aa7d", 0.18))
		"dirt":
			for i in range(14):
				draw_circle(Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y), 34.0 + rng.randf() * 58.0, Color(Game.COL_DIRT, 0.24))
		"quarry":
			for i in range(18):
				var p := Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y)
				draw_circle(p, 32.0 + rng.randf() * 70.0, Color("7b735f", 0.24))
				draw_circle(p + Vector2(8, -5), 14.0 + rng.randf() * 32.0, Color("dfc995", 0.18))
		"patches":
			for i in range(14):
				draw_circle(Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y), 40.0 + rng.randf() * 50.0, Color(Game.COL_DIRT, 0.30))
		"plaza":
			draw_rect(Rect2(WORLD * 0.5 - Vector2(230, 168), Vector2(460, 336)), Color("3c2717", 0.18))
			draw_rect(Rect2(WORLD * 0.5 - Vector2(210, 150), Vector2(420, 300)), Color("8d7a5a", 0.46))
		"coast":
			draw_rect(Rect2(0.0, 0.0, WORLD.x * 0.18, WORLD.y), Color("18677a", 0.48))
			draw_rect(Rect2(WORLD.x * 0.18, 0.0, WORLD.x * 0.035, WORLD.y), Color("ead9a0", 0.46))
			for i in range(18):
				var y := rng.randf() * WORLD.y
				draw_line(Vector2(WORLD.x * 0.17, y), Vector2(WORLD.x * 0.21, y + rng.randf_range(-18.0, 18.0)), Color("fff1c4", 0.16), 2.0)
		"fence":
			var x := WORLD.x * 0.52
			draw_rect(Rect2(x - 36.0, 0.0, 72.0, WORLD.y), Color("4d3825", 0.20))
			for y in range(0, int(WORLD.y), 54):
				draw_line(Vector2(x - 22.0, y), Vector2(x + 22.0, y + 30.0), Color("d6c38b", 0.52), 2.0)
				draw_line(Vector2(x + 22.0, y), Vector2(x - 22.0, y + 30.0), Color("d6c38b", 0.38), 2.0)
		"scrub":
			for i in range(26):
				var p := Vector2(rng.randf() * WORLD.x, rng.randf() * WORLD.y)
				draw_circle(p, 18.0 + rng.randf() * 34.0, Color("787a3e", 0.15))
		"flowers":
			var fr := RandomNumberGenerator.new()
			fr.seed = 99
			for i in range(140):
				var p := Vector2(fr.randf() * WORLD.x, fr.randf() * WORLD.y)
				draw_circle(p, 3.0, Color("ff79ba") if i % 2 == 0 else Color("ffe15a"))
		_:
			pass

func _draw() -> void:
	var cfg := Game.arena_cfg()
	var ground := Color(cfg.ground)
	var biome := String(cfg.get("biome", "grass"))
	draw_rect(Rect2(Vector2.ZERO, WORLD), ground)
	var battlefield_texture := battlefield_sand if biome == "sand" else battlefield_grass
	if battlefield_texture:
		draw_texture_rect(battlefield_texture, Rect2(Vector2.ZERO, WORLD), false, Color(1, 1, 1, 1))
	var variation_paths := SAND_VARIATION_PATHS if biome == "sand" else GRASS_VARIATION_PATHS
	if variation_paths.size() > 0:
		var tile_rng := RandomNumberGenerator.new()
		tile_rng.seed = 260626
		for i in range(18 if biome == "sand" else 10):
			var tex: Texture2D = load(variation_paths[tile_rng.randi() % variation_paths.size()])
			if tex == null:
				continue
			var size := Vector2(256, 256) * (0.8 + tile_rng.randf() * 0.45)
			var pos := Vector2(tile_rng.randf() * WORLD.x, tile_rng.randf() * WORLD.y)
			draw_texture_rect(tex, Rect2(pos - size * 0.5, size), false, Color(1, 1, 1, 0.16 if biome == "sand" else 0.20))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_draw_feature(String(cfg.feature), rng)
	# dirt aprons under the two keeps
	if _node_alive(player_keep):
		draw_circle(player_keep.position + Vector2(0, 18), 118.0, Color("3c2717", 0.12))
		draw_circle(player_keep.position + Vector2(0, 18), 96.0, Color(Game.COL_DIRT, 0.32))
	if _node_alive(rival_keep):
		draw_circle(rival_keep.position + Vector2(0, 18), 118.0, Color("3c2717", 0.12))
		draw_circle(rival_keep.position + Vector2(0, 18), 96.0, Color(Game.COL_DIRT, 0.32))
	# subtle tile grid
	var grid := Color(0, 0, 0, 0.032)
	for gx in range(0, int(WORLD.x), 96):
		draw_line(Vector2(gx, 0), Vector2(gx, WORLD.y), grid, 1.0)
	for gy in range(0, int(WORLD.y), 96):
		draw_line(Vector2(0, gy), Vector2(WORLD.x, gy), grid, 1.0)
	draw_rect(Rect2(Vector2.ZERO, WORLD), Game.COL_EDGE, false, 4.0)
	for ping in alert_pings:
		var pos: Vector2 = ping.get("pos", Vector2.ZERO)
		var age := float(ping.get("age", 0.0))
		var duration := maxf(float(ping.get("duration", 1.0)), 0.01)
		var t := clampf(age / duration, 0.0, 1.0)
		var col := alert_ping_color(String(ping.get("kind", "danger")))
		var alpha := 1.0 - t
		draw_circle(pos, 24.0 + 68.0 * t, Color(col, 0.10 * alpha))
		draw_arc(pos, 24.0 + 68.0 * t, 0.0, TAU, 42, Color(col, 0.95 * alpha), 3.0, true)
		draw_arc(pos, 12.0 + 32.0 * t, 0.0, TAU, 32, Color(Game.COL_BONE, 0.45 * alpha), 1.3, true)
	for item in _selected():
		var u := item as Unit
		if _node_alive(u):
			_draw_command_marker("select", u.position + Vector2(0, 13), 42.0, Color(1, 1, 1, 0.86))
	# rally flag
	if rally_point != Vector2.ZERO:
		_draw_command_marker("rally", rally_point, 34.0, Color(1, 1, 1, 0.95))
	_draw_selected_order_indicators()
	# selection marquee
	if selecting:
		var r := Rect2(sel_start, sel_now - sel_start).abs()
		draw_rect(r, Color(Game.COL_ACCENT_BRIGHT, 0.12))
		draw_rect(r, Game.COL_ACCENT_BRIGHT, false, 1.5)

func _draw_command_marker(kind: String, pos: Vector2, size := 34.0, tint := Color.WHITE) -> void:
	var tex: Texture2D = command_markers.get(kind, null)
	if tex == null:
		draw_arc(pos, size * 0.32, 0.0, TAU, 28, tint, 2.0, true)
		return
	var half := Vector2(size, size) * 0.5
	draw_texture_rect(tex, Rect2(pos - half, Vector2(size, size)), false, tint)

func _draw_selected_order_indicators() -> void:
	for item in _selected():
		var u := item as Unit
		var kind := _unit_order_kind(u)
		if kind == "":
			continue
		var p := _unit_order_point(u)
		var col := Game.COL_ACCENT_BRIGHT
		if kind == "attack":
			col = Game.COL_ENEMY.lightened(0.25)
		elif kind == "gather":
			col = Color("ffd15c")
		draw_line(u.position + Vector2(0, 8), p, Color(col, 0.42), 1.4)
		_draw_command_marker(kind, p, 34.0, Color(1, 1, 1, 0.95))
		if kind == "attack":
			_draw_command_marker("target", p, 46.0, Color(1, 1, 1, 0.72))
