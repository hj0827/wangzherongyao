# 仓库真实结构 vs 文档描述

> 这份文件存在的原因：`docs/ARCHITECTURE.md` 描述的目录树是**目标态**，与实际代码**不一致**。
> 照文档去写，会写出没有任何地方引用的死代码。

---

## 1. 真实的运行时结构

```
godot/                          ← Godot 工程根（project.godot 在这层）
├── sim/                        ★ 真正的"逻辑核"，纯 RefCounted
│   ├── match_sim.gd            主仿真循环：tick、伤害、击杀、快照
│   ├── hero_defs.gd            4 个英雄的静态数值表
│   ├── skill_system.gd         技能施放 / 召唤师技能 / 被动
│   ├── economy_system.gd       ⚠️ 有实现有测试，**未接线**（见 §4）
│   ├── item_shop.gd            ⚠️ 同上
│   ├── combat_announcer.gd     ⚠️ 有实现有测试，**未接线**
│   ├── map_data.gd             基地坐标、分路边点、边界
│   ├── map_intel.gd            小地图点击查情报
│   └── map/                    collision / vision / tower_rules / wave_rules
│                               / jungle / objectives / recall / map_layout
├── net/                        联机：protocol / session / room / discovery
│   └── client_prediction.gd    ⚠️ 有实现有测试，**未接线**
├── scripts/
│   ├── app/main.gd             ★ 应用壳：菜单、选人、建房、进战斗（1200+ 行）
│   ├── game/                   ★ 实际的 view 层
│   │   ├── arena.gd            1900+ 行，承担相机/单位同步/特效/指示器/输入
│   │   ├── unit_visual.gd      单位装配 + 骨骼动画 + 血条
│   │   ├── map_view.gd         ✅ 地图表现，**唯一真正接线的新模块**
│   │   ├── input_assist.gd     键鼠/触控 → 战局方向向量
│   │   └── match_menu.gd       暂停菜单文案与状态判断
│   ├── ui/                     ★ 实际的 ui 层：hud / minimap / skill_button
│   │   │                       / touch_joystick / touch_layout / game_theme
│   │   │                       / depth_card / cinematic_background
│   │   ├── targeting_system.gd     ⚠️ 锁敌/补刀/推塔优先级，**未接线**
│   │   ├── skill_indicator.gd      ⚠️ 技能指示器，**未接线**
│   │   └── cancel_cast_zone.gd     ⚠️ 取消施法区，**未接线**
│   ├── view/hit_stop_manager.gd    ⚠️ 顿帧，**未接线**
│   ├── core/                   ⚠️ 只有 README.md，**空壳**
│   └── infra/                  ⚠️ 只有 README.md，**空壳**
├── shaders/billboard_bar.gdshader   血条/蓝条自定义 billboard
├── scenes/                     只有 main_menu.tscn 与 preview.tscn
├── tests/                      test_*.gd + test_base.gd + run_tests.gd
├── tools/                      截图 / 性能 / 资源巡检 / 设备验收
├── assets/                     运行时资产（入库）
└── build/                      导出产物（不入库）
```

> 标 ⚠️ 的都是"文件在、测试绿、但生产代码没引用"的模块，详见 §4。这份树会变，以 `git status` 与实测为准。

---

## 2. ARCHITECTURE.md 说的 → 实际在哪

| ARCHITECTURE.md 的位置 | 实际文件 |
| --- | --- |
| `core/sim/match_sim.gd` | `godot/sim/match_sim.gd` |
| `core/combat/`（碰撞/伤害/护盾） | `godot/sim/skill_system.gd` + `sim/map/collision.gd` + `sim/map/tower_rules.gd` |
| `core/entities/hero_defs.gd` | `godot/sim/hero_defs.gd` |
| `core/map/map_data.gd` | `godot/sim/map_data.gd` + `sim/map/map_layout.gd` |
| `view/camera/`、`view/units/`、`view/combat/`、`view/indicators/`、`view/effects/` | **全部**在 `godot/scripts/game/arena.gd` 与 `unit_visual.gd` 里，没有拆目录 |
| `ui/hud/`、`ui/screens/`、`ui/popups/` | `godot/scripts/ui/*`（平铺，没有 hud/screens 子目录） |
| `infra/pool/` | **没有独立池类**。池内联在 `arena.gd`：`_minion_pool_blue/_red`、`_damage_labels_pool`、`_hit_particles_pool` |
| `infra/audio/` | **不存在**。全项目零音频（见 `05-ui-and-feel.md`） |
| `infra/input/` | `godot/scripts/game/input_assist.gd` |
| `app/bootstrap.gd` | **不存在**。预热在 `arena._build_staged()` 与 `UnitVisual.warmup()` |

---

## 3. 两个必须知道的规模事实

- **`arena.gd` 1921 行**，是 ARCHITECTURE 铁律 5（单文件 ≤500 行，超 600 必须拆）的 3.8 倍。
  往里加功能前先想清楚：**要不要顺手拆**。继续堆会让"改一处连带改几处"的半径越来越大。
- **`main.gd` 1264 行**，同样超标。菜单/选人/联机大厅/进战斗全在一个文件里。

---

## 4. ★ 本仓库最大的坑：已实现 / 已测试 / **未接线**

> 这一节比整份文档其他部分都重要。

`docs/upgrades/README.md` 里那些模块，现在**文件都真的存在了，测试也真的全绿**——但它们的生产代码引用数是 **0**，只有自己的测试文件在引用。

也就是说：**功能写完了、测过了、没接进游戏。**

| 模块 | 非测试引用 | 状态 |
| --- | --- | --- |
| `scripts/ui/targeting_system.gd`（锁敌/补刀/推塔优先级） | **0** | sim 的 `_try_attack` 仍走老的 `_nearest_enemy`，没用它 |
| `scripts/ui/skill_indicator.gd`（技能指示器） | **0** | HUD 没挂 |
| `scripts/ui/cancel_cast_zone.gd`（取消施法区） | **0** | HUD 没挂 |
| `scripts/view/hit_stop_manager.gd`（顿帧） | **0** | arena 没调 |
| `sim/combat_announcer.gd`（多杀/团灭播报） | **0** | arena 没调 |
| `net/client_prediction.gd`（客户端预测） | **0** | arena 没调 |
| `sim/economy_system.gd`（金币） | **0** | hero 字典无 `gold` 字段，tick 不调 |
| `sim/item_shop.gd`（装备） | **0** | 无商店 UI |
| `scripts/game/map_view.gd`（地图表现） | 4 ✅ | **唯一真正接上的**（arena + minimap 在用） |

### 怎么自己验证（写任何"已完成"结论之前必须跑）

```bash
# 换成你要查的类名
grep -rn "EconomySystem" --include="*.gd" godot/scripts godot/sim godot/net
```

如果结果里**只有 `tests/`**，那这个模块就是没接线。不要因为"测试绿了"就认为它在跑。

### 为什么这很危险

227 个测试全绿 + 文档写着"已完成" + 文件确实存在 —— 三个信号都指向"做完了"，但游戏里一点效果都没有。

**这正是"测试绿 ≠ 做完了"的具体形态。**

---

## 5. 另一个已确认的事实：玩家只能放 Q/E

- `arena.gd` 的 `_local_input` 现在有 `move / aim / skill_q / skill_e / attack / recall` 六个键。
- **没有 `skill_w` / `skill_r` / `summoner`**，所以玩家按不出 W、R 和召唤师技能。
- 但 `match_sim._apply_human_inputs()` 会读这些键，`skill_system` 全部支持，bot AI 也在用。
- **结论：人机对战时，AI 比玩家多两个技能和一次闪现。**

`recall`（回城）已经接上了，是最近补的——说明"加输入键"这条路是通的，W/R 只是还没做。

---

## 6. 同名目录陷阱

`godot/assets/ui/`（美术资源）与 `godot/scripts/ui/`（代码）**同名不同层**。

写 `res://` 路径时写错一边，`load()` 返回 null 而不是报错（除非你显式 `ResourceLoader.exists()` 判断）。改资源路径前，先确认你要的是哪一个。
