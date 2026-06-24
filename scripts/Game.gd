extends Node
## Global state + brand palette for Age of Memepires (Godot port).

# --- Blue pixel identity (ported from the web build's tokens) ---
const COL_INK := Color("06101f")
const COL_PANEL := Color("14233a")
const COL_PANEL_HI := Color("21456e")
const COL_EDGE := Color("030813")
const COL_ACCENT := Color("3d9fe0")
const COL_ACCENT_BRIGHT := Color("7fd6ff")
const COL_BONE := Color("e6f1ff")
const COL_MUTED := Color("9db4d4")
const COL_GRASS := Color("65a844")
const COL_GRASS_DK := Color("4f8a36")
const COL_DIRT := Color("6b4a2a")
const COL_RIVER := Color("21879d")
const COL_ENEMY := Color("9b3a31")

# --- Meme kings ---
const KINGS := {
	"fartcoin": {"name": "$FARTCOIN", "kingdom": "Gas Crown", "color": Color("f0c044")},
	"pepe": {"name": "$PEPE", "kingdom": "Frog Throne", "color": Color("43c865")},
	"doge": {"name": "$DOGE", "kingdom": "Doge Keep", "color": Color("e7a93a")},
	"pnut": {"name": "$PNUT", "kingdom": "Peanut Court", "color": Color("f4f1df")},
}

const COSTS := {
	"villager": {"food": 50},
	"swordsman": {"food": 60, "timber": 20},
	"archer": {"food": 45, "timber": 35},
	"lancer": {"food": 70, "timber": 30},
	"siege": {"food": 90, "timber": 60, "memp": 20},
	"house": {"timber": 75},
	"forge": {"timber": 120, "memp": 30},
	"tower": {"timber": 100},
	"market": {"timber": 90, "memp": 20},
	"upgrade_atk": {"food": 90, "memp": 40},
	"upgrade_armor": {"timber": 90, "memp": 40},
	"upgrade_eco": {"food": 110, "timber": 60},
}

# meme-renamed unit roster (display labels). Internal kinds stay sprite-keyed.
const UNIT_KINDS := ["villager", "swordsman", "archer", "lancer", "siege"]
const UNIT_NAME := {
	"villager": "JEETS",
	"swordsman": "TRENCHER",
	"archer": "DEGENS",
	"lancer": "SOLTARD",
	"siege": "WHALE",
}

var atk_bonus := 0.0
var armor_bonus := 0.0
var eco_bonus := 1.0
var has_forge := false

var player_king := "fartcoin"
var rival_king := "pepe"
var pressure := "standard"   # standard | rush | siege
var wave := 0
var arena := "meadow"

# 16 arenas (data-driven terrain). feature drives the central terrain renderer.
const ARENAS := {
	"meadow":     {"label": "Meadow",     "ground": "65a844", "feature": "none",    "decor": 150},
	"creek":      {"label": "Creek",      "ground": "63a642", "feature": "river",   "decor": 150},
	"garden":     {"label": "Garden",     "ground": "6cb049", "feature": "patches", "decor": 220},
	"ruins":      {"label": "Ruins",      "ground": "5e9a40", "feature": "dirt",    "decor": 120},
	"grove":      {"label": "Grove",      "ground": "5a9a3c", "feature": "forest",  "decor": 260},
	"crossroads": {"label": "Crossroads", "ground": "67a846", "feature": "cross",   "decor": 130},
	"pond":       {"label": "Pond",       "ground": "66ab48", "feature": "pond",    "decor": 160},
	"courtyard":  {"label": "Courtyard",  "ground": "6fae50", "feature": "plaza",   "decor": 110},
	"orchard":    {"label": "Orchard",    "ground": "69ad45", "feature": "forest",  "decor": 210},
	"quarry":     {"label": "Quarry",     "ground": "5c8f3e", "feature": "dirt",    "decor": 100},
	"wildflower": {"label": "Wildflower", "ground": "6cb24d", "feature": "flowers", "decor": 280},
	"millpond":   {"label": "Millpond",   "ground": "64a644", "feature": "pond",    "decor": 170},
	"isle":       {"label": "Isle",       "ground": "67a846", "feature": "pond",    "decor": 150},
	"festival":   {"label": "Festival",   "ground": "6db04e", "feature": "cross",   "decor": 190},
	"causeway":   {"label": "Causeway",   "ground": "61a040", "feature": "river",   "decor": 140},
	"bannerfield":{"label": "Bannerfield","ground": "66ac48", "feature": "patches", "decor": 170},
}
const ARENA_ORDER := ["meadow", "creek", "garden", "ruins", "grove", "crossroads", "pond", "courtyard", "orchard", "quarry", "wildflower", "millpond", "isle", "festival", "causeway", "bannerfield"]

# stable wire indices for snapshot encoding
const KING_ORDER := ["fartcoin", "pepe", "doge", "pnut"]
const STRUCT_TYPES := ["keep", "house", "forge", "tower", "market"]

# multiplayer role (set by the lobby, preserved across reset())
var net_mode := ""   # "" single-player | "host" | "join"
var my_team := 0     # which team this client controls (host=0, joiner=1)

func arena_cfg() -> Dictionary:
	return ARENAS.get(arena, ARENAS["meadow"])

# each meme king's passive edge (thematic), applied to its own units
const KING_BONUS := {
	"fartcoin": {"gather": 1.5, "hp": 1.0, "speed": 1.0, "atk": 1.0},
	"pepe": {"gather": 1.0, "hp": 1.0, "speed": 1.18, "atk": 1.0},
	"doge": {"gather": 1.0, "hp": 1.22, "speed": 1.0, "atk": 1.0},
	"pnut": {"gather": 1.0, "hp": 1.0, "speed": 1.0, "atk": 1.2},
}

func king_bonus(king: String, stat: String) -> float:
	var kb: Dictionary = KING_BONUS.get(king, {})
	return float(kb.get(stat, 1.0))

# --- Economy ---
const START_FOOD := 420
const START_TIMBER := 360
const START_MEMP := 90
const START_POP_CAP := 24

var food := START_FOOD
var timber := START_TIMBER
var memp := START_MEMP
var pop := 0
var pop_cap := START_POP_CAP
var kills := 0

signal resources_changed
signal selection_changed(count: int)
signal logged(text: String)

var log_lines: Array[String] = []
var web_event_count := 0

func log_event(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 40:
		log_lines.pop_front()
	logged.emit(text)
	publish_web_state({"lastLog": text})

func publish_web_state(patch: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var js := "window.__memepireState = Object.assign(window.__memepireState || {}, %s);" % JSON.stringify(patch)
	JavaScriptBridge.eval(js, true)

func web_event(name: String, data := {}) -> void:
	if not OS.has_feature("web"):
		return
	web_event_count += 1
	var payload := {
		"eventId": web_event_count,
		"event": name,
		"data": data,
	}
	var js := "window.__memepireEvents = window.__memepireEvents || []; window.__memepireEvents.push(%s); window.__memepireEvents = window.__memepireEvents.slice(-80);" % JSON.stringify(payload)
	JavaScriptBridge.eval(js, true)

var wager_stake := 250
const WAGER_TAX := 0.05
var board := {}   # king -> {wins, losses}
var suppress_result_persistence := false

func _ready() -> void:
	_load_board()

func wager_tax() -> int:
	return int(round(wager_stake * WAGER_TAX))

func wager_net() -> int:
	return maxi(0, wager_stake - wager_tax())

func wager_payout(won := true) -> int:
	return int(round(float(wager_net()) * (1.9 if won else 0.0)))

func cost_text(kind: String) -> String:
	var c: Dictionary = COSTS.get(kind, {})
	var parts: Array[String] = []
	if int(c.get("food", 0)) > 0:
		parts.append("%dF" % int(c["food"]))
	if int(c.get("timber", 0)) > 0:
		parts.append("%dT" % int(c["timber"]))
	if int(c.get("memp", 0)) > 0:
		parts.append("%dM" % int(c["memp"]))
	return " ".join(parts)

func _load_board() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load("user://board.cfg") == OK
	for k in KINGS.keys():
		if ok:
			board[k] = {"wins": int(cfg.get_value("wins", k, 0)), "losses": int(cfg.get_value("losses", k, 0))}
		else:
			board[k] = {"wins": 0, "losses": 0}

func record_result(king: String, won: bool, meta := {}) -> void:
	if not board.has(king):
		board[king] = {"wins": 0, "losses": 0}
	if won:
		board[king]["wins"] += 1
	else:
		board[king]["losses"] += 1
	var cfg := ConfigFile.new()
	for k in board:
		cfg.set_value("wins", k, board[k]["wins"])
		cfg.set_value("losses", k, board[k]["losses"])
	if not suppress_result_persistence:
		cfg.save("user://board.cfg")
	_post_web_result(king, won, meta)

func _post_web_result(king: String, won: bool, meta: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var seconds := int(meta.get("seconds", 0))
	var payout := wager_payout(won)
	var entry := {
		"id": "%s-%d" % [king, Time.get_unix_time_from_system()],
		"kingId": king,
		"king": String(KINGS.get(king, {}).get("name", king)),
		"rivalId": String(meta.get("rivalId", rival_king)),
		"rival": String(KINGS.get(String(meta.get("rivalId", rival_king)), {}).get("name", String(meta.get("rivalId", rival_king)))),
		"result": "won" if won else "lost",
		"wave": int(meta.get("wave", wave)),
		"kills": int(meta.get("kills", kills)),
		"seconds": seconds,
		"time": "%02d:%02d" % [seconds / 60, seconds % 60],
		"arena": String(meta.get("arena", arena)),
		"pressure": String(meta.get("pressure", pressure)),
		"stake": wager_stake,
		"tax": wager_tax(),
		"payout": payout,
		"wallet": Wallet.address if Wallet.connected else "",
		"walletLabel": Wallet.short() if Wallet.verified else "Ticket mode",
		"verified": Wallet.verified,
	}
	var wallet_token := Wallet.token if Wallet.connected else ""
	var js := """
fetch('/leaderboard', {
  method: 'POST',
  headers: {'content-type':'application/json'},
  body: JSON.stringify({entry: %s, walletToken: %s})
}).then(function(r){ return r.json(); }).then(function(data){
  window.__memepireLeaderboard = data;
  window.__memepireState = Object.assign(window.__memepireState || {}, {leaderboardPosted: true, leaderboardScore: data.submitted && data.submitted.score});
}).catch(function(err){
  window.__memepireState = Object.assign(window.__memepireState || {}, {leaderboardPosted: false, leaderboardError: String(err && err.message || err)});
});
""" % [JSON.stringify(entry), JSON.stringify(wallet_token)]
	JavaScriptBridge.eval(js, true)

func reset() -> void:
	food = START_FOOD
	timber = START_TIMBER
	memp = START_MEMP
	pop = 0
	pop_cap = START_POP_CAP
	kills = 0
	wave = 0
	atk_bonus = 0.0
	armor_bonus = 0.0
	eco_bonus = 1.0
	has_forge = false
	log_lines.clear()

func can_afford(kind: String) -> bool:
	var c: Dictionary = COSTS.get(kind, {})
	return food >= int(c.get("food", 0)) and timber >= int(c.get("timber", 0)) and memp >= int(c.get("memp", 0))

func pay(kind: String) -> bool:
	if not can_afford(kind):
		return false
	var c: Dictionary = COSTS.get(kind, {})
	food -= int(c.get("food", 0))
	timber -= int(c.get("timber", 0))
	memp -= int(c.get("memp", 0))
	resources_changed.emit()
	return true

func add_food(n: int) -> void:
	food += n
	resources_changed.emit()

func add_timber(n: int) -> void:
	timber += n
	resources_changed.emit()

func unit_sheet(king: String, kind: String) -> String:
	if kind == "siege":
		if king == "doge":
			return "res://assets/units/doge_siege_walk.png"
		return "res://assets/units/breaker_walk.png"  # generic siege engine
	return "res://assets/units/%s_%s_walk.png" % [king, kind]
