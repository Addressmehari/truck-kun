## GameState — lightweight autoload singleton.
## Persists data that must survive scene transitions (e.g. the retry seed).
extends Node

## 0 = pick random seed on next game load.
## Any other value = use that specific seed.
var pending_road_seed: int = 0

# Carryover state for transitioning to Silhouette Mode
var is_continuing: bool = false
var is_biome_transition: bool = false
var carryover_coins: int = 0
var carryover_distance_m: float = 0.0

var total_coins: int = 0
var total_gems: int = 0
var best_distance: float = 0.0
var music_enabled: bool = true
var sfx_enabled: bool = true
const SAVE_PATH: String = "user://highscore.cfg"

var fade_layer: CanvasLayer
var fade_rect: ColorRect

func _ready() -> void:
	load_coins()
	
	# Create a CanvasLayer for transition overlay (high layer index to draw on top of HUD)
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 128
	add_child(fade_layer)

	# Full-screen ColorRect
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0) # start transparent
	fade_rect.anchor_left = 0.0
	fade_rect.anchor_top = 0.0
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	fade_rect.offset_left = 0
	fade_rect.offset_top = 0
	fade_rect.offset_right = 0
	fade_rect.offset_bottom = 0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)

func load_coins() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		total_coins = config.get_value("progression", "total_coins", 0)
		total_gems = config.get_value("progression", "total_gems", 0)
		best_distance = config.get_value("progression", "best_distance", 0.0)
		music_enabled = config.get_value("settings", "music_enabled", true)
		sfx_enabled = config.get_value("settings", "sfx_enabled", true)
	else:
		total_coins = 0
		total_gems = 0
		best_distance = 0.0
		music_enabled = true
		sfx_enabled = true

func save_coins() -> void:
	var config = ConfigFile.new()
	# Load existing file first to avoid overwriting other keys (e.g. best_distance)
	var _err = config.load(SAVE_PATH)
	config.set_value("progression", "total_coins", total_coins)
	config.set_value("progression", "total_gems", total_gems)
	config.set_value("settings", "music_enabled", music_enabled)
	config.set_value("settings", "sfx_enabled", sfx_enabled)
	config.save(SAVE_PATH)

func add_to_total_coins(amount: int) -> void:
	total_coins += amount
	save_coins()

func add_to_total_gems(amount: int) -> void:
	total_gems += amount
	save_coins()
func reset_progress() -> void:
	total_coins = 0
	total_gems = 0
	best_distance = 0.0
	
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("highscore.cfg"):
		dir.remove("highscore.cfg")
		
	var config = ConfigFile.new()
	config.set_value("progression", "total_coins", 0)
	config.set_value("progression", "total_gems", 0)
	config.set_value("progression", "best_distance", 0.0)
	config.save(SAVE_PATH)

## Performs a smooth video-like fade-to-black scene transition
func transition_to_scene(target_scene_path: String) -> void:
	# Block interaction during transition
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var tween = create_tween()
	# Smoothly fade to black
	tween.tween_property(fade_rect, "color:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target_scene_path)
	)
	# Wait brief duration for layout initialization in new scene
	tween.tween_interval(0.15)
	# Smoothly fade back to transparent
	tween.tween_callback(func():
		var tween_in = create_tween()
		tween_in.tween_property(fade_rect, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween_in.tween_callback(func():
			# Restore interaction
			fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		)
	)
