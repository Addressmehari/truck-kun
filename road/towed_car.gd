extends RigidBody2D
class_name TowedCar

var tyre_back: RigidBody2D
var tyre_front: RigidBody2D

var sports_car_arches: Array[PackedVector2Array] = []
var custom_font: Font

func _ready() -> void:
	# Configure physics properties
	mass = 1.0
	can_sleep = false
	z_index = -1
	collision_layer = 1
	collision_mask = 1
	
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 0.2
	phys_mat.bounce = 0.1
	physics_material_override = phys_mat
	
	# Precalculate wheel arches for drawing
	for arch_x in [35.0, -35.0]:
		var arch_center = Vector2(arch_x, -2.0)
		var arch_radius = 18.0
		var arch_points = PackedVector2Array()
		var arch_steps = 12
		for i in range(arch_steps + 1):
			var angle = PI + (PI * i / arch_steps)
			arch_points.append(arch_center + Vector2(cos(angle), sin(angle)) * arch_radius)
		sports_car_arches.append(arch_points)
		
	# Setup Collision shape
	var col_poly = CollisionPolygon2D.new()
	col_poly.polygon = PackedVector2Array([
		Vector2(-55, -2),
		Vector2(-55, -15),
		Vector2(-30, -28),
		Vector2(20, -28),
		Vector2(45, -14),
		Vector2(55, -14),
		Vector2(55, -2)
	])
	add_child(col_poly)
	
	# Instantiate Tyres
	var tyre_scene = load("res://truck/tyre.tscn")
	if tyre_scene:
		# tyre_back (X = -35)
		tyre_back = tyre_scene.instantiate()
		tyre_back.name = "tyre_back"
		tyre_back.position = Vector2(-35, 10)
		tyre_back.mass = 0.5
		tyre_back.contact_monitor = true
		tyre_back.max_contacts_reported = 2
		# Scale down tyre sprite
		tyre_back.scale = Vector2(0.7, 0.7)
		add_child(tyre_back)
		
		var gj_back = GrooveJoint2D.new()
		gj_back.name = "gj_back"
		gj_back.position = Vector2(-35, 0)
		gj_back.length = 15.0
		gj_back.initial_offset = 8.0
		add_child(gj_back)
		gj_back.node_a = gj_back.get_path_to(self)
		gj_back.node_b = gj_back.get_path_to(tyre_back)
		
		# tyre_front (X = 35)
		tyre_front = tyre_scene.instantiate()
		tyre_front.name = "tyre_front"
		tyre_front.position = Vector2(35, 10)
		tyre_front.mass = 0.5
		tyre_front.contact_monitor = true
		tyre_front.max_contacts_reported = 2
		tyre_front.scale = Vector2(0.7, 0.7)
		add_child(tyre_front)
		
		var gj_front = GrooveJoint2D.new()
		gj_front.name = "gj_front"
		gj_front.position = Vector2(35, 0)
		gj_front.length = 15.0
		gj_front.initial_offset = 8.0
		add_child(gj_front)
		gj_front.node_a = gj_front.get_path_to(self)
		gj_front.node_b = gj_front.get_path_to(tyre_front)
		
	var font_path = "res://retro_font.ttf"
	if ResourceLoader.exists(font_path):
		custom_font = load(font_path)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Drawing a premium broken/rusted sports sedan
	var body_color = Color("#8a5a44") # Rusted orange-brown base
	var dark_trim = Color("#503325") # Darker rust trim
	var glass_color = Color("#223344", 0.8) # Broken dark glass
	
	# 1. Main chassis outline
	var chassis_pts = PackedVector2Array([
		Vector2(-55, -2),
		Vector2(-55, -15),
		Vector2(-30, -28),
		Vector2(20, -28),
		Vector2(45, -14),
		Vector2(55, -14),
		Vector2(55, -2)
	])
	draw_polygon(chassis_pts, PackedColorArray([body_color]))
	draw_polyline(chassis_pts, dark_trim, 2.0)
	
	# 2. Windows
	var window_pts = PackedVector2Array([
		Vector2(-25, -26),
		Vector2(15, -26),
		Vector2(32, -15),
		Vector2(-25, -15)
	])
	draw_polygon(window_pts, PackedColorArray([glass_color]))
	draw_polyline(window_pts, dark_trim, 1.5)
	# Window divider / pillar
	draw_line(Vector2(-3, -26), Vector2(-3, -15), dark_trim, 1.5)
	
	# 3. Draw wheel arches
	for arch in sports_car_arches:
		draw_polyline(arch, dark_trim, 2.5)
		# Draw interior arch shading
		var shadow_pts = arch.duplicate()
		shadow_pts.append(Vector2(arch[arch.size()-1].x, -2))
		shadow_pts.append(Vector2(arch[0].x, -2))
		draw_polygon(shadow_pts, PackedColorArray([Color(0.1, 0.1, 0.1, 0.6)]))
		
	# 4. Rusty details & scratches
	draw_line(Vector2(-48, -10), Vector2(-40, -6), Color("#5c341a"), 1.5)
	draw_line(Vector2(10, -8), Vector2(18, -12), Color("#5c341a"), 1.5)
	draw_line(Vector2(40, -6), Vector2(48, -10), Color("#5c341a"), 1.5)
	
	# 5. Broken headlight (crack effect)
	draw_circle(Vector2(50, -8), 3.0, Color("#ffffaa", 0.5))
	draw_line(Vector2(48, -8), Vector2(52, -8), Color.BLACK, 1.0)
	draw_line(Vector2(50, -10), Vector2(50, -6), Color.BLACK, 1.0)
	
	# 6. Towing hook loop at the front bumper (X = 55, Y = -5)
	draw_circle(Vector2(57, -5), 3.0, Color("#ffd200"))
	draw_circle(Vector2(57, -5), 1.5, Color.BLACK)
	
	# 7. Font overlay "TOW"
	var font_to_use = custom_font if custom_font else ThemeDB.fallback_font
	if font_to_use:
		var txt = "TOW"
		var txt_size = font_to_use.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		draw_string(font_to_use, Vector2(-txt_size.x / 2.0, -34), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color("#ffd200"))
