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
│   ├── economy_system.gd       ✅ 已接线（自然金币/击杀/补刀/推塔/助攻）
│   ├── item_shop.gd            ✅ 已接线（商店 UI + 属性重算 + 快速购买）
│   ├── combat_announcer.gd     ✅ 已接线（多杀/一血/团灭事件）
│   ├── map_data.gd             基地坐标、分路边点、边界
│   ├── map_intel.gd            小地图点击查情报
│   └── map/                    collision / vision / tower_rules / wave_rules
│                               / jungle / objectives / recall / map_layout
├── net/                        联机：protocol / session / room / discovery
│   └── client_prediction.gd    ✅ 已接线（客机预测 + last_input_seq 对账）
├── scripts/
│   ├── app/main.gd             ★ 应用壳：菜单、选人、建房、进战斗（1200+ 行）
│   ├── game/                   ★ 实际的 view 层
│   │   ├── arena.gd            2500+ 行，承担相机/单位同步/特效/指示器/输入
│   │   ├── unit_visual.gd      单位装配 + 骨骼动画 + 血条
│   │   ├── map_view.gd         ✅ 地图表现，**唯一真正接线的新模块**
│   │   ├── bush_eye.gd         进草头顶斜划眼（程序化 96px 贴图 + 静态缓存）
│   │   ├── input_assist.gd     键鼠/触控 → 战局方向向量
│   │   ├── match_menu.gd       暂停菜单文案与状态判断
│   │   ├── audio_plan.gd       ✅ 事件→音效 cue 的纯逻辑（距离/节流/热度）
│   │   ├── audio_cues.gd       ✅ 38 条合成音效（无资源文件，现场生成 PCM）
│   │   ├── bgm_synth.gd        ✅ 程序化 BGM：菜单/战斗/强度层/胜利/失败
│   │   └── audio_director.gd   ✅ Node：10 声道池 + 音乐淡入淡出 + 暂停压低
│   ├── ui/                     ★ 实际的 ui 层：hud / minimap / skill_button
│   │   │                       / touch_joystick / touch_layout / game_theme
│   │   │                       / depth_card / cinematic_background
│   │   ├── hud_layout.gd           ✅ 常驻 HUD 分区的唯一坐标源（桌面/触屏），纯数据可测
│   │   ├── targeting_system.gd     仅转发 sim/targeting_rules.gd（生产直接走 sim 侧）
│   │   ├── skill_indicator.gd      ✅ 已接线（HUD 技能指示器/触摸拖拽）
│   │   ├── cancel_cast_zone.gd     ✅ 已接线（HUD 取消施法区）
│   │   └── debug_panel.gd          ✅ 已接线（F3 开发者面板，只主机可作弊）
│   ├── view/hit_stop_manager.gd    ✅ 已接线（arena 顿帧 + 震屏）
│   ├── core/                   ⚠️ 只有 README.md，**空壳**
│   └── infra/                  ⚠️ 只有 README.md，**空壳**
├── shaders/billboard_bar.gdshader   血条/蓝条自定义 billboard
├── shaders/camp_sigil.gdshader      营地/首领坑贴地旋转符阵（随野怪存活亮暗）
├── scenes/                     只有 main_menu.tscn 与 preview.tscn
├── tests/                      test_*.gd + test_base.gd + run_tests.gd
├── tools/                      截图 / 性能 / 资源巡检 / 设备验收
├── assets/                     运行时资产（入库）
└── build/                      导出产物（不入库）
```

> 这份树会变，以 `git status` 与实测为准。2026-10-23 已完成一轮"文档说做了但实际没接线"的清理，§4 记录历史与当前接线位置。

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
| `infra/audio/` | **不存在**。音频在 `scripts/game/`：`audio_plan.gd`（纯逻辑映射）/ `audio_cues.gd`（音效合成）/ `bgm_synth.gd`（BGM 合成）/ `audio_director.gd`（Node 声道池），见 `05-ui-and-feel.md` §9 |
| `infra/input/` | `godot/scripts/game/input_assist.gd` |
| `app/bootstrap.gd` | **不存在**。预热在 `arena._build_staged()` 与 `UnitVisual.warmup()` |

---

## 3. 两个必须知道的规模事实

- **`scripts/game/arena.gd` 3921 行**，是 ARCHITECTURE 铁律 5（单文件 ≤500 行，超 600 必须拆）的近 8 倍。
  往里加功能前先想清楚：**要不要顺手拆**。继续堆会让"改一处连带改几处"的半径越来越大。
- **`scripts/app/main.gd` 1459 行**，同样超标。菜单/选人/联机大厅/进战斗全在一个文件里。

---

## 4. ★ 历史坑：已实现 / 已测试 / **未接线**（2026-10-23 已清理）

> 这一节记录的是本仓库最危险的一类假完成。**现在这些模块都已接线**，但每次新增模块都要重新验证。

曾经 `docs/upgrades/README.md` 里的模块**文件存在、测试全绿、生产引用为 0**。也就是说：功能写完了、测过了、没接进游戏。

| 模块 | 当前生产引用 | 接线位置 |
| --- | --- | --- |
| `sim/targeting_rules.gd`（锁敌/补刀/推塔） | ✅ | `match_sim._try_attack()` |
| `scripts/ui/targeting_system.gd` | 仅测试 | 生产直接走 sim 侧规则；此文件只是转发层 |
| `scripts/ui/skill_indicator.gd`（技能指示器） | ✅ | `scripts/ui/game_hud.gd` 触摸拖拽瞄准 |
| `scripts/ui/cancel_cast_zone.gd`（取消施法区） | ✅ | `scripts/ui/game_hud.gd` 拖拽取消 |
| `scripts/ui/hud_layout.gd`（HUD 分区表） | ✅ | `game_hud._apply_layout()` / `main.gd` 窗口下限 |
| `scripts/view/hit_stop_manager.gd`（顿帧） | ✅ | `scripts/game/arena.gd` |
| `sim/combat_announcer.gd`（多杀/团灭播报） | ✅ | `match_sim._kill_entity()` → `arena._process_events()` |
| `net/client_prediction.gd`（客户端预测） | ✅ | `arena._update_local_prediction()` / `_reconcile_local_prediction()` |
| `sim/economy_system.gd`（金币） | ✅ | `match_sim._update_hero_timers()` / `_kill_entity()` |
| `sim/item_shop.gd`（装备） | ✅ | `match_sim` + `scripts/ui/shop_panel.gd` |
| `scripts/ui/attack_cluster.gd`（攻击键簇） | ✅ | `scripts/ui/game_hud.gd` |
| `scripts/game/map_view.gd`（地图表现） | ✅ | `arena` + `minimap` |
| `scripts/game/audio_plan.gd` + `audio_cues.gd` + `bgm_synth.gd` + `audio_director.gd`（音频） | ✅ | `main.gd` 建导演并传 `configure({"audio": ...})`；`arena._build_audio()` / `_process_events()` / `_open_pause()` |

### 怎么自己验证（写任何"已完成"结论之前必须跑）

```bash
# 换成你要查的类名
grep -rn "EconomySystem" --include="*.gd" godot/scripts godot/sim godot/net
```

如果结果里**只有 `tests/`**，那这个模块就是没接线。不要因为"测试绿了"就认为它在跑。

### 为什么这很危险

测试全绿 + 文档写着"已完成" + 文件确实存在 —— 三个信号都指向"做完了"，但游戏里一点效果都没有。

**这正是"测试绿 ≠ 做完了"的具体形态。**

---

## 5. 玩家输入与联机字段现状

- `arena.gd` 的 `_local_input` 已覆盖：`move / aim / skill_q / skill_w / skill_e / skill_r / summoner / attack / attack_mode / locked_target / recall / teleport / buy_item / sell_slot / seq`。
- 全部输入键都已进 `net/net_protocol.gd` 的 `sanitize_input()`，联机不会静默吞键。
- 英雄快照与实体白名单已覆盖 W/R/召唤师冷却、金币、装备、AP、暴击、`revealed_timer`、`last_input_seq`。
- 单机/主机也走战争迷雾：`arena.current_snapshot = sim.snapshot_for(local_team)`；客机由服务端按队伍过滤后下发。
- 客机移动使用本地预测，服务端通过 `last_input_seq` 回执校正；大误差瞬移、小误差平滑衰减。

加新输入键仍按 `04-combat-chain.md` 的 5 处清单改，少一处就是"按了没反应"。

---

## 6. 同名目录陷阱

`godot/assets/ui/`（美术资源）与 `godot/scripts/ui/`（代码）**同名不同层**。

写 `res://` 路径时写错一边，`load()` 返回 null 而不是报错（除非你显式 `ResourceLoader.exists()` 判断）。改资源路径前，先确认你要的是哪一个。
