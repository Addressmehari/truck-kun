extends RigidBody2D
class_name TowedDuck

var custom_font: Font
var landing_dust: CPUParticles2D

# State variables for squash, stretch, and jiggle
var last_linear_velocity := Vector2.ZERO
var was_colliding := false
var squish_timer := 0.0
var current_squish := 0.0
var visual_scale := Vector2(1.0, 1.0)

# Pixel art duck sprite definition (32x24 grid)
# 0: transparent
# 1: Yellow body (#ffd200)
# 2: Darker/shadow yellow (#d9a300)
# 3: Beak orange (#ff6600)
# 4: Black outlines / sunglasses (#1a1c2c)
# 5: White highlight (#ffffff)
# 6: Wing yellow highlight (#ffee55)

const PIXEL_SIZE = 3.0
const SPRITE_OFFSET = Vector2(-48.0, -68.0)

const DUCK_SPRITE = [
	"00000000000000000000000000000000",
	"00000000000000004444400000000000",
	"00000000000000441111144000000000",
	"00000000000044111111111400000000",
	"00000000000411111111111140000000",
	"00000000004111144444441114000000",
	"00000000004111455445544114444000",
	"00000000004111444444444143333400",
	"00000004444111144444441143333340",
	"00000441111111111111111143333400",
	"00004111111111111111111114444000",
	"00041111111111111111111111140000",
	"00411111111111111111111111114000",
	"04111111666661111111111111114000",
	"41111116666666111111111111111400",
	"41111166666666611111111111111400",
	"42111166666666611111111111112400",
	"04211116666666111111111111124000",
	"00422111666661111111111112240000",
	"00042221111111111111111222400000",
	"00004422222222222222222244000000",
	"00000044444444444444444400000000",
	"00000000000000000000000000000000",
	"00000000000000000000000000000000"
]

func _ready() -> void:
	# Configure physics properties
	mass = 0.8
	can_sleep = false
	z_index = -1
	collision_layer = 1
	collision_mask = 1
	
	# Enable contact monitoring for landing detection
	contact_monitor = true
	max_contacts_reported = 4
	
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 0.05
	phys_mat.bounce = 0.05
	physics_material_override = phys_mat
	
	# Setup Collision shape (Duck body is a flat-bottomed slider)
	var col_poly = CollisionPolygon2D.new()
	col_poly.polygon = PackedVector2Array([
		Vector2(-45, -2),
		Vector2(-45, -25),
		Vector2(-25, -45),
		Vector2(10, -45),
		Vector2(15, -55),
		Vector2(38, -55),
		Vector2(45, -35),
		Vector2(45, -2)
	])
	add_child(col_poly)
	
	# Setup landing particle burst
	landing_dust = CPUParticles2D.new()
	landing_dust.name = "LandingDust"
	landing_dust.position = Vector2(0, -2)
	landing_dust.amount = 14
	landing_dust.lifetime = 0.45
	landing_dust.one_shot = true
	landing_dust.emitting = false
	landing_dust.direction = Vector2(0, -1)
	landing_dust.spread = 70.0
	landing_dust.gravity = Vector2(0, 180)
	landing_dust.initial_velocity_min = 45.0
	landing_dust.initial_velocity_max = 95.0
	landing_dust.scale_amount_min = 2.0
	landing_dust.scale_amount_max = 5.0
	
	var dust_ramp = Gradient.new()
	dust_ramp.set_color(0, Color(0.72, 0.65, 0.55, 0.85)) # Muddy dust
	dust_ramp.set_color(1, Color(0.72, 0.65, 0.55, 0.0))
	landing_dust.color_ramp = dust_ramp
	add_child(landing_dust)
	
	var font_path = "res://retro_font.ttf"
	if ResourceLoader.exists(font_path):
		custom_font = load(font_path)

func _physics_process(_delta: float) -> void:
	var colliding = get_colliding_bodies().size() > 0
	
	# Detect landing (vertical impact speed)
	if colliding and not was_colliding:
		var impact_speed = last_linear_velocity.y
		if impact_speed > 130.0:
			# Apply squish based on landing force (slighter)
			current_squish = clamp((impact_speed - 130.0) * 0.0007, 0.0, 0.16)
			squish_timer = 0.25 # faster decay
			
			# Trigger particle burst
			if landing_dust:
				landing_dust.restart()
				landing_dust.emitting = true
				
	was_colliding = colliding
	last_linear_velocity = linear_velocity

func _process(delta: float) -> void:
	var target_scale = Vector2(1.0, 1.0)
	var in_air = not was_colliding
	
	# Apply air stretch (subtler)
	if in_air:
		var speed_y = abs(linear_velocity.y)
		var stretch = clamp(speed_y * 0.0003, 0.0, 0.08)
		target_scale = Vector2(1.0 - stretch * 0.5, 1.0 + stretch)
		
	# Apply landing squash and spring oscillation (faster and slighter)
	if squish_timer > 0.0:
		squish_timer -= delta
		var t = squish_timer / 0.25
		var wave = cos((0.25 - squish_timer) * 32.0)
		var squish_x = current_squish * wave * t
		visual_scale = Vector2(1.0 + squish_x, 1.0 - squish_x)
	else:
		visual_scale = visual_scale.lerp(target_scale, 12.0 * delta)
		
	queue_redraw()

func _draw() -> void:
	# Apply scale transform relative to bottom anchor (0, 0)
	draw_set_transform(Vector2.ZERO, 0.0, visual_scale)
	
	# Colors palette
	var colors = {
		"0": Color(0, 0, 0, 0),
		"1": Color("#ffd200"),
		"2": Color("#d9a300"),
		"3": Color("#ff6600"),
		"4": Color("#1a1c2c"),
		"5": Color("#ffffff"),
		"6": Color("#ffee55")
	}
	
	# Draw pixel art matrix
	for y in range(DUCK_SPRITE.size()):
		var row = DUCK_SPRITE[y]
		for x in range(row.length()):
			var char = row[x]
			if char != "0":
				var draw_pos = SPRITE_OFFSET + Vector2(x * PIXEL_SIZE, y * PIXEL_SIZE)
				draw_rect(Rect2(draw_pos, Vector2(PIXEL_SIZE, PIXEL_SIZE)), colors[char], true)
				
	# Front tow attachment ring (X = 38, Y = -12)
	draw_circle(Vector2(38, -12), 3.0, Color("#ff6600"))
	draw_circle(Vector2(38, -12), 1.5, Color.BLACK)
	
	# Text label "QUACK"
	var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
	if font_to_use:
		var txt = "QUACK"
		var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -72), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color("#ffd200"))
