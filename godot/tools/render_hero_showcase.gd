extends SceneTree

# 离线渲染英雄展示视频：复用对局里的 UnitVisual（同一套模型、动作库、武器挂点），
# 在离屏 SubViewport 里逐帧推进动画并导出 30fps 帧序列，再交给 ffmpeg 编码 Theora。
# 窗口保持 1x1、无边框、移出屏幕，不打断用户操作。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

const OUT_DIR := "res://assets/ui/hero_videos"
const FRAME_DIR := "res://build/showcase_frames"
const FFMPEG := "D:/Tools/ffmpeg/bin/ffmpeg.exe"
const SIZE := Vector2i(720, 405)
const FPS := 30
const DURATION := 8.0

const HEROES := [
	{
		"id": "mage",
		"name": "星璃",
		"accent": Color(0.52, 0.42, 1.0),
		"backdrop": "res://build/showcase_backdrops/mage.png",
		"fog": Color(0.16, 0.14, 0.30),
		"ambient": Color(0.30, 0.28, 0.55),
		"key_color": Color(0.78, 0.86, 1.0),
		"fill_color": Color(0.48, 0.34, 1.0),
		"rim_color": Color(0.72, 0.86, 1.0),
		"actions": [[3.0, "Spell_Simple_Shoot"], [4.9, "Spell_Simple_Enter"], [6.4, "Spell_Simple_Shoot"]],
	},
	{
		"id": "tank",
		"name": "铁壁",
		"accent": Color(1.0, 0.6, 0.26),
		"backdrop": "res://build/showcase_backdrops/tank.png",
		"fog": Color(0.22, 0.13, 0.07),
		"ambient": Color(0.38, 0.28, 0.22),
		"key_color": Color(1.0, 0.82, 0.58),
		"fill_color": Color(0.40, 0.55, 1.0),
		"rim_color": Color(1.0, 0.62, 0.32),
		"actions": [[3.0, "Sword_Regular_A"], [4.9, "Sword_Block"], [6.4, "Chest_Open"]],
	},
]

var viewport: SubViewport
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	Engine.max_fps = 0
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	_run()

func _run() -> void:
	for spec in HEROES:
		var ok := await _render_hero(spec)
		if not ok:
			printerr("SHOWCASE FAILED: ", spec.id)
			quit(1)
			return
	print("SHOWCASE DONE")
	quit()

func _render_hero(spec: Dictionary) -> bool:
	var hero_id := str(spec.id)
	var frames_abs := ProjectSettings.globalize_path(FRAME_DIR) + "/" + hero_id
	DirAccess.make_dir_recursive_absolute(frames_abs)

	var scene := Node3D.new()
	scene.name = "Showcase_" + hero_id
	viewport.add_child(scene)

	var accent: Color = spec.accent
	var camera := _build_camera(scene)
	var backdrop_tex := _load_backdrop(str(spec.get("backdrop", "")))
	var backdrop := _build_environment(scene, spec, accent, backdrop_tex, camera)
	var hero := _build_hero(scene, hero_id, str(spec.name))
	var fx := _build_effects(scene, accent)

	# 等两帧：让材质、灯光和阴影完成首帧准备，避免第一帧闪黑。
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var total := int(DURATION * FPS)
	var actions: Array = spec.actions
	var next_action := 0
	var dt := 1.0 / FPS
	for i in total:
		var t := float(i) / FPS
		while next_action < actions.size() and t >= float(actions[next_action][0]):
			hero.play_action(str(actions[next_action][1]))
			next_action += 1

		if i > 0:
			for player in hero.animation_players:
				if player != null:
					player.advance(dt)
			hero.process_visual(dt)
		# 直接驱动骨骼而不是依赖真实帧间隔：截图写盘偶尔变慢也不会拖慢动作。
		# animation_players 已在 _build_hero 里设为 active=false。
		_animate_camera(camera, t)
		_animate_hero(hero, t)
		_animate_backdrop(backdrop, t)
		_animate_effects(fx, t, dt)

		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null:
			printerr("null frame at ", hero_id, " #", i)
			return false
		var path := "%s/%s_%04d.jpg" % [frames_abs, hero_id, i]
		if image.save_jpg(path, 0.95) != OK:
			printerr("save failed: ", path)
			return false
		if i % 60 == 0:
			print("  ", hero_id, " frame ", i, "/", total)

	viewport.remove_child(scene)
	scene.free()

	var out_abs := ProjectSettings.globalize_path(OUT_DIR) + "/hero_" + hero_id + ".ogv"
	var pattern := frames_abs.replace("\\", "/") + "/" + hero_id + "_%04d.jpg"
	var args := PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-y",
		"-framerate", str(FPS), "-i", pattern,
		"-vf", "vignette=PI/5,fade=t=in:st=0:d=0.45,fade=t=out:st=7.35:d=0.65",
		"-c:v", "libtheora", "-q:v", "9", "-an", out_abs,
	])
	var exit_code := OS.execute(FFMPEG, args)
	if exit_code != 0:
		printerr("ffmpeg failed (", exit_code, ") for ", hero_id)
		return false
	print("  encoded ", out_abs)
	return true

func _build_environment(scene: Node3D, spec: Dictionary, accent: Color, backdrop_tex: Texture2D, camera: Camera3D) -> MeshInstance3D:
	var ambient: Color = spec.get("ambient", Color(0.24, 0.34, 0.5))
	var fog_color: Color = spec.get("fog", Color(0.12, 0.19, 0.3))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_light_energy = 0.55
	env.fog_density = 0.011
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	scene.add_child(world_env)

	# 地面：深色镜面圆台 + 一圈装饰环
	var stage := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.12
	disc.radial_segments = 72
	var stage_mat := StandardMaterial3D.new()
	stage_mat.albedo_color = Color(0.032, 0.045, 0.062)
	stage_mat.metallic = 0.55
	stage_mat.roughness = 0.32
	stage.mesh = disc
	stage.position.y = -0.06
	stage.material_override = stage_mat
	scene.add_child(stage)

	var outer := MeshInstance3D.new()
	var outer_disc := CylinderMesh.new()
	outer_disc.top_radius = 13.0
	outer_disc.bottom_radius = 13.0
	outer_disc.height = 0.05
	outer_disc.radial_segments = 64
	var outer_mat := StandardMaterial3D.new()
	outer_mat.albedo_color = Color(0.012, 0.018, 0.028)
	outer_mat.roughness = 0.9
	outer.mesh = outer_disc
	outer.position.y = -0.1
	outer.material_override = outer_mat
	scene.add_child(outer)

	# 远处地面，补上圆台与背景板之间的空隙，避免镜头移动时露出黑边。
	var far_ground := MeshInstance3D.new()
	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(120.0, 120.0)
	var far_mat := StandardMaterial3D.new()
	far_mat.albedo_color = Color(0.01, 0.014, 0.022)
	far_mat.roughness = 0.95
	far_ground.mesh = far_plane
	far_ground.position.y = -0.115
	far_ground.material_override = far_mat
	far_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(far_ground)

	var ring_color := Color(accent.r, accent.g, accent.b, 0.85)
	for ring_data in [[1.62, 0.006, 0.55], [2.42, 0.003, 0.22]]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = float(ring_data[0])
		torus.outer_radius = float(ring_data[0]) + float(ring_data[1])
		torus.rings = 72
		torus.ring_segments = 8
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(accent.r, accent.g, accent.b, float(ring_data[2]))
		mat.emission_enabled = true
		mat.emission = accent
		mat.emission_energy_multiplier = 1.4
		ring.mesh = torus
		ring.position.y = 0.015
		ring.material_override = mat
		scene.add_child(ring)

	# 背景：AI 场景图铺满远景（缺失时回落到渐变幕布），柔光 halo 把人物从背景里托出来。
	var radial := _radial_texture()
	var backdrop := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(27.0, 15.19)
	var bd_mat := StandardMaterial3D.new()
	bd_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bd_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if backdrop_tex != null:
		bd_mat.albedo_texture = backdrop_tex
		bd_mat.albedo_color = Color(0.68, 0.68, 0.72)
	else:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.02, 0.032, 0.052))
		gradient.set_color(1, Color(0.055, 0.085, 0.14))
		var gtex := GradientTexture2D.new()
		gtex.gradient = gradient
		gtex.fill = GradientTexture2D.FILL_LINEAR
		gtex.fill_from = Vector2(0.5, 1.0)
		gtex.fill_to = Vector2(0.5, 0.0)
		bd_mat.albedo_texture = gtex
	backdrop.mesh = quad
	# 抬高半个画面：让远景的山脊/城楼落在人物肩线附近，而不是沉到地平线以下。
	backdrop.position = Vector3(0.0, 3.0, -20.0)
	backdrop.material_override = bd_mat
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 挂在相机下：镜头环绕时背景始终铺满画面，不会露出背景板边缘。
	camera.add_child(backdrop)

	var halo := MeshInstance3D.new()
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(9.0, 9.0)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.albedo_texture = radial
	halo_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.20)
	halo.mesh = halo_quad
	halo.position = Vector3(0.0, 2.35, -6.0)
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(halo)

	rng.seed = 20261023
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.018, 0.024, 0.036)
	pillar_mat.roughness = 0.85
	for i in 8:
		var height := rng.randf_range(2.0, 6.0)
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(8.0, 12.0)
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.45, 1.05), height, rng.randf_range(0.45, 1.05))
		pillar.mesh = box
		pillar.position = Vector3(cos(angle) * radius, height * 0.5, sin(angle) * radius)
		pillar.rotation.y = rng.randf_range(0.0, TAU)
		pillar.material_override = pillar_mat
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(pillar)

	# 灯光：主光/补光/轮廓光按英雄场景配色，人物边缘与背景分开。
	var key_color: Color = spec.get("key_color", Color(1.0, 0.83, 0.6))
	var fill_color: Color = spec.get("fill_color", Color(0.36, 0.55, 1.0))
	var rim_color: Color = spec.get("rim_color", Color(0.55, 0.82, 1.0))
	var key := SpotLight3D.new()
	key.light_color = key_color
	key.light_energy = 7.5
	key.spot_range = 14.0
	key.spot_angle = 30.0
	key.shadow_enabled = true
	scene.add_child(key)
	key.look_at_from_position(Vector3(2.6, 3.8, 3.2), Vector3(0.0, 1.25, 0.0), Vector3.UP)

	var fill := OmniLight3D.new()
	fill.light_color = fill_color
	fill.light_energy = 2.8
	fill.omni_range = 9.0
	fill.position = Vector3(-3.0, 2.2, 2.2)
	scene.add_child(fill)

	var rim := SpotLight3D.new()
	rim.light_color = rim_color
	rim.light_energy = 10.0
	rim.spot_range = 12.0
	rim.spot_angle = 28.0
	scene.add_child(rim)
	rim.look_at_from_position(Vector3(-1.8, 2.9, -3.4), Vector3(0.0, 1.4, 0.0), Vector3.UP)

	var accent_light := OmniLight3D.new()
	accent_light.light_color = accent
	accent_light.light_energy = 1.4
	accent_light.omni_range = 4.0
	accent_light.position = Vector3(0.0, 0.7, 1.3)
	scene.add_child(accent_light)

	return backdrop

func _build_hero(scene: Node3D, hero_id: String, display_name: String) -> UnitVisual:
	var hero := UnitVisual.new()
	hero.name = "Hero"
	scene.add_child(hero)
	hero.setup("hero", "blue", hero_id, display_name, false)
	hero.set_process(false)
	hero.set_physics_process(false)
	hero.position = Vector3.ZERO
	hero.rotation.y = deg_to_rad(-10.0)
	if hero.bar_root != null:
		hero.bar_root.visible = false
	if hero.team_ring != null:
		hero.team_ring.visible = false
	if hero.local_ring != null:
		hero.local_ring.visible = false
	# 手动推进骨骼：录像时每帧固定 1/30 秒，不受渲染耗时影响。
	for player in hero.animation_players:
		if player != null:
			player.active = false
	return hero

func _build_camera(scene: Node3D) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.05
	camera.far = 80.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	scene.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0.0, 1.6, 3.9), Vector3(0.0, 1.22, 0.0), Vector3.UP)
	return camera

func _build_effects(scene: Node3D, accent: Color) -> Dictionary:
	var fx := {"rings": [], "pillar": null, "pillar_mat": null, "motes": [], "glow_mat": null}

	for entry in [[3.0, 0.9], [4.9, 1.35], [6.4, 0.85]]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.78
		torus.outer_radius = 0.86
		torus.rings = 64
		torus.ring_segments = 8
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.0)
		mat.emission_enabled = true
		mat.emission = accent
		mat.emission_energy_multiplier = 2.0
		ring.mesh = torus
		ring.position.y = 0.035
		ring.material_override = mat
		ring.visible = false
		scene.add_child(ring)
		fx.rings.append({"mesh": ring, "mat": mat, "time": float(entry[0]), "dur": float(entry[1])})

	var pillar := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.26
	cylinder.bottom_radius = 0.4
	cylinder.height = 3.8
	cylinder.radial_segments = 32
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pillar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pillar_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.0)
	pillar.mesh = cylinder
	pillar.position.y = 1.9
	pillar.material_override = pillar_mat
	pillar.visible = false
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(pillar)
	fx.pillar = pillar
	fx.pillar_mat = pillar_mat

	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.022
	mote_mesh.height = 0.044
	mote_mesh.radial_segments = 8
	mote_mesh.rings = 4
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.7)
	mote_mat.emission_enabled = true
	mote_mat.emission = accent
	mote_mat.emission_energy_multiplier = 2.2
	rng.seed = 7719
	for i in 26:
		var mote := MeshInstance3D.new()
		mote.mesh = mote_mesh
		mote.material_override = mote_mat
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(mote)
		fx.motes.append({
			"mesh": mote,
			"angle": rng.randf_range(0.0, TAU),
			"radius": rng.randf_range(0.55, 2.7),
			"speed": rng.randf_range(0.08, 0.28),
			"base_y": rng.randf_range(0.0, 3.0),
			"sway": rng.randf_range(0.15, 0.45),
		})

	# 脚下柔光：用径向渐变贴图铺在地面，避免额外写一份全屏辉光
	var glow := MeshInstance3D.new()
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(6.4, 6.4)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.albedo_texture = _radial_texture()
	glow_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.4)
	glow.mesh = glow_quad
	glow.rotation_degrees.x = -90.0
	glow.position.y = 0.018
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(glow)
	fx.glow_mat = glow_mat

	return fx

func _animate_camera(camera: Camera3D, t: float) -> void:
	var u := clampf(t / DURATION, 0.0, 1.0)
	var az := deg_to_rad(lerpf(-26.0, 20.0, smoothstep(0.0, 1.0, u))) + sin(t * 0.5) * 0.012
	var push := 0.1 * _bell(t, 3.0, 0.75) + 0.16 * _bell(t, 4.9, 0.95) + 0.08 * _bell(t, 6.4, 0.8)
	var dist := 3.95 - 0.28 * u + 0.05 * sin(t * 0.8) - push
	var target := Vector3(0.0, 1.22 + 0.03 * sin(t * 0.7), 0.0)
	var cam_y := 1.52 + 0.06 * sin(t * 0.55) - 0.05 * u
	var pos := Vector3(
		target.x + sin(az) * dist + sin(t * 1.7) * 0.008,
		cam_y + cos(t * 1.3) * 0.006,
		target.z + cos(az) * dist
	)
	camera.look_at_from_position(pos, target, Vector3.UP)
	camera.fov = 38.0 - 0.9 * _bell(t, 4.9, 0.95)

func _animate_hero(hero: UnitVisual, t: float) -> void:
	var u := clampf(t / DURATION, 0.0, 1.0)
	hero.rotation.y = deg_to_rad(lerpf(-12.0, 10.0, smoothstep(0.0, 1.0, u)) + sin(t * 0.4) * 2.0)

func _animate_effects(fx: Dictionary, t: float, _delta: float) -> void:
	for entry in fx.rings:
		var age: float = t - float(entry.time)
		var dur: float = float(entry.dur)
		var mesh: MeshInstance3D = entry.mesh
		var mat: StandardMaterial3D = entry.mat
		if age < 0.0 or age > dur:
			mesh.visible = false
			continue
		mesh.visible = true
		var k := age / dur
		var s := 0.75 + 3.6 * (1.0 - pow(1.0 - k, 2.2))
		mesh.scale = Vector3(s, 1.0, s)
		mat.albedo_color.a = (1.0 - k) * 0.85

	var pillar: MeshInstance3D = fx.pillar
	var pillar_mat: StandardMaterial3D = fx.pillar_mat
	var page := t - 4.9
	if page >= 0.0 and page <= 1.05:
		pillar.visible = true
		var k := page / 1.05
		var s := 0.55 + 0.9 * k
		pillar.scale = Vector3(s, 1.0 + 0.25 * sin(k * PI), s)
		pillar_mat.albedo_color.a = sin(k * PI) * 0.22
	else:
		pillar.visible = false

	for mote in fx.motes:
		var mesh: MeshInstance3D = mote.mesh
		var angle: float = float(mote.angle) + t * 0.32
		var radius: float = float(mote.radius) + sin(t * 0.7 + float(mote.angle)) * float(mote.sway) * 0.12
		var y: float = fmod(float(mote.base_y) + t * float(mote.speed), 3.4)
		mesh.position = Vector3(cos(angle) * radius, y, sin(angle) * radius)

	var glow_mat: StandardMaterial3D = fx.glow_mat
	glow_mat.albedo_color.a = 0.34 + 0.08 * sin(t * 1.6)

func _load_backdrop(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	# 走 Image.load_from_file 而不是 load()：build 目录里的素材不参与导入流程。
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

func _animate_backdrop(backdrop: MeshInstance3D, t: float) -> void:
	if backdrop == null:
		return
	# 极缓慢的横移和呼吸，让静态背景图有一点空气感。
	backdrop.position.x = sin(t * 0.10) * 0.55
	backdrop.position.y = 3.0 + cos(t * 0.08) * 0.16

func _radial_texture() -> ImageTexture:
	# 手写径向 alpha：GradientTexture2D 的 FILL_RADIAL 在兼容渲染器里
	# 四角仍是全不透明，加法混合时会露出方形亮斑。
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center) / (size * 0.5)
			var alpha := clampf(1.0 - distance, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _bell(t: float, center: float, width: float) -> float:
	var x := (t - center) / width
	return exp(-x * x)
