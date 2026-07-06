## GameState — lightweight autoload singleton.
## Persists data that must survive scene transitions (e.g. the retry seed).
extends Node

## 0 = pick random seed on next game load.
## Any other value = use that specific seed.
var pending_road_seed: int = 0

# Carryover state for transitioning to Silhouette Mode
var is_continuing: bool = false
var carryover_coins: int = 0
var carryover_distance_m: float = 0.0

var fade_layer: CanvasLayer
var fade_rect: ColorRect

func _ready() -> void:
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
