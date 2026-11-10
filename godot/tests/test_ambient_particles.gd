extends "res://tests/test_base.gd"

# 环境浮尘（P1 SCENE-03 的第一版）。
# 36 个光点在 1600×900 下几乎看不见；桌面 120 / 移动端 60，仍是单批次。

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
	check(particle.amount >= 60, "环境粒子至少 60 个，实际 %d" % particle.amount)
	check(particle.emitting, "环境粒子默认发射")
	var material := (particle.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	check(material != null and material.albedo_texture == FxTextures.soft_glow(), "环境粒子用柔光贴图")
	arena.free()
