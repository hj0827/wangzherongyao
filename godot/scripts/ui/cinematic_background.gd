extends Control
## 电影感动态背景
## 层次（由远到近）：原画缓推 → 冷/暖辉光 → 三层流动雾气 → 上升火星 → 暗角。
## 每一层带独立的鼠标视差系数，移动指针时层次会产生前后位移，画面不再是“一张死图”。

const KEY_ART := preload("res://assets/ui/key_art.png")

## 动态背景优先播放视频；找不到视频时回落到原画的程序化推拉（保证任何环境都有画面）
const VIDEO_CANDIDATES := [
	"res://assets/ui/menu_bg.ogv",
	"res://assets/ui/background.ogv",
	"res://assets/ui/bg_loop.ogv",
]

## 雾层参数：from/to 是纵向锚点，amp 是漂移幅度，depth 是视差系数
const FOG_SPECS := [
	{
		"from": 0.38, "to": 0.80, "alpha": 0.055, "speed": 0.09, "amp": 36.0,
		"depth": 8.0, "seed": 11, "tint": Color(0.60, 0.75, 0.88), "scale": 1.22,
	},
	{
		"from": 0.50, "to": 0.98, "alpha": 0.08, "speed": 0.145, "amp": 54.0,
		"depth": 17.0, "seed": 27, "tint": Color(0.72, 0.82, 0.90), "scale": 1.30,
	},
	{
		"from": 0.66, "to": 1.10, "alpha": 0.105, "speed": 0.22, "amp": 78.0,
		"depth": 27.0, "seed": 43, "tint": Color(0.84, 0.87, 0.92), "scale": 1.40,
	},
]

var _art: TextureRect
var _video: VideoStreamPlayer
var _video_ready := false
var _warm_glow: TextureRect
var _cool_glow: TextureRect
var _title_glow: TextureRect
var _contact_shadow: TextureRect
var _vignette: TextureRect
var _embers: CPUParticles2D
var _fog_nodes: Array[TextureRect] = []

var _time := 0.0
var _last_size := Vector2(-1, -1)
var _pointer := Vector2.ZERO
var _pointer_target := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_relayout)
	_relayout()

## 进对局时整个 UI 层会被隐藏：这时停掉视频解码和逐帧动画，别让背景偷偷吃 CPU
func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED:
		return
	var shown := is_visible_in_tree()
	set_process(shown)
	if _video != null and _video_ready:
		_video.paused = not shown

func _process(delta: float) -> void:
	_time += delta
	if size != _last_size:
		_relayout()

	# 指针视差：整体跟着指针反向轻移，越靠前的层动得越多
	if size.x > 1.0 and size.y > 1.0:
		var mp: Vector2 = get_viewport().get_mouse_position() - global_position
		var centered := (mp / size - Vector2(0.5, 0.5)) * 2.0
		_pointer_target = centered.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	_pointer = _pointer.lerp(_pointer_target, clampf(delta * 2.0, 0.0, 1.0))

	var breathe := 0.5 - 0.5 * cos(_time * 0.62)          # 约 10 秒一次的呼吸
	var push := 0.5 - 0.5 * cos(_time * 0.085)           # 约 74 秒一次的缓推

	# 远景原画：极缓推拉 + 轻微上浮（有视频时由视频接管，只留作加载期的底图）
	if _art != null:
		var zoom := 1.045 + 0.05 * push
		_art.scale = Vector2(zoom, zoom)
		_art.position = _pointer * -8.0 + Vector2(0.0, -7.0 * push - 3.0 * breathe)

	# 视频底图：比屏幕略大一圈，留出视差位移的余量，避免露边
	if _video_ready and _video != null:
		if _video.is_playing() and _art != null and _art.visible:
			_art.visible = false
		_video.pivot_offset = size * 0.5
		var video_zoom := 1.03 + 0.015 * push
		_video.scale = Vector2(video_zoom, video_zoom)
		_video.position = _pointer * -6.0

	# 地平线暖光：呼吸式明灭，太阳的位置在“活着”
	if _warm_glow != null:
		_warm_glow.modulate.a = 0.55 + 0.45 * breathe
		_warm_glow.scale = Vector2.ONE * (1.0 + 0.035 * breathe)
		_warm_glow.position = _pointer * -4.0

	# 冷色辅光：与暖光错相位，让画面始终有冷暖对撞
	if _cool_glow != null:
		_cool_glow.modulate.a = 0.42 + 0.3 * (1.0 - breathe)
		_cool_glow.position = _pointer * -6.0

	# 标题背光：缓慢游移，把左侧文字从暗部里托起来
	if _title_glow != null:
		_title_glow.modulate.a = 0.6 + 0.4 * breathe
		_title_glow.position = _pointer * -5.0 + Vector2(sin(_time * 0.23) * 14.0, cos(_time * 0.19) * 7.0)

	# 三层雾气：速度、幅度、视差都不相同 —— 空气透视的来源
	for index in _fog_nodes.size():
		var fog: TextureRect = _fog_nodes[index]
		var spec: Dictionary = FOG_SPECS[index]
		var phase: float = float(index) * 1.7
		var amp: float = float(spec.amp)
		var drift := sin(_time * float(spec.speed) + phase) * amp
		var bob := sin(_time * float(spec.speed) * 0.63 + phase * 2.0) * 6.0
		fog.position = Vector2(drift, bob) + _pointer * -float(spec.depth)

	# 火星整体随风摆动
	if _embers != null:
		_embers.position = Vector2(size.x * 0.5, size.y * 0.82) + _pointer * -12.0

	# 暗角极缓慢呼吸，画面像有景深边缘在轻微伸缩
	if _vignette != null:
		_vignette.modulate.a = 0.88 + 0.12 * sin(_time * 0.31)

func _build() -> void:
	_video = VideoStreamPlayer.new()
	_video.name = "VideoBG"
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.visible = false
	add_child(_video)
	var video_path := _first_video()
	if not video_path.is_empty():
		var stream := load(video_path)
		if stream is VideoStream:
			_video.stream = stream
			_video.visible = true
			_video.play()
			_video_ready = true
			print("[background] video: ", video_path)
		else:
			push_warning("[background] 视频无法加载：%s" % video_path)
	else:
		print("[background] 未找到背景视频，使用原画动态推拉")

	_art = TextureRect.new()
	_art.name = "KeyArt"
	_art.texture = KEY_ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill(_art)
	add_child(_art)

	_cool_glow = _glow("CoolGlow", [
		[0.0, Color(0.42, 0.66, 1.0, 0.30)],
		[0.45, Color(0.24, 0.44, 0.85, 0.13)],
		[1.0, Color(0.10, 0.20, 0.45, 0.0)],
	], Vector2(0.12, 0.72), Vector2(1.05, 0.72))
	add_child(_cool_glow)

	_warm_glow = _glow("WarmGlow", [
		[0.0, Color(1.0, 0.82, 0.44, 0.62)],
		[0.28, Color(1.0, 0.62, 0.26, 0.30)],
		[0.62, Color(0.85, 0.36, 0.14, 0.10)],
		[1.0, Color(0.55, 0.18, 0.08, 0.0)],
	], Vector2(0.54, 0.28), Vector2(1.42, 0.28))
	add_child(_warm_glow)

	_title_glow = _glow("TitleGlow", [
		[0.0, Color(1.0, 0.84, 0.5, 0.34)],
		[0.42, Color(1.0, 0.66, 0.3, 0.13)],
		[1.0, Color(0.9, 0.5, 0.2, 0.0)],
	], Vector2(0.22, 0.20), Vector2(0.92, 0.20))
	add_child(_title_glow)

	for index in FOG_SPECS.size():
		var spec: Dictionary = FOG_SPECS[index]
		var fog := TextureRect.new()
		fog.name = "Fog%d" % index
		fog.texture = _fog_texture(int(spec.seed))
		fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fog.stretch_mode = TextureRect.STRETCH_SCALE
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog.anchor_left = 0.0
		fog.anchor_right = 1.0
		fog.anchor_top = float(spec.from)
		fog.anchor_bottom = float(spec.to)
		fog.offset_left = 0.0
		fog.offset_right = 0.0
		fog.offset_top = 0.0
		fog.offset_bottom = 0.0
		fog.scale = Vector2(float(spec.scale), 1.0)
		var tint: Color = spec.tint
		fog.modulate = Color(tint.r, tint.g, tint.b, float(spec.alpha))
		add_child(fog)
		_fog_nodes.append(fog)

	_embers = _make_embers()
	add_child(_embers)

	# 底部与左侧压暗，保证文字可读，同时把视线收进画面中心
	_contact_shadow = _gradient_rect("BottomShade", [
		[0.0, Color(0.004, 0.010, 0.016, 0.0)],
		[0.55, Color(0.004, 0.010, 0.016, 0.30)],
		[1.0, Color(0.002, 0.006, 0.010, 0.88)],
	], false)
	_contact_shadow.anchor_top = 0.55
	_contact_shadow.anchor_bottom = 1.0
	add_child(_contact_shadow)

	var left_shade := _gradient_rect("LeftShade", [
		[0.0, Color(0.005, 0.011, 0.017, 0.96)],
		[0.26, Color(0.005, 0.011, 0.017, 0.80)],
		[0.48, Color(0.005, 0.011, 0.017, 0.44)],
		[0.70, Color(0.005, 0.011, 0.017, 0.14)],
		[1.0, Color(0.005, 0.011, 0.017, 0.0)],
	], true)
	add_child(left_shade)

	_vignette = _glow("Vignette", [
		[0.0, Color(0.0, 0.0, 0.0, 0.0)],
		[0.52, Color(0.0, 0.0, 0.0, 0.0)],
		[0.78, Color(0.0, 0.0, 0.0, 0.26)],
		[1.0, Color(0.0, 0.0, 0.0, 0.86)],
	], Vector2(0.5, 0.5), Vector2(1.02, 0.5))
	add_child(_vignette)

func _relayout() -> void:
	_last_size = size
	if _art != null:
		_art.pivot_offset = size * 0.5
	for fog in _fog_nodes:
		fog.pivot_offset = fog.size * 0.5
	if _warm_glow != null:
		_warm_glow.pivot_offset = size * 0.5
	if _cool_glow != null:
		_cool_glow.pivot_offset = size * 0.5
	if _embers != null:
		_embers.emission_rect_extents = Vector2(size.x * 0.55, size.y * 0.16)

func _fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _first_video() -> String:
	for path in VIDEO_CANDIDATES:
		if FileAccess.file_exists(String(path)):
			return String(path)
	return ""

func _gradient_rect(node_name: String, stops: Array, horizontal: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1] as Color)
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256 if horizontal else 1
	texture.height = 1 if horizontal else 256
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fill(rect)
	return rect

func _glow(node_name: String, stops: Array, from: Vector2, to: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1] as Color)
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 288
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = from
	texture.fill_to = to
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fill(rect)
	return rect

## 程序化生成一层雾：分形噪声 + 上下柔化，边缘自然消失，横向拉伸铺满即可
func _fog_texture(seed_value: int) -> ImageTexture:
	var width := 192
	var height := 120
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var v := float(y) / float(height - 1)
		var envelope := smoothstep(0.0, 0.32, v) * (1.0 - smoothstep(0.58, 1.0, v))
		for x in width:
			var value := noise.get_noise_2d(float(x) * 1.6, float(y) * 2.4)
			var alpha := clampf((value + 0.28) * 1.7, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha * envelope))
	return ImageTexture.create_from_image(image)

func _make_embers() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = "Embers"
	particles.amount = 34
	particles.lifetime = 11.0
	particles.preprocess = 8.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(800.0, 150.0)
	particles.position = Vector2(800.0, 740.0)
	particles.direction = Vector2(0, -1)
	particles.spread = 26.0
	particles.gravity = Vector2(0, -2.6)
	particles.initial_velocity_min = 10.0
	particles.initial_velocity_max = 34.0
	particles.angular_velocity_min = -18.0
	particles.angular_velocity_max = 18.0
	particles.scale_amount_min = 0.35
	particles.scale_amount_max = 1.15
	particles.texture = _ember_texture()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.16, 0.62, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.78, 0.42, 0.0),
		Color(1.0, 0.74, 0.36, 1.0),
		Color(1.0, 0.48, 0.16, 0.62),
		Color(0.85, 0.24, 0.06, 0.0),
	])
	particles.color_ramp = ramp
	return particles

func _ember_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.34, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.82, 1.0),
		Color(1.0, 0.66, 0.30, 0.55),
		Color(1.0, 0.36, 0.10, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
