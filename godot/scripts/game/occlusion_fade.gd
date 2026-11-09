extends RefCounted

# 基地水晶「让路」——英雄走近时把挡视线的那几件淡出去。
#
# 为什么需要：相机是 51° 俯角，`pedestal`(r=1.3~1.8, h=1.2) 和 `gem`(y=3.55)
# 在屏幕上的投影正好罩住英雄站立的环带。英雄进了泉水，屏幕上就只剩一顶绿帽子。
# LoL / 王者荣耀的处理都是同一套：挡人的那件建筑变半透明，英雄透出来。
#
# 为什么不用 screen-door dither / alpha hash：
# - alpha hash 逐帧抖动，本工程没开 TAA，静止时会持续闪；
# - 真正的 dither 要给水晶的贴图材质、自发光材质、加法混合的光圈各写一份 shader，
#   四份代码必然会走形。
# 直接调 albedo 的 alpha（常驻 TRANSPARENCY_ALPHA）是唯一一处改动。
#
# 为什么 dais 不在名单里：它是半径 4.4、高 0.35 的贴地圆盘，俯视下挡不住任何人，
# 却同时是「这儿有个水晶」的唯一定位线索。淡了它，玩家会以为自己站在空地上。

## 英雄进入这个半径（米）水晶开始让路。
## 取 12 而不是泉水半径 10：进泉水的路上就该开始过渡，而不是踩到线才突变。
const FADE_FAR := 12.0

## 到这个半径（米）淡到下限。
## 取 4 而不是 0：水晶基座半径就在 4.4 左右，贴到基座之前必须已经全淡，
## 否则最后 4 米里英雄是被「突然揭开」的，近身打水晶时最刺眼。
const FADE_NEAR := 4.0

## 最低保留的不透明度。
## 不能是 0：水晶彻底消失后，玩家在泉水里会失去方位感，而且水晶被打掉时
## 那一下碎裂反馈会「凭空冒出来」。0.16 在 21 米机位上是「看得见轮廓、完全透光」。
const MIN_VISIBLE := 0.16

## 淡化强度：0 = 完全不透明，1 = 完全让路。
static func reveal_amount(distance: float) -> float:
	if distance >= FADE_FAR:
		return 0.0
	if distance <= FADE_NEAR:
		return 1.0
	return 1.0 - (distance - FADE_NEAR) / (FADE_FAR - FADE_NEAR)

## 实际写进 albedo 的 alpha。
## 收尾用 smoothstep：靠近时先快后慢，走开时不会「啪一下恢复成实心」。
static func visible_alpha(distance: float) -> float:
	var t := reveal_amount(distance)
	var eased := t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, MIN_VISIBLE, eased)

## 一个水晶里「会被英雄走过去挡住」的部件。构建时由 arena 登记进 record。
static func fade_parts(record: Dictionary) -> Array:
	return record.get("crystal_fade_parts", [])

## 按英雄到水晶的距离刷新所有部件的 alpha，返回本次用到的 alpha（给探针/测试读）。
static func apply(record: Dictionary, distance: float) -> float:
	var alpha := visible_alpha(distance)
	for part in fade_parts(record):
		set_part_alpha(part, alpha)
	return alpha

## 单个部件设 alpha。忽略 null 与没挂 StandardMaterial3D 的部件 ——
## 水晶里还有 ShaderMaterial 的血条，它不该被这里碰到。
static func set_part_alpha(part: Variant, alpha: float) -> void:
	if part == null or not (part is MeshInstance3D):
		return
	var material := (part as MeshInstance3D).material_override as StandardMaterial3D
	if material == null:
		return
	var color := material.albedo_color
	if is_equal_approx(color.a, alpha):
		return
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
