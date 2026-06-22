extends ParallaxLayer

@export var scroll_speed := Vector2(0.08, 0.0) # Motion scale relative to camera (slower means further away)
@export var auto_drift_speed := 10.0 # Slow constant drift in pixels per second

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	# Configure motion scale for parallax effect
	motion_scale = scroll_speed
	
	# Ignore camera zoom on the parent ParallaxBackground to keep the sky at a stable size
	var parent_bg = get_parent() as ParallaxBackground
	if parent_bg:
		parent_bg.scroll_ignore_camera_zoom = true
	
	_update_bg_layout()
	
	# Handle screen resizing dynamically
	get_viewport().size_changed.connect(_update_bg_layout)

func _update_bg_layout():
	if not is_instance_valid(sprite):
		return
		
	# If texture is missing, load the default sky texture as a dimension fallback
	if not sprite.texture:
		sprite.texture = load("res://skyy.png")
		
	# Align top-left of sprite to (0,0) for simple canvas layout positioning
	sprite.centered = false
	sprite.position = Vector2(0, 0)
	
	# Calculate scale to fit the viewport height perfectly
	var viewport_size = get_viewport_rect().size
	var tex_size = sprite.texture.get_size()
	
	if tex_size.y > 0:
		var scale_y = viewport_size.y / tex_size.y
		# Uniform scale to preserve aspect ratio
		sprite.scale = Vector2(scale_y, scale_y)
		
		# Set mirroring to the scaled width so it repeats infinitely
		var texture_width = tex_size.x * sprite.scale.x
		motion_mirroring = Vector2(texture_width, 0)

func apply_biome_settings(sky_tex: Texture2D, sky_modulate: Color, sky_shader: Shader, sky_shader_params: Dictionary) -> void:
	if not is_inside_tree():
		await ready
		
	if not is_instance_valid(sprite):
		return
		
	# Set texture with fallback
	sprite.texture = sky_tex if sky_tex else load("res://skyy.png")
	sprite.modulate = sky_modulate
	
	# Apply shader if provided
	if sky_shader:
		var mat = ShaderMaterial.new()
		mat.shader = sky_shader
		for param in sky_shader_params:
			mat.set_shader_parameter(param, sky_shader_params[param])
		sprite.material = mat
	else:
		sprite.material = null
		
	_update_bg_layout()

func _process(delta):
	# Apply a continuous slow drift over time (wind effect)
	motion_offset.x -= auto_drift_speed * delta
