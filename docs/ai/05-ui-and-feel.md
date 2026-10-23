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
| `scripts/ui/game_theme.gd` | 配色、字体、StyleBox | 132 行 |
| `scripts/game/arena.gd` | 3D 表现：相机、特效、飘字、震屏、指示环、输入 | 2544 行 |
| `scripts/game/unit_visual.gd` | 单位装配、骨骼动画、头顶血条 | 809 行 |

---

## 2. 布局常量（改之前先看这里，别自己拍脑袋）

```gdscript
# touch_layout.gd
const BOTTOM_PANEL_HEIGHT := 180.0     # 触控底栏
const SKILL_TOUCH_SIZE := Vector2(128, 148)
const SKILL_DESKTOP_SIZE := Vector2(96, 112)
const ATTACK_BUTTON_SIZE := 152.0
const ATTACK_MARGIN := Vector2(18, 40)
const SKILL_ARC_RADIUS := 330.0
const SKILL_ARC_ANGLES_DEG := [185.0, 210.0, 235.0, 260.0]   # 四个技能位
const UTILITY_BUTTON_SIZE := Vector2(96, 96)
const UTILITY_SUMMONER_RECT := Rect2(-784.0, -326.0, 96.0, 96.0)
const UTILITY_TELEPORT_RECT := Rect2(-688.0, -326.0, 96.0, 96.0)
const UTILITY_RECALL_RECT := Rect2(-592.0, -326.0, 96.0, 96.0)
```

半径 330 是为了让四个 128×148 的技能触摸区沿弧线互不重叠；回城/传送/召唤师另起一排放在技能弧上方，右下角锚点偏移见上，**不要再塞回 Q 旁边**——真机上回城键会盖住 Q 的触摸区（`UI-01` 与 `test_utility_buttons_do_not_cover_the_skill_arc` 会抓）。

桌面底栏高度写死在 `game_hud.gd:_build_bottom_panel()`：`160.0`，宽度 `840`（`-420 .. 420`）。

**已知观感问题**：在 900 高的虚拟分辨率里，底栏占 160~180px ≈ 屏高的 18~20%，加上底部 inset 后视觉占比更大，会压住战场下方视野。想压缩时改这两个数，注意别把血条文字挤出面板。

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

**运行时仍然没有的东西**（写新反馈时别去找）：受击闪白、击退、护盾吸收飘字、低血量屏幕边缘红晕、完整音效资产（目前只有草丛进出等少量合成音）。

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
- [ ] 用了 `queue_free()` 吗？（高频对象应该回池）
- [ ] 特效颜色是不是落到了默认分支？（`_hero_vfx_color()` 只认 4 个英雄）
- [ ] 5v5 满员时会不会糊成一片？（同屏 10 英雄 + 几十小兵）
- [ ] 截图存到 `godot/shots/` 了吗？（别提交）
