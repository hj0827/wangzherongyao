extends RefCounted
class_name HeroLook

## 每个英雄的「视觉身份」——纯数据 + 纯函数，可在 --headless 下断言。
##
## 为什么要有这一层：
##   现在 5 个英雄共用 2 套身体 + 4 套衣服，靠 `ModelUtils.tint(albedo_color)` 染色。
##   通用包的贴图本身是「米白内衬 + 褐皮甲 + 绿布料」的杂色，乘一个色相之后是脏绿、
##   脏棕、脏紫 —— 5 个人一起站成一片土色，谁都不像谁。
##
## 这里把「英雄长什么样」拆成三件可独立替换的事：
##   1. **配色**（`palette`）：主色 / 副色 / 金属色 / 发色 / 点缀光，来自立绘；
##   2. **材质**（`skin_slots`）：每个槽位（身体布料 / 外衣 / 头发 / 武器）一套着色参数；
##   3. **服饰**（`costume`）：挂在骨骼上的专属 3D 配件规格（护肩 / 披风 / 下摆 / 头饰…）。
##
## 三条硬口径（都是对着立绘 + 实拍图定的，别凭手感改）：
##   - **主色必须压得住**：本工程走 FILMIC + exposure 1.05，albedo 写 0.5 出来是中灰。
##     布料主色落在 0.12~0.32 这一档，才在实机上读成「深绿袍子」而不是「灰袍子」。
##   - **每个英雄必须有一件「远看认得出」的大件**：苍刃的披风、星璃的下摆、铁壁的
##     战旗、翎羽的羽披、墨鸦的兜帽斗篷。21 米机位下能读到的只有这个。
##   - **金/铜不是装饰色，是分层色**：只出现在边缘（护肩外沿、腰带扣、头饰），
##     面积一大就会变成「全身发黄的塑料人」。

# ---------------------------------------------------------------------------
# 单槽位材质参数
# ---------------------------------------------------------------------------
#
# 每个槽位交给 hero_skin.gdshader 的参数集。字段与 uniform 一一对应，
# `HeroCostume.skin_material()` 是唯一的消费处（少一个键就是静默回落默认值）。

const DEFAULT_SLOT := {
	"base": Color(0.8, 0.8, 0.8),
	"accent": Color(0.2, 0.2, 0.2),
	"accent_amount": 0.0,
	"recolor": 0.85,
	"lighting_keep": 0.55,
	"contrast": 1.35,
	"brightness": 1.0,
	"rim": Color(1.0, 0.95, 0.85),
	"rim_strength": 0.0,
	"rim_power": 3.0,
	"glow": Color(1.0, 1.0, 1.0),
	"glow_strength": 0.0,
	"roughness": 0.82,
	"metallic": 0.0,
	"specular": 0.35,
}

static func slot_params(params: Dictionary) -> Dictionary:
	var merged := DEFAULT_SLOT.duplicate()
	for key in params:
		merged[key] = params[key]
	return merged

# ---------------------------------------------------------------------------
# 5 个英雄
# ---------------------------------------------------------------------------

const LOOKS := {
	# 苍刃 · 战士 —— 立绘：墨绿长袍 + 黑皮甲 + 旧金扣，深色短发，巨剑。
	"blade": {
		"palette": {
			"primary": Color(0.13, 0.24, 0.16),
			"secondary": Color(0.07, 0.06, 0.05),
			"metal": Color(0.42, 0.32, 0.15),
			"hair": Color(0.09, 0.08, 0.07),
			"glow": Color(1.0, 0.70, 0.28),
		},
		"skin_slots": {
			# 身体的「布料面」（贴图面之外的纯色面）统一压成墨绿，皮肤/眼睛保持原贴图。
			"body": {
				"base": Color(0.17, 0.29, 0.19), "accent": Color(0.08, 0.09, 0.07),
				"recolor": 0.88, "contrast": 1.32, "lighting_keep": 0.6,
			},
			"outfit": {
				"base": Color(0.15, 0.27, 0.18), "accent": Color(0.10, 0.075, 0.05),
				"accent_amount": 0.3, "recolor": 0.94, "contrast": 1.5,
				"lighting_keep": 0.62, "roughness": 0.87,
			},
			"hair": {
				"base": Color(0.10, 0.09, 0.08), "recolor": 0.95, "contrast": 1.2,
				"lighting_keep": 0.5, "roughness": 0.55,
			},
			# 巨剑：刃口带暖金光，是「这个英雄是橙金色系」在模型上的落点。
			"weapon": {
				"base": Color(0.34, 0.30, 0.24), "accent": Color(0.55, 0.42, 0.18),
				"accent_amount": 0.35, "recolor": 0.8, "contrast": 1.3,
				"metallic": 0.45, "roughness": 0.38,
				"glow": Color(1.0, 0.70, 0.28), "glow_strength": 0.55,
				"rim": Color(1.0, 0.74, 0.34), "rim_strength": 0.5,
			},
		},
	},
	# 星璃 · 法师 —— 立绘：深靛紫星纹长袍 + 金月饰 + 乌黑长发，月牙法杖。
	"mage": {
		"palette": {
			"primary": Color(0.16, 0.13, 0.34),
			"secondary": Color(0.31, 0.22, 0.55),
			"metal": Color(0.55, 0.44, 0.18),
			"hair": Color(0.07, 0.06, 0.11),
			"glow": Color(0.62, 0.52, 1.0),
		},
		"skin_slots": {
			"body": {
				"base": Color(0.21, 0.17, 0.40), "accent": Color(0.10, 0.09, 0.2),
				"recolor": 0.9, "contrast": 1.34, "lighting_keep": 0.6,
			},
			"outfit": {
				"base": Color(0.20, 0.15, 0.42), "accent": Color(0.42, 0.30, 0.70),
				"accent_amount": 0.22, "recolor": 0.95, "contrast": 1.45,
				"lighting_keep": 0.58, "roughness": 0.75,
			},
			"hair": {
				"base": Color(0.075, 0.065, 0.115), "recolor": 0.95, "contrast": 1.15,
				"lighting_keep": 0.45, "roughness": 0.4,
				# 星璃的发丝带一点点星尘冷光，是「她是法师」的最便宜暗示。
				"glow": Color(0.55, 0.45, 1.0), "glow_strength": 0.35,
			},
			"weapon": {
				"base": Color(0.24, 0.20, 0.42), "accent": Color(0.62, 0.50, 0.20),
				"accent_amount": 0.4, "recolor": 0.78, "contrast": 1.28,
				"metallic": 0.5, "roughness": 0.32,
				"glow": Color(0.66, 0.55, 1.0), "glow_strength": 1.1,
				"rim": Color(0.70, 0.60, 1.0), "rim_strength": 0.7,
			},
		},
	},
	# 铁壁 · 坦克 —— 立绘：黑铁札甲 + 锈橙披巾 + 青铜兽首，络腮胡，双头锤。
	"tank": {
		"palette": {
			"primary": Color(0.20, 0.17, 0.15),
			"secondary": Color(0.58, 0.24, 0.09),
			"metal": Color(0.40, 0.30, 0.14),
			"hair": Color(0.10, 0.08, 0.06),
			"glow": Color(1.0, 0.48, 0.16),
		},
		"skin_slots": {
			"body": {
				"base": Color(0.26, 0.22, 0.18), "accent": Color(0.10, 0.08, 0.07),
				"recolor": 0.9, "contrast": 1.3, "lighting_keep": 0.62,
			},
			"outfit": {
				# 甲片偏冷铁，披巾偏锈橙：两色并置才是立绘里那个「铁壁」。
				"base": Color(0.24, 0.21, 0.19), "accent": Color(0.56, 0.24, 0.09),
				"accent_amount": 0.34, "recolor": 0.93, "contrast": 1.45,
				"lighting_keep": 0.6, "roughness": 0.7, "metallic": 0.2,
			},
			"hair": {
				"base": Color(0.11, 0.09, 0.07), "recolor": 0.95, "contrast": 1.2,
				"lighting_keep": 0.5, "roughness": 0.6,
			},
			"weapon": {
				"base": Color(0.30, 0.27, 0.24), "accent": Color(0.50, 0.34, 0.13),
				"accent_amount": 0.45, "recolor": 0.8, "contrast": 1.3,
				"metallic": 0.55, "roughness": 0.34,
				"glow": Color(1.0, 0.52, 0.18), "glow_strength": 0.6,
				"rim": Color(1.0, 0.55, 0.25), "rim_strength": 0.45,
			},
		},
	},
	# 翎羽 · 射手 —— 立绘：米白内衬 + 青碧色 + 白羽饰，双丸子头，长弓。
	"archer": {
		"palette": {
			"primary": Color(0.62, 0.62, 0.55),
			"secondary": Color(0.10, 0.36, 0.32),
			"metal": Color(0.36, 0.30, 0.16),
			"hair": Color(0.10, 0.085, 0.07),
			"glow": Color(0.45, 0.95, 0.78),
		},
		"skin_slots": {
			"body": {
				"base": Color(0.55, 0.60, 0.52), "accent": Color(0.11, 0.34, 0.30),
				"recolor": 0.9, "contrast": 1.28, "lighting_keep": 0.62,
			},
			"outfit": {
				# 米白是主色、青碧是副色，跟立绘一致。反过来会变成「蓝绿女枪手」。
				"base": Color(0.60, 0.61, 0.55), "accent": Color(0.09, 0.33, 0.30),
				"accent_amount": 0.42, "recolor": 0.94, "contrast": 1.38,
				"lighting_keep": 0.6, "roughness": 0.86,
			},
			"hair": {
				"base": Color(0.11, 0.09, 0.075), "recolor": 0.95, "contrast": 1.2,
				"lighting_keep": 0.48, "roughness": 0.5,
			},
			"weapon": {
				"base": Color(0.28, 0.24, 0.20), "accent": Color(0.14, 0.42, 0.36),
				"accent_amount": 0.3, "recolor": 0.82, "contrast": 1.3,
				"metallic": 0.2, "roughness": 0.55,
				"glow": Color(0.45, 0.95, 0.78), "glow_strength": 0.75,
				"rim": Color(0.5, 0.98, 0.82), "rim_strength": 0.55,
			},
		},
	},
	# 墨鸦 · 刺客 —— 立绘：近黑皮衣 + 紫披风 + 浅钢匕首，高马尾。
	"assassin": {
		"palette": {
			"primary": Color(0.10, 0.09, 0.11),
			"secondary": Color(0.26, 0.15, 0.36),
			"metal": Color(0.46, 0.44, 0.42),
			"hair": Color(0.07, 0.06, 0.075),
			"glow": Color(0.80, 0.42, 0.92),
		},
		"skin_slots": {
			"body": {
				"base": Color(0.15, 0.13, 0.16), "accent": Color(0.24, 0.13, 0.32),
				"recolor": 0.9, "contrast": 1.3, "lighting_keep": 0.62,
			},
			"outfit": {
				"base": Color(0.13, 0.11, 0.14), "accent": Color(0.28, 0.16, 0.38),
				"accent_amount": 0.38, "recolor": 0.94, "contrast": 1.42,
				"lighting_keep": 0.58, "roughness": 0.62, "metallic": 0.1,
			},
			"hair": {
				"base": Color(0.075, 0.065, 0.08), "recolor": 0.96, "contrast": 1.15,
				"lighting_keep": 0.45, "roughness": 0.42,
			},
			"weapon": {
				"base": Color(0.42, 0.42, 0.44), "accent": Color(0.30, 0.17, 0.40),
				"accent_amount": 0.3, "recolor": 0.7, "contrast": 1.25,
				"metallic": 0.75, "roughness": 0.22,
				"glow": Color(0.82, 0.45, 0.95), "glow_strength": 0.9,
				"rim": Color(0.85, 0.55, 1.0), "rim_strength": 0.75,
			},
		},
	},
}

const HEROES := ["blade", "mage", "tank", "archer", "assassin"]

static func has_look(hero_type: String) -> bool:
	return LOOKS.has(hero_type)

static func look(hero_type: String) -> Dictionary:
	return LOOKS.get(hero_type, LOOKS["blade"])

static func palette(hero_type: String) -> Dictionary:
	return look(hero_type).get("palette", {})

static func primary(hero_type: String) -> Color:
	return palette(hero_type).get("primary", Color.WHITE)

static func glow(hero_type: String) -> Color:
	return palette(hero_type).get("glow", Color.WHITE)

## 某个槽位的着色参数。`slot` ∈ body / outfit / hair / weapon。
static func slot(hero_type: String, slot_name: String) -> Dictionary:
	var slots: Dictionary = look(hero_type).get("skin_slots", {})
	return slot_params(slots.get(slot_name, {}))

## 队伍色：蓝方偏冷、红方偏暖，只压暗部（见 shader 里的 team_tint 口径）。
## 0.06~0.18 是实拍调出来的：再高帽子/披风就开始读成纯蓝/纯红。
static func team_tint(team: String) -> Color:
	if team == "red":
		return Color(1.32, 0.62, 0.56)
	return Color(0.86, 0.96, 1.28)

static func team_amount() -> float:
	return 0.16

# ---------------------------------------------------------------------------
# 服饰规格（纯数据，HeroCostume 消费）
# ---------------------------------------------------------------------------
#
# 每个英雄一组「大件」。字段：
#   key      唯一名（测试用来查重）
#   bone     挂靠骨骼（upperarm / clavicle / spine_03 / pelvis / Head …）
#   note     一句话说明它在剪影里的作用（也是给下一个模型读的注释）
#
# 具体的几何尺寸写在 HeroCostume 的 builder 里：这里只登记「有哪些件、挂在哪」，
# 测试因此可以断言「5 个英雄的大件两两不同、每人至少 3 件、且都挂在真实骨骼上」。

const COSTUME_PARTS := {
	"blade": [
		{"key": "blade_pauldron_r", "bone": "upperarm_r", "note": "右肩圆顶鳞甲 + 金环 + 外翻刺（重）"},
		{"key": "blade_pauldron_l", "bone": "upperarm_l", "note": "左肩薄皮甲（轻，不对称）"},
		{"key": "blade_cape", "bone": "spine_03", "note": "墨绿连帽披风（整片曲面 + 破边），俯视第一识别点"},
		{"key": "blade_belt", "bone": "pelvis", "note": "窄皮带 + 旧金方扣"},
		{"key": "blade_sash", "bone": "pelvis", "note": "腰侧两片垂布，跑动时摆"},
	],
	"mage": [
		{"key": "mage_skirt", "bone": "pelvis", "note": "敞口圆台长裙 + 金线压边 + 前开衩"},
		{"key": "mage_halo", "bone": "spine_03", "note": "背后竖立星环（缓慢自转），法师的远看标记"},
		{"key": "mage_crown", "bone": "Head", "note": "额前金月冠 + 星坠"},
		{"key": "mage_sleeves", "bone": "lowerarm_l", "note": "宽袖垂布（两侧同 builder）"},
		{"key": "mage_shoulders", "bone": "upperarm_l", "note": "双肩金月牙饰（两侧同 builder）"},
	],
	"tank": [
		{"key": "tank_pauldron_l", "bone": "upperarm_l", "note": "左肩青铜兽首重甲（圆顶 + 双琥珀眼 + 外角）"},
		{"key": "tank_pauldron_r", "bone": "upperarm_r", "note": "右肩铁札甲 + 外刺"},
		{"key": "tank_banner", "bone": "spine_03", "note": "背后锈橙战旗（杆 + 会飘的旗面）"},
		{"key": "tank_chest", "bone": "spine_02", "note": "胸口青铜兽面盘"},
		{"key": "tank_sash", "bone": "pelvis", "note": "腰间双条锈橙披巾 + 铜环"},
		{"key": "tank_tassets", "bone": "pelvis", "note": "四片铁札甲裙"},
	],
	"archer": [
		{"key": "archer_mantle", "bone": "spine_03", "note": "双肩白羽披肩（13 片参差羽）"},
		{"key": "archer_quiver", "bone": "spine_02", "note": "背后箭袋 + 三支带羽箭"},
		{"key": "archer_sash", "bone": "pelvis", "note": "左胯三根垂羽"},
		{"key": "archer_skirt", "bone": "pelvis", "note": "米白短下摆（四片）"},
		{"key": "archer_hairpins", "bone": "Head", "note": "双丸子头的白羽冠 + 青玉环"},
	],
	"assassin": [
		{"key": "assassin_hood", "bone": "Head", "note": "深色兜帽（后脑圆顶 + 背尖 + 颊片，正面留脸）"},
		{"key": "assassin_cloak", "bone": "spine_03", "note": "左侧三片紫斗篷（不对称）"},
		{"key": "assassin_scarf", "bone": "neck_01", "note": "颈间紫围巾 + 背后长尾"},
		{"key": "assassin_sheath", "bone": "pelvis", "note": "后腰双匕首鞘"},
		{"key": "assassin_pauldron", "bone": "upperarm_r", "note": "右肩薄钢护肩"},
	],
}

static func costume_parts(hero_type: String) -> Array:
	return COSTUME_PARTS.get(hero_type, [])

## 所有挂在骨骼上的件都必须用真实骨骼名，否则 BoneAttachment3D 静默不动。
const VALID_BONES := [
	"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r",
	"lowerarm_l", "lowerarm_r", "hand_l", "hand_r",
	"thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r",
]

static func is_valid_bone(bone_name: String) -> bool:
	return VALID_BONES.has(bone_name)

## 每个英雄的「身份色」摘要，用于测试断言 5 个人真的不同色。
static func identity_signature(hero_type: String) -> String:
	var p := palette(hero_type)
	return "%s|%s|%s" % [str(p.get("primary", Color.BLACK)), str(p.get("secondary", Color.BLACK)), str(p.get("glow", Color.BLACK))]

## 所有英雄共用的一档「皮肤」参数。
##
## 为什么必须单独一档：通用角色包的肤色贴图本身是暖橙（hue 0.07、sat 0.52），
## 在 FILMIC + 1.68 主光下会顶成一块发白的浅橙 —— 五个英雄都像「光膀子的白人」。
## 这里不换色相，只压亮度、提对比、加一点点暖边，让它接得住深色戏服。
## 眼睛（T_Eye）不在这一档里，永远保持原贴图。
const SKIN_SLOT := {
	"base": Color(0.62, 0.42, 0.31),
	"accent": Color(0.44, 0.26, 0.19),
	"accent_amount": 0.22,
	"recolor": 0.6,
	"contrast": 1.3,
	"lighting_keep": 0.9,
	"brightness": 0.52,
	"rim": Color(1.0, 0.84, 0.68),
	"rim_strength": 0.18,
	"roughness": 0.66,
	"metallic": 0.0,
	"specular": 0.18,
}

static func skin_slot() -> Dictionary:
	return slot_params(SKIN_SLOT)
