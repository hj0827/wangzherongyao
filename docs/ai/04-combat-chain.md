# 战斗字段与输入键的改动链路

> 只在"给英雄加字段 / 加技能 / 加输入键 / 改数值"时读这份。
> 这份文件的存在意义：**这个项目里"改一处"几乎永远不够，漏改的地方不会报错。**

---

## A. 给英雄加一个字段（如 `gold`、`stacks`、`shield_timer`）

按顺序改这 6 处，缺一处就静默失效：

| # | 位置 | 做什么 | 漏了会怎样 |
| --- | --- | --- | --- |
| 1 | `sim/match_sim.gd` → `_spawn_hero()` | 在 hero 字典里初始化该字段 | 读到 `null` → `float(null)` = `0.0`，**不报错** |
| 2 | `sim/match_sim.gd` → `_update_hero_timers()` 或对应 `_update_*` | 每 tick 递减/累加 | 值永远不变（CD 不转、计时器不走） |
| 3 | `sim/match_sim.gd` → `_snapshot_entity()` 的 `if entity.type == "hero"` 分支 | 把字段写进快照 | view 与 HUD 永远读不到 |
| 4 | `net/net_protocol.gd` → `_sanitize_entity()` 的 `if type == "hero"` 分支 | 加进白名单 + 范围钳制 | **只在联机丢**，单机正常 |
| 5 | `scripts/game/unit_visual.gd` → `set_snapshot()` | 表现层消费（动画/血条/颜色） | 数值对但表现不变 |
| 6 | `scripts/ui/game_hud.gd` → `update_snapshot()` | UI 消费（数字/图标/进度条） | 玩家看不到 |

### 第 1 步的写法约定

hero 字典是**无类型的 `Dictionary`**，没有 schema 校验。新字段紧跟同类字段放，并给默认值：

```gdscript
"shield": 0.0,
"shield_timer": 0.0,
"gold": 0,              # 新增：紧跟同类资源字段
"gold_fraction": 0.0,   # 小数部分单独存，避免每 tick 取整丢精度
```

### 第 4 步的写法约定

白名单不是简单 `entity["x"] = source["x"]`，而是**带钳制**。照着已有行抄：

```gdscript
entity["skill_q_cd"] = clampf(_number(source.get("skill_q_cd", 0.0)), 0.0, 600.0)
entity["gold"] = clampi(int(_number(source.get("gold", 0))), 0, 1000000)
```

**当前状态**：`skill_w_cd`、`skill_r_cd`、`summoner_cd`、`summoner_spell` 均已加入 `_sanitize_entity`，联机客机能看到 W/R 冷却与召唤师技能。再新增英雄字段时仍按上表 6 处逐一检查。

### 加"金币"这类新资源字段时

`sim/economy_system.gd` 与 `sim/item_shop.gd` 已完成接线（自然跳钱、补刀/击杀/推塔收益、购买/出售、属性重算、商店 UI）。新增资源字段时不要重新设计，直接按 §A 的 6 处挂上去，并同步 `_sanitize_entity` 与快照字段。

---

## B. 加一个玩家可用的输入键（如 `skill_w`）

同样 5 处，缺一处就是"按了没反应"：

| # | 位置 | 做什么 |
| --- | --- | --- |
| 1 | `scripts/game/arena.gd` → `_local_input` 字典 | 加键，默认 `false` |
| 2 | `scripts/game/arena.gd` → `_gather_input()`（键鼠）/ `_gather_touch_input()`（触控） | 赋值 |
| 3 | `net/net_protocol.gd` → `EMPTY_INPUT` + `sanitize_input()` | 加键 + `_flag()` 清洗 |
| 4 | `scripts/ui/game_hud.gd` → `_build_bottom_panel()` / `_build_touch_controls()` | 创建按钮并连到 `skill_pressed` |
| 5 | `scripts/ui/touch_layout.gd` → `SKILL_ARC_ANGLES_DEG` | 触控弧形排布角度（现在是 `[185.0, 210.0, 235.0, 260.0]` 四个位） |

### 输入从按下到生效的完整路径

```
按键/触屏
  → arena._gather_input()         写入 _local_input
  → sim.set_input(owner, input)   每个 tick 前提交
  → match_sim._apply_human_inputs()  读 input["skill_x"]
  → SkillSystem.cast_skill()
  → sim._emit("skill", {...})
  → arena._process_events()       表现层响应
  → hud.update_snapshot()         按钮进入 CD
```

**关键**：`_apply_human_inputs` 用 `input.get("skill_w", false)` 读键。键不存在时返回 `false`，所以**永远不会报错，只是没反应**。这是本项目最容易踩的静默坑。

### 当前状态（2026-10-23 实测）

- `_local_input` 已覆盖：`move / aim / skill_q / skill_w / skill_e / skill_r / summoner / attack / attack_mode / locked_target / recall / teleport / buy_item / sell_slot / seq`。
- 桌面与触控两条输入路径都已赋值；触控技能键支持按下→拖拽瞄准→松手施放，拖到取消区则中断。
- `net/net_protocol.gd` 的 `EMPTY_INPUT` / `sanitize_input()` 已同步全部字段，联机不会再静默吞键。
- 金币、装备、购买/出售也已走同一条输入链路（`buy_item` / `sell_slot`，可靠通道 + 序号去重）。

### 攻击目标选择：sim 侧统一裁决

`match_sim._try_attack()` 已调用 `sim/targeting_rules.gd` 的 `resolve_attack_target()`，支持：

- 默认智能索敌（英雄优先）
- 补刀模式（小兵优先）
- 推塔模式（建筑优先）
- 头像锁定（`locked_target`，死亡/超距自动失效）
- 轮盘拖拽索敌（`attack_drag` 方向筛选）

`scripts/ui/targeting_system.gd` 只是转发同一份规则，生产代码直接走 sim 侧，避免双实现漂移。

---

## C. 改数值 / 平衡性

数值都在 `sim/hero_defs.gd` 的 `HEROES` 字典里，纯数据，改完直接生效，不用碰逻辑。

- 英雄：`max_hp / hp_growth / attack_damage / damage_growth / speed / attack_range / attack_interval`
- 技能：`cost / cooldown / range / damage / kind`
- `kind` 决定技能形状，`skill_system.gd:cast_skill()` 里 `match kind` 分支消费：
  `slash / spin / dash / leap_slam / burst / line / slow / meteor_storm / quake / charge / shield / taunt_aura / arrow / aoe_shot / haste / arrow_barrage`

**加一个新 `kind`** 必须同时在 `cast_skill()` 的 `match` 里加分支，否则走 `_:` 默认分支（单体伤害），表现会变成"技能没特效但掉了血"。

全局常量在 `match_sim.gd` 顶部：

```gdscript
const TICK_RATE := 30.0
const HERO_RESPAWN_BASE := 6.0      # 复活 = 6 + level * 0.4，满级 12s
const WAVE_INTERVAL := 18.0
const MAX_LEVEL := 15
const FIELD_HP_REGEN := 0.025
const FOUNTAIN_HP_RATE := 0.18
```

改这些会影响所有英雄，改完必须跑 `test_match` 与 `test_global_integrity`。

---

## D. 加一个英雄

1. `sim/hero_defs.gd` → `HEROES` 加一项（含 `passive/q/w/e/r`、`video_path`）
2. `sim/hero_defs.gd` → `BOT_TYPES` 如果要让 AI 也会用
3. `scripts/app/main.gd` → `HERO_ORDER` 加进去（选人界面才显示）
4. `assets/ui/portraits/<type>.png` 立绘 + `assets/ui/hero_videos/hero_<type>.ogv` 选人视频
5. `scripts/ui/game_theme.gd` → `portrait_path()` 能拼出路径
6. `scripts/game/arena.gd` → `_hero_vfx_color()` 加一个配色，否则特效颜色落到默认分支
7. 写 `tests/test_hero_readout.gd` 风格的断言：满级数值、技能 CD、射程
8. **打包前确认 `export_presets.cfg` 的 `include_filter` 覆盖 `*.ogv`**

漏第 6 步：英雄能玩，但所有技能特效是同一个颜色——不报错。
