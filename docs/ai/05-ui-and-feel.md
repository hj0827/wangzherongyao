# UI、手感与表现层

> 只在"改 HUD / 触控布局 / 特效 / 打击感 / 播报"时读这份。

---

## 1. 文件分工

| 文件 | 职责 | 规模 |
| --- | --- | --- |
| `scripts/ui/game_hud.gd` | 局内全部 2D：顶栏、小地图、底栏、技能键、播报、死亡/结算/暂停遮罩 | 813 行 |
| `scripts/ui/minimap.gd` | 小地图绘制（206×206）+ 点击查情报 | 149 行 |
| `scripts/ui/skill_button.gd` | 单个技能键（CD 扇形遮罩、法力不足、禁用态） | 111 行 |
| `scripts/ui/touch_joystick.gd` / `touch_action_button.gd` | 摇杆 / 圆形动作键 | 91 / 77 行 |
| `scripts/ui/touch_layout.gd` | 触控尺寸与弧度的**唯一常量源** | 常量 |
| `scripts/ui/game_theme.gd` | 配色、字体、StyleBox | 132 行 |
| `scripts/game/arena.gd` | 3D 表现：相机、特效、飘字、震屏、指示环、输入 | 1921 行 |
| `scripts/game/unit_visual.gd` | 单位装配、骨骼动画、头顶血条 | 758 行 |

---

## 2. 布局常量（改之前先看这里，别自己拍脑袋）

```gdscript
# touch_layout.gd
const BOTTOM_PANEL_HEIGHT := 180.0     # 触控底栏
const SKILL_TOUCH_SIZE := Vector2(128, 148)
const SKILL_DESKTOP_SIZE := Vector2(96, 112)
const ATTACK_BUTTON_SIZE := 152.0
const ATTACK_MARGIN := Vector2(18, 40)
const SKILL_ARC_RADIUS := 210.0
const SKILL_ARC_ANGLES_DEG := [190.0, 255.0]   # ← 只有两个技能位
```

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
| 震屏 | `_camera_shake` | **只有两档**：受击 `0.12`、坦克技能 `0.18`；线性衰减 `delta * 1.8` |
| 范围环 | `_spawn_ring()` / `_flash_skill_range()` | 按下技能键时闪一次，不是持续指示器 |
| 弹道/光束 | `_spawn_projectile()` / `_spawn_beam()` | 法师/射手技能、塔攻击共用 |
| 播报 | `hud.announce()` | 中央横幅，0.18s 淡入 → 停留 → 0.4s 淡出 |
| 战报 | `hud.add_feed()` | 右上滚动 6 条，4.5s 后淡出 |
| 死亡遮罩 | `_build_death_overlay()` | 全屏红 48% + 复活倒计时 + 击杀者名 |

**运行时没有的东西**（写新反馈时别去找）：顿帧 / hit-stop、受击闪白、击退、暴击区分、护盾吸收飘字、低血量屏幕边缘红晕、任何音效。

**注意区分"没有"和"没接"**：`scripts/view/hit_stop_manager.gd`（顿帧）、`sim/combat_announcer.gd`（多杀播报）、`scripts/ui/skill_indicator.gd`（指示器）、`scripts/ui/cancel_cast_zone.gd`（取消施法）**文件都存在、测试都绿，但没有任何生产代码调用它们**。见 `01-repo-reality.md` §4。

想启用它们，工作内容是"接线"（在 `arena._process_events` / `_handle_hit_event` / `game_hud` 里调起来），不是"重新实现"。

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

- **交互**：触屏是"按下即 `pressed.emit()`"；桌面是鼠标左键按下即发。**没有拖拽瞄准、没有取消施法**。
- 瞄准点来自 `arena._local_input.aim`（鼠标地面投影 / 最后一次触控点），不是按钮拖拽向量。
- HUD 当前只建 **Q / E 两个技能键**，外加一个回城键（`_recall_button`）。

### 想加"按住拖拽调方向 + 拖到取消区松手取消"

**不用从零写**：`scripts/ui/skill_indicator.gd` 和 `scripts/ui/cancel_cast_zone.gd` 已经实现了，测试也覆盖了（`tests/test_indicators_and_cancel.gd`）。要做的是：

1. 在 `game_hud.gd` 里实例化并挂到技能键上
2. 把 `skill_button.gd:_gui_input()` 从"按下即发"改成状态机：按下出指示器 → 拖拽更新 `aim` → 松手提交或取消
3. `arena.gd` 侧不用动——`cast_skill()` 本来就接受任意 `aim` 点

**注意**：`skill_button.gd` 的触摸分支和鼠标分支是两套代码，改的时候两边都要动。

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
