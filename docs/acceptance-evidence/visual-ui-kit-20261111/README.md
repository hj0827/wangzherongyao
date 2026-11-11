# 视觉第二批 · UI 骨架资产 验收证据（2026-11-11）

基线 commit：`e182432`（本批改动**尚未提交**，工作树）｜ Godot：4.7.2-stable ｜ 窗口：1600×900
原则：这批是**程序化骨架 / 占位**，目标是先固定"布局 + 比例 + 显隐逻辑 + 验收断言"，
手绘或 AI 位图到位后只覆盖同名 PNG，**不改** `game_theme` 访问器、HUD 接线与测试。

---

## 1. 本批做了什么

| 产出 | 文件 | 消费方（生产引用） |
| --- | --- | --- |
| 生成器（确定性、headless、零依赖） | `godot/tools/make_ui_assets.gd` | 离线运行；`--only=frames\|banners\|mvp` |
| 9-slice 边框 6 张 | `assets/ui/frames/{panel_gold,button_gold,slot_quality_basic/rare/epic/legendary}.png` | `GameTheme.ornate_panel()/button_frame()/quality_frame()` → `shop_panel.gd`（格子/买按钮/快捷购买）、`game_hud.gd`（结算返回按钮） |
| 击杀横幅 + 连杀纹章 6 张 | `assets/ui/banners/{kill_banner,streak_first/double/triple/quadra/penta}.png` | `GameHUD.show_kill_banner()`，由 `arena.gd::_handle_death_event` 用 `KILL_STREAK_LEVEL` 驱动 |
| 结算页 3 张 | `assets/ui/mvp/{mvp_bg,medal_mvp,medal_participation}.png` | `GameHUD.show_result()`（背景 + 按 KDA 切换勋章） |
| 新增测试 | `godot/tests/test_ui_assets_p1.gd`（9 条） | — |
| 合规登记 | `docs/art-credits.md`（新建，此前不存在） | G7 |

---

## 2. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

- 末行：`TESTS: 1028  PASSED: 1028  FAILED: 0`（本批前 1019 → +9 条）
- `FAIL` 行：0
- **`ERROR:` 扫描**：只剩与基线完全相同的既有噪声，本批新增用例内 0 条
  - `Parameter "material" is null` ×4 —— 出现在既有 `test_hero_silhouette.gd:26`（headless dummy renderer）
  - `Parse JSON failed` —— `test_lan_discovery` 的负例，故意触发
  - 退出期 RID/instance 泄漏 —— 与本批无关
- 生成器确定性：全量重跑两次 15/15 产物哈希一致；`--only=mvp` 与全量跑出的 `mvp_bg.png` 也一致（**顺序无关**）
  - 过程中抓到并修掉一个真缺陷：`_row_patch` 原来用 `Color.to_html(true)` 做缓存键，8bit 量化会把不同资产的相近颜色混成同一个 patch，
    于是产物随"先生成哪一类"变化 —— 已改为浮点全精度键。

## 3. G2 变异关

| # | 变异点 | 预期 | 实测 |
| --- | --- | --- | --- |
| M1 | `GameTheme.quality_frame()` 的 `tier` 写死 `"basic"` | 商店品质框 + 品质差异断言变红 | ✅ 红（2 条：`basic 与 epic 必须是两张不同的品质框`、`品质框与品质不符：infinity_edge（epic）` 等） |
| M2 | `show_kill_banner()` 里 `streak_emblem(streak)` 改成 `streak_emblem(1)` | 纹章跟随连杀的断言变红 | ✅ 红（2 条） |
| M3 | `show_result()` 里勋章写死 `mvp_medal(true)` | 参战勋章断言变红 | ✅ 红（1 条：`0/3 要挂参战勋章`） |

**M1 第一次没变红 —— 抓到的是测试自己的缺陷**：原断言是
`style.texture == GameTheme.quality_frame(quality).texture`，两边同源，改坏被一起改坏，恒真。
已改成按「品质 → 文件名」直接 `load(GameTheme.QUALITY_FRAME_DIR + quality + ".png")` 比对，
并补一条"basic 与 epic 必须不同"。同理，纹章断言也改成直接 `load(... + "triple.png")`。
> 这条正是 `03-tdd.md` §5 的变异验证存在的理由：**自证式断言等于没有断言**。

## 4. G3 接线关

```
grep -rn "button_frame|quality_frame|kill_banner|streak_emblem|mvp_background|mvp_medal|show_kill_banner"
```

命中生产文件（非 tests/tools）：

| 文件 | 命中数 | 说明 |
| --- | --- | --- |
| `scripts/ui/game_theme.gd` | 15 | 路径常量 + 访问器 + 缓存 |
| `scripts/ui/game_hud.gd` | 10 | 击杀横幅节点与显隐、结算页背景/勋章、返回按钮边框 |
| `scripts/ui/shop_panel.gd` | 5 | 格子品质框、买按钮、快捷购买按钮 |
| `scripts/game/arena.gd` | 1 | 击杀事件 → `show_kill_banner()` |

协议影响：**无**。击杀横幅的连杀等级来自 sim 已有的 `announcement` 字段（本就在 `_sanitize_event` 白名单内），
客户端不新增判定、不新增字段，联机两端同源。

## 5. G4 视觉关（`godot/shots/`，不入库）

命令：`godot --path godot --script res://.tmp/kit_shot.gd`（本地探针，`.tmp/` 已忽略）

| 截图 | 看什么 | 结论 |
| --- | --- | --- |
| `kit_kill_banner_penta.png` | 横幅底图 / 双方头像金框 / 中央文案 / 五杀纹章 | ✅ 头像嵌框、无拉伸、纹章在横幅上沿 |
| `kit_kill_banner_tower.png` | 非英雄击杀只留受害者 | ✅ 左侧头像位**整格收起**（不是空金环） |
| `kit_result_mvp.png` | 结算页背景 + MVP 勋章 + 金边按钮 | ✅ 背景 1.5:1 无拉伸，勋章与标题不打架 |
| `kit_result_participation.png` | 0/3 时换参战勋章 | ✅ 钢色勋章 |
| `kit_shop_quality.png` | 商店格子品质框（basic 灰 / rare 蓝 / epic 紫）+ 金边按钮 | ✅ 品质一眼可分 |

## 6. G6 性能关 / G7 资产合规 / G8 真机

- **G6**：本批不新增战斗路径节点（横幅在 `_ready` 建一次，事件只改 `texture` 与 `visible`），
  但**桌面 ≥60fps 的目标仍未达成**（既有基线：Quadro K420 / 1600×900 = 32fps），不因本批改善。
- **G7**：新建 [`docs/art-credits.md`](../../art-credits.md)。本批 15 张登记为"程序化生成 / 项目自有 / 可复现"。
  既有第三方 glb 与 AI 立绘仍为 ⬜/🟨，已列清单待项 15.2 收口。
- **G8**：`adb` 不在 PATH、无设备，真机未跑（与第一批相同的环境阻塞）。

## 7. 未做 / 下一步

- [ ] 击杀横幅的逐杀配色差异（现在只有 5 张纹章区分等级，横幅本体是同一张）
- [ ] 结算页数据条 / 点赞（UI-06 剩余项）
- [ ] UI-07 仍非"全量面板"：只接了商店与结算
- [ ] 用手绘 / AI 位图替换骨架，并同步更新 `docs/art-credits.md` 对应行
- [ ] `tools/art_credits_audit.py`（缺登记即失败，进 CI 静态段）

## 8. 签字

| 项 | 结论 | 证据 | 签字 | 日期 |
| --- | --- | --- | --- | --- |
| G1 机器 | ✅ 1028/1028，ERROR 扫描无新增 | `.tmp/tests_uikit_final.log` | 待签 | 2026-11-11 |
| G2 变异 | ✅ 3/3 变红（并修正 1 条自证式断言） | 本文件 §3 | 待签 | 2026-11-11 |
| G3 接线 | ✅ 生产引用 31 处，协议无改动 | 本文件 §4 | 待签 | 2026-11-11 |
| G4 视觉 | 🟨 5 张截图已目视，待第二人复核 | `godot/shots/kit_*.png` | 待签 | 2026-11-11 |
| G6 性能 | ❌ 未达标（既有 32fps，非本批引入） | — | — | 2026-11-11 |
| G7 合规 | 🟨 本批 ✅ / 既有第三方与 AI 资产待补 | `docs/art-credits.md` | 待签 | 2026-11-11 |
| G8 真机 | ⬜ 无设备 | `adb` 缺失 | — | 2026-11-11 |

---

## 9. 追加：面板统一（同批次后续，2026-11-11）

把金边 9-slice 从"商店/结算"推到常驻界面。**没有新增资产**，复用已有的 `panel_gold.png`。

### 9.1 做法（为什么不是简单替换）

- 新增 `GameTheme.panel_frame(content_x := 14, content_y := 10, tint := WHITE)`：
  内容边距**默认值与 `GameTheme.style()` 完全一致**，所以把已有 `StyleBoxFlat` 换成它时
  面板最小尺寸不变 —— 否则"换皮"会悄悄顶破已经标定过的布局（本仓库踩过尺寸回归的坑）。
- 选中/未选中不新出资产：`StyleBoxTexture.modulate_color` 把同一张金边调暗即可。

### 9.2 接入点

| 界面 | 位置 | 说明 |
| --- | --- | --- |
| 计分板主面板 | `scoreboard.gd` `_build()` | 1240×470，内容边距保持 14/10 |
| 暂停面板 | `game_hud.gd::_build_pause_overlay()` | 内容边距保持 14/10 |
| 选人页 5 张英雄卡 | `main.gd::_refresh_hero_selection()` | 内容边距保持 6/6；选中 `WHITE`、未选中 `Color(0.60,0.58,0.62)` |
| 台词横幅 | `main.gd::_show_hero_select()` | 内容边距保持 28/8 |

未接入（有意）：大厅房间面板（边框承担蓝/红队伍色语义，需另出两套边）、
小地图与 HUD 小面板（9-slice 最小尺寸 48px 会把它们顶大）。

### 9.3 证据

- **G1**：`TESTS: 1033  PASSED: 1033  FAILED: 0`（+5 条）；`ERROR:` 扫描仍只有既有噪声。
- **G2 变异 3/3 变红**：

  | # | 变异点 | 实测 |
  | --- | --- | --- |
  | M1 | `panel_frame()` 内容边距各 +4 | ✅ 红 7 条（含"卡片内容边距必须保持 6"） |
  | M2 | 计分板改回 `style()`（不接线） | ✅ 红 1 条（"计分板面板必须是 9-slice 金边"） |
  | M3 | 未选中卡片 tint 改成与选中同亮 | ✅ 红 1 条（"选中的卡片要比未选中更亮"） |

- **G3**：`grep panel_frame` 命中生产文件 `game_theme.gd` / `scoreboard.gd` / `game_hud.gd` / `main.gd`。
- **G4**：`godot --path godot --script res://.tmp/panel_shot.gd` → 三张图目视通过：
  - `kit_hero_select.png`：5 张卡全部金边，选中的翎羽明显更亮，台词横幅金边
  - `kit_pause.png`：暂停面板金边 + 角饰，按钮不被边饰挤压
  - `kit_scoreboard.png`：外框金边，蓝/红两列仍保留队伍色边框（层级分明）
- 测试用例：`godot/tests/test_panel_frames.gd`（5 条，建真实节点而非只读源码字符串）。
