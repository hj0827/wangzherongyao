extends Node3D
class_name ChannelFx

# 回城 / 传送的「引导中」视觉：地面法阵 + 光柱 + 上升粒子。
#
# 外观由进度驱动，不是单纯循环播放 —— 玩家要能靠眼睛读出「读了多少」：
#   法阵随进度收拢（力量被抽走）、旋转加速、光柱升高、粒子变密。
# 完成与打断的瞬时爆发不在这里判断原因，由 Arena 收到事件后调用 burst / shatter。
#
# 生命周期：Arena 每帧调 set_channel()，状态机结束时调 release()，
# 本节点自己把淡出跑完再隐藏，避免法阵「啪」地消失。

const COLOR_RECALL := Color(1.0, 0.66, 0.14)
const COLOR_TELEPORT := Color(0.26, 0.8, 1.0)

const RING_INNER := 0.86
const RING_OUTER := 1.0
const BEAM_BASE_RADIUS := 1.05
const PARTICLE_TIERS: Array[int] = [16, 34, 52]
# 圆环是各向同性的，单靠它转起来根本看不出来。绕圈排布的符条才是「法阵在转」的视觉证据。
const RUNE_COUNT := 6

var _active := false
var _kind := ""
var _progress := 0.0
var _fade := 0.0
var _spin := 0.0
var _pulse := 0.0
var _color := COLOR_RECALL
var _particle_tier := -1

var _glow: MeshInstance3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _runes: Node3D
var _beam: MeshInstance3D
var _particles: GPUParticles3D
var _glow_material: StandardMaterial3D
var _outer_material: StandardMaterial3D
var _inner_material: StandardMaterial3D
var _rune_material: StandardMaterial3D
var _beam_material: StandardMaterial3D

# ---------------- 进度 → 外观（纯函数，测试直接钉这些） ----------------

static func progress_clamped(value: float) -> float:
	return clampf(value, 0.0, 1.0)

static func color_for(kind: String) -> Color:
	return COLOR_TELEPORT if kind == "teleport" else COLOR_RECALL

# 弧度/秒。传送比回城更急促，进度越满转得越快。
static func spin_speed(kind: String, progress: float) -> float:
	var p := progress_clamped(progress)
	if kind == "teleport":
		return 3.4 + 6.2 * p
	return 1.7 + 3.4 * p

# 法阵半径：随进度收拢，视觉上就是「读条」。
static func ring_radius(kind: String, progress: float) -> float:
	var p := progress_clamped(progress)
	if kind == "teleport":
		return lerpf(2.15, 0.92, p)
	return lerpf(2.6, 1.15, p)

static func beam_height(kind: String, progress: float) -> float:
	var p := progress_clamped(progress)
	# 用 0.85 次方而不是平方：引导刚开始光柱就要立起来，
	# 否则前两秒画面几乎没有变化，玩家会以为没按上。
	var ease := pow(p, 0.85)
	if kind == "teleport":
		return lerpf(0.0, 5.0, ease)
	return lerpf(0.0, 6.2, ease)

static func particle_rate(kind: String, progress: float) -> int:
	var p := progress_clamped(progress)
	var peak: int = PARTICLE_TIERS[PARTICLE_TIERS.size() - 1]
	if kind == "teleport":
		return int(round(float(peak) * p))
	return int(round(float(peak) * 0.82 * p))

# ---------------- 节点 ----------------

func _ready() -> void:
	_build()
	set_process(true)
	visible = false

func _build() -> void:
	_glow = _make_disc(2.4)
	_glow_material = _glow.material_override
	add_child(_glow)

	_outer_ring = _make_ring(RING_INNER, RING_OUTER, 2.6)
	_outer_material = _outer_ring.material_override
	add_child(_outer_ring)

	_inner_ring = _make_ring(RING_INNER, RING_OUTER, 1.4)
	_inner_material = _inner_ring.material_override
	_inner_ring.position.y = 0.02
	add_child(_inner_ring)

	_runes = _make_runes()
	add_child(_runes)

	_beam = _make_beam()
	_beam_material = _beam.material_override
	add_child(_beam)

	_particles = _make_particles()
	add_child(_particles)

func _make_runes() -> Node3D:
	var root := Node3D.new()
	_rune_material = _make_material(Color(0.0, 0.0, 0.0, 0.0), 0.9)
	for i in RUNE_COUNT:
		var rune := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.02, 0.46)
		rune.mesh = box
		var angle := TAU * float(i) / float(RUNE_COUNT)
		rune.position = Vector3(cos(angle), 0.0, sin(angle))
		rune.rotation.y = -angle + PI * 0.5
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rune.material_override = _rune_material
		root.add_child(rune)
	root.position.y = 0.07
	return root

func _make_disc(radius: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.02
	cylinder.radial_segments = 48
	disc.mesh = cylinder
	disc.position.y = 0.03
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.material_override = _make_material(Color(0.0, 0.0, 0.0, 0.0), 1.2)
	return disc

func _make_ring(inner: float, outer: float, radius: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.08
	ring.scale = Vector3.ONE * radius
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = _make_material(Color(0.0, 0.0, 0.0, 0.0), 2.0)
	return ring

func _make_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	# 高度 1 的圆柱，靠 scale.y 拉伸，避免每帧重建网格。
	# 上下必须同半径。锥台（上小下大）在俯视角下像一只倒扣的灯罩，
	# 读起来是「光在往下灌」，与「人被一束光吸上去」正好相反。
	cylinder.top_radius = BEAM_BASE_RADIUS
	cylinder.bottom_radius = BEAM_BASE_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 28
	beam.mesh = cylinder
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.material_override = _make_material(Color(0.0, 0.0, 0.0, 0.0), 1.4)
	return beam

func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = emission_energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _make_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = PARTICLE_TIERS[0]
	particles.lifetime = 1.1
	particles.one_shot = false
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3(0, 1, 0)
	process.emission_ring_radius = 1.6
	process.emission_ring_inner_radius = 0.5
	process.emission_ring_height = 0.1
	process.direction = Vector3(0, 1, 0)
	process.spread = 8.0
	process.initial_velocity_min = 1.4
	process.initial_velocity_max = 3.6
	process.gravity = Vector3(0, 1.8, 0)
	process.scale_min = 0.5
	process.scale_max = 1.15
	process.color = COLOR_RECALL
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.draw_pass_1 = quad
	return particles

# ---------------- 驱动 ----------------

# 每帧由 Arena 调用：更新目标外观。淡入淡出由 _process 自己收敛。
func set_channel(kind: String, progress: float) -> void:
	if kind == "":
		release()
		return
	if not _active:
		_active = true
		visible = true
		_spin = 0.0
	if kind != _kind:
		# 回城 ↔ 传送就地换色，不重建节点：重开一次会有可见的闪断。
		_kind = kind
		_particle_tier = -1
		_particles.restart()
		_particles.emitting = true
	_progress = progress_clamped(progress)
	var target := color_for(_kind)
	_color = _color.lerp(target, 0.25)

# 状态机报告引导结束：不立刻隐藏，交给淡出跑完。
func release() -> void:
	_active = false

func is_active() -> bool:
	return _active

func _process(delta: float) -> void:
	var target_fade := 1.0 if _active else 0.0
	# 起手快、收尾稍慢：引导开始要「立起来」，结束时不能拖泥带水。
	_fade = move_toward(_fade, target_fade, delta * (5.0 if _active else 3.2))
	if _fade <= 0.001 and not _active:
		if visible:
			visible = false
			_particles.emitting = false
		return
	_pulse += delta
	_spin += delta * spin_speed(_kind, _progress)
	var radius := ring_radius(_kind, _progress)
	var height := beam_height(_kind, _progress)
	var breathe := 0.5 + 0.5 * sin(_pulse * 5.4)

	_glow.visible = true
	_glow.scale = Vector3.ONE * radius
	# 加法混合叠在亮草地上很容易过曝成白团，透明度必须压住。
	_glow_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.11 * _fade * (0.7 + 0.3 * breathe))

	_outer_ring.scale = Vector3(radius, 1.0, radius)
	_outer_ring.rotation.y = _spin
	_outer_material.albedo_color = Color(_color.r, _color.g, _color.b, (0.44 + 0.16 * breathe) * _fade)

	_inner_ring.scale = Vector3(radius * 0.62, 1.0, radius * 0.62)
	_inner_ring.rotation.y = -_spin * 1.6
	_inner_ring.position.y = 0.02 + 0.05 * sin(_pulse * 3.1)
	_inner_material.albedo_color = Color(_color.r, _color.g, _color.b, (0.32 + 0.14 * breathe) * _fade)

	# 符条是唯一能看出旋转的部分：圆环各向同性，转不转在画面上完全一样。
	_runes.scale = Vector3(radius, 1.0, radius)
	_runes.rotation.y = _spin * 1.15
	_rune_material.albedo_color = Color(_color.r, _color.g, _color.b, (0.62 + 0.2 * breathe) * _fade)

	_beam.visible = height > 0.05
	if _beam.visible:
		_beam.scale = Vector3(1.0 + 0.12 * breathe, height, 1.0 + 0.12 * breathe)
		_beam.position.y = height * 0.5
		_beam_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.24 * _fade * (0.75 + 0.25 * breathe))

	var tier := _tier_for(particle_rate(_kind, _progress))
	if tier != _particle_tier:
		_particle_tier = tier
		_particles.amount = PARTICLE_TIERS[tier]
		_particles.emitting = _active
	var process := _particles.process_material as ParticleProcessMaterial
	if process:
		process.color = _color
		process.emission_ring_radius = maxf(radius, 0.35)

func _tier_for(rate: int) -> int:
	var tier := 0
	for i in PARTICLE_TIERS.size():
		if rate >= PARTICLE_TIERS[i]:
			tier = i
	return tier

# ---------------- 瞬时爆发 ----------------

# 完成：一圈快速外扩的冲击环 + 光柱闪白，落点必须有「成」的实感。
func burst(color: Color) -> void:
	_spawn_burst_ring(color, 1.0, 7.0, 0.7, 0.15)
	_spawn_burst_ring(color, 0.6, 3.6, 0.45, 0.3)
	_flash_beam(color)
	_burst_particles(color)

# 打断：能量失控散开 —— 环往外炸、立刻转红，语义是「断了」而不是「成了」。
func shatter(color: Color) -> void:
	var broken := color.lerp(Color(1.0, 0.38, 0.26), 0.6)
	# 法阵立刻暗下去，把注意力让给炸开的环；否则大光环还在，看不出「断了」。
	_fade = minf(_fade, 0.28)
	_spawn_burst_ring(broken, 1.0, 3.8, 0.42, 0.1)
	_spawn_burst_ring(broken, 0.6, 2.0, 0.3, 0.22)
	_active = false

func _spawn_burst_ring(color: Color, from_scale: float, to_scale: float, duration: float, y: float) -> void:
	var ring := _make_ring(RING_INNER, RING_OUTER, from_scale)
	var material := ring.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.emission = color
	material.emission_energy_multiplier = 2.6
	ring.position.y = y
	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * to_scale, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)

func _flash_beam(color: Color) -> void:
	if not _beam.visible:
		return
	var flash := _make_beam()
	var material := flash.material_override as StandardMaterial3D
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	material.emission = color
	material.emission_energy_multiplier = 3.2
	flash.scale = _beam.scale
	flash.position.y = _beam.position.y
	add_child(flash)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3(flash.scale.x * 1.9, flash.scale.y * 1.15, flash.scale.z * 1.9), 0.28)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(flash.queue_free)

func _burst_particles(color: Color) -> void:
	var process := _particles.process_material as ParticleProcessMaterial
	if process == null:
		return
	var original := process.initial_velocity_max
	process.initial_velocity_max = original * 2.4
	process.color = color
	_particles.amount = PARTICLE_TIERS[PARTICLE_TIERS.size() - 1]
	_particles.restart()
	_particles.emitting = true
	# 爆发后交还给常规密度，靠下一次 set_channel 的档位判断拉回来。
	_particle_tier = PARTICLE_TIERS.size() - 1
	create_tween().tween_callback(func(): process.initial_velocity_max = original).set_delay(0.05)
