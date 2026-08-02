extends CanvasLayer

var _title_label: Label
var _prompt_label: Label
var _elapsed: float = 0.0
var _can_input: bool = false

func _ready() -> void:
	layer = 128
	visible = false

	# Root control
	var root = Control.new()
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# VBox container for center-aligned text
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_left   = 0.5
	vbox.anchor_top    = 0.5
	vbox.anchor_right  = 0.5
	vbox.anchor_bottom = 0.5
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	vbox.offset_left   = -400.0
	vbox.offset_top    = -100.0
	vbox.offset_right  =  400.0
	vbox.offset_bottom =  100.0
	vbox.add_theme_constant_override("separation", 20)
	root.add_child(vbox)

	# 1. Large white text "JOURNEY COMPLETED"
	_title_label = Label.new()
	_title_label.text = "JOURNEY COMPLETED"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 56)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_title_label.add_theme_constant_override("outline_size", 10)
	_title_label.modulate.a = 0.0 # start invisible to fade in slowly
	vbox.add_child(_title_label)

	# 2. Pulsing subtext "PRESS ANY KEY TO RE-RUN"
	_prompt_label = Label.new()
	_prompt_label.text = "PRESS ANY KEY TO RE-RUN"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.modulate.a = 0.0 # start invisible
	vbox.add_child(_prompt_label)

	set_process(true)

func show_completed() -> void:
	visible = true
	# Fade in the title text slowly over 2 seconds
	var tween = create_tween()
	tween.tween_property(_title_label, "modulate:a", 1.0, 2.0)
	tween.tween_callback(func(): _can_input = true)
	if get_node_or_null("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("victory")

func _process(delta: float) -> void:
	if not visible:
		return
		
	_elapsed += delta
	
	# Only start pulsing the prompt once input is active/allowed
	if _can_input:
		# Pulsing effect: modulate alpha between 0.3 and 1.0 using a sine wave
		var pulse = 0.65 + sin(_elapsed * 4.5) * 0.35
		_prompt_label.modulate.a = pulse

func _input(event: InputEvent) -> void:
	if not visible or not _can_input:
		return
		
	# Trigger reload on any keypress or mouse button click
	var is_trigger = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if is_trigger:
		_trigger_retry()

func _trigger_retry() -> void:
	_can_input = false
	visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.pending_road_seed = randi()
		gs.is_continuing = false
		gs.carryover_coins = 0
		gs.carryover_distance_m = 0.0
		gs.transition_to_scene("res://main.tscn")
	else:
		get_tree().change_scene_to_file("res://main.tscn")
