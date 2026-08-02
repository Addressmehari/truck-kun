extends Node

# Preload synthesized audio resources
var streams: Dictionary = {
	"theme": preload("res://audio/music_theme.wav"),
	"click": preload("res://audio/sfx_click.wav"),
	"coin": preload("res://audio/sfx_coin.wav"),
	"jump": preload("res://audio/sfx_jump.wav"),
	"crash": preload("res://audio/sfx_crash.wav"),
	"glass": preload("res://audio/sfx_glass.wav"),
	"victory": preload("res://audio/sfx_victory.wav"),
	"horn": preload("res://audio/sfx_horn.wav"),
	"engine": preload("res://audio/sfx_engine.wav")
}

var music_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var pool_size := 8

# Engine target volume & state
var engine_volume_db := -80.0
var target_engine_pitch := 1.0

# Sound cooldown timers
var last_play_times: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep playing even if game is paused!
	
	# 1. Setup BGM Player
	music_player = AudioStreamPlayer.new()
	var theme_stream = streams["theme"]
	if theme_stream is AudioStreamWAV:
		theme_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		theme_stream.loop_begin = 0
		theme_stream.loop_end = int(theme_stream.get_length() * theme_stream.mix_rate)
	music_player.stream = theme_stream
	music_player.volume_db = -15.0
	add_child(music_player)
	
	# 2. Setup Engine Player
	engine_player = AudioStreamPlayer.new()
	var engine_stream = streams["engine"]
	if engine_stream is AudioStreamWAV:
		engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		engine_stream.loop_begin = 0
		engine_stream.loop_end = int(engine_stream.get_length() * engine_stream.mix_rate)
	engine_player.stream = engine_stream
	engine_player.volume_db = -80.0
	add_child(engine_player)
	
	# 3. Setup SFX Player Pool
	for i in range(pool_size):
		var p = AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		sfx_pool.append(p)
		
	# 4. Automatically connect button click sounds
	get_tree().node_added.connect(_on_node_added)
	_register_buttons_recursive(get_tree().root)

func _process(delta: float) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		# Sync music player volume/playback
		var target_music_vol = -15.0 if gs.music_enabled else -80.0
		if music_player.volume_db != target_music_vol:
			music_player.volume_db = target_music_vol
			
		# If music enabled but not playing, start it
		if gs.music_enabled and not music_player.playing:
			music_player.play()
		elif not gs.music_enabled and music_player.playing:
			# Keep playing but muted so it doesn't restart when toggled on
			pass
			
		# Sync engine player volume
		if engine_player.playing:
			var target_engine_vol = engine_volume_db if gs.sfx_enabled else -80.0
			# Smooth volume interpolation
			engine_player.volume_db = lerp(engine_player.volume_db, target_engine_vol, 15.0 * delta)
			# Smooth pitch interpolation
			engine_player.pitch_scale = lerp(engine_player.pitch_scale, target_engine_pitch, 10.0 * delta)

func play_music(music_name: String) -> void:
	if not streams.has(music_name):
		return
	if music_player.stream != streams[music_name]:
		music_player.stream = streams[music_name]
		var stream = music_player.stream
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	
	var gs = get_node_or_null("/root/GameState")
	if gs and not gs.music_enabled:
		music_player.volume_db = -80.0
	else:
		music_player.volume_db = -15.0
		
	if not music_player.playing:
		music_player.play()

func play_sfx(sfx_name: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs and not gs.sfx_enabled:
		return
		
	if not streams.has(sfx_name):
		return
		
	# Cooldown to prevent noisy sound cluttering
	var now = Time.get_ticks_msec()
	if sfx_name == "crash":
		if last_play_times.has("crash") and now - last_play_times["crash"] < 400:
			return
		last_play_times["crash"] = now
	elif sfx_name == "coin":
		if last_play_times.has("coin") and now - last_play_times["coin"] < 60:
			return
		last_play_times["coin"] = now
	elif sfx_name == "click":
		if last_play_times.has("click") and now - last_play_times["click"] < 80:
			return
		last_play_times["click"] = now
		
	# Find first available player in pool
	for p in sfx_pool:
		if not p.playing:
			p.stream = streams[sfx_name]
			p.pitch_scale = randf_range(0.95, 1.05) # slight pitch variation for organic feel!
			p.play()
			return
			
	# If pool is full, override the first player
	var oldest = sfx_pool[0]
	oldest.stream = streams[sfx_name]
	oldest.pitch_scale = randf_range(0.95, 1.05)
	oldest.play()

func start_engine() -> void:
	var gs = get_node_or_null("/root/GameState")
	engine_volume_db = -24.0
	target_engine_pitch = 1.0
	engine_player.pitch_scale = 1.0
	engine_player.volume_db = engine_volume_db if (gs and gs.sfx_enabled) else -80.0
	if not engine_player.playing:
		engine_player.play()

func stop_engine() -> void:
	engine_player.stop()

func update_engine(speed_kmh: float, throttle: float) -> void:
	# Pitch scales from 0.8x (idle) to 2.2x (max speed)
	target_engine_pitch = 0.8 + clamp(speed_kmh / 80.0, 0.0, 1.4)
	
	# Engine volume increases slightly with throttle
	var base_vol = -24.0
	if throttle > 0.1:
		base_vol += 4.0
	engine_volume_db = base_vol

func _on_node_added(node: Node) -> void:
	if node is Button:
		_register_button(node)

func _register_buttons_recursive(node: Node) -> void:
	if node is Button:
		_register_button(node)
	for child in node.get_children():
		_register_buttons_recursive(child)

func _register_button(btn: Button) -> void:
	if not btn.pressed.is_connected(_on_button_pressed):
		btn.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play_sfx("click")
