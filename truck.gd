extends Node2D

@export var torque_power := 25000.0
@export var air_tilt_power := 6000.0
@export var max_angular_velocity := 45.0

@onready var chassis: RigidBody2D = $chassis
@onready var container_body: RigidBody2D = $container_body
@onready var tyre_1: RigidBody2D = $"tyre-1"
@onready var tyre_2: RigidBody2D = $"tyre-2"
@onready var tyre_3: RigidBody2D = $"tyre-3"

@onready var park_btn: Button = $HUD/ShifterPanel/VBox/ParkBtn
@onready var rev_btn: Button = $HUD/ShifterPanel/VBox/RevBtn
@onready var drv_btn: Button = $HUD/ShifterPanel/VBox/DrvBtn
@onready var shifter_panel: PanelContainer = $HUD/ShifterPanel

enum Gear { PARK, DRIVE, REVERSE }
var current_gear: Gear = Gear.DRIVE
var is_e_toggled: bool = false

# Parking with "O" hold logic
var o_hold_time: float = 0.0
const O_HOLD_THRESHOLD: float = 1.0
var o_trigger_locked: bool = false
var o_hold_start_ticks: int = 0
var is_o_currently_holding: bool = false

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	setup_shifter_ui()
	if shifter_panel:
		shifter_panel.visible = false
		
	# Instantiate visual parking indicator
	var indicator_script = load("res://parking_indicator.gd")
	if indicator_script:
		var indicator = Node2D.new()
		indicator.set_script(indicator_script)
		indicator.name = "ParkingIndicator"
		indicator.truck = self
		indicator.chassis = chassis
		indicator.container_body = container_body
		add_child(indicator)

func setup_shifter_ui() -> void:
	# Style Shifter Panel (wooden panel backboard)
	var style_panel = StyleBoxFlat.new()
	style_panel.bg_color = Color(0.24, 0.15, 0.10) # Dark mahogany
	style_panel.border_color = Color(0.35, 0.22, 0.12) # Oak trim
	style_panel.border_width_left = 3
	style_panel.border_width_top = 3
	style_panel.border_width_right = 3
	style_panel.border_width_bottom = 3
	style_panel.corner_radius_top_left = 0
	style_panel.corner_radius_top_right = 0
	style_panel.corner_radius_bottom_left = 0
	style_panel.corner_radius_bottom_right = 0
	shifter_panel.add_theme_stylebox_override("panel", style_panel)
	
	# Connect signals for cursor-only click
	park_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.PARK))
	rev_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.REVERSE))
	drv_btn.pressed.connect(_on_gear_button_pressed.bind(Gear.DRIVE))
	
	update_shifter_visuals()

func update_shifter_visuals() -> void:
	# Active Style (glowing, bright pine wood block)
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.65, 0.46, 0.28) # Warm golden pine
	active_style.border_color = Color(0.92, 0.72, 0.05) # Gold highlight
	active_style.border_width_left = 2
	active_style.border_width_top = 2
	active_style.border_width_right = 2
	active_style.border_width_bottom = 6 # 3D look
	active_style.corner_radius_top_left = 0
	active_style.corner_radius_top_right = 0
	active_style.corner_radius_bottom_left = 0
	active_style.corner_radius_bottom_right = 0
	
	# Inactive Style (flat, dark oak wood block)
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.42, 0.28, 0.15) # Dark oak
	inactive_style.border_color = Color(0.25, 0.15, 0.08)
	inactive_style.border_width_left = 2
	inactive_style.border_width_top = 2
	inactive_style.border_width_right = 2
	inactive_style.border_width_bottom = 2
	inactive_style.corner_radius_top_left = 0
	inactive_style.corner_radius_top_right = 0
	inactive_style.corner_radius_bottom_left = 0
	inactive_style.corner_radius_bottom_right = 0
	
	# Apply overrides
	park_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.PARK else inactive_style)
	rev_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.REVERSE else inactive_style)
	drv_btn.add_theme_stylebox_override("normal", active_style if current_gear == Gear.DRIVE else inactive_style)
	
	# Color overrides for active/inactive text
	var active_color = Color(1.0, 0.95, 0.8)
	var inactive_color = Color(0.65, 0.55, 0.45)
	
	park_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.PARK else inactive_color)
	rev_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.REVERSE else inactive_color)
	drv_btn.add_theme_color_override("font_color", active_color if current_gear == Gear.DRIVE else inactive_color)
	
	# Hover style
	var hover_style = active_style.duplicate()
	hover_style.bg_color = Color(0.72, 0.52, 0.32)
	
	park_btn.add_theme_stylebox_override("hover", hover_style)
	rev_btn.add_theme_stylebox_override("hover", hover_style)
	drv_btn.add_theme_stylebox_override("hover", hover_style)
	
	# Font sizes
	park_btn.add_theme_font_size_override("font_size", 22)
	rev_btn.add_theme_font_size_override("font_size", 22)
	drv_btn.add_theme_font_size_override("font_size", 22)

func _physics_process(_delta: float) -> void:
	# Simplified driving mechanics:
	# "D" key (and W, UP, RIGHT) drives forward
	# "A" key (and S, DOWN, LEFT) drives backward
	var forward_pressed = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_RIGHT)
	var backward_pressed = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT)
	
	var move_input = 0.0
	var is_braking = false
	
	if forward_pressed and not backward_pressed:
		if current_gear != Gear.PARK:
			move_input = 1.0
	elif backward_pressed and not forward_pressed:
		if current_gear != Gear.PARK:
			move_input = -1.0
	elif forward_pressed and backward_pressed:
		is_braking = true

	# Long press "O" to park when speed is less than 20 (on speedometer)
	var speed_kmh = chassis.linear_velocity.length() * 0.08 if is_instance_valid(chassis) else 0.0
	var can_park = speed_kmh < 20.0
	
	if can_park:
		if Input.is_key_pressed(KEY_O):
			if not o_trigger_locked:
				if not is_o_currently_holding:
					is_o_currently_holding = true
					o_hold_start_ticks = Time.get_ticks_msec()
				
				var held_duration = (Time.get_ticks_msec() - o_hold_start_ticks) / 1000.0
				o_hold_time = held_duration
				
				if held_duration >= O_HOLD_THRESHOLD:
					if current_gear == Gear.PARK:
						set_gear(Gear.DRIVE)
					else:
						set_gear(Gear.PARK)
					o_trigger_locked = true
					o_hold_time = 0.0
					is_o_currently_holding = false
		else:
			o_hold_time = 0.0
			is_o_currently_holding = false
			o_trigger_locked = false
	else:
		o_hold_time = 0.0
		is_o_currently_holding = false
		o_trigger_locked = false
		
	# Read user input for air tilting (A/D or Left/Right)
	var tilt_input = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		tilt_input -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		tilt_input += 1.0

	# Active braking logic to make controls feel premium and snappy
	var avg_vel = 0.0
	if is_instance_valid(tyre_1) and is_instance_valid(tyre_2) and is_instance_valid(tyre_3):
		avg_vel = (tyre_1.angular_velocity + tyre_2.angular_velocity + tyre_3.angular_velocity) / 3.0
		
	# Quick braking: if moving opposite to input
	if forward_pressed and avg_vel < -5.0:
		is_braking = true
	elif backward_pressed and avg_vel > 5.0:
		is_braking = true
		
	# Mild coasting brake when no movement inputs are pressed
	if not forward_pressed and not backward_pressed:
		if is_instance_valid(tyre_1) and is_instance_valid(tyre_2) and is_instance_valid(tyre_3):
			tyre_1.angular_velocity = lerp(tyre_1.angular_velocity, 0.0, 1.5 * _delta)
			tyre_2.angular_velocity = lerp(tyre_2.angular_velocity, 0.0, 1.5 * _delta)
			tyre_3.angular_velocity = lerp(tyre_3.angular_velocity, 0.0, 1.5 * _delta)
			
	# Apply driving state or parking handbrake
	if current_gear == Gear.PARK:
		tyre_1.lock_rotation = true
		tyre_2.lock_rotation = true
		tyre_3.lock_rotation = true
		tyre_1.angular_velocity = 0.0
		tyre_2.angular_velocity = 0.0
		tyre_3.angular_velocity = 0.0
	else:
		tyre_1.lock_rotation = false
		tyre_2.lock_rotation = false
		tyre_3.lock_rotation = false
		
		# Apply driving torque (only if not actively braking)
		if move_input != 0.0 and not is_braking:
			tyre_1.apply_torque(move_input * torque_power)
			tyre_2.apply_torque(move_input * torque_power)
			tyre_3.apply_torque(move_input * torque_power)
			
		# Apply active braking/friction to quickly halt wheels
		if is_braking:
			tyre_1.angular_velocity = lerp(tyre_1.angular_velocity, 0.0, 12.0 * _delta)
			tyre_2.angular_velocity = lerp(tyre_2.angular_velocity, 0.0, 12.0 * _delta)
			tyre_3.angular_velocity = lerp(tyre_3.angular_velocity, 0.0, 12.0 * _delta)
			
		# Synchronize wheel speeds (locked differential)
		if is_instance_valid(tyre_1) and is_instance_valid(tyre_2) and is_instance_valid(tyre_3):
			var new_avg_vel = (tyre_1.angular_velocity + tyre_2.angular_velocity + tyre_3.angular_velocity) / 3.0
			tyre_1.angular_velocity = new_avg_vel
			tyre_2.angular_velocity = new_avg_vel
			tyre_3.angular_velocity = new_avg_vel
				
			# Cap wheel spin velocity
			tyre_1.angular_velocity = clamp(tyre_1.angular_velocity, -max_angular_velocity, max_angular_velocity)
			tyre_2.angular_velocity = clamp(tyre_2.angular_velocity, -max_angular_velocity, max_angular_velocity)
			tyre_3.angular_velocity = clamp(tyre_3.angular_velocity, -max_angular_velocity, max_angular_velocity)

	# Apply air tilting torque (active in mid-air or balance controls)
	if tilt_input != 0.0:
		chassis.apply_torque(-tilt_input * air_tilt_power)
		container_body.apply_torque(-tilt_input * air_tilt_power * 1.5)

func _input(_event: InputEvent) -> void:
	pass

func _on_gear_button_pressed(gear_type: Gear) -> void:
	set_gear(gear_type)

func set_gear(new_gear: Gear) -> void:
	current_gear = new_gear
	is_e_toggled = (current_gear == Gear.PARK)
	
	if current_gear != Gear.PARK:
		_drop_all_dragging_crates()
	
	update_shifter_visuals()

func _drop_all_dragging_crates() -> void:
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.get("is_dragging"):
			crate.set("is_dragging", false)
			if crate.has_method("_update_physics_state"):
				crate.call("_update_physics_state")
			if crate.has_method("_check_drop_on_container"):
				crate.call("_check_drop_on_container")

func is_any_crate_dragged_near() -> bool:
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.get("is_dragging"):
			var dist = container_body.global_position.distance_to(crate.global_position)
			if dist < 250.0:
				return true
	return false

func is_zoom_requested() -> bool:
	if is_instance_valid(container_body) and container_body.get("backdoor_blocked"):
		return false
	return (current_gear == Gear.PARK) or is_any_crate_dragged_near()


