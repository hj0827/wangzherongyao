# UI、手感与表现层

> 只在"改 HUD / 触控布局 / 特效 / 打击感 / 播报"时读这份。

---

## 1. 文件分工

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/ui/game_hud.gd` | 局内全部 2D：顶栏、小地图、底栏、技能键、商店/播报、死亡/结算/暂停遮罩 | 1314 行 |
| `scripts/ui/minimap.gd` | 小地图绘制（206×206）+ 英雄圆形头像 + 点击查情报 | 574 行 |
| `scripts/ui/skill_button.gd` | 单个技能键（CD 扇形遮罩、法力不足、禁用态、触摸拖拽） | 245 行 |
| `scripts/ui/shop_panel.gd` | 商店面板：购买/出售/快速购买、金币显示 | 283 行 |
| `scripts/ui/attack_cluster.gd` | 攻击键簇：补刀/推塔模式切换、头像锁敌 | 188 行 |
| `scripts/ui/touch_joystick.gd` / `touch_action_button.gd` | 摇杆 / 圆形动作键 | 150 / 156 行 |
| `scripts/ui/touch_layout.gd` | 触控尺寸与弧度的**唯一常量源** | 136 行 |
| `scripts/ui/hud_layout.gd` | 常驻 HUD 分区的**唯一坐标源**（桌面/触屏两套），纯数据、可无头测 | 158 行 |
| `scripts/ui/game_theme.gd` | 配色、字体、StyleBox | 203 行 |
| `scripts/game/arena.gd` | 3D 表现：相机、特效、飘字、震屏、指示环、输入 | 3921 行 |
| `scripts/game/unit_visual.gd` | 单位装配、骨骼动画、头顶血条、野怪名牌、草丛斜划眼 | 917 行 |
| `scripts/game/bush_eye.gd` | 进草「不可见」标记：96px 斜划眼，逐像素生成 + 静态缓存 | 74 行 |
| `scripts/ui/debug_panel.gd` | 开发者调试面板（F3 / 触控 DEV）：时间倍率/暂停/作弊开关/运行指标 | 304 行 |

---

## 2. HUD 分区（`hud_layout.gd` 是唯一坐标源）

**不要再在 `game_hud.gd` 里给常驻面板手写 anchor/offset。** 所有常驻分区都由 `scripts/ui/hud_layout.gd` 的 `zones(viewport, touch)` 算出来，`game_hud._apply_layout()` 只负责把节点按分区摆上去；`resized` 会自动重算。

桌面 1600×900 的实际分区：

| 分区 | 位置 / 尺寸 | 说明 |
| --- | --- | --- |
| `minimap` | (16,16) 234×256 | 小地图 + 目标计时。拖动说明改成悬停提示，不再常驻两行字 |
| `score` | 居中 (570,16) 460×80 | 蓝方 / 计时 / 红方 + 波次 |
| `shop` | 右上 (1434,16) 150×56 | 商店 |
| `feed` | 右上 (1264,76) 320×132 | 击杀播报，**退到商店下面**（以前两者压在一起） |
| `bush` | 居中 (640,102) 320×26 | 草丛隐匿提示（瞬时，不占常驻契约） |
| `hero` | 左下 (16,732) 640×152 | 头像 / 名字 / 血蓝 / 击杀 / 金币 |
| `hints` | 左下 (16,698) 840×24 | 键位提示，**进场 14s 后淡出**，Esc 菜单里能再查 |
| `skills` | 右下 (1072,772) 512×112 | 5 个技能键，96×112，间距 8 |
| `mode` | 右下 (1072,680) 512×84 | 攻击模式 + 锁敌，与技能条左边缘对齐 |

三条硬约束（`tests/test_hud_layout.gd` 会逐条抓，多个窗口尺寸都跑）：

1. 任意两个常驻分区**不许相交**；
2. 中央视野安全区（`SAFE_CENTER`：横向 27%~73%、纵向 14%~68%）里**不许有常驻 HUD**——那里是兵线交汇、敌人出现、自己站位的地方；
3. 所有分区留在 16px 安全边距内。

**分区尺寸必须 ≥ 控件的真实最小尺寸**，否则 `PanelContainer` 会被内容顶大、向外压住邻居，而按分区表算的测试还查不出来（这是本次修的第一批 bug）。量真实矩形：

```cmd
godot --path godot --script res://tools/probe_hud_rects.gd
```

已量到的值：比分板 77 高、英雄卡 149 高、商店按钮 53 高、小地图面板 248 高、攻击模式条 84 高（两行 30 + 内边距）。`test_zone_sizes_cover_the_measured_minimum_sizes` 把这些数钉住了。

窗口下限 `MIN_VIEWPORT = 1280×720`（`main.gd` 设成窗口 `min_size`）：1600×900 的设计稿再缩小就掉到 0.7 倍以下，14px 说明文字实机只剩 9px。

触屏的技能弧与摇杆尺寸仍归 `touch_layout.gd`；`hud_layout` 只补摇杆/状态卡/攻击模式条的位置。

---

## 2.1 键位提示

`KEY_HINTS` 只在 `_build_hints()` 里出现一次，`show_pause()` 里也复用同一份字符串。它**不是常驻 UI**：进场 `HINT_SECONDS = 14` 秒后淡出，窄窗口下宽度按 `hint_width()` 收窄并用省略号收尾（`clip_text`），避免伸到右下操作簇底下。

---

## 2.2 小地图英雄头像

`minimap.gd` 的 `hero_avatar()` 把立绘裁到头部（`HERO_FACE_CROP`，必须是正方形）→ 缩到 64² → 圆形遮罩 → 静态缓存，`_draw()` 每帧只做查表。关系色画在头像外圈（自己绿 / 友军蓝 / 敌军红），本地英雄额外加一道同色细环（`hero_facing_tab()` 画朝向）；朝向由贴在环外的小三角表示。快照里 `hero_type` 缺失/未知时返回 `null`，回落到关系色箭头——**不要画空图**。

---

## 2.3 小地图朝向

小地图永远是「**自家基地左下、敌方基地右上**」，并且和画面同向：屏幕上方 = 镜头前方，屏幕右侧 = 镜头右方。

世界坐标不直接铺到图上，要先过 `Minimap.oriented(world, local_team)`：蓝方相机朝世界 +Y 看、屏幕右是 -X，所以蓝方整张图转 180°；红方的世界轴本来就对得上，不转。`world_to_screen` / `screen_to_world` / `screen_to_world_clamped`、英雄朝向箭头、`map_frame()` 必须**全部**走这一个函数——漏掉哪一处，点击就会落到镜像位置，或者箭头指着反方向。`test_minimap_orientation.gd` 把「两家基地位置 / 轴与相机一致 / 点击往返 / 边框尺寸」都钉住了。

边框用 `map_frame()` 取内框，**不要再拿「世界左上角 / 右下角」两个点算矩形**：翻转后这两个点会互换，围出来的矩形是负尺寸，整条墙带都画不出来。

---

## 2.4 相机与边界墙

三份数据决定贴墙时看到什么，改任何一份都会改变观感：

| 位置 | 作用 | 硬约束 |
| --- | --- | --- |
| `arena.CAMERA_PITCH_UP/BACK`（0.94 / 0.76） | 机位：注视点上方 `0.94×zoom`、身后 `0.76×zoom`，俯角 51° | 相机位置与 `look_at` 必须吃**同一个 target**，否则相位差 = 抖 |
| `camera_focus.gd` | 注视点的唯一真身（刚性跟英雄 / 观察态滑行） | 常态分支不许叠 lerp |
| `camera_edge.gd` | 贴到可走边界时把注视点往地图中心推 | **只动相机，不动可走边界** |

`MapData.CAMERA_WALL_MARGIN = 3.8` 是**模拟层**的可走边距：英雄离墙内表面至少 4.35 米。
它不是观感参数，是「相机在墙外时不至于被墙挡住自己」的物理下限，`test_wall_occlusion.gd`
按 zoom 14/21/34 三个档位验视线高过墙顶。**不要为了让英雄「更贴墙」去调小它** ——
要贴墙感就改 `camera_edge.gd` 的内推量。

内推的两个关键取值（都有实测依据，别凭手感改）：

- `EDGE_INSET_RATIO = 0.24`（×zoom ≈ 5 米）：左右两侧墙外草地基本收干净，英雄偏到画面 60~70% 处。
- `EDGE_SPAN = 4.0`：边路中心在 `|pos| = 50`、可走极限 53.65，过渡带一旦宽到十几米，
  **沿边路正常走路时画面会一直往内偏**。4 米让边路行走只偏 0.1 米。
- `NEAR_INSET_SCALE = 0.0`：相机后方那面墙不内推。实测推 1.8 米后，墙外草地只少 30px，
  但墙的立面反而更高（相机离墙更远、视线更平），英雄还被从墙边拽开 50px —— 三项全变差。

墙外**地形与水面**一起渐隐（`ArenaLook.OUTSIDE_*`，公式只允许出现在 `arena_look.gd`）：

- 起点是 `MapData.BOUNDS`（= 城墙内表面），用切比雪夫距离 `max(|x|,|z|)`，与方形城墙同口径；
- `OUTSIDE_BASE = 0.55`：墙根处**已经**压掉一半。从 0 开始渐变是错的 —— 画面里看到的墙外
  恰恰是墙脚下最近那一圈，从 0 起意味着最该退后的那块是全场最亮的；
- 两个 shader 都通过 `ArenaLook.apply_outside_fade()` / `bind_outside_fade()` 拼接，
  `test_outside_fade.gd` 会抓「占位符没替换」和「某一边偷偷抄了一份公式」。

验证手段：`tools/probe_wall_sides.gd` 把英雄摆到四面墙的可走极限各拍一张
（`shots/wall_side_*.png`，过程文件不入库）。

---

## 3. 表现层的三个硬约束

1. **只能读快照**：`set_snapshot()` 里不许回写 `hp`、不许触发结算。
2. **高频对象走池**：飘字、粒子、范围环、弹道必须从 `_damage_labels_pool` / `_hit_particles_pool` / `_ring_pool` 取，用完 `visible=false` 放回，**不要 `queue_free()`**。
3. **事件驱动，不要轮询**：一次性表现（技能、击杀、塔毁）挂在 `_process_events(events)` 的 `match` 分支里，不要每帧扫描状态变化。

---

## 4. 现有反馈手段与具体数值

| 手段 | 位置 | 现状 |
| --- | --- | --- |
| 伤害飘字 | `arena._spawn_damage_number()` | 只有数字；`amount >= 150` 金色，否则近白；上飘 0.9、0.65s 淡出 |
| 命中粒子 | `_handle_hit_event()` | 英雄 10 颗，小兵/建筑 4 颗 |
| 普攻特效 | `_handle_minion_attack()` / `_handle_monster_attack()` / `_handle_structure_attack()` | 三者共用纯函数 `attack_fx_plan()` 的配方，由 `shape` 分派：`arc`（近战兵/超级兵/野怪爪光）、`slam`（BUFF 石像/首领砸地）、`orb`（远程兵/炮车）、`splash`（河道之灵）、`lance`（塔）。走 `_slash_pool` / `_tracer_pool` / `_ring_pool` / `_lance_pool` / `_spawn_decal`，**战斗期零分配** |
| **野怪普攻** | `_handle_monster_attack()` | 2026-11-11 新增。**在此之前野怪不出手事件**，表现层只能从 `hit` 的 `source` 反推一次前倾，打野时怪一动不动。现在 sim 每次出手发 `monster_attack`（带 `monster_type / camp_id / buff_type / objective`，已进 `_sanitize_event` 白名单），配方按物种分：狼双爪、猪扬土、蜥蜴突咬、红鸟双击、石像砸地、河道之灵水花、首领地裂。详见 §4.2 |
| 英雄普攻 | `_handle_hero_attack()` | 配方是纯函数 `hero_attack_fx_plan()`：攻击距离 < `HERO_RANGED_REACH`(4.0) 的近战英雄挥一片新月刀光（`_slash_pool`，12 片），远程英雄打一条弹道 + 枪口小闪；暴击只放大不改形态（更亮、火星更多、带一点震屏） |
| 震屏 | `_camera_shake` + `_hit_stop` | 受击 `0.12`、坦克技能 `0.18`；顿帧触发时附加击退感 shake |
| 顿帧 | `scripts/view/hit_stop_manager.gd` | 暴击/击杀/破塔/破盾/终局分别触发；只冻结表现层，模拟与网络照常 |
| 范围环 | `_spawn_ring()` / `_flash_skill_range()` | 技能命中/施放时闪一次；触摸拖拽时由 `SkillIndicator` 实时绘制 |
| 技能指示器 | `scripts/ui/skill_indicator.gd` | 触摸按下技能键后显示圆形/直线/扇形指示，松手施放 |
| 取消施法区 | `scripts/ui/cancel_cast_zone.gd` | 触摸拖拽到屏幕上方取消区，松手中断施法 |
| 弹道/光束 | `_spawn_tracer()` / `_spawn_lance()` | 法师/射手技能、塔攻击、英雄普攻共用同一批池节点。**2026-11-11 起技能链路不再 `new` 弹丸/光束**：旧的 `_spawn_projectile()` / `_spawn_beam()` 是战斗期 `MeshInstance3D.new()` + `queue_free()`（违反硬规则 4），已删除 |
| 技能签名 | `skill_fx.gd` 的 `recipe(kind)` + `arena._spawn_skill_fx()` | 17 个 `kind` 各有独立的形状/节奏轴：粒子贴图（spark/smoke/glow/rune/slash/shock）、粒子尺寸、延迟二次爆（`_fx_queue`）、竖直环（`ring.tilt`）、落点刀光（`arc`）、地面残留贴图/大小（`decal`）、渐宽光束（`beam_taper`）。`signature` 是给人读的名字，`signature_axes()` 是给测试读的机指纹 |
| 播报 | `hud.announce()` | 中央横幅，0.18s 淡入 → 停留 → 0.4s 淡出 |
| 多杀/一血/团灭 | `sim/combat_announcer.gd` → `arena._handle_death_event()` | 双杀/三杀/四杀/五杀/终结/团灭/一血，两端看到同一份结果 |
| 战报 | `hud.add_feed()` | 右上滚动 6 条，4.5s 后淡出 |
| 死亡遮罩 | `_build_death_overlay()` | 全屏红 48% + 复活倒计时 + 击杀者名 |
| **防御塔分级外观** | `tower_visual.gd` 的 `TIER_STYLES` + `tier_style(tier)` | 外/内/高地/双子塔的**塔冠肋数**（6/7/8/5）、**肋顶宝珠**（0/3/6/2）、**石箍圈数**（3/4/5/2）、高地塔独有的**塔冠金箍**。`TowerVisual.build(team_color, tier)` 必须收到 tier —— 只靠 `visual_scale`（1.00/1.07/1.16/0.92）在 21m 机位下读不出层级 |
| **塔开火反馈** | `_handle_structure_attack()` → `_pulse_tower_fire()` → `_apply_tower_fire()` | 核心闪亮（`emission × up to 1.85`）、光环涨一圈、塔身约 2.2° 后坐；`TOWER_FIRE_SECONDS = 0.26` 内一起衰减并**精确复位**。只改已有材质与变换，不新建节点 |
| **塔低血残破** | `_apply_tower_damage()` + `TowerVisual.damage_tone()` | 血量低于 `DAMAGE_THRESHOLD = 0.55` 起：石料压暗、裂纹显隐、核心变弱。回满血会复原（复活/调试不会留下永久黑塔） |
| **塔摧毁演出** | `_start_structure_collapse()` → `_advance_tower_collapse()` | 收到 `tower_destroyed` / `guard_destroyed` 后塔先倾斜 16° + 下沉 0.55m（`TOWER_COLLAPSE_SECONDS = 0.55`），演完才交出残骸；**没有事件时走旧路径**（客机先收到快照也不会卡在"倒一半"） |

**运行时仍然没有的东西**（写新反馈时别去找）：击退、护盾吸收飘字、治疗飘字、低血量屏幕边缘红晕、加速风线、免控可视。
（受击闪白已于 2026-11-10 落地：`unit_visual.gd` 的 `HitFlash` 节点 + `play_hit()`；特效的**显示机制**——分层/可见性/同屏预算/配方契约——见 [`../特效升级-对标王者荣耀.md`](../特效升级-对标王者荣耀.md）。）

### 4.2 野怪 / 小兵普攻（2026-11-11 升级）

改之前的三处「看不见」：

1. **野怪根本没有攻击事件**。`_update_monsters()` 只结算伤害，表现层只能从 `hit` 的 `source`
   反推「有东西打了我」→ 打野时野怪一动不动、没有爪光、没有音效，玩家读不出「它在还手」。
2. **近战兵画的是飞过去的小球**。近战兵打近战兵也是，兵线对拼时满屏小球，读不出「谁在砍谁」。
3. **`smoke` 贴图在生产代码里 0 引用**（差距文档 §3 D5）——野怪扬尘只能用火星凑。

现在 **sim 与渲染层各改一处**：

| 层 | 改动 |
| --- | --- |
| `sim/match_sim.gd::_update_monsters()` | 出手时发 `monster_attack`，字段与 `minion_attack` 同构 + `monster_type / camp_id / buff_type / objective / objective_id` |
| `net/net_protocol.gd::_sanitize_event()` | 上述 4 个新键进白名单（漏一个 = 客机看到「血在掉、怪没动」） |
| `arena.attack_fx_plan()` | 按 `shape` 出配方；`reach` 由**真实目标距离**算（写死半径会让近身挥出两米长的光） |
| `arena._play_unit_attack_fx()` | 小兵与野怪的**唯一**渲染入口；`shape` 分派，全部走池 |
| `unit_visual.play_attack()` | 狼播骨骼 `Attack`，程序化形态靠前冲；`_attack_lunge_strength` 按体型放大（只升不降，见下） |
| `audio_plan` / `audio_cues` | `monster_swipe`（挥爪，短噪声）/ `monster_slam`（首领砸地，低频+碎石） |

**五种野怪的出手必须能分辨**（`test_monster_attack_fx` 逐条钉住）：

| 物种 | shape | 记忆点 |
| --- | --- | --- |
| 狼（兜底） | `arc` ×2 | **双爪**交错：两片弧比一片更粗的弧更像一次扑咬 |
| 三猪 | `arc` ×1 | 单爪宽弧（108°）+ 扬土 |
| 蜥蜴 | `arc` ×1 | 窄（76°）、贴地 0.62m、几乎不起土 |
| 红鸟 | `arc` ×2 | 最宽（120°）、节奏最短 |
| BUFF 石像 | `slam` | 整块砸下 + 冲击环 + 法阵残留，红/蓝各自配色 |
| 河道之灵 | `splash` | 一圈水花，**不是爪光**（水系生物画成爪痕会被读成野狼） |
| 暴君 / 主宰 | `slam` | 最长震屏（0.18）+ 地裂残留（`shock`）+ 14 颗命中火星 |

**三个必须知道的坑**：

1. **前冲力度只升不降**。同一次出手会先后到达两条事件：`monster_attack`（野怪 2.2 倍）
   与 `hit`（默认 1.0 倍）。`play_attack_reaction()` 里的 `maxf` 不能删 —— 后到的
   `hit` 把力度压回基准的话，扑咬会退化成「原地抖一下」，而且不报错。
   `test_a_followup_hit_does_not_shrink_the_monster_lunge` 守着这一条。
2. **无名贴图会静默变白方片**。配方里出现的每个 `dust` / `decal` / `texture` 名字都必须
   真实存在，`test_every_texture_named_by_the_new_plans_exists` 逐条核实。
3. **弧长依赖事件坐标**。`attack_fx_plan()` 用 `target_x/y - x/y` 算 `reach`；
   事件缺坐标时回落到 0.6m 起步值，不会挥出一片零长度的弧（零长度 = 什么都看不见）。

验证：

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
:: 纯逻辑 + 接线 + 白名单 + 音频（12 条）
godot --headless --path godot --script res://.tmp/run_subset.gd -- test_monster_attack_fx

:: 视觉对照（依赖 frame_post_draw，必须走隐藏桌面，见 AGENTS.md 环境硬约束）
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\unit_attack_shot.gd --fixed-fps 30
:: 产物：godot/shots/unit_attack_{key}.png + unit_attack_sheet.png + unit_attack_control.png
```

`unit_attack_shot.gd` 的三个机位约束（每一条都是实拍改出来的，别凭直觉改回去）：
**必须关掉 `arena.set_process(false)`**（否则 `_update_camera()` 每帧覆盖机位）、
**必须 `--fixed-fps 30`**（刀光只有 0.12~0.22s，慢显卡上一帧就淡完了）、
**每格都要清场并把节点还回池**（不还池会让「池空抢占」退化成抢同一个节点）。

音频**有**了（2026-10-23 补齐），见 §9：战斗/菜单 BGM + 38 条合成音效。没有音频资源文件，全部现场合成。

**接线状态**：顿帧、多杀播报、技能指示器、取消施法区都已接入生产代码（见 `01-repo-reality.md` §4）。新增反馈模块时照旧要先 `grep` 确认生产引用，不能只写测试。

### 4.1 技能特效的四个坑（2026-11-11）

改 `skill_fx.gd` 的配方或 `arena._spawn_skill_fx()` 之前先看这四条，每条都踩过：

1. **`size` 曾经是空参数**。配方里写了 `size: 0.12`、`_spawn_particles()` 也收下了，但函数体从来没读过它 —— 所有粒子都是一样大的方片，`烟` 和 `火星` 在画面上没有任何体量差别。这种"参数传了但没人用"的失效不报错、测试也不会红，只能靠断 `quad.size` 抓（`test_skill_signature` 第 2 条变异就是这么来的）。
2. **竖直环必须每帧显式复位**。`_spawn_ring()` 的节点是从池里复用的，写完 `if tilt: rotation.x = PI*0.5` 就完事的话，上一枚竖环的朝向会残留到下一个英雄的贴地技能上。两个分支都要写。
3. **W/R 不能画两次弹道**。`SkillSystem.cast_skill()` 会为远程技能（burst / arrow / aoe_shot / line / meteor_storm / arrow_barrage）在 sim 里 `spawn_projectile`，发 `projectile_spawned`；配方里再画一颗就是两颗粒子并排飞。`_slot_fires_a_real_projectile()` 用 **slot** 判断（slot 在 `_sanitize_event` 白名单里、客机拿得到；`owner_id` 不在，客机上恒为 0）。Q/E 走 `_cast_q/_cast_e`，是瞬发不发弹道事件，**必须**继续靠配方出表现。
4. **延迟二次爆不进 `SceneTreeTimer`**。用 `_fx_queue`（`_update_fx_queue(delta)` 逐帧推进）：计时器的回调在无头测试里拿不到 SceneTree，等于这条配方不可测；队列还顺便在顿帧期间和残留一起停。

验证：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\skill_fx_shot.gd
:: 产物：godot/shots/skill_fx_<kind>.png（17 张）+ skill_fx_sheet.png（5×4 总览）+ skill_fx_control.png（对照组）
```

**必须先看 `skill_fx_control.png`**：那是"不放任何技能"的同一机位。没有它，攻击范围环 / 防御塔范围环会被当成技能特效，或者反过来把自己的特效当成场景。另外画廊每轮**必须把上一轮的节点 `visible = false` 再清数组** —— `_decal_active` 存的是 `Dictionary`（键 `node`），直接当节点用不会报错，只会一张都没藏住，表现为"每张图上叠着七八圈同心圆"。

### 4.2 防御塔的四个坑（2026-11-11）

改 `tower_visual.gd` 或塔在 `arena` 里的那段之前先看这四条：

1. **`tier` 必须真的传到 `TowerVisual.build()`**。以前建塔只传队伍色，层级完全靠 `visual_scale` 缩放。加了造型表之后，忘传 tier 不会报错，只会让四座塔长得一模一样——症状就是"明明改了塔冠，进游戏没区别"。
2. **残血变暗要改「渲染时真正生效的那份材质」**。`ModelUtils.tint()` 会为每个面 `duplicate()` 一份材质塞进 `surface_override`，所以 `TowerVisual.build()` 返回的 `stone_material` 已经不是实际渲染的那份。必须从 `MeshInstance3D.get_active_material(0)` 重新取，否则改的是没人用的副本（静默失效）。记录里存的是 `stone_render_mat`。
3. **`tower_destroyed` / `guard_destroyed` 事件不带 `id`**（只有 `team / tier / x / y`），所以倒塌演出只能按坐标反查，匹配半径 1.6m（塔基 1.34 + 余量；两塔最近 20m 以上，不会误伤）。record 里必须存 `team`，否则按阵营筛不出来。
4. **塔的瞬时反馈不能依赖 `_effects_root`**。`_handle_structure_attack()` 原本第一行就 `if _effects_root == null: return`，把开火反馈排在它后面会让进场分帧构建期间完全没有反应。塔的反应只碰它自己的材质，所以必须排在早退之前（和 `_handle_hero_attack()` 的顿帧是同一条理由）。

验证：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\tower_gallery.gd
:: 产物：godot/shots/tower_tiers_field.png（四级同框）、tower_crown_{outer,inner,high}.png、
::       tower_health_{full,low}.png
```

画廊的环境与主光直接吃 `ArenaLook`（和 `monster_gallery.gd` 同口径），所以图上看到的亮度就是游戏里的亮度。**相机必须用 `look_at_from_position()`**：构建阶段相机还没进树时 `look_at()` 会静默失败，拍出来是天空 + 塔顶，很容易被误读成"塔没建出来"。

---

## 5. 触控与桌面的双路径

`game_hud.gd` 里几乎每个构建函数都有 `if touch_mode:` 分支，两套按钮、两套布局、两套提示文案。

**规则**：改 UI 必须两条路径都改，并且各截一张图确认。只改一条的典型症状是——桌面正常、手机上按钮重叠。

截图验证：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\ui_shot.gd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\mobile_shot.gd
```

产物在 `godot/shots/`（不入库）。

### 5.1 输入采样不丢点

输入每 20Hz 采样一次（`arena._gather_input`）。**按住类**动作（走位、持续普攻）直接读实时状态；**点按类**动作（普攻 / 技能 / 召唤师 / 回城 / 传送）必须锁存：按下时置位，真正发出去之后才清（见 `_queued_attack` 与 `_consume_skill_queue()`）。

否则 60FPS 下 16ms 的一次点击可能刚好落在两次采样之间，被整帧吞掉——玩家看到的就是"我明明点了却没出手"。新增即时键时，除了加进 `net_protocol.EMPTY_INPUT` 白名单与 §6 的强制发送条件，还要按同样方式锁存。

### 5.2 触控键位：王者常规布局

右手拇指区的三组键从右到左：

| 区域 | 内容 |
| --- | --- |
| 最右 | 普攻大键（152），上方/左侧是 Q/W/E/R 四技能弧（半径 380，角度 186°~264°） |
| 技能弧左侧 | **底部横排** 回城 → 传送 → 召唤师（96/颗，间隔 12，召唤师紧贴 Q） |
| 普攻键左侧 | 普攻/补刀/推塔三颗模式圆（88/颗，纵向排列） |

左下是摇杆，底部正中是回城读取条，左上角是小地图与状态卡。**不要**再把回城/传送/召唤师竖成一列：那是旧版布局，实战里和技能弧挤成一小摞圆点。所有坐标来自 `TouchLayout.utility_button_rects()` / `skill_arc_centers()`；`tools/device_checks.py` 里的 `RECALL_RECT / TELEPORT_RECT / SUMMONER_RECT` 必须同步，否则真机自动点击会点到空处。

---

## 6. 技能键的现状与扩展点

`skill_button.gd` 是纯 `Control` + `_draw()` 手绘：外圈、CD 扇形遮罩、剩余秒数、技能名、法力不足提示。

- **交互**：桌面是鼠标左键按下即发（瞄准点来自 `arena._local_input.aim` 的地面投影）。触屏是"按下出指示器 → 拖拽调方向 → 松手施放"，拖到顶部中央取消区（半径 66）松手则取消。
- 触屏拖拽由 `skill_button.gd` 的 `drag_started/updated/released` 三个信号驱动，`game_hud.gd` 用 `SkillIndicator` 画方向/落点、用 `CancelCastZone` 判定取消并变色。**按钮自身不再直接 emit `pressed`**，触摸分支和鼠标分支是两套代码。
- HUD 建 **Q / W / E / R + 召唤师（F）+ 回城**：桌面 W 技能绑数字键 `1`（键盘 W 用于走位），按钮上直接标注实际键位；触屏按钮沿右下弧线排布。
- 新技能槽的扩展点：`_create_skill(slot, key, accent)` + `_skill_button_for(slot)`，两处都要加分支；`skill_button.gd` 的触摸/鼠标分支也要同步。

---

## 7. 头顶血条

`shaders/billboard_bar.gdshader`，英雄尺寸 `1.9 × 0.26`（蓝条 `1.9 × 0.13`），小兵/野怪按 `width_scale` 等比缩放（小兵 `0.62`、普通野怪 `0.9`、首领 `1.55`，基准 `1.24 × 0.14`）。

- 填充是**连续** `ratio`，**没有分段刻度**（王者是每 1000 血一格）。
- 加了护盾会在血条右侧叠一段白色 `shield_ratio`。
- **不要换成 `BaseMaterial3D.BILLBOARD_ENABLED`**，原因见 `02-godot-pitfalls.md` §3。

**首领体型**：暴君 `3.8 m`、主宰 `4.2 m`，分别是英雄 `2.7 m` 的 `1.41 / 1.56` 倍。两只首领是**程序化拼的重甲魔兽**（见 §7.1），实测宽 `5.14 / 5.27 m`，与模拟层 `2.8` 的碰撞半径（直径 5.6）同一量级，避免「身板看着小、实际被打范围大」。首领血条整体抬到 `身高 + 0.55`、名字字号 `44`；普通野怪仍是 `身高 + 0.25` / `32`。`UnitVisual.setup()` 的 `objective / pit_id` 由 `Arena` 从快照的 `objective / objective_id` 传入，**普通营地只能走小体型分支**。

---

## 7.0 英雄外观层（2026-11-12）

玩家原话：「利用能使用的工具、mcp、skill 去继续优化英雄的形象，效果，要做得和王者荣耀英雄一样的效果」。

**改前的实际状态**：5 个英雄共用 2 套身体 + 4 套衣服，靠 `ModelUtils.tint(albedo_color)` 染色。
通用包的贴图是「米白内衬 + 褐皮甲 + 暗橄榄布料」的杂色，乘一个色相之后是脏绿/脏棕/脏紫 ——
5 个人站成一排是一片土色，谁都不像谁；而且所有人都**光着膀子**（包本身是背心短裤的西式游侠）。

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/game/hero_look.gd` | 每个英雄的视觉身份：`palette`（主/副/金属/发/点缀光）+ `skin_slots`（4 个槽位的着色参数）+ `COSTUME_PARTS`（配件登记）+ 共用 `SKIN_SLOT` | 300 行 |
| `scripts/game/hero_costume.gd` | 工具箱：皮肤着色器材质缓存、骨骼挂点（`attach` / `shared_pivot`）、几何缓存与拼装、服饰构建与网格合并、布料摆动 | 1015 行 |
| `scripts/game/hero_costume_parts.gd` | 5 个英雄的专属服饰几何（底衣 + 披风/下摆/战旗/羽披/斗篷等） | 560 行 |
| `shaders/hero_skin.gdshader` | 逐像素重上色：明暗分层保留 + 轮廓光 + 自发光 + 队伍色（只压暗部） | 100 行 |
| `tests/test_hero_look.gd` | 21 条契约：配色独特性、uniform 全绑定、配件真建出来、网格预算、合并不杀摆动、兜帽去留、身份色单一来源 | 380 行 |
| `tools/hero_gallery.gd` | 画廊：正面 / 侧面 / 头肩特写 / **21 米实战机位**四列 × 5 行对照图 | 230 行 |

**接线只有一处**（全在表现层，sim / 协议一行没动）：`UnitVisual._apply_hero_look()`，
在 `_build_hero()` 里**量完身高、装好武器之后**调用 —— 顺序错了会让配件顶破身高契约。

### ★ 七条实拍踩出来的口径（别凭直觉改）

1. **模型正面是 +Z，不是 -Z。** 判反一次，披风会盖在胸口、星环会挡在脸上，而且**不报错**。
   判据：`arena` 里 `facing_y=1` 时 `rotation.y=0`，而 0° 的脸朝 +Z。
2. **先穿衣服，再挂配件。** 不先包一层主色躯干/袖管/裤管，21 米机位下最抢眼的是
   大片浅肤色 —— 五个英雄全是「光膀子的白人」，再好看的护肩也救不回来。
3. **布用 `sheet_mesh`，甲用 `dome`/`band`，羽用 `shard`。** 一整块 `BoxMesh` 披风
   在任何机位都读成「背着一块板」；盒子做的护肩是砖；薄盒子做的羽毛是木片。
4. **`BoneAttachment3D` 每帧把自身 transform 整个覆盖。** 在它身上写 `basis` 会被下一帧
   覆盖（症状：配件第一帧对、动一下就歪）。坐标系必须掰在它的**子节点**上 —— 见 `attach()` 的
   `Align` 层。另外它只有**在场景树里**才会被骨骼姿态驱动，无头测试里读到的全是单位矩阵。
5. **通用角色包自带的兜帽会盖住整张脸**（`Male_/Female_Ranger_Head_Hood`，y≈1.47~1.87）。
   5 张立绘里没有一个人戴兜帽 —— 不处理的话实拍是「五个绿布袋」。由
   `HeroCostume.KEEP_HEAD_HOOD` 显式决定，现在是空的（全部隐藏），剪影改由各英雄配件承担。
6. **头发一律深色。** 头发贴图是灰度的（sat 0.02），会**完整接受** `base` 的色相：
   为了「和披风统一」写成 0.155/0.265/0.18，实拍出来是一顶亮绿头盔。
   `test_hair_stays_dark_on_every_hero` 卡死 base.v < 0.16。
7. **肤色是全英雄共用一档，不跟英雄主色走**（`HeroLook.SKIN_SLOT`）。跟主色走会有
   绿脸/紫脸。亮度 0.62 是实拍调的：0.52 太黑，0.72 又回到「发白的浅橙」。

### 性能与 draw call（必须量，不能猜）

一套配件原始是 30~44 个 `MeshInstance3D`。10 个英雄同屏实测 **614 draw call / 686 mesh**，
移动端预算（≤400）直接被吃穿。两级合并之后压到 **502 / 580**：

| 手段 | 作用 |
| --- | --- |
| `shared_pivot()` | 同一根骨骼只建**一个** `BoneAttachment3D`。袖子/护肩/臂环都挂 `upperarm` 上，各建一个就是 4 次 draw call，但它们的父骨骼与每帧变换完全相同 |
| `merge_anchor()` | 挂点内按**材质**跨层烘成一份网格。摆动节点（`SWAY_PREFIXES`）各自保留一层并在自己名下就地合并 —— 烘平的话跑动时披风焊死，而且不报错 |
| 配件预算测试 | 每英雄 ≤30 个配件网格（`test_costume_mesh_count_stays_within_budget`） |

`tools/probe_hero_draw_calls.gd` 是唯一的量化手段（探针，不入库）：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\probe_hero_draw_calls.gd
:: 打印每人 total/costume/body 网格数，以及 10 人同屏的 draw_calls / objects / primitives
```

### 身份色只有一个来源

模型配色（`HeroLook`）、技能特效色（`arena._hero_vfx_color()`）、HUD 技能键主色
（`game_hud._create_skill`）**全部读 `HeroLook.glow(hero_type)`**。
以前 `arena.gd` 里硬编码一份谱系色，铁壁的模型改成锈橙之后技能还是青色 ——
一个英雄身上出现两套身份色。`test_hero_colour_has_a_single_source` 守这一条。

### 验证

```cmd
:: 画廊（必须走隐藏桌面，见 AGENTS.md 环境硬约束）
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_gallery.gd
:: 产物：godot/shots/hero_sheet.png（4 列 × 5 行）
::       hero_<type>_front.png（单英雄正面）+ hero_field.png（五人同框实战机位）
```

**先看第 4 列（21 米实战机位）**：前三是近景，只有它对应玩家 90% 时间的视角。
近景好看而实战认不出，等于没改。

### 英雄级技能变体（HERO-06）

`SkillFx.recipe(kind)` 只按 kind 分派，而 17 个 kind 里有 **3 个被两个英雄共用**：

| kind | 英雄 A | 英雄 B |
| --- | --- | --- |
| `burst` | 星璃 Q 星陨（法术球迟爆） | 墨鸦 W 毒牙（近身毒爆） |
| `charge` | 铁壁 W 野蛮冲撞（重装冲撞） | 墨鸦 Q 影袭（瞬身突刺） |
| `leap_slam` | 苍刃 R 裂地崩山（巨剑砸地） | 墨鸦 R 绝影处决（突进处决） |

改前三对**形状完全一样**，只靠英雄色 + 强调色混合区分 —— 团战里「是谁放的」
和「这是哪个技能」两个问题互相顶掉。

现在 `SkillFx.HERO_VARIANTS` 按 `"<hero_type>|<kind>"` 覆盖，`recipe_for(hero_type, kind)`
以通用配方为底再叠覆盖（所以结构字段默认继承，不会因为漏写而丢）。
`requests()` 走的是 `recipe_for`，**渲染层不需要改一行**。

**三条口径（都有测试钉住，见 `tests/test_hero_skill_variants.gd`）**：

1. **只许改外观，不许改结构**。`projectile` / `beam` / `shake` / `hit_stop` 决定
   「sim 里有没有真实弹道、要不要震屏」，是行为不是外观。改错了就是重复画一颗弹丸。
   （`trail` 是残影圈数，例外放行并已在测试里注明。）
2. **每一对必须真的分开**。测试不只断言「轴串不同」，还要求
   `has_variant` 至少命中一个 —— 否则那对英雄就是「什么都没做」。
3. **`amount=1` 必须完全取强调色**。这是 `blend_color` 的既有契约，
   所以色相冲突**不能**在 `blend_color` 里自适应修，只能在变体里覆盖
   `accent`（`SkillFx.accent_for()` 读）。

**一个实测发现的配色坑**：星璃立绘 `9e85ff` 与墨鸦 `cc6beb` 都是紫系
（色相差 0.03），而 `burst` 的强调色也是紫 —— 两人放同一个 burst 出来**近乎同色**。
解法是给墨鸦的三个变体各指定一个 `accent`（青绿 / 冷白 / 洋红），
最终渲染色拉开到色相差 ≥ 0.10。`test_shared_kind_colours_are_visually_separable`
用「色相差 ≥ 0.10」而不是「颜色不相等」守这一条 —— 后者对差 3% 也算通过，玩家看不出来。

**验收图**：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\skill_variants_shot.gd
:: 产物：godot/shots/skill_variants.png（3 行 × 2 列：每行一对共用 kind）
::       skill_variant_<hero>_<kind>.png（单张）
```

**背景选错会让你误以为变体没生效**（踩过两次）：

- 中路石板正中央：石板 albedo 接近 0.9，加法混合的特效被高光整个吃掉；
- 河道水面：水面 shader 本身是亮青色，青系技能（墨鸦 charge 的冷白）完全看不见。

结论：验收技能必须站在**中低亮度背景**上，否则读的是背景不是技能。
另外机位**必须交给 arena 自己管**（`_update_camera()` 每帧覆盖），
做法是把本地英雄钉在落点上、让相机跟过去 —— 手工摆相机一定被下一帧冲掉。

### 待机站姿（HERO-07）

改前：5 个英雄只用两套 clip —— 苍刃/铁壁/墨鸦都是 `Sword_Idle`，星璃/翎羽都是
`Spell_Simple_Idle`。三个人站成一排**姿势一模一样**，只有武器不同。

待机是玩家看得最久的画面（补刀间隙、等 CD、看线上），它比任何技能特效都更能决定
「这是不是同一个角色」。现在 `HeroLook.IDLE_POSES` 一人一套：

| 英雄 | clip | 依据（立绘气质） |
| --- | --- | --- |
| 苍刃 | `Idle_FoldArms` | 立绘是「剑扛肩上、眼神懒」→ 抱臂而立 |
| 星璃 | `Spell_Simple_Idle` | 施法者垂手待发 |
| 铁壁 | `Idle_Shield` | 重装持盾站桩 |
| 翎羽 | `Pistol_Idle` | 射手搭箭未满弦 |
| 墨鸦 | `Crouch_Idle` | 压低重心的潜行待机 |

**两条硬约束**（`test_idle_clips_exist_loop_and_are_long_enough` 逐条抓）：

1. **clip 必须在 `UnitVisual.LOOPING_CLIPS` 里**。漏了 → 播完停在最后一帧，
   变成一个「石头人」，而且不报错。这份清单以前是单行 6 个，现在是多行 9 个。
2. **长度 ≥ 1.0s**。太短会读成抽搐（`Idle_Shield_Break` 1.07s 已接近下限）。

接线：`UnitVisual._build_hero()` 用 `HeroLook.idle_pose(hero_type)`，
`HERO_SETUPS` 里**不再有 `idle` 键** —— 一个配置只有一个来源。

**验收图**：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_idle_shot.gd
:: 产物：godot/shots/hero_idle_sheet.png（5 行 × 3 帧：0s / 0.55s / 1.10s）
```

三帧是必需的：只有一帧证明不了「它在循环呼吸还是停住了」。
`hero_idle_shot.gd` 手动 `player.advance()` 推进，不依赖真实帧间隔
（截图写盘会拖慢帧率，三张图会拍到同一姿态）。

### 头顶血条的高度必须跟着身体量（HERO-08）

改前血条写死 `HERO_HEIGHT + 0.30`（3.00）—— 那是「静立姿势」的头顶。
待机换成抱臂/持盾/拉弓之后武器举过头顶，血条**压在脑袋上**，
21 米机位下看就是「血条把人头切掉了」（实拍确认）。

现在 `UnitVisual._posed_body_top()` 按**实际骨骼姿态**算头顶：

```gdscript
头骨静止 y + HEAD_ABOVE_BONE(0.21) + (当前姿态 y − 静止 y)，再乘 model_root.scale.y
```

再加 `BAR_CLEARANCE = 0.30`。实测五个英雄的落地值：

| 英雄 | 待机 | 血条 y |
| --- | --- | --- |
| 苍刃 | `Idle_FoldArms` | 2.81 |
| 星璃 | `Spell_Simple_Idle` | 2.86 |
| 铁壁 | `Idle_Shield` | 2.89 |
| 翎羽 | `Pistol_Idle` | 2.86 |
| 墨鸦 | `Crouch_Idle` | **1.84** |

墨鸦比其他人低整整 1 米 —— 这正是「按姿势量」和「按固定值量」的差别。

### ★ 三条只在实战机位下才暴露的坑（HERO-08）

这一轮把 `arena_shot.gd` 的整帧裁出来放大，才看到下面三条。**近景画廊全部看不出来**。

**① 血条高度不能在装配时量。**
`MeshInstance3D.get_aabb()` 返回的是**未蒙皮**的网格包围盒，骨骼怎么动它都不变。
更隐蔽的是：`AnimationPlayer.advance()` / `seek()` **也不会**更新
`Skeleton3D.get_bone_global_pose()` —— 骨架姿态由渲染前的 AnimationMixer 求值写入，
**必须真的进场景树、过至少一帧**。实测墨鸦 `Crouch_Idle`：

| 时刻 | Head 骨 y |
| --- | --- |
| 装配瞬间 | 1.55（静止姿态） |
| `advance()` × 20 次 | 1.55（完全没动） |
| 进树两帧后 | 0.81（真实蹲姿） |

所以 `_settle_bar_height()` 只置一个 `_pending_bar_settle` 标记，
真正的测量在 `process_visual()` 里等 2 帧后做一次。

**② 武器的 glb 原点不在握把上。**
实测（`tools/probe_weapon_grip.gd` 打印沿 Y 的宽度剖面找突变点）：

| 武器 | 原点位置 | 握把段 | 正确 `weapon_offset.y` |
| --- | --- | --- | --- |
| `Claymore.glb` | y=0 在**剑尖那头** | 0.00~2.20 | −1.10 |
| `Dagger.glb` | y=0 在护手处 | 0.00~0.58 | −0.29 |
| `Scythe` / `Hammer_Double` / `Bow_Wooden2` | 沿 Y 均匀，无明显握把 | — | 0 |

不补偏移时剑会从拳头**末端**伸出去，看起来像「剑插在小臂上」。
一个容易搞错的细节：`weapon.position` 是节点自身位移，**不受自身 `scale` 影响**，
所以偏移写**未缩放**的原始值（1.10），不是乘过 `weapon_scale` 的 0.31。

**③ 披风内衬必须比主布片宽。**
内衬窄于主布片时从背后被完全盖住，实拍是一整块没有层次的纯黑面。
改成内衬**宽 0.02、短 0.12**（两侧各露一条窄边）+ 一道中缝压条 + 下缘亮边。

### 逐个英雄的实战验收（HERO-08）

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_field_zoom.gd
:: 产物：godot/shots/hero_field_zoom.png（5 行 × 2 列：整帧缩略 + 英雄 4× 放大）
::       godot/shots/hero_field_<hero>.png（整帧原图）
```

**为什么必须逐个英雄**：每个英雄的暴露点不同 —— 苍刃是血条压头 + 剑脱手，
铁壁是战旗糊成橙色块，墨鸦是蹲姿让血条浮空一臂高。只验一个人等于没验。

工具里有两个坑，都踩过：
- **换 `hero_type` 后不能只删 `_views` 条目等下一帧重建** —— `_sync_units` 只在
  「快照里出现新 id」时才创建视图，id 没变就再也不画了（第一版拍出五张空地图）。
  必须直接调 `arena._create_unit_view(entity)`。
- **相机要手动推**：`arena.set_process(false)` 之后 `_update_camera()` 不再执行，
  得自己调一次 `arena._update_camera(0.016, true)`。

### 浅色英雄与「brightness 被稀释」（HERO-09）

翎羽是唯一「米白为主色」的英雄。实测它的战衣渲出来是 **114,128,133**（灰蓝），
和立绘的米白差了整整一档 —— 换成 `base 0.78 + brightness 1.18` 也**只亮了 7 个单位**。

根因是 `hero_skin.gdshader` 的一处静默失效：

```glsl
vec3 original = tex.rgb * brightness;              // ← 第一版只有这里乘了
vec3 lit = mix(original, toned * (0.42 + shade*0.62), recolor);
```

`recolor` 通常 0.86~0.94，所以 `brightness` 被混到只剩 **6~14%**，
调它几乎无效。改成 `toned * brightness * (0.42 + shade*0.62)` 之后才真正生效。

`test_brightness_affects_the_recoloured_branch_too` 用源码守卫钉住这一条
（它挡的是「参数传了但被别的 mix 稀释」这类最隐蔽的失效）。

**浅色材质的判定口径**：`palette.primary.s < 0.18` 视为中性色，上限放宽到 0.85。
上限不是美学判断，是「别过曝成纯白」的技术线：实测米白 base 0.80 渲出来是
187/191/192，地面 205 —— 仍是「布」不是「灯」。

### 弓的发光必须单独压（HERO-09）

`Bow_Wooden2.glb` 由三段组成：`White`（弓弦，极细）、`LightWood`（握把）、
**`DarkWood`（弓臂，占整把弓 90% 的体积）**。

按「整把武器」统一给 `glow 0.75 / rim 0.55` 时，弓臂糊成一整块发光的青白板，
21 米机位下读成「英雄举着一块玻璃」（实拍确认）。翎羽的 weapon 槽位单独压到
`glow 0.22 / rim 0.20`，靠木色本身认人。

**通用教训**：`skin_slots.weapon` 是**按整把武器**一套参数。武器里如果有一件
体积占比极大的部件（弓臂、巨锤头），发光参数要按「最大的那件」定，
不能按「想让它亮」定。

### 敌我识别：队伍色必须占「暗部 + 轮廓」两处（HERO-10）

改前 `team_amount = 0.16`，只压暗部。实测（`fight_close.png` 里两个苍刃对砍）：
**红方和蓝方的苍刃身体颜色几乎一样**，只能靠血条和脚下光环分辨。
5v5 团战里这是致命的 —— 玩家会对着队友挥技能。

新口径（`shaders/hero_skin.gdshader`）：

| 通道 | 参数 | 作用 |
| --- | --- | --- |
| 暗部染色 | `team_amount` 0.34（原 0.16） | 衣服主体偏冷/偏暖 |
| **轮廓光** | `team_rim_color` + `team_rim_strength` 0.42 | 边缘一圈队伍色，人群里看轮廓就能分敌我 |

**为什么必须两处**：暗部染色不占「亮部」的色彩面积，主色仍然认得出是谁；
但它在 21 米机位下**太弱**。边缘染色正好相反 —— 醒目但不抢主色。
两者叠加才能同时满足「认得出是谁」和「认得出是哪边」。

**强度上限是实拍定的**：`0.42`。0.72 时整个人像镶了一圈红边、
读起来像英雄在发光（放大图确认）。低于 0.30 在草地上又认不出。

### 显式限制（写在这里，避免下一个人以为「再做一点就能到王者」）

- **没有定制骨骼**：动作仍从 UAL1/UAL2 两套通用库 retarget，Q/W/E/R 只是 4 个 clip 的映射。
  真正的「专属动作」需要动画资产，不是代码能补的。见 `docs/英雄定制模型规范-HERO-04.md`。
- **模型仍是 2 套身体**：脸/骨架/体型无法逐个定制。这一层做的是**配色、材质、服饰、
  身份色统一**，把「五个人看起来像五个人」做到极限；再往上必须换资产。
- **配件是程序化基本体**：受 `docs/gap-analysis-vs-honor-of-kings.md` §5.1 的授权约束，
  不引第三方模型；代价是近景能看出是几何体拼的。

---

玩家反馈原话：「红蓝buff和野怪的形象还是不够好看，要继续优化，可以参考王者荣耀等游戏的野怪设计」。
改前的实际状态是：**12 个野点全都用同一只 `Wolf.glb`**（只靠头顶名牌区分），暴君/主宰共用同一只
Kenney 兽人 —— 俯视下野区是一串一模一样的狼。现在每个野点有自己的剪影与配色。

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/game/monster_kit.gd` | 工具箱：材质/网格静态缓存、基本体拼装、量体对齐（`fit_height`）、形态字典收尾（`finish`） | 330 行 |
| `scripts/game/monster_forms_jungle.gd` | 蔚蓝石像 / 猩红石像 / 蜥蜴 / 三猪 / 红鸟 | 400 行 |
| `scripts/game/monster_forms_boss.gd` | 暴君 / 主宰（共用 `_beast` 骨架，靠配色 + 角数 + 甲刺长度分开） | 180 行 |
| `scripts/game/monster_forms.gd` | 形态派发（`form_key` / `CAMP_FORMS` / `build` / `ring_radius`）+ 程序化动画（`animate`） | 160 行 |
| `tools/monster_gallery.gd` | 画廊：每种形态单独特写拼成对照图 + 一张实战取景图（入库工具） | 230 行 |

**接线只有三处**（都在表现层，sim / 协议一行没动）：`Arena._create_unit_view()` 把快照里的
`camp_id / objective_id / monster_type` 三项传给 `UnitVisual.setup()`；`UnitVisual._build_monster()`
用 `MonsterForms.form_key()` 换出形态键，程序化形态交给 `_build_procedural_monster()`，
狼走 `_build_wolf_monster()`，河道之灵仍是原来的水球分支。`Arena` 只负责**把快照字段递下去**，
形态语义收在 `MonsterForms` 里 —— 和 `set_monster_badge()` 的分工一致。

**为什么程序化拼、不再找现成模型**：现成包的 glb 里连 `license` 字段都没有
（差距文档 §5.1），野怪再引一套资产等于再加一处合规风险；基本体 + 共享材质的显存与包体代价
接近零；而俯视 20 米机位下玩家读的是**剪影 + 配色**，不是面数。

**四条设计口径**（都是看实拍图改出来的，别凭手感推翻）：

1. **剪影第一**：同一体积拆成两三块各自转几度，比一整块大方块像「石头/甲壳」；发光件要**小而亮**，
   做大了在 bloom 下糊成一坨白斑（第一版蓝石像的晶体就把整个胸甲吃掉了）。
2. **配色按 FILMIC 反解**：石头基色要压到 `0.1~0.3` 这一档。写 `0.5` 上去，经过
   `TONE_MAPPER_FILMIC + exposure 1.05 + 天空环境光` 出来是中灰色，红石像会读成「奶咖色」。
   这和 §7 血条三色（`HP_SELF/HP_ALLY/HP_ENEMY`）是同一类坑。
3. **体型与碰撞半径必须同量级**：`Jungle.monster_stats()` 给的 `radius`（小野点 1.5 / buff 2.2 /
   首领 2.8）就是「被打到的范围」。`fit_height()` 负责把形象对齐到标定身高，`test_monster_forms`
   再按 AABB 卡住「不能明显超出、也不能缩成小点」。
4. **獠牙/角一律朝上外翻**：朝前摆会连成一排白板，正面读成「一张嘴」。

**动画不用骨骼**：形象是基本体拼的，没有骨骼可播。`MonsterForms.animate()` 每帧按
「腿绕髋关节摆 / 翅膀扇 / 尾巴摇 / 肩甲与火星绕体转 / 晶体呼吸」驱动关节节点，
`moving` 与 `unit_speed` 决定步频与幅度。死亡时（`_update_death_pose`）向前倒 + 下沉，
复活时 `_restore_model_rest_pose()` 收回 —— **倒地只叠加在静止姿态上**，直接写
`model_root.scale/rotation` 会覆盖 `fit_height` 的结果，野怪一死就变大浮空。

**性能纪律**：材质与网格都走 `MonsterKit` 的静态缓存（`stone/gem/glow/aura/hide_mat/chitin` +
`_box_mesh/_sphere_mesh/_cylinder_mesh/_shard_mesh`），同形态重复装配**不新建**材质与网格
（`test_monster_forms` 有守卫）。首领约 55 个 `MeshInstance3D`，小野点 26~35 个；
它们共用材质、关闭投影，同屏最多也就是几个野点。

**改形象的操作顺序**（否则你会盯着一张缩成一坨的图瞎调）：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\monster_gallery.gd
:: 产物：godot/shots/monster_sheet.png（8 宫格特写）、monster_field.png（51° 俯角实战取景）
```

画廊的**环境与主光直接吃 `ArenaLook`**（`apply_environment` / `apply_sun`），
所以图上看到的颜色就是游戏里的颜色 —— 自己另写一套光照、尤其是不开 bloom 时，
「晶体到底亮不亮」根本判断不了。

**遗留**：`assets/characters/Orc.glb` 现在没有生产引用了（旧版首领模型），
保留为素材；`test_global_integrity` 仍在资产清单里断言它能加载。

血条之外的头顶信息：

| 单位 | 头顶 | 规则 |
| --- | --- | --- |
| 英雄 | 名字 + 等级 + 草丛斜划眼 | 眼睛只给**本地英雄**，敌人进草不显示（否则是透视） |
| 野怪 | 名字 + `蓝BUFF`/`红BUFF`/`首领` 前缀 | 前缀与颜色由 `Arena` 从快照字段传给 `set_monster_badge()`，`UnitVisual` 不猜语义 |
| 小兵 | 只有血条 | 数量太多，名字会糊成一片 |

营地/首领坑的**地面**信息（`arena._sync_camp_states`）：

- 贴地符阵 `shaders/camp_sigil.gdshader` 随野怪存活状态亮/暗；
- 野怪死亡后视图会被回收，所以在营地上保留一块 `Label3D` 倒计时牌（`名称 + 剩余秒数`）；
- 小地图同步画倒计时弧（`Minimap.camp_timer_marks()`），三者共用快照里的 `respawn_timer`。
- 符阵/倒计时只在营地进入本地视野时显示：快照里没有那只野怪，就不隔墙读计时。

---

## 7.1 野怪形象（2026-11-10）

玩家反馈原话：「红蓝buff和野怪的形象还是不够好看，要继续优化，可以参考王者荣耀等游戏的野怪设计」。
改前的实际状态是：**12 个野点全都用同一只 `Wolf.glb`**（只靠头顶名牌区分），暴君/主宰共用同一只
Kenney 兽人 —— 俯视下野区是一串一模一样的狼。现在每个野点有自己的剪影与配色。

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/game/monster_kit.gd` | 工具箱：材质/网格静态缓存、基本体拼装、量体对齐（`fit_height`）、形态字典收尾（`finish`） | 330 行 |
| `scripts/game/monster_forms_jungle.gd` | 蔚蓝石像 / 猩红石像 / 蜥蜴 / 三猪 / 红鸟 | 400 行 |
| `scripts/game/monster_forms_boss.gd` | 暴君 / 主宰（共用 `_beast` 骨架，靠配色 + 角数 + 甲刺长度分开） | 180 行 |
| `scripts/game/monster_forms.gd` | 形态派发（`form_key` / `CAMP_FORMS` / `build` / `ring_radius`）+ 程序化动画（`animate`） | 160 行 |
| `tools/monster_gallery.gd` | 画廊：每种形态单独特写拼成对照图 + 一张实战取景图（入库工具） | 230 行 |

**接线只有三处**（都在表现层，sim / 协议一行没动）：`Arena._create_unit_view()` 把快照里的
`camp_id / objective_id / monster_type` 三项传给 `UnitVisual.setup()`；`UnitVisual._build_monster()`
用 `MonsterForms.form_key()` 换出形态键，程序化形态交给 `_build_procedural_monster()`，
狼走 `_build_wolf_monster()`，河道之灵仍是原来的水球分支。`Arena` 只负责**把快照字段递下去**，
形态语义收在 `MonsterForms` 里 —— 和 `set_monster_badge()` 的分工一致。

**为什么程序化拼、不再找现成模型**：现成包的 glb 里连 `license` 字段都没有
（差距文档 §5.1），野怪再引一套资产等于再加一处合规风险；基本体 + 共享材质的显存与包体代价
接近零；而俯视 20 米机位下玩家读的是**剪影 + 配色**，不是面数。

**四条设计口径**（都是看实拍图改出来的，别凭手感推翻）：

1. **剪影第一**：同一体积拆成两三块各自转几度，比一整块大方块像「石头/甲壳」；发光件要**小而亮**，
   做大了在 bloom 下糊成一坨白斑（第一版蓝石像的晶体就把整个胸甲吃掉了）。
2. **配色按 FILMIC 反解**：石头基色要压到 `0.1~0.3` 这一档。写 `0.5` 上去，经过
   `TONE_MAPPER_FILMIC + exposure 1.05 + 天空环境光` 出来是中灰色，红石像会读成「奶咖色」。
   这和 §7 血条三色（`HP_SELF/HP_ALLY/HP_ENEMY`）是同一类坑。
3. **体型与碰撞半径必须同量级**：`Jungle.monster_stats()` 给的 `radius`（小野点 1.5 / buff 2.2 /
   首领 2.8）就是「被打到的范围」。`fit_height()` 负责把形象对齐到标定身高，`test_monster_forms`
   再按 AABB 卡住「不能明显超出、也不能缩成小点」。
4. **獠牙/角一律朝上外翻**：朝前摆会连成一排白板，正面读成「一张嘴」。

**动画不用骨骼**：形象是基本体拼的，没有骨骼可播。`MonsterForms.animate()` 每帧按
「腿绕髋关节摆 / 翅膀扇 / 尾巴摇 / 肩甲与火星绕体转 / 晶体呼吸」驱动关节节点，
`moving` 与 `unit_speed` 决定步频与幅度。死亡时（`_update_death_pose`）向前倒 + 下沉，
复活时 `_restore_model_rest_pose()` 收回 —— **倒地只叠加在静止姿态上**，直接写
`model_root.scale/rotation` 会覆盖 `fit_height` 的结果，野怪一死就变大浮空。

**性能纪律**：材质与网格都走 `MonsterKit` 的静态缓存（`stone/gem/glow/aura/hide_mat/chitin` +
`_box_mesh/_sphere_mesh/_cylinder_mesh/_shard_mesh`），同形态重复装配**不新建**材质与网格
（`test_monster_forms` 有守卫）。首领约 55 个 `MeshInstance3D`，小野点 26~35 个；
它们共用材质、关闭投影，同屏最多也就是几个野点。

**改形象的操作顺序**（否则你会盯着一张缩成一坨的图瞎调）：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\monster_gallery.gd
:: 产物：godot/shots/monster_sheet.png（8 宫格特写）、monster_field.png（51° 俯角实战取景）
```

画廊的**环境与主光直接吃 `ArenaLook`**（`apply_environment` / `apply_sun`），
所以图上看到的颜色就是游戏里的颜色 —— 自己另写一套光照、尤其是不开 bloom 时，
「晶体到底亮不亮」根本判断不了。

**遗留**：`assets/characters/Orc.glb` 现在没有生产引用了（旧版首领模型），
保留为素材；`test_global_integrity` 仍在资产清单里断言它能加载。

血条之外的头顶信息：

| 单位 | 头顶 | 规则 |
| --- | --- | --- |
| 英雄 | 名字 + 等级 + 草丛斜划眼 | 眼睛只给**本地英雄**，敌人进草不显示（否则是透视） |
| 野怪 | 名字 + `蓝BUFF`/`红BUFF`/`首领` 前缀 | 前缀与颜色由 `Arena` 从快照字段传给 `set_monster_badge()`，`UnitVisual` 不猜语义 |
| 小兵 | 只有血条 | 数量太多，名字会糊成一片 |

营地/首领坑的**地面**信息（`arena._sync_camp_states`）：

- 贴地符阵 `shaders/camp_sigil.gdshader` 随野怪存活状态亮/暗；
- 野怪死亡后视图会被回收，所以在营地上保留一块 `Label3D` 倒计时牌（`名称 + 剩余秒数`）；
- 小地图同步画倒计时弧（`Minimap.camp_timer_marks()`），三者共用快照里的 `respawn_timer`。
- 符阵/倒计时只在营地进入本地视野时显示：快照里没有那只野怪，就不隔墙读计时。

---

## 8. 改表现时的自查

- [ ] 桌面上看过了吗？触控模式下看过了吗？
- [ ] 常驻面板的位置是从 `hud_layout.zones()` 取的吗？（别手写 anchor/offset）
- [ ] 新面板/新文案把最小尺寸顶大了吗？（`probe_hud_rects.gd` 量一遍，回填分区表）
- [ ] 用了 `queue_free()` 吗？（高频对象应该回池）
- [ ] 特效颜色是不是落到了默认分支？（`_hero_vfx_color()` 只认 4 个英雄）
- [ ] 5v5 满员时会不会糊成一片？（同屏 10 英雄 + 几十小兵）
- [ ] 调试面板加了按钮吗？后端必须有同名 `debug_*` 方法（`_call` 用 `has_method` 静默跳过，漏了不报错）。
- [ ] 截图存到 `godot/shots/` 了吗？（别提交）

---

## 9. 音频（BGM + 音效）

**没有任何音频资源文件**，全部用 PCM 现场合成（`AudioStreamWAV`）。这样仓库里不用放二进制资产，循环点也能精确对齐到采样。

| 文件 | 职责 | 能不能在测试里跑 |
| --- | --- | --- |
| `scripts/game/audio_plan.gd` | **纯逻辑**：事件 → cue 名 + 增益；距离衰减、同名冷却、单帧上限、战斗热度 | ✅ 全测得到 |
| `scripts/game/audio_cues.gd` | 音效波形（38 条）与 `cue(name)` 派发表 | ✅ 只测波形属性 |
| `scripts/game/bgm_synth.gd` | 程序化 BGM：菜单 / 战斗 / 战斗强度层 / 胜利 / 失败 | ✅ 只测波形属性 |
| `scripts/game/audio_director.gd` | Node：10 个复用声道 + 音乐淡入淡出 + 暂停压低 | ❌ 进不了树，靠 `tools/probe_audio_*.gd` |

**关键设计**（改之前先理解，否则很容易改成「糊成噪音」）：

- **距离衰减**：贴身 0dB，40 米外直接丢弃（不占声道）；自己身上的事不衰减。`AudioPlan.gain_for_distance()`。
- **节流**：同名 cue 有最小间隔（小兵命中 0.10s、英雄命中 0.06s…），且一帧最多 `MAX_CUES_PER_FRAME = 6` 个声音。5v5 团战一帧能有 20+ 事件，全放就是噪音墙。
- **声道池**：`VOICE_COUNT = 10`，启动时建好，之后只换 `stream` 重播。**不要**在战斗里 `AudioStreamPlayer.new()`（硬规则 4）。
- **战斗 BGM 是两层**：`battle` 常驻 + `battle_stem` 一直播但音量从 -48dB 起。交战时按 `AudioPlan.heat()` 把 STEM 推到 -13dB —— 是「同一首曲子更紧张」，不换曲、不破拍。
- **一个导演实例**：`main.gd` 建一个挂在应用壳上，通过 `configure({"audio": ...})` 传给 arena。菜单/选人/大厅/战斗共用，切曲靠淡入淡出。单独跑 arena 的工具会自建一个。
- **暂停**：`set_paused(true)` 只是把音乐压低 8dB，不停播 —— 回来时不用重新起拍。

**加一条新音效，要改 3 处**（少一处就是静默失效）：

1. `audio_cues.gd`：加 `const CUE_X := "x"` + 写 builder + 在 `NAMES` 和 `cue()` 的 `match` 里各加一行；
2. `audio_plan.gd`：在 `cues_for()` 的对应事件分支里 `_push(out, CUE_X, gain)`，并把 `CUE_X` 加进 `CUES`；
3. `tests/test_audio_system.gd` 不用改 —— `test_every_planned_cue_can_be_synthesized` 会逐条核实「计划能发的每个 cue 都有波形」，漏了直接红。

**验证**：

```cmd
godot --headless --path godot --script res://tests/run_tests.gd          # 逻辑 + 波形 + 接线守卫
godot --headless --path godot --script res://tools/probe_audio_dump.gd    # 每条曲/RMS/低中高频占比
godot --headless --path godot --script res://tools/probe_audio_runtime.gd # 声道池/淡入淡出/强度层
godot --headless --path godot --script res://tools/probe_audio_arena.gd   # arena 端到端：事件→声音
```

`probe_*` 已在 `.gitignore` 里，不入库。

---

## 10. 开发者调试面板（F3 / 触控 DEV）

入口：`Arena._build_debug_panel()`，只有以下任一条件成立才会创建：

- `OS.is_debug_build()`（编辑器 / debug 导出）；
- 启动参数带 `--dev`；
- 比赛配置显式 `debug_panel = true`。

正式包默认没有面板，F3 也不响应。

**打开方式**（2026-11-10 玩家反馈「F3 调不出调试面板」后加固）：

| 入口 | 说明 |
| --- | --- |
| `F3` | 键鼠主入口。判定走 `DebugPanel.matches_toggle_key()`，**同时认 `keycode` 与 `physical_keycode`** |
| `Ctrl+Shift+D` | 备用组合键。笔记本的 Fn 锁会把 F3 变成音量/亮度键，**系统层面就不交给游戏**，代码再怎么写也收不到 |
| `DEV` 圆键 | 屏幕入口，**触屏与键鼠都显示**（键鼠贴小地图下方 64px，触屏贴暂停键下方 96px）。面板只存在于调试构建，不会污染正式包 |

**为什么现在键鼠也挂 DEV 键**：原设计是「键鼠有 F3 就不挂常驻键」。实测两种真实失效：
中文输入法/非美式布局下功能键常常只填 `physical_keycode`、`keycode` 为 0（症状是
**按 F3 完全没反应且不报错**）；笔记本 Fn 锁干脆不发 F3。这两条都不是代码能"修好"的，
所以留一个点得到的入口。`test_debug_mode` 会断言它不压住小地图与状态卡。

**排查**：对局构建完成时控制台必打一行 —— `[调试面板] 已就绪：F3（或 Ctrl+Shift+D）`
或 `[调试面板] 未启用：<原因>`；按了开关键却没有面板时，会把同一句原因再打一次
（只打一次，不刷屏）。看不到面板时先看这一行，就不用猜了。
`CanvasLayer` 常驻、只切换 `root.visible`，否则收起面板会把入口一起隐藏；面板标题栏和 DEV 键都能关闭。

**所有权**：作弊全部落在 `sim` 的本地英雄实体上（`debug_god` / `debug_infinite_mana` / `debug_no_cooldown`），
`MatchSim._damage()` 与 `_update_hero_timers()` 读取这些键。它们**不进快照白名单**，客机拿不到 sim，天然无效。

**唯一的 UI→后端契约**：`DebugPanel._call()` 用 `has_method` 静默跳过不存在的接口。
新按钮必须同时在 `Arena` 上实现同名 `debug_*` 方法，并由 `tests/test_debug_mode.gd` 的方法清单守住。

面板当前能做的事：

| 分组 | 功能 |
| --- | --- |
| 模拟 | 0.25x ~ 4x 时间倍率、暂停模拟、单步 1 tick |
| 英雄 | 无敌、无限法力、无冷却、+1000 金币、等级 +1、回满血蓝、传送到鼠标 |
| 世界 | 清空小兵、刷新野怪、全图视野（只改本地快照，广播仍按队伍过滤） |
| 表现 | 关闭顿帧（`_trigger_hit_stop` 统一入口）、关闭震屏 |
| 网络 | 只读：FPS / 实体数 / tick 耗时 / 快照耗时 / 缓冲深度 / 主机或客机 |

注意：时间倍率只作用于主机模拟，表现层永远按真实时间走；客机上所有作弊控件会被禁用。

---

## 11. 地图地形与野区分布（2026-10-28）

**野区 12 个野点**：每半场 2 个 buff 营地 + 4 个小野点，对齐王者峡谷结构：

| 野区 | buff | 小野点 |
| --- | --- | --- |
| 蓝方蓝区 / 红方蓝区 | 蓝BUFF | 双狼、蜥蜴 |
| 蓝方红区 / 红方红区 | 红BUFF | 三猪、红鸟 |

| 野点（`camp_id`） | 形象（`MonsterForms.CAMP_FORMS`） | 说明 |
| --- | --- | --- |
| 霜狼 / 赤狼（蓝 BUFF / 红 BUFF） | `blue_sentinel` / `red_sentinel` | 蔚蓝石像 / 猩红石像（漂浮石躯 + 胸口晶簇 / 岩浆裂纹） |
| 双狼 | `wolf` | 现成狼模型（`Wolf.glb`），眼睛换成自发光琥珀 |
| 蜥蜴 | `lizard` | 低伏长身 + 背脊鳍刺 + 拖尾 |
| 三猪 | `boar` | 前高后低的桶身 + 上翘獠牙 + 鬃背 |
| 红鸟 | `bird` | 赤色猛禽 + 后掠翼板 + 三根长尾羽 |
| 暴君 / 主宰（`objective_id`） | `tyrant` / `overlord` | 四足重甲魔兽（暗赤 / 紫黑，见 §7.1） |

**形象登记在 `scripts/game/monster_forms.gd` 的 `CAMP_FORMS`，不在 `MapLayout.CAMPS` 里**：
换模型不改任何玩法数值，它是纯表现层的事；`camp_id` 本来就在快照与
`net_protocol._sanitize_entity` 的白名单里，所以主机与客机自动一致。
新增野点忘了登记会被 `test_monster_forms` 直接拦下（那张表必须与 `CAMPS` 一一对应）。

- `MapLayout.CAMPS` 是唯一数据源；小野点 `radius = 1.5`、`disc_radius = 2.4`，没有 `buff` 字段。
- `Jungle.monster_stats()` 读取营地可选的 `hp / damage / xp / respawn_time`：buff 怪保持 720/780 血、70 秒刷新；小野点 420~500 血、60 秒刷新、只给经验。
- 击杀小野点**不发 `buff_taken`**：空 `buff` 会被播报层误读成红BUFF。只加经验，死亡事件仍然发。
- 小地图用草绿色标记小野点；buff 营地保留红/蓝标记与重生倒计时，小野点倒计时按各自 `respawn_time` 走。

**buff 营地的不规则石壁围栏（2026-11-02）**

玩家原话（附王者荣耀截图）：「红蓝buff要有这种不规则的墙围起来」。上一版是「一对平行短墙」，
俯视一眼是两块摆正的板子，读不出 MOBA 野区那种乱石围成的窝。

- 数据在 `MapLayout.CAMP_RINGS`：每座 buff 营地一条**折线**，顶点写「营地局部极坐标」
  （`[角度, 半径]`，0° = +x，逆时针，角度可超过 360）。写极坐标而不是绝对 xy，
  是因为营地会挪、半场要镜像 —— 半径表挪营地时不用重算。
- 只定义**蓝方半场两座**的形状；红方两座由 `mirror()` 得到。四座 buff 营地在镜像下正好两两成对
  （蓝蓝 (-1,-23) ↔ 红蓝 (23,1)；蓝红 (6,27) ↔ 红红 (-27,-6)），所以不会挪错营地。
  **不要改成 180° 旋转 `-p`** —— 那会把围栏塞到隔壁营地头上。
- 折线是**开口**的，首尾之间那一段就是进出通道。**开口朝己方基地一侧**（2026-11-10
  玩家反馈改的：之前朝河道/敌方一侧，等于自家 buff 窝的门开在敌境方向）。镜子规律：
  开口中心 θ 镜像后落在 −θ−90，蓝方两座对准蓝基地，红方两座镜像后自动对准红基地。
- 墙段压到河岸坡的那几个顶点把半径收小（3.6~4.2 米），保证 river_d ≥ 10.9：
  水面在 -0.42，再靠近墙基就要泡水/悬空。
- 半径有鼓有收（3.60 ~ 6.75）：一条等距圆弧俯视还是「围栏」，不是山体。
- 每个顶点都过了 `tools/probe_ring_fit.gd`（探针，不入库）：地形平坦、不压兵线、
  不盖营地/草丛/首领坑/传送阵、与保留石壁留出净宽、**折线整段**合法而不只是顶点。

`MapLayout.WALLS` 现在是 `static var`，= `STRAIGHT_WALLS`（直墙）+ `camp_ring_walls()`（围栏展开）。
它是碰撞/视野/小地图/渲染的**唯一**墙列表，**不要往里 push**（共享实例，改一次污染整局）。

配套改动（三条都是「不加就会互相穿模」）：

- 直墙从 12 段减到 8 段：`wall_blue_buff_ring_*`、`wall_red_upper/lower_ring_*` 这 6 段是原先
  贴着 buff 营地的「平行短墙」，现在整段被围栏取代；`wall_top_east` / `wall_bottom_east`
  也整段并入了红方两座围栏。
- `wall_top_west` / `wall_bottom_west` 从围栏表面外 1.4 米处**截断**（原长 15.6 → 6.5 米），
  保留它们作为深野区隔断的作用。
- `MapLayout.wall_ends()` 按**位置去重**：围栏相邻两段共用顶点，不去重的话墙角会叠两块
  完美重合的露头石（z-fighting，俯视是一块抖动的石头）。

`test_jungle_walls` 的「墙不能交叉」也放宽成「不能**中途**交叉」：折线相邻段共享端点，
`Geometry2D.segment_intersects_segment` 对共享端点同样返回交点，那不是穿模。

**墙体视觉**：`STRAIGHT_WALLS` 与 `CAMP_RINGS` 共用同一套渲染语言：

- 每段墙先铺一条低砌石基座（野区 `WALL_CORE_HEIGHT = 1.25`、边界 `BOUNDARY_CORE_HEIGHT = 2.0`），砖缝仍在 `rock_wall.gdshader`；
- 基座上方沿墙铺 `Rock.glb` 岩脊，高度/宽度/朝向随机，野区岩脊高低交替；**低石沿墙左右摆出 S 形**（`sin` 相位每段不同），高石仍贴中线，保证墙面轮廓不是直线又不穿进英雄贴墙位置；
- 墙脚每 2 米一块低矮乱石，左右交替、位置抖动，把墙脚那条数学直线啃成参差石根；
- 边界岩脊进深在 `-0.5 ~ +0.8` 米之间摆动，四角各压三块大岩，把直角吞掉；不再有等距壁柱和外挑压顶（`test_wall_look` 会拦住它们回来）。
- 高度预算：野区 `WALL_TOP = 2.45`、边界 `BOUNDARY_TOP = 3.7`，相机安全边距按这两个值反解。
- 野区岩脊按**真实顶点**校验：到墙心距离不超过 `0.8 + 0.55 + 0.06` 米，避免玩家穿进石头；边界岩脊最内缘留在 54.3 米外。

**两个空角落：纯路面贯通 + 角落传送阵（2026-10-31 第三版）**

玩家看完第二版（角落铺石广场）之后的反馈：「不需要这个桥，只需要路即可」。于是：

- **移除角落石桥与广场**：角落不再生成桥梁或 `CornerPlaza` 石质平台。`MapLayout.corner_plazas()` 返回空数组，`inside_corner_plaza()` 返回 false。
- **河道两端自然收坡**：`TerrainBuilder` 在 `(±35, ±35)` 附近（`along = 50m`）平滑升起河床，水面长度收为 98 米（半长 49m），河道在端头草坡下自然收口，不再穿过边路。
- **纯路面贯通**：边路角落为完整平地，三层路面连续贯通，两层路缘石不再因广场而剔除，直接沿路面完整铺过拐角。
- **传送阵**：`MapLayout.TELEPORT_PADS` 的阵心 `(∓52, ∓52)` 保持在最角落，高度恢复为平地草面高度（`base_y = 0.04`）。
- **中路主桥保留**：`_build_river()` 仅保留中路中心的主桥（`_build_bridge("mid", Vector2.ZERO, BRIDGE_SPAN_MID)`）。

### 11.1 传送阵造型与状态表现（2026-11-11 升级）

**改前的实际状态**：两座阵是 `arena._add_map_disc()` 画的一块青色薄饼 + `_add_map_totem()` 立的一根灰杆。
俯视下它和野区营地的圆盘**几乎一模一样**，玩家读不出「这个角落是传送阵」；
更读不出「现在有人正在这里读条」—— 引导进度只体现在英雄脚下的 `ChannelFx` 法阵上，
阵本身全程是一张静止贴图。灰杆还正好从阵心穿出来，把中间切开一条竖线。

现在造型与状态收在**一个新文件**里，Arena 只给世界坐标与朝向：

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/game/portal_visual.gd` | 石台 / 符文轮 / 三根方尖柱 / 浮空晶体 / 点光源，以及「进度 → 外观」的纯函数 | 470 行 |
| `shaders/teleport_rune.gdshader` | 符文轮：三层差速齿环 + 六芒星内阵 + 读数指针 + 呼吸/裂开 | 140 行 |
| `tools/portal_shot.gd` | 验收截图（待机 / 起手 / 过半 / 将满 / 抵达 / 打断 / 总览） | 150 行 |
| `tests/test_portal_visual.gd` | 16 条契约（几何 / 状态映射 / 接线守卫 / 着色器） | 280 行 |

**接线只有三处**（全在表现层，sim / 协议一行没动）：

1. `Arena._build_map_features()` → `_build_portal(pad)`：建两座阵，根节点名 `portal_<pad_id>`；
2. `Arena._process()` → `_tick_portals(delta)`：每帧喂引导进度；
3. `_handle_channel_departure()` / `_handle_channel_break()` → `_flash_portal_at()` / `_shatter_portal_at()`：
   抵达点亮对端的阵、打断让符文裂开。

**引导进度怎么读**：快照白名单里**没有** `teleport_pad` 字段，所以不能按 pad id 匹配。
但引导期间英雄不能移动（移动就打断），**位置就是阵心** —— 于是按位置判定，
主客机拿的是同一份数据，不需要动协议。见 `PortalVisual.charge_from_entities()`。

**五条设计口径**（都是看实拍图 + 量像素改出来的，别凭手感推翻）：

1. **石台半径必须 = 传送判定半径**（`PortalVisual.DAIS_RADIUS == MapLayout.PAD_DISC_RADIUS`）。
   两处各写一个 3.0 的下场是「看着站在台上、按下去没反应」。
2. **柱子必须立在阵盘之外**（`PILLAR_RADIUS 3.42 > DAIS_RADIUS 3.0`）。立在阵内会挡住读条的人，
   51° 俯角下柱影正好压在阵心上。
3. **台面必须真的暗，但不能是黑洞**。第一版台面 `albedo 0.255` 经 FILMIC + 曝光 1.05 后
   实测落到 175/255，加法混合的阵纹叠上去直接推成 255 全白 —— 外环、齿、六芒星、读数弧
   全糊成一块白饼，什么都读不出。压到 `0.055` 又过头：实测 41/255，而阵外草地 178 ——
   那不是石板，是草地上一个洞，第一眼读成「坑」。**0.105 落在 91**，两头都成立。
   写这类数值前先用探针量一遍，别靠肉眼。
4. **符文必须收敛到「清楚可见」就到顶**，不能继续堆亮度。`band_gain`（0.60）是亮度口径的
   唯一闸门。引导进度的变化放在**形状**（线变粗、扫过的弧）与**读数指针**上 ——
   纯靠亮度从 start 到 late 只差 0~15 个 luminance 单位，实战里根本数不出来。
5. **点光源待机必须熄灭**。两盏常亮的 `OmniLight3D` 在移动端是最先吃掉帧预算的东西之一；
   引导/闪光时才点亮（`light_energy(0,0) == 0` 有测试钉住）。

**着色器必须用完就跑一次真实渲染再交**：`const float TAU = ...` 会重定义 Godot 内置常量，
后果是**编译失败 → 材质回落纯白**，整块石台变成一张白纸。这个失效不报错、
headless 测试也全绿（日志里只有一行 `SHADER ERROR`），只有在 1600×900 的整图里
才看得出来 —— 而且很容易漏。`test_portal_visual` 现在按名字逐条拦住内置常量重定义。

**验证**（截图必须开渲染上下文，走隐藏桌面，见 `AGENTS.md` 环境硬约束）：

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\portal_shot.gd
:: 产物：godot/shots/portal_idle.png / portal_idle_far.png / portal_charge_{start,mid,late}.png
::       / portal_arrive.png / portal_break.png / portal_sheet.png（不入库）
```

`portal_idle_far.png` 是 21 米默认对局机位：**先看这张**。近景好看不代表实战里认得出，
而这张才是玩家 90% 时间看到的距离。`portal_sheet.png` 看两座阵的相对位置与和河道之灵的分色。

**性能**：两座阵各约 22 个 `MeshInstance3D`（3 层石台 + 12 块缘石 + 3 根柱的各 5 段 + 晶体 + 符文 + 光池），
材质与网格全部走 `PortalVisual` 的静态缓存，同屏两座共享同一批资源。
点光源 `shadow_enabled = false`，不参与 shadow pass。

---

## 12. 移动端性能（2026-10-28）

**症状**：手机移动英雄、镜头扫过地图时卡顿。离屏探针 `tools/perf_check.gd` 在 1600×900 5v5 下约 34 FPS；自转镜头约 20~27 FPS，静态和移动差 10+ FPS，说明瓶颈在**像素填充/阴影**，不是模拟 tick。

**实测大头**（`_probe_perf_move.gd` 离线探针，已删除）：
- 整屏地表 shader：6 次纹理采样，移动镜头时铺满屏幕；
- 阴影 pass：关闭太阳阴影 FPS +7 左右，且墙体 Rock 曾全部逐块投射；
- 墙石数百个独立 draw call；
- 草簇 12000 个 MultiMesh 实例。

**移动端已做的降级**（桌面不受影响）：
- `project.godot`：`scaling_3d/scale.mobile = 0.72`（原 0.82）；
- 地表 shader 只保留 1 层草 + 1 层泥土，去掉第二层草与法线采样（`TerrainBuilder.build_material(true)` 可单测）；
- 草簇 12000 → 6000；
- 太阳阴影距离 48 → 36 米，边界岩脊/角岩批次不投影，地形不投影；
- 墙石（岩脊、墙脚石、边界角岩、碎石）合并成 `wall_rocks` / `boundary_rocks` 两个 MultiMesh，每个 1 个 draw call；逐块数据在 `rock_specs` meta 里，测试仍逐块校验。

改墙石时不要退回「每块一个 MeshInstance」：移动端最先炸的就是 draw call 和 shadow pass。桌面全量画质仍走完整 shader 和 48 米阴影，不要拿移动端帧率反推桌面参数。

---

## 13. 基地水晶美术（2026-11-12 二轮）

> 本节在 2026-11-12 被一次跨会话的文档合并误删，现按 `crystal_visual.gd` 与
> `test_crystal_*.gd` **重新整理**（源码与测试一直是完整的，没有丢失）。
> 如果原作者保留了更详细的版本，以那份为准；这里只保证「下一任模型读得到约束」。

主堡原版是「一颗六棱球 + 圆柱台座 + 一道 torus 光圈 + 一根半透明圆柱光柱」，
21 米机位下能读成「蓝/红发光球」，但离王者的水晶差很远：没有台基层次、
没有晶簇、没有环绕碎片、没有符文轮，两个阵营只靠球体颜色区分。

### 13.1 文件分工

| 文件 | 职责 |
| --- | --- |
| `scripts/game/crystal_visual.gd` | 造型 + 状态表现：五层结构、`build()`、`apply_state()`、`apply_damage()`、`apply_shield()`，以及纯函数 `damage_tone()` / `gem_energy()` / `shield_strength()` |
| `shaders/crystal_beam.gdshader` | 双层光柱 |
| `shaders/crystal_sigil.gdshader` | 贴地法阵 |
| `shaders/crystal_shield.gdshader` | 护盾球壳 |
| `shaders/crystal_energy.gdshader` | 二轮新增：能量外壳（fresnel 亮边 + 内部流光上涌 + 晶尖呼吸） |
| `tests/test_crystal_visual.gd` | 造型 / 调色 / 淡化契约 / 残破曲线 / 轨道碎片 |
| `tests/test_crystal_energy.gd` | 二轮观感层：能量外壳、金环符文、晶尖配色、网格预算 |
| `tests/test_crystal_occlusion.gd` | 遮挡淡化：哪些部件必须淡、哪些绝不能淡 |
| `tests/test_high_ground_crystal.gd` | 高地水晶 + 双子塔 + 护盾状态接线 |
| `tools/crystal_gallery.gd` | 画廊：两座同框 / 蓝顶视 / 蓝近景 / 红近景 / 红护盾 / 蓝残破 / 蓝淡化 |

### 13.2 五层结构（每层在俯视机位下各承担一个可读信号）

1. **台基 `dais`**：三层收分圆台 + 8 块径向石墩 + 8 道弧槽 + 金环压边；
2. **柱座 `pedestal`**：8 棱收分石柱 + 8 片花瓣托 + 4 条拱券石肋；
3. **晶簇 `gem`**：一根 4.35 m 主晶 + 3 根贴地副晶，全部是**平面法线**多面体；
4. **环绕 `rings` / `shards` / `halo`**：三层差速金环 + 6 块轨道碎片 + 一道斜光环；
5. **光效 `beam` / `sigil` / `shield`**：双层光柱 + 贴地法阵 + 双壁护盾。

### 13.3 三条不能改的契约（测试逐条抓）

1. **`pedestal` / `gem` 必须在 `crystal_fade_parts` 里**，且材质常驻 `TRANSPARENCY_ALPHA`。
   英雄走进泉水时要把挡视线的部分淡到 `OcclusionFade.MIN_VISIBLE`；
   **`dais` 是贴地定位线，绝不能跟着淡** —— 淡了英雄就像浮在空中。
2. **所有每帧动画只改 transform / 材质参数**，不新建节点、不新建材质（硬规则 4）。
   材质**不做静态缓存**：`OcclusionFade` 会直接改 `albedo_color.a`，静态缓存会被
   同一进程里的下一局复用，上一局淡到 0.16 的水晶会在新局里一出生就半透明。
   **网格**仍然缓存（一局只有两座主堡，逐座 new 材质的代价可以忽略）。
3. **主晶顶部必须高于柱座，晶簇宽度不得超出台基** —— 否则是「一坨浮在台座外面的碎片」。
   二轮新增部件后，网格数仍卡在 34 以内（`test_crystal_tip_keeps_faction_colour_and_mesh_budget_holds`）。

### 13.4 二轮改了什么（只改观感，不动分层与接线）

首版实拍是「实心蓝塑料宝石 + 三圈黑铁丝 + 灰白井盖底座」：结构和王者对齐了，质感没对齐。

- `gem_energy` 能量外壳：复用 gem 网格再画一遍加法薄壳，**不新建几何**；
- 晶尖去白帽、棱线降亮：阵营色一直贯到顶端，不再像「红宝石上插了截白蜡」；
- 金环加粗 + 自发光 + 等距符文：远景从「铁丝」变成「在运转的能量环」；
- 轨道碎片从水滴改扁晶片：主堡周围应该是碎裂的晶屑，不是六颗雨滴；
- 光柱去白灯管 + 加上升光屑；护盾保住阵营色；台基黑辐条改金属嵌条；法阵加一层贴地柔光池。

### 13.5 验证

```cmd
powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\crystal_gallery.gd
:: 产物：godot/shots/crystal_bases_field.png / crystal_blue_top.png / crystal_blue_closeup.png
::       crystal_red_closeup.png / crystal_red_shield.png / crystal_blue_damaged.png / crystal_blue_faded.png
```

着色器必须真的跑一次渲染再交：`const float TAU = ...` 会重定义 Godot 内置常量，
后果是**编译失败 → 材质回落纯白**，日志里只有一行 `SHADER ERROR`，headless 测试也全绿。
`test_crystal_energy` 与 `test_portal_visual` 都按名字逐条拦住内置常量重定义。
