# UI、手感与表现层

> 只在"改 HUD / 触控布局 / 特效 / 打击感 / 播报"时读这份。

---

## 1. 文件分工

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/ui/game_hud.gd` | 局内全部 2D：顶栏、小地图、底栏、技能键、商店/播报、死亡/结算/暂停遮罩 | 1131 行 |
| `scripts/ui/minimap.gd` | 小地图绘制（206×206）+ 点击查情报 | 278 行 |
| `scripts/ui/skill_button.gd` | 单个技能键（CD 扇形遮罩、法力不足、禁用态、触摸拖拽） | 134 行 |
| `scripts/ui/shop_panel.gd` | 商店面板：购买/出售/快速购买、金币显示 | 207 行 |
| `scripts/ui/attack_cluster.gd` | 攻击键簇：补刀/推塔模式切换、头像锁敌 | 159 行 |
| `scripts/ui/touch_joystick.gd` / `touch_action_button.gd` | 摇杆 / 圆形动作键 | 91 / 77 行 |
| `scripts/ui/touch_layout.gd` | 触控尺寸与弧度的**唯一常量源** | 36 行 |
| `scripts/ui/hud_layout.gd` | 常驻 HUD 分区的**唯一坐标源**（桌面/触屏两套），纯数据、可无头测 | 132 行 |
| `scripts/ui/game_theme.gd` | 配色、字体、StyleBox | 132 行 |
| `scripts/game/arena.gd` | 3D 表现：相机、特效、飘字、震屏、指示环、输入 | 2544 行 |
| `scripts/game/unit_visual.gd` | 单位装配、骨骼动画、头顶血条 | 809 行 |

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

## 3. 表现层的三个硬约束

1. **只能读快照**：`set_snapshot()` 里不许回写 `hp`、不许触发结算。
2. **高频对象走池**：飘字、粒子、弹道必须从 `_damage_labels_pool` / `_hit_particles_pool` 取，用完 `visible=false` 放回，**不要 `queue_free()`**。
3. **事件驱动，不要轮询**：一次性表现（技能、击杀、塔毁）挂在 `_process_events(events)` 的 `match` 分支里，不要每帧扫描状态变化。

---

## 4. 现有反馈手段与具体数值

| 手段 | 位置 | 现状 |
| --- | --- | --- |
| 伤害飘字 | `arena._spawn_damage_number()` | 只有数字；`amount >= 150` 金色，否则近白；上飘 0.9、0.65s 淡出 |
| 命中粒子 | `_handle_hit_event()` | 英雄 10 颗，小兵/建筑 4 颗 |
| 震屏 | `_camera_shake` + `_hit_stop` | 受击 `0.12`、坦克技能 `0.18`；顿帧触发时附加击退感 shake |
| 顿帧 | `scripts/view/hit_stop_manager.gd` | 暴击/击杀/破塔/破盾/终局分别触发；只冻结表现层，模拟与网络照常 |
| 范围环 | `_spawn_ring()` / `_flash_skill_range()` | 技能命中/施放时闪一次；触摸拖拽时由 `SkillIndicator` 实时绘制 |
| 技能指示器 | `scripts/ui/skill_indicator.gd` | 触摸按下技能键后显示圆形/直线/扇形指示，松手施放 |
| 取消施法区 | `scripts/ui/cancel_cast_zone.gd` | 触摸拖拽到屏幕上方取消区，松手中断施法 |
| 弹道/光束 | `_spawn_projectile()` / `_spawn_beam()` | 法师/射手技能、塔攻击共用 |
| 播报 | `hud.announce()` | 中央横幅，0.18s 淡入 → 停留 → 0.4s 淡出 |
| 多杀/一血/团灭 | `sim/combat_announcer.gd` → `arena._handle_death_event()` | 双杀/三杀/四杀/五杀/终结/团灭/一血，两端看到同一份结果 |
| 战报 | `hud.add_feed()` | 右上滚动 6 条，4.5s 后淡出 |
| 死亡遮罩 | `_build_death_overlay()` | 全屏红 48% + 复活倒计时 + 击杀者名 |

**运行时仍然没有的东西**（写新反馈时别去找）：受击闪白、击退、护盾吸收飘字、低血量屏幕边缘红晕。

音频**有**了（2026-10-23 补齐），见 §9：战斗/菜单 BGM + 38 条合成音效。没有音频资源文件，全部现场合成。

**接线状态**：顿帧、多杀播报、技能指示器、取消施法区都已接入生产代码（见 `01-repo-reality.md` §4）。新增反馈模块时照旧要先 `grep` 确认生产引用，不能只写测试。

---

## 5. 触控与桌面的双路径

`game_hud.gd` 里几乎每个构建函数都有 `if touch_mode:` 分支，两套按钮、两套布局、两套提示文案。

**规则**：改 UI 必须两条路径都改，并且各截一张图确认。只改一条的典型症状是——桌面正常、手机上按钮重叠。

截图验证：

```cmd
godot --path godot --script res://tools/ui_shot.gd
godot --path godot --script res://tools/mobile_shot.gd
```

产物在 `godot/shots/`（不入库）。

---

## 6. 技能键的现状与扩展点

`skill_button.gd` 是纯 `Control` + `_draw()` 手绘：外圈、CD 扇形遮罩、剩余秒数、技能名、法力不足提示。

- **交互**：桌面是鼠标左键按下即发（瞄准点来自 `arena._local_input.aim` 的地面投影）。触屏是"按下出指示器 → 拖拽调方向 → 松手施放"，拖到顶部中央取消区（半径 66）松手则取消。
- 触屏拖拽由 `skill_button.gd` 的 `drag_started/updated/released` 三个信号驱动，`game_hud.gd` 用 `SkillIndicator` 画方向/落点、用 `CancelCastZone` 判定取消并变色。**按钮自身不再直接 emit `pressed`**，触摸分支和鼠标分支是两套代码。
- HUD 建 **Q / W / E / R + 召唤师（F）+ 回城**：桌面 W 技能绑数字键 `1`（键盘 W 用于走位），按钮上直接标注实际键位；触屏按钮沿右下弧线排布。
- 新技能槽的扩展点：`_create_skill(slot, key, accent)` + `_skill_button_for(slot)`，两处都要加分支；`skill_button.gd` 的触摸/鼠标分支也要同步。

---

## 7. 头顶血条

`shaders/billboard_bar.gdshader`，尺寸 `1.24 × 0.14`（英雄），小兵 `0.62` 宽，带法力条。

- 填充是**连续** `ratio`，**没有分段刻度**（王者是每 1000 血一格）。
- 加了护盾会在血条右侧叠一段白色 `shield_ratio`。
- **不要换成 `BaseMaterial3D.BILLBOARD_ENABLED`**，原因见 `02-godot-pitfalls.md` §3。

---

## 8. 改表现时的自查

- [ ] 桌面上看过了吗？触控模式下看过了吗？
- [ ] 常驻面板的位置是从 `hud_layout.zones()` 取的吗？（别手写 anchor/offset）
- [ ] 新面板/新文案把最小尺寸顶大了吗？（`probe_hud_rects.gd` 量一遍，回填分区表）
- [ ] 用了 `queue_free()` 吗？（高频对象应该回池）
- [ ] 特效颜色是不是落到了默认分支？（`_hero_vfx_color()` 只认 4 个英雄）
- [ ] 5v5 满员时会不会糊成一片？（同屏 10 英雄 + 几十小兵）
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
