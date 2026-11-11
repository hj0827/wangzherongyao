extends "res://tests/test_base.gd"

# 环境浮尘（P1 SCENE-03）。
# 密度目标：桌面 400 / 移动端 200（旧版 120/60），仍是单批次。

const Arena = preload("res://scripts/game/arena.gd")
const FxTextures = preload("res://scripts/game/fx_textures.gd")

func test_ambient_particles_are_dense_enough_and_soft() -> void:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._build_ambient_particles()
	var particle: GPUParticles3D = null
	for child in arena._effects_root.get_children():
		if child is GPUParticles3D:
			particle = child
			break
	check(particle != null, "环境粒子必须创建")
	if particle == null:
		arena.free()
		return
	# 无头桌面机没有 mobile 特性，走桌面档。
	check(particle.amount >= 200, "环境粒子至少 200 个（桌面目标 400），实际 %d" % particle.amount)
	check(particle.emitting, "环境粒子默认发射")
	var material := (particle.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	check(material != null and material.albedo_texture == FxTextures.soft_glow(), "环境粒子用柔光贴图")
	var process := particle.process_material as ParticleProcessMaterial
	var ramp := process.color_ramp as GradientTexture1D if process != null else null
	check(ramp != null and ramp.gradient != null and ramp.gradient.get_point_count() >= 4,
		"浮尘要有青→绿→金的生命期渐变，而不是单色")
	arena.free()
