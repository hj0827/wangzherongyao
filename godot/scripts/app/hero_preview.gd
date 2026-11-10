extends SubViewportContainer
class_name HeroPreview

## 选人页 3D 预览骨架：复用现有 UnitVisual 模型，旋转展示 + 播放待机动作。
## 不新增模型资产；正式皮肤/专属动作仍属于 HERO-04。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

var _viewport: SubViewport
var _pivot: Node3D
var _hero: UnitVisual
var _built := false
var _current_hero := ""

func _ready() -> void:
	_ensure_built()

func setup(hero_type: String) -> void:
	_ensure_built()
	if _viewport == null or _current_hero == hero_type:
		return
	_current_hero = hero_type
	if _hero != null and is_instance_valid(_hero):
		_hero.queue_free()
	_hero = UnitVisual.new()
	_hero.setup("hero", "blue", hero_type, "", false, "blue")
	if _hero.bar_root != null:
		_hero.bar_root.visible = false
	if _hero.team_ring != null:
		_hero.team_ring.visible = false
	_pivot.add_child(_hero)

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(96.0, 96.0)
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(96, 96)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 4.3)
	camera.fov = 32.0
	camera.look_at_from_position(Vector3(0.0, 1.7, 4.3), Vector3(0.0, 1.35, 0.0))
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	light.light_color = Color(1.0, 0.93, 0.82)
	light.light_energy = 1.5
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.03, 0.045, 0.06, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.82)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.8
	environment.environment = env
	world.add_child(environment)
	_pivot = Node3D.new()
	world.add_child(_pivot)

func _process(delta: float) -> void:
	if _pivot != null:
		_pivot.rotation.y += delta * 0.65
	if _hero != null and is_instance_valid(_hero):
		_hero.process_visual(delta)
