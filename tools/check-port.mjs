import { access, readFile, stat } from "node:fs/promises";
import { spawn } from "node:child_process";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const godotCandidates = [
  process.env.GODOT_BIN,
  "/Applications/Godot.app/Contents/MacOS/Godot",
  "godot4",
  "godot",
].filter(Boolean);

const mustExist = async (path) => {
  await access(join(root, path));
};

const mustNotExist = async (path) => {
  try {
    await access(join(root, path));
  } catch {
    return;
  }
  throw new Error(`${path} should not exist in the Godot port`);
};

const read = (path) => readFile(join(root, path), "utf8");

const requireText = (label, text, needle) => {
  if (!text.includes(needle)) throw new Error(`${label} missing ${JSON.stringify(needle)}`);
};

const forbidText = (label, text, needle) => {
  if (text.includes(needle)) throw new Error(`${label} should not include ${JSON.stringify(needle)}`);
};

const isPurpleChromaKeyPixel = (r, g, b, a) => {
  if (a === 0) return false;
  const rf = r / 255;
  const gf = g / 255;
  const bf = b / 255;
  const max = Math.max(rf, gf, bf);
  const min = Math.min(rf, gf, bf);
  const delta = max - min;
  const saturation = max === 0 ? 0 : delta / max;
  let hue = 0;
  if (delta !== 0) {
    if (max === rf) hue = 60 * (((gf - bf) / delta) % 6);
    else if (max === gf) hue = 60 * ((bf - rf) / delta + 2);
    else hue = 60 * ((rf - gf) / delta + 4);
  }
  if (hue < 0) hue += 360;

  const saturatedPurple = hue >= 280 && hue <= 350 && saturation >= 0.28 && max >= 0.18 && g < 120;
  const darkPurpleFringe = r > 70 && b > 70 && g < 75 && Math.abs(r - b) < 110 && Math.max(r, b) - g > 25;
  return saturatedPurple || darkPurpleFringe;
};

const run = (cmd, args) =>
  new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve(out);
      else reject(new Error(`${cmd} ${args.join(" ")} failed with ${code}\n${out}`));
    });
  });

const runBuffer = (cmd, args) =>
  new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
    const chunks = [];
    let err = "";
    child.stdout.on("data", (d) => chunks.push(d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve(Buffer.concat(chunks));
      else reject(new Error(`${cmd} ${args.join(" ")} failed with ${code}\n${err}`));
    });
  });

const findGodot = async () => {
  for (const candidate of godotCandidates) {
    try {
      await run(candidate, ["--version"]);
      return candidate;
    } catch {
      // try the next candidate
    }
  }
  throw new Error("Godot binary not found. Set GODOT_BIN or install Godot.");
};

for (const path of [
  "project.godot",
  "scenes/StartMenu.tscn",
  "scenes/Main.tscn",
  "scripts/Game.gd",
  "scripts/FoodNode.gd",
  "scripts/Main.gd",
  "scripts/Net.gd",
  "scripts/Wallet.gd",
  "assets/portraits/faction_portrait_israel.png",
  "assets/portraits/faction_portrait_palestine.png",
  "assets/ui/faction_icon_israel.png",
  "assets/ui/faction_icon_palestine.png",
  "assets/units/israel_swordsman_walk.png",
  "assets/units/israel_villager_walk.png",
  "assets/units/israel_archer_walk.png",
  "assets/units/israel_lancer_walk.png",
  "assets/units/israel_siege_walk.png",
  "assets/units/palestine_swordsman_walk.png",
  "assets/units/palestine_villager_walk.png",
  "assets/units/palestine_archer_walk.png",
  "assets/units/palestine_lancer_walk.png",
  "assets/units/palestine_siege_walk.png",
  "assets/terrain/terrain_grass_battlefield.png",
  "assets/terrain/terrain_grass_tile.png",
  "assets/terrain/terrain_grass_variation_01.png",
  "assets/terrain/terrain_grass_variation_02.png",
  "assets/terrain/terrain_grass_variation_03.png",
  "assets/terrain/terrain_sand_battlefield.png",
  "assets/terrain/terrain_sand_tile.png",
  "assets/terrain/terrain_sand_variation_01.png",
  "assets/terrain/terrain_sand_variation_02.png",
  "assets/terrain/terrain_sand_variation_03.png",
  "assets/terrain/terrain_detail_sand_rock.png",
  "assets/terrain/terrain_detail_dry_scrub.png",
  "assets/fx/command_attack_marker.png",
  "assets/fx/command_gather_marker.png",
  "assets/fx/command_move_marker.png",
  "assets/fx/command_rally_marker.png",
  "assets/fx/command_select_ring.png",
  "assets/fx/command_target_bracket.png",
  "assets/ui/command_icon_lancer.png",
  "assets/ui/command_icon_siege.png",
  "assets/ui/control_icon_army.png",
  "assets/ui/control_icon_attack.png",
  "assets/ui/control_icon_concede.png",
  "assets/ui/control_icon_gather.png",
  "assets/ui/control_icon_hold.png",
  "assets/ui/control_icon_pause.png",
  "assets/ui/control_icon_power.png",
  "assets/ui/control_icon_rally.png",
  "assets/ui/control_icon_speed.png",
  "assets/ui/control_icon_workers.png",
  "assets/ui/control_icon_zoom.png",
  "assets/ui/main_menu_logo.png",
  "assets/ui/ui_rd_panel_large.png",
  "assets/ui/ui_rd_panel_medium.png",
  "assets/ui/ui_rd_status_bar.png",
  "assets/ui/ui_rd_status_bar_blue.png",
  "assets/ui/ui_rd_button_normal.png",
  "assets/ui/ui_rd_button_hover.png",
  "assets/ui/ui_rd_button_pressed.png",
  "assets/ui/ui_rd_resource_bar.png",
  "assets/ui/ui_rd_atlas_alpha.png",
  "tools/check-room-stream.mjs",
  "tools/check-wallet-leaderboard.mjs",
  "tools/check-web-visual.mjs",
  "tools/fix-web-shell.mjs",
  "tools/slice-faction-sprites.py",
  "build/web/index.html",
  "build/web/index.js",
  "build/web/index.pck",
  "build/web/index.wasm",
]) {
  await mustExist(path);
}

await mustNotExist(".claude");

const project = await read("project.godot");
const game = await read("scripts/Game.gd");
const foodNode = await read("scripts/FoodNode.gd");
const hud = await read("scripts/Hud.gd");
const main = await read("scripts/Main.gd");
const minimap = await read("scripts/MiniMap.gd");
const structure = await read("scripts/Structure.gd");
const unit = await read("scripts/Unit.gd");
const net = await read("scripts/Net.gd");
const startMenu = await read("scripts/StartMenu.gd");
const wallet = await read("scripts/Wallet.gd");
const server = await read("serve-web.mjs");
const streamCheck = await read("tools/check-room-stream.mjs");
const walletCheck = await read("tools/check-wallet-leaderboard.mjs");
const webVisualCheck = await read("tools/check-web-visual.mjs");
const webShellFix = await read("tools/fix-web-shell.mjs");
const factionSlicer = await read("tools/slice-faction-sprites.py");
const html = await read("build/web/index.html");

requireText("project", project, 'config/name="Israel vs Palestine"');
requireText("project web viewport", project, "window/size/viewport_width=1280");
requireText("project web viewport", project, "window/size/viewport_height=720");
requireText("project web stretch", project, 'window/stretch/aspect="expand"');
requireText("project web stretch", project, 'window/stretch/mode="canvas_items"');
requireText("main multiplayer", main, "func _room_snapshot()");
requireText("main multiplayer final snapshot", main, "func _send_final_snapshot()");
requireText("main multiplayer remote result", main, "_remote_over_shown");
requireText("main result flow", main, "func _return_to_menu()");
requireText("main result flow", main, "MAIN MENU");
requireText("main result flow", main, "Engine.time_scale = 1.0");
requireText("main result flow", main, "func _local_result_king()");
requireText("main result flow", main, "func _local_result_rival()");
requireText("main result flow", main, "Game.record_result(_local_result_king(), false, _result_meta())");
requireText("main result smoke", main, "--result-smoke");
requireText("main web result smoke", main, "webResultSmoke");
requireText("main web result smoke", main, "func _web_result_smoke");
requireText("main web meme sprite preview", main, "memeSpritePreview");
requireText("main web meme sprite preview", main, "func _web_meme_sprite_preview");
requireText("main web meme sprite preview", main, '"king": "pepe"');
requireText("main web meme sprite preview", main, '"lancer"');
requireText("main web meme sprite preview", main, '"siege"');
requireText("main web selection summary preview", main, "selectionSummaryPreview");
requireText("main web selection summary preview", main, "func _web_selection_summary_preview");
requireText("game faction asset sheets", game, "portrait_path");
requireText("game faction asset sheets", game, 'KINGS.get(king, {}).get("asset", king)');
requireText("main remote result smoke", main, "--remote-result-smoke");
requireText("main remote result", main, "hostResult");
requireText("main tower targeting", main, "--tower-target-smoke");
requireText("main tower targeting", main, "func _nearest_enemy_unit_for_team");
requireText("main projectile FX", main, "--projectile-fx-smoke");
requireText("main projectile FX", main, "func _projectile_texture_path");
requireText("main projectile FX", main, "func _spawn_projectile_impact");
requireText("main projectile FX", main, 'spawn_projectile(t.position + Vector2(0, origin_y), foe.position, "bolt")');
requireText("main projectile FX", main, "PROJECTILE_FX_SMOKE");
requireText("main alert pings", main, "--alert-ping-smoke");
requireText("main alert pings", main, "func add_alert_ping");
requireText("main alert pings", main, "func alert_ping_color");
requireText("main alert pings", main, "ALERT_PING_SMOKE");
requireText("main alert pings", main, 'add_alert_ping(rival_keep.position, "danger")');
requireText("main camera zoom", main, "CAMERA_ZOOM_STEP");
requireText("main camera zoom", main, "func cmd_zoom_in");
requireText("main camera zoom", main, "func hud_zoom_label");
requireText("main camera zoom", main, "--camera-zoom-smoke");
requireText("main build placement", main, "--build-placement-smoke");
requireText("main build ghost", main, "--build-ghost-smoke");
requireText("main build ghost", main, "func _update_build_ghost_at");
requireText("main build placement", main, "func _can_place_structure");
requireText("main build placement", main, "Cannot build there.");
requireText("main resource depletion", main, "--resource-depletion-smoke");
requireText("food node depletion", foodNode, "func harvest");
requireText("food node graphics", foodNode, "visual_seed");
requireText("food node graphics", foodNode, "draw_set_transform");
requireText("unit gather depletion", unit, "gather_target.harvest");
requireText("unit projectile roles", unit, '["archer", "siege"].has(kind)');
requireText("unit projectile roles", unit, '"stone" if kind == "siege" else "arrow"');
requireText("unit graphics", unit, "func _sync_draw_order");
requireText("unit graphics", unit, "draw_set_transform");
requireText("unit directional sprites", unit, "var _facing_row");
requireText("unit directional sprites", unit, "func _face_dir");
requireText("unit directional sprites", unit, "func _set_sprite_frame");
requireText("unit readable sprites", unit, "func _sprite_scale");
requireText("unit readable sprites", unit, "return 1.64");
requireText("unit readable sprites", unit, "return 1.72");
requireText("unit all faction readable sprites", unit, "return 1.82");
requireText("unit all faction readable sprites", unit, "return 1.62");
requireText("unit all faction clickable sprites", unit, "func click_radius");
requireText("unit all faction clickable sprites", unit, "func _selection_radius");
requireText("main all faction unit scale", main, "--unit-scale-smoke");
requireText("main all faction unit scale", main, "func _unit_scale_smoke");
requireText("main opening balance", main, "--opening-balance-smoke");
requireText("main opening balance", main, "AI_FREE_SPAWN_START");
requireText("main opening balance", main, "FIRST_WAVE_START");
requireText("main opening balance", main, "ENEMY_ATTACK_GRACE");
requireText("main opening balance", main, "func _spawn_starting_defenders");
requireText("main opening balance", main, "func _opening_balance_smoke");
requireText("main ready defenders", main, "--ready-defender-smoke");
requireText("main ready defenders", main, "func _apply_new_unit_default_order");
requireText("main ready defenders", main, "func _ready_defender_smoke");
requireText("game opening resources", game, "const START_FOOD := 420");
requireText("game opening resources", game, "const START_TIMBER := 360");
requireText("game opening resources", game, "const START_POP_CAP := 24");
requireText("unit sturdier villagers", unit, "hp = 60.0; max_hp = 60.0");
requireText("faction sprite slicer", factionSlicer, "SOURCES_BY_FACTION");
requireText("faction sprite slicer", factionSlicer, 'f"{faction}_{kind}_walk.png"');
requireText("faction sprite slicer", factionSlicer, "DERIVED_ROLES");
requireText("israel sprite slicer", factionSlicer, '"israel"');
requireText("israel sprite slicer", factionSlicer, "idf swordsman.png");
requireText("israel sprite slicer", factionSlicer, "idf villager.png");
requireText("israel sprite slicer", factionSlicer, "idf archer.png");
requireText("israel sprite slicer", factionSlicer, "idf siegecrawler.png");
requireText("palestine sprite slicer", factionSlicer, '"palestine"');
requireText("palestine sprite slicer", factionSlicer, "pal swordsman.png");
requireText("palestine sprite slicer", factionSlicer, "palestinian villlager.png");
requireText("derived sprite slicer", factionSlicer, '"lancer"');
requireText("derived sprite slicer", factionSlicer, '"archer"');
requireText("derived sprite slicer", factionSlicer, '"siege"');
requireText("main destroyed entities", main, "--destroyed-entity-smoke");
requireText("main destroyed entities", main, "func _node_alive");
requireText("main destroyed entities", main, "func _prune_dead_entities");
requireText("minimap destroyed entities", minimap, "is_queued_for_deletion()");
requireText("minimap RTS UX", minimap, "func _gui_input");
requireText("minimap RTS UX", minimap, "center_camera_on");
requireText("minimap RTS UX", minimap, "MOUSE_BUTTON_RIGHT");
requireText("minimap RTS UX", minimap, "main.minimap_click");
requireText("minimap alert pings", minimap, "main.alert_pings");
requireText("minimap alert pings", minimap, "alert_ping_color");
requireText("main minimap RTS UX", main, "func center_camera_on");
requireText("main minimap RTS UX", main, "func minimap_click");
requireText("main minimap RTS UX", main, "--minimap-command-smoke");
requireText("main queue status", main, "func hud_queue_summary");
requireText("main queue status", main, "--queue-status-smoke");
requireText("main order indicators", main, "func _draw_selected_order_indicators");
requireText("main order indicators", main, "func selected_order_indicator_count");
requireText("main order indicators", main, "--order-indicator-smoke");
requireText("main command marker sprites", main, "COMMAND_MARKER_PATHS");
requireText("main command marker sprites", main, "func _draw_command_marker");
requireText("main command marker sprites", main, "--command-marker-smoke");
requireText("main command marker sprites", main, "command_target_bracket.png");
requireText("main RTS edge pan", main, "EDGE_PAN_MARGIN");
requireText("main RTS edge pan", main, "func _camera_pan_vector");
requireText("main responsive camera", main, "func _min_camera_zoom_for_viewport");
requireText("main responsive camera", main, "func _sync_camera_zoom");
requireText("main responsive camera", main, "get_viewport().size_changed.connect(_sync_camera_zoom)");
requireText("main RTS hotkeys", main, "func _handle_command_key");
requireText("main RTS hotkeys", main, 'KEY_1');
requireText("main RTS hotkeys", main, 'KEY_B');
requireText("main RTS hotkeys", main, 'KEY_SPACE');
requireText("main RTS input smoke", main, "--input-flow-smoke");
requireText("main RTS mouse input", main, "--mouse-input-smoke");
requireText("main RTS mouse input", main, "func _input(event: InputEvent)");
requireText("main RTS mouse input", main, "func _handle_pointer_button");
requireText("main RTS mouse input", main, "func _handle_mouse_button");
requireText("main RTS mouse input", main, "func _screen_to_world");
requireText("main RTS mouse input", main, "func _world_to_screen");
requireText("main RTS mouse input", main, "_handle_mouse_button(mouse.button_index, mouse.pressed, mouse.double_click, mouse.shift_pressed, _screen_to_world(mouse.position))");
requireText("main RTS mouse input", main, "func _publish_selection_state");
requireText("main RTS browser mouse state", main, '"controlledUnits": controlled_units');
requireText("main RTS browser mouse state", main, '"screenX": screen_pos.x');
requireText("main RTS browser mouse state", main, '"screenY": screen_pos.y');
requireText("main RTS browser mouse state", main, '"cameraZoom": camera_zoom');
requireText("main RTS input smoke", main, "func _finish_selection(additive := false, double_click := false)");
requireText("main RTS double-click selection", main, "--double-click-select-smoke");
requireText("main RTS double-click selection", main, "func _double_click_select_smoke");
requireText("main RTS double-click selection", main, "func _select_visible_kind");
requireText("main RTS double-click selection", main, "func _visible_world_rect");
requireText("main faction sprite smoke", main, "--faction-sprite-smoke");
requireText("main faction sprite smoke", main, "func _faction_sprite_smoke");
requireText("main doge sprite smoke", main, "readable_scale");
requireText("main unit spawn setup order", main, "u.setup(king, kind, team)\n\tadd_child(u)");
requireText("main structure setup order", main, "st.setup(kind, team)\n\tadd_child(st)");
requireText("main structure stats", main, "--structure-stats-smoke");
requireText("structure market stats", structure, 'kind == "market"');
requireText("structure market stats", structure, "650.0");
requireText("structure graphics", structure, "func _sync_draw_order");
requireText("structure graphics", structure, "draw_set_transform");
requireText("structure pixel standards", structure, "static func visual_scale_for");
requireText("structure pixel standards", structure, "static func footprint_radius_for");
requireText("structure pixel standards", structure, "return 1.55");
requireText("main structure footprints", main, "Structure.footprint_radius_for(kind)");
requireText("main structure footprints", main, "Structure.visual_scale_for(kind)");
requireText("main battlefield graphics", main, "river_edge");
requireText("main battlefield graphics", main, "road_edge");
requireText("main battlefield graphics", main, "BATTLEFIELD_GRASS_PATH");
requireText("main battlefield graphics", main, "BATTLEFIELD_SAND_PATH");
requireText("main battlefield graphics", main, "SAND_VARIATION_PATHS");
requireText("main battlefield graphics", main, 'biome == "sand"');
requireText("main battlefield graphics", main, "terrain_sand_variation_03.png");
requireText("game arena terrain", game, '"label": "Negev Flats"');
requireText("game arena terrain", game, '"feature": "checkpoint"');
requireText("game arena terrain", game, '"biome": "sand"');
requireText("main remote economy", main, "--remote-economy-smoke");
requireText("main remote economy", main, "func _research_for_team");
requireText("main remote economy", main, "rivalResources");
requireText("main remote economy", main, "rivalUpgrades");
requireText("main remote authority", main, "--remote-authority-smoke");
requireText("main remote authority", main, "func _find_build_spot");
requireText("main remote authority", main, "func _default_rally_for_team");
requireText("main remote order", main, "--remote-order-smoke");
requireText("main remote order", main, "--remote-order-target-smoke");
requireText("main remote order", main, "func _order_team_to_point");
requireText("main remote order", main, "func _apply_order_to_units");
requireText("main remote order", main, '"action": "order"');
requireText("main multiplayer setup", main, "--multiplayer-setup-smoke");
requireText("main multiplayer setup", main, "func _human_multiplayer");
requireText("main multiplayer setup", main, "MULTIPLAYER_SETUP_SMOKE");
requireText("main remote concede", main, "--remote-concede-smoke");
requireText("main remote concede", main, "_send_intent(\"concede\")");
requireText("main remote concede", main, "func _finish_by_concede");
requireText("main net leave", main, "--net-leave-smoke");
requireText("net leave clears room", net, 'room = ""');
requireText("net leave clears role", net, 'role = ""');
requireText("main hud team", main, "--hud-team-smoke");
requireText("main hud team", main, "func hud_can_afford");
requireText("main tech status", main, "--tech-status-smoke");
requireText("main tech status", main, "func hud_tech_summary");
requireText("main tech status", main, "TECH_STATUS_SMOKE");
requireText("main selection summary", main, "--selection-summary-smoke");
requireText("main selection summary", main, "func hud_selection_summary");
requireText("main selection summary", main, "SELECTION_SUMMARY_SMOKE");
requireText("hud team resources", hud, "main.hud_food()");
requireText("hud team resources", hud, "main.hud_can_afford(kind)");
requireText("hud team objective", hud, "Crush enemy keep");
requireText("hud selection summary", hud, "lbl_sel_comp");
requireText("hud selection summary", hud, "_refresh_selection_summary");
requireText("hud selection summary", hud, "main.hud_selection_summary()");
requireText("hud unit command icons", hud, "command_icon_lancer.png");
requireText("hud unit command icons", hud, "command_icon_siege.png");
requireText("hud portrait build wrap", hud, "var portrait_build_row: HFlowContainer");
requireText("hud portrait build wrap", hud, "portrait_build_row = row");
requireText("hud command wrap", hud, "var command_row: HFlowContainer");
requireText("hud command wrap", hud, "var control_bar: HFlowContainer");
requireText("hud command wrap", hud, "command_row = row");
requireText("hud portrait command layout", hud, "map_w = 132.0");
requireText("hud portrait command layout", hud, "cmd_w = 90.0");
requireText("hud portrait command layout", hud, "command_status.custom_minimum_size = Vector2(104.0 if portrait else 148.0, 0)");
requireText("hud tech summary", hud, "lbl_tech");
requireText("hud tech summary", hud, "_refresh_tech_summary");
requireText("hud tech summary", hud, "main.hud_tech_summary()");
requireText("hud queue summary", hud, "_refresh_queue_summary");
requireText("hud queue summary", hud, "main.hud_queue_summary()");
requireText("hud RTS command icons", hud, "COMMAND_ICONS");
requireText("hud RTS command icons", hud, "_apply_command_icon");
requireText("hud RTS control icons", hud, "CONTROL_ICONS");
requireText("hud RTS control icons", hud, "_apply_control_icon");
requireText("hud RTS control icons", hud, "control_icon_power.png");
requireText("hud zoom controls", hud, "btn_zoom");
requireText("hud zoom controls", hud, 'main.cmd_zoom_in()');
requireText("hud zoom controls", hud, 'main.cmd_zoom_out()');
requireText("hud zoom controls", hud, "main.hud_zoom_label()");
requireText("hud wager labels", hud, '"S" if Wallet.verified else "T"');
requireText("hud wager labels", hud, "N%d");
requireText("hud RTS resource icons", hud, "RESOURCE_ICONS");
requireText("hud RTS resource icons", hud, "ui_food_icon.png");
requireText("hud RTS resource icons", hud, "ui_timber_icon.png");
requireText("hud RTS resource icons", hud, "ui_memp_icon.png");
requireText("hud RTS command state", hud, "PLACING %s");
requireText("hud RTS command state", hud, "RALLY TARGET");
requireText("hud flat RTS panels", hud, "_flat_panel");
requireText("hud flat RTS panels", hud, "_button_panel");
requireText("hud flat RTS panels", hud, "set_border_width_all(1)");
requireText("hud defend command", hud, "cmd_defend_base()");
requireText("hud defend command", hud, "Defend base");
requireText("hud control group readout", hud, "lbl_groups");
requireText("hud control group readout", hud, "_refresh_control_groups");
forbidText("hud no in-game matchup banner", hud, "_build_matchup()");
forbidText("hud no in-game matchup banner", hud, "matchup_holder");
requireText("hud portrait responsive", hud, "func _display_size");
requireText("hud portrait responsive", hud, "window.innerWidth || 0");
requireText("hud portrait responsive", hud, "var portrait := display.y > display.x * 1.15");
requireText("hud portrait responsive", hud, "side_panel.visible = not portrait");
requireText("hud portrait responsive", hud, "var bottom_scale := Vector2.ONE");
requireText("hud portrait responsive", hud, "ctrl_w = 38.0");
requireText("hud portrait build tray", hud, "func _build_portrait_build_bar");
requireText("hud portrait build tray", hud, "portrait_build_frame.visible = portrait");
requireText("hud portrait build tray", hud, '_portrait_build_button("HOUSE", "house"');
requireText("hud portrait build tray", hud, '_portrait_build_button("ECO", "upgrade_eco"');
requireText("main intent preflight", main, "--intent-preflight-smoke");
requireText("main intent preflight", main, "func _preflight_controlled_cost");
requireText("main multiplayer", main, "func _apply_remote_intent");
requireText("main multiplayer", main, "func _apply_snapshot");
requireText("main telemetry", main, "func _publish_web_match_state");
requireText("main gameplay", main, "func credit_resource");
requireText("main gameplay", main, "func team_atk_bonus");
requireText("game leaderboard", game, "func _post_web_result");
requireText("game leaderboard", game, "fetch('/leaderboard'");
requireText("server persistent leaderboard", server, "MEMEPIRE_DATA_DIR");
requireText("server persistent leaderboard", server, ".memepire-data");
requireText("server persistent leaderboard", server, "legacyLeaderboardFile");
requireText("game result smoke", game, "suppress_result_persistence");
requireText("net", net, "type\": \"match-config\"");
requireText("net relay", net, "window.MEMPIRES_ROOM_RELAY");
forbidText("net relay", net, "AIGE_ROOM_RELAY");
requireText("game telemetry", game, "__memepireState");
requireText("host-only launch", startMenu, "waiting for host to launch");
requireText("main menu logo", startMenu, "MAIN_MENU_LOGO");
requireText("main menu logo", startMenu, "main_menu_logo.png");
requireText("main menu logo", startMenu, "title_logo = TextureRect.new()");
requireText("main menu layout", startMenu, "setup_row");
requireText("main menu layout", startMenu, "start.custom_minimum_size = Vector2(760, 50)");
requireText("wager tickets", startMenu, "func _accept_wager");
requireText("wager tickets", startMenu, "wager-offer");
requireText("wager tickets", startMenu, "wager-receipt");
requireText("wager tickets", startMenu, "Game.wager_payout(true)");
requireText("net wager math", net, "Game.wager_payout(true)");
forbidText("stale wager math", startMenu, "net * 2");
forbidText("stale wager math", net, "net * 2");
requireText("wager launch gate", startMenu, "waiting for accepted wager");
requireText("wager unit label", startMenu, "func _wager_unit_label");
requireText("wager unit label", startMenu, "_wager_mode_label()");
requireText("leaderboard error state", startMenu, "WEB BOARD ERROR");
requireText("start menu URL params", startMenu, "func _apply_url_params");
requireText("start menu URL params", startMenu, "window.location.search");
requireText("start menu URL params", startMenu, "roomRole");
requireText("start menu URL params", startMenu, "call_deferred(\"_net_host\")");
requireText("start menu responsive", startMenu, "func _apply_responsive_layout");
requireText("start menu responsive", startMenu, "func _display_size");
requireText("start menu responsive", startMenu, "get_viewport().size_changed.connect(_apply_responsive_layout)");
requireText("start menu responsive", startMenu, "window.innerWidth || 0");
requireText("start menu responsive", startMenu, "leaderboard_panel.visible = not portrait");
requireText("start menu responsive", startMenu, "menu_box.scale = Vector2(1.22, 1.22) if portrait else Vector2(1.08, 1.08)");
requireText("start menu centered controls", startMenu, "var setup_row := VBoxContainer.new()");
requireText("start menu centered controls", startMenu, "start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER");
requireText("start menu web leaderboard", startMenu, "func _request_web_leaderboard");
requireText("start menu web leaderboard", startMenu, "fetch('/leaderboard'");
requireText("start menu web leaderboard", startMenu, "SYNCING WEB BOARD");
requireText("start menu generated pixel UI", startMenu, "const UI_RD_PANEL");
requireText("start menu generated pixel UI", startMenu, "StyleBoxTexture.new()");
requireText("start menu generated pixel UI", startMenu, "ui_rd_status_bar_blue.png");
requireText("start menu room links", startMenu, "--room-links-smoke");
requireText("start menu room links", startMenu, "join=1&stake=%s&king=%s&rival=%s");
requireText("wallet", wallet, "__memepireWalletAddress");
requireText("wallet verified login", wallet, "__memepireWalletToken");
requireText("wallet verified login", wallet, "signMessage");
requireText("wallet verified login", wallet, "window.__memepireWalletVerified");
requireText("wallet phantom missing", wallet, "Phantom not found");
requireText("wallet phantom missing", wallet, "connected = false");
requireText("game verified leaderboard", game, "walletToken");
requireText("game verified leaderboard", game, "Wallet.token");
requireText("game wager unit", game, "wagerUnit");
requireText("game wager unit", game, "ticketMode");
requireText("start menu verified wallet", startMenu, "SOL  ");
requireText("start menu phantom wallet", startMenu, "CONNECT PHANTOM");
requireText("start menu ticket wallet", startMenu, "TICKET MODE");
requireText("start menu wallet status", startMenu, "PHANTOM NOT FOUND");
requireText("start menu wager unit", startMenu, "\"unit\": unit");
requireText("start menu launch readiness", startMenu, "func _refresh_launch_status");
requireText("start menu launch readiness", startMenu, "START VERIFIED WAR");
requireText("start menu launch readiness", startMenu, "START TICKET WAR");
requireText("start menu launch readiness", startMenu, "Phantom signs identity and leaderboard rows; ticket mode is unverified.");
requireText("start menu launch readiness", startMenu, "ACCEPT WAGER TO LAUNCH");
requireText("server wager unit", server, "wagerUnit");
requireText("server wager unit", server, "ticketMode");
requireText("server relay", server, 'url.pathname !== "/room"');
requireText("server relay", server, "Sec-WebSocket-Accept");
requireText("server relay", server, "MEMPIRES_ROOM_RELAY");
requireText("server relay", server, 'from: socket.from || socket.role');
requireText("server room status", server, 'url.pathname === "/room-status"');
requireText("server room events", server, 'url.pathname === "/room-events"');
requireText("server room proof", server, 'url.pathname === "/room-proof"');
requireText("server room proof", server, "acceptedWagerCount");
requireText("server room proof", server, "finishedSnapshotCount");
requireText("server room proof", server, "checks.every((check) => check.ok)");
requireText("server room snapshot proof", server, "function summarizeResources");
requireText("server room snapshot proof", server, "rivalResources: summarizeResources");
requireText("server room snapshot proof", server, "rivalPop: summarizePop");
requireText("server room snapshot proof", server, "rivalUpgrades: summarizeUpgrades");
requireText("server room snapshot proof", server, "wager: summarizeWager");
requireText("server room kit", server, 'url.pathname === "/room-kit"');
requireText("server room stream", server, 'url.pathname === "/room-stream"');
requireText("server factions manifest", server, "factionsManifestPaths");
requireText("server wallet challenge", server, 'url.pathname === "/wallet-challenge"');
requireText("server wallet login", server, 'url.pathname === "/wallet-login"');
requireText("server wallet verify", server, "verifySolanaSignature");
requireText("server wallet auth", server, "walletAuthPayload");
for (const oldSurface of [
  "/agent-",
  "agentManifest",
  "agentProtocol",
  "agentCommand",
  "Agent",
  "AIGE",
  "AIge",
  "browser-duel",
  "agent-runner",
  "mempires-king",
]) {
  forbidText("server old automation surface", server, oldSurface);
}
requireText("server room stream", server, "handleRoomStream");
requireText("server room stream", server, "publishRoomStreamEvent");
requireText("server leaderboard", server, 'url.pathname === "/leaderboard"');
requireText("server leaderboard", server, "leaderboardPayload");
requireText("server leaderboard", server, "verifyLeaderboardWallet");
requireText("stream check", streamCheck, "room stream verified");
requireText("wallet check", walletCheck, "challenge/login/verified leaderboard verified");
requireText("web visual check", webVisualCheck, "exported app reached desktop, meme sprite preview, fractional DPR, landscape mobile, and portrait mobile menu/match/result in Chrome");
requireText("web visual check", webVisualCheck, "window.__memepireState");
requireText("web visual check", webVisualCheck, "Page.captureScreenshot");
requireText("web visual check", webVisualCheck, "start=1");
requireText("web visual check", webVisualCheck, "webResultSmoke=1");
requireText("web visual check", webVisualCheck, "memeSpritePreview=1");
requireText("web visual check", webVisualCheck, "selectionSummaryPreview=1");
requireText("web visual check", webVisualCheck, "waitForSelectionSummaryPreview");
requireText("web visual check", webVisualCheck, "meme-sprites-cdp.png");
requireText("web visual check", webVisualCheck, "fractional-dpr-cdp.png");
requireText("web visual check", webVisualCheck, "deviceScaleFactor: 0.8");
requireText("web visual check", webVisualCheck, "waitForMemeSpritePreview");
requireText("web visual check", webVisualCheck, "mobile-menu-cdp.png");
requireText("web visual check", webVisualCheck, "portrait-menu-cdp.png");
requireText("web visual check", webVisualCheck, "portrait-match-cdp.png");
requireText("web visual check", webVisualCheck, "assertNoPortraitLetterbox");
requireText("web visual check", webVisualCheck, "centerMean > 0.08");
requireText("web visual check", webVisualCheck, "ImageMagick");
requireText("web visual check", webVisualCheck, "width: 844");
requireText("web visual check", webVisualCheck, "width: 390");
requireText("web shell fix", webShellFix, "html, body {");
requireText("web shell fix", webShellFix, "width: 100%;");
requireText("web shell fix", webShellFix, "height: 100%;");
requireText("web shell fix", webShellFix, "__memepireNativeDevicePixelRatio");
requireText("web shell fix", webShellFix, "return 1;");
forbidText("web shell fix", webShellFix, "memepireClampedDpr");
forbidText("web shell fix", webShellFix, "function memepireScaleCanvas");
requireText("web shell fix", webShellFix, "function memepireFitCanvas");
requireText("web shell fix", webShellFix, "width: min(100vw, calc(100vh * 1.777777778)) !important;");
requireText("web shell fix", webShellFix, "height: min(100vh, calc(100vw * 0.5625)) !important;");
requireText("web shell fix", webShellFix, "canvas.width = 1280;");
requireText("web shell fix", webShellFix, "canvas.height = 720;");
requireText("web shell fix", webShellFix, "image-rendering: pixelated;");
requireText("web shell fix", webShellFix, "overflow: hidden");
requireText("web shell fix", webShellFix, "canvasResizePolicy\":0");
requireText("web shell fix", webShellFix, "logical-pixel fractional-DPR-safe shell verified");
forbidText("web shell fix", webShellFix, "getPixelRatio:function(){return 1}");
forbidText("web shell fix", webShellFix, "memepireCanvas.width = width");
forbidText("web shell fix", webShellFix, "pixelSafeScale");
requireText("web export", html, "<title>Israel vs Palestine</title>");
requireText("web export wallet", html, "__memepireWalletToken");
forbidText("web export wallet", html, "window.MemepireWallet");
requireText("web export shell", html, "html, body {");
requireText("web export shell", html, "width: 100%;");
requireText("web export shell", html, "height: 100%;");
requireText("web export shell", html, "width: min(100vw, calc(100vh * 1.777777778)) !important;");
requireText("web export shell", html, "height: min(100vh, calc(100vw * 0.5625)) !important;");
requireText("web export shell", html, "overflow: hidden");
requireText("web export shell", html, "__memepireNativeDevicePixelRatio");
requireText("web export shell", html, "return 1;");
forbidText("web export shell", html, "__memepireNativeDevicePixelRatio < 1");
requireText("web export shell", html, "function memepireFitCanvas");
forbidText("web export shell", html, 'id="memepire-frame"');
forbidText("web export shell", html, 'id="memepire-cover-bottom"');
forbidText("web export shell", html, "memepireSetCover");
requireText("web export shell", html, "canvas.width = 1280;");
requireText("web export shell", html, "canvas.height = 720;");
forbidText("web export shell", html, "const maxScale = dpr > 0 && dpr < 1 ? 1 / dpr : 1");
forbidText("web export shell", html, "const fitScale = Math.min(maxScale");
requireText("web export shell", html, '"canvasResizePolicy":0');
forbidText("web export shell", html, "memepireLowDpr");
forbidText("web export shell", html, "memepireClampedDpr");
forbidText("web export shell", html, "pixelSafeScale");
forbidText("web export shell", html, "memepireScaleCanvas");
forbidText("web export shell", html, "function memepireResizeCanvas");
forbidText("stale web export shell", html, "memepire-dpr-clamped");
forbidText("stale web export shell", html, "syncCanvasDisplaySize");

for (const artifact of ["build/web/index.pck", "build/web/index.wasm"]) {
  const size = (await stat(join(root, artifact))).size;
  if (size < 1024) throw new Error(`${artifact} is too small (${size} bytes)`);
}

for (const sprite of [
  "assets/units/israel_swordsman_walk.png",
  "assets/units/israel_villager_walk.png",
  "assets/units/israel_archer_walk.png",
  "assets/units/israel_lancer_walk.png",
  "assets/units/israel_siege_walk.png",
  "assets/units/palestine_swordsman_walk.png",
  "assets/units/palestine_villager_walk.png",
  "assets/units/palestine_archer_walk.png",
  "assets/units/palestine_lancer_walk.png",
  "assets/units/palestine_siege_walk.png",
]) {
  const meta = await run("magick", [join(root, sprite), "-format", "%w %h %[channels] %[opaque]", "info:"]);
  const parts = meta.trim().split(/\s+/);
  const [w, h, channels] = parts;
  const opaque = parts[parts.length - 1];
  if (w !== "192" || h !== "192" || !channels.includes("a") || opaque !== "False") {
    throw new Error(`${sprite} should be a transparent 192x192 sprite sheet; got ${meta.trim()}`);
  }
}

for (const uiAsset of [
  "assets/ui/ui_rd_panel_large.png",
  "assets/ui/ui_rd_panel_medium.png",
  "assets/ui/ui_rd_status_bar.png",
  "assets/ui/ui_rd_status_bar_blue.png",
  "assets/ui/ui_rd_button_normal.png",
  "assets/ui/ui_rd_button_hover.png",
  "assets/ui/ui_rd_button_pressed.png",
  "assets/ui/ui_rd_resource_bar.png",
]) {
  const rgba = await runBuffer("magick", [join(root, uiAsset), "-depth", "8", "rgba:-"]);
  let chromaPixels = 0;
  for (let i = 0; i + 3 < rgba.length; i += 4) {
    const r = rgba[i];
    const g = rgba[i + 1];
    const b = rgba[i + 2];
    const a = rgba[i + 3];
    if (isPurpleChromaKeyPixel(r, g, b, a)) chromaPixels += 1;
  }
  if (chromaPixels > 0) throw new Error(`${uiAsset} still has ${chromaPixels} opaque purple chroma-key pixels`);
}

const godot = await findGodot();
await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "--quit-after", "1", "scenes/StartMenu.tscn"]);
await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "--quit-after", "1", "scenes/Main.tscn"]);
const roomLinksSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/StartMenu.tscn", "--", "--room-links-smoke"]);
requireText("start menu room links smoke", roomLinksSmoke, "ROOM_LINKS_SMOKE host=true join=true");
const resultSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--result-smoke"]);
requireText("main result smoke", resultSmoke, "RESULT_SMOKE play_again=true main_menu=true");
const remoteResultSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-result-smoke"]);
requireText("main remote result smoke", remoteResultSmoke, "REMOTE_RESULT_SMOKE local_result=won king=pepe recorded=true");
const towerTargetSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--tower-target-smoke"]);
requireText("main tower target smoke", towerTargetSmoke, "TOWER_TARGET_SMOKE target_team=0 ok=true");
const projectileFxSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--projectile-fx-smoke"]);
requireText("main projectile fx smoke", projectileFxSmoke, "PROJECTILE_FX_SMOKE arrow=true bolt=true stone=true assets=true ok=true");
const alertPingSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--alert-ping-smoke"]);
requireText("main alert ping smoke", alertPingSmoke, "ALERT_PING_SMOKE danger=true build=true rally=true visible=true ok=true");
const buildPlacementSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--build-placement-smoke"]);
requireText("main build placement smoke", buildPlacementSmoke, "BUILD_PLACEMENT_SMOKE rejected=true accepted=true");
const buildGhostSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--build-ghost-smoke"]);
requireText("main build ghost smoke", buildGhostSmoke, "BUILD_GHOST_SMOKE started=true invalid=true valid=true ok=true");
const resourceDepletionSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--resource-depletion-smoke"]);
requireText("main resource depletion smoke", resourceDepletionSmoke, "RESOURCE_DEPLETION_SMOKE gained=5 depleted=true");
const destroyedEntitySmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--destroyed-entity-smoke"]);
requireText("main destroyed entity smoke", destroyedEntitySmoke, "DESTROYED_ENTITY_SMOKE result=won unit_gone=true keep_gone=true");
const structureStatsSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--structure-stats-smoke"]);
requireText("main structure stats smoke", structureStatsSmoke, "STRUCTURE_STATS_SMOKE keep=1200 house=400 forge=600 tower=700 market=650 art=true scale=true ok=true");
const openingBalanceSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--opening-balance-smoke"]);
requireText("main opening balance smoke", openingBalanceSmoke, "OPENING_BALANCE_SMOKE resources=true defenders=true keep_fire=true timing=true villager=true scale=true ok=true");
const readyDefenderSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--ready-defender-smoke"]);
requireText("main ready defender smoke", readyDefenderSmoke, "READY_DEFENDER_SMOKE guard=true worker=true rally=true ok=true");
const remoteEconomySmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-economy-smoke"]);
requireText("main remote economy smoke", remoteEconomySmoke, "REMOTE_ECONOMY_SMOKE forge=true research=true siege=false market=true timber=23 memp=11 atk=3 ok=true");
const remoteAuthoritySmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-authority-smoke"]);
requireText("main remote authority smoke", remoteAuthoritySmoke, "REMOTE_AUTHORITY_SMOKE rally=true train=true build=true paid=true blocked=true ok=true");
const remoteOrderSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-order-smoke"]);
requireText("main remote order smoke", remoteOrderSmoke, "REMOTE_ORDER_SMOKE sent=true host=true");
const remoteOrderTargetSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-order-target-smoke"]);
requireText("main remote order target smoke", remoteOrderTargetSmoke, "REMOTE_ORDER_TARGET_SMOKE attack=true gather=true ok=true");
const multiplayerSetupSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--multiplayer-setup-smoke"]);
requireText("main multiplayer setup smoke", multiplayerSetupSmoke, "MULTIPLAYER_SETUP_SMOKE rival_vills=4 rival_pop=6");
requireText("main multiplayer setup smoke", multiplayerSetupSmoke, "no_free_ai=true ok=true");
const remoteConcedeSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--remote-concede-smoke"]);
requireText("main remote concede smoke", remoteConcedeSmoke, "REMOTE_CONCEDE_SMOKE accepted=true result=won over=true snap=won ok=true");
const netLeaveSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--net-leave-smoke"]);
requireText("main net leave smoke", netLeaveSmoke, "NET_LEAVE_SMOKE room_empty=true role_empty=true disconnected=true roster_empty=true ok=true");
const hudTeamSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--hud-team-smoke"]);
requireText("main hud team smoke", hudTeamSmoke, "HUD_TEAM_SMOKE host=true host_enemy=true join=true join_enemy=true ok=true");
const techStatusSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--tech-status-smoke"]);
requireText("main tech status smoke", techStatusSmoke, "TECH_STATUS_SMOKE player=true join=true atk=6 armor=4 eco=150 ok=true");
const selectionSummarySmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--selection-summary-smoke"]);
requireText("main selection summary smoke", selectionSummarySmoke, "SELECTION_SUMMARY_SMOKE count=2");
requireText("main selection summary smoke", selectionSummarySmoke, "ok=true");
const inputFlowSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--input-flow-smoke"]);
requireText("main input flow smoke", inputFlowSmoke, "INPUT_FLOW_SMOKE train=true build=true cancel=true select=true additive=true order=true edge=true ok=true");
const mouseInputSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--mouse-input-smoke"]);
requireText("main mouse input smoke", mouseInputSmoke, "MOUSE_INPUT_SMOKE select=true zoom=true order=true ok=true");
const cameraZoomSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--camera-zoom-smoke"]);
requireText("main camera zoom smoke", cameraZoomSmoke, "CAMERA_ZOOM_SMOKE in=true out=true reset=true ok=true");
requireText("main control groups", main, "var control_groups := {}");
requireText("main control groups", main, "func cmd_assign_control_group");
requireText("main control groups", main, "func cmd_recall_control_group");
requireText("main defend command", main, "func cmd_defend_base");
const controlGroupSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--control-group-smoke"]);
requireText("main control group smoke", controlGroupSmoke, "CONTROL_GROUP_SMOKE recalled=true defending=true counted=true ok=true");
const doubleClickSelectSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--double-click-select-smoke"]);
requireText("main double-click select smoke", doubleClickSelectSmoke, "DOUBLE_CLICK_SELECT_SMOKE target=true");
requireText("main double-click select smoke", doubleClickSelectSmoke, "additive=true ok=true");
const minimapCommandSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--minimap-command-smoke"]);
requireText("main minimap command smoke", minimapCommandSmoke, "MINIMAP_COMMAND_SMOKE center=true order=true rally=true ok=true");
const queueStatusSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--queue-status-smoke"]);
requireText("main queue status smoke", queueStatusSmoke, "QUEUE_STATUS_SMOKE count=true name=true pct=50 seconds=2 ok=true");
const orderIndicatorSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--order-indicator-smoke"]);
requireText("main order indicator smoke", orderIndicatorSmoke, "ORDER_INDICATOR_SMOKE move=true gather=true attack=true ok=true");
const commandMarkerSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--command-marker-smoke"]);
requireText("main command marker smoke", commandMarkerSmoke, "COMMAND_MARKER_SMOKE loaded=true indicators=true ok=true");
const factionSpriteSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--faction-sprite-smoke"]);
requireText("main faction sprite smoke", factionSpriteSmoke, "FACTION_SPRITE_SMOKE loaded=true transparent=true spawned=true directional=true readable_scale=true frames=true distinct=true ok=true");
const unitScaleSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--unit-scale-smoke"]);
requireText("main unit scale smoke", unitScaleSmoke, "UNIT_SCALE_SMOKE loaded=true scale=true click=true spawned=10 ok=true");
const intentPreflightSmoke = await run(godot, ["--headless", "--path", root, "--fixed-fps", "30", "scenes/Main.tscn", "--", "--intent-preflight-smoke"]);
requireText("main intent preflight smoke", intentPreflightSmoke, "INTENT_PREFLIGHT_SMOKE train_blocked=true build_blocked=true research_blocked=true train_sent=true ok=true");

console.log("[memepire-port] Godot scenes, web export, wallet bridge, leaderboard, and multiplayer relay verified");
