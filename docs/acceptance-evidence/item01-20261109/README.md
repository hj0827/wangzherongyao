# 项 1 验收证据 · 战斗属性系统

日期：2026-11-09 ｜ 基线：747 → **783 用例全绿**（新增 36 条）
配套：[验收表 项1](../../acceptance-vs-honor-of-kings.md) ｜ [差距文档 §3.1](../../gap-analysis-vs-honor-of-kings.md)

---

## 1. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
TESTS: 783  PASSED: 783  FAILED: 0
```

假绿扫描（`03-tdd.md` §1）：日志中 `SCRIPT ERROR|Invalid call|Nonexistent|Cannot load|out of bounds` **命中 0 行**。

> 这一扫描真抓到过一次假绿：`test_board_stats_survive_the_wire` 首版误写 `sim._snapshot()`，
> 断言在求值前抛错中断、`failures` 仍为空 → 框架打印 PASS。修正为 `sim.snapshot()` 后才是真绿。

新套件：`godot/tests/test_damage_types.gd`（36 条，自动发现无需注册）。

## 2. G2 变异关（19 条，全部变红后字节级还原）

| # | 变异点 | 变红的用例 |
| --- | --- | --- |
| M1 | 减伤公式整体失效 | physical / magic / pve叠加 / 回归护栏（4 条） |
| M2 | 物理读魔抗（接反） | 3 条 |
| M3 | 暴伤退回硬编码 1.5 | crit_damage 字段化 |
| M4 | 普攻间隔不吃攻速 | try_attack 有效间隔 |
| M5 | 被动攻速不进间隔函数 | 2 条 |
| M6 | 被动窗口不清账 | archer 被动 |
| M7 | CDR 不封顶 | CDR 上限 |
| M8 | 回复不吃 hp_regen | hp_regen 属性化 |
| M9 | 快照漏 armor | snapshot 链路 |
| M10 | board 漏 armor | board 链路 |
| M11 | W/R 路径不吃 CDR | cast_skill CDR |
| M12 | 终结不是真实伤害 | execute 真伤 |
| M13 | 装备护甲不聚合 | 防御装给抗性 |
| M14 | 白名单漏 magic_resist | 2 条 |
| M15 | 白名单不封顶魔抗 | clamp 守卫 |
| M16 | 预算判断恒真（=硬塞） | 决策字段不被裁 |
| M17 | 可用宽恒返回兜底常数 | **首版逃过检测**，补结构不变量守卫后被抓 |
| M18 | 决策字段可被降级 | 决策字段不被裁 |
| M19 | 法师 Q 漏标 damage_type | 3 条（含两条新守卫） |

> M17 是本轮最有价值的一条：它证明"宽度测量静默退回兜底值"当时无人能抓。
> 修法是加**结构不变量**断言（桌面可用宽必须 > 触屏），而不是断言"等于 561"——
> 后者会随布局调整变成需要跟着改的魔数。

## 3. G3 接线关（6 处链路 + 双白名单）

`04-combat-chain.md` §A 逐处，7 个新属性（armor / magic_resist / cooldown_reduction / attack_speed / crit_damage / hp_regen / mana_regen）：

| 链路 | 位置 | 状态 |
| --- | --- | --- |
| 1 出生初始化 | `sim/match_sim.gd:206-219`（含 `base_*` 六个） | ✅ |
| 2 每 tick 推进 | `_update_hero_timers`（CDR/攻速/回复 + `passive_as_timer` 收账） | ✅ |
| 3 快照输出 | `_snapshot_entity` + `_snapshot_board` | ✅ |
| 4 协议白名单 | `_sanitize_entity` **与** `_sanitize_board` 两条路径 | ✅ |
| 5 表现层 | `_damage` 的 `hit` 事件 `amount` = 减伤**后**数值（飘字读它） | ✅ |
| 6 UI 消费 | `scoreboard._stats_text` + `shop_panel._describe` | ✅ |

生产引用 grep：7 个字段在 `sim/net/scripts` 命中 6–25 处，**均含生产文件**（非只 tests）。

链路 4 的关键点：board 走 `sanitize_snapshot` 里**单独一份**逐字段清单。只加 `_snapshot_board` 不加这里，就是"单机正常、客机读 0 且不报错"——本轮实际差点留下这个坑，靠 `test_board_stats_survive_the_wire` 补住。

## 4. G4 表现关

**离线双路（已完成）**

| 手段 | 结果 |
| --- | --- |
| `tools/ui_shot.gd`（桌面） | 10 张截图全产出，脚本错误 0 |
| `tools/mobile_shot.gd`（触屏） | 50 项：47 通过 / 3 失败 |
| 计分板双路实拍 | `shots/board_desktop.png`、`shots/board_touch.png` |

**3 条 FAIL 非本次引入**：用 `git stash` 取 HEAD 基线重跑 `mobile_shot`，得到**完全相同的 3 条**（skills queue while the joystick is held / skill button queues raw touch cast / skill cast fires with auto aim），同为 47/50；stash 前后 7 个改动文件 SHA256 逐字节一致。
→ 这是**改动前既有**的离屏触控施法问题，与项 1 无关，建议单独立项排查（不在本项范围）。

**双路实拍结论**：
- 桌面（面板 1240）：`护甲 55 · 魔抗 25` 全显，尾部 `推塔 3` 未被裁。
- 触屏（面板 1180）：`魔抗` 被预算降级掉，`输出/承伤/推塔` 三个决策字段仍在——降级逻辑按设计生效。

**真机（未完成）**：`adb devices` 列表为空，设备未连接。
按 `08-delivery-checklist.md` 第 8 项与验收表 §0，设备离线的 `ENV-01 FAIL + PHASE SKIP` **不算通过**，且本项改了 `scoreboard.gd`/`shop_panel.gd`（Android 可见行为），必须重导 APK 后真机复验。

## 5. 实测数据

**属性生效确认**（`tools/pacing_report.gd`，纯 sim 可复现）：

```
sim_hero_fields_present: armor, magic_resist, crit_rate, crit_damage, ability_power,
  attack_speed, cooldown_reduction, hp_regen, mana_regen, shield, ...
sim_hero_fields_missing: penetration, lifesteal
```

差距文档 §3.1 列的 9 个缺失属性，本项补掉 7 个；`penetration` / `lifesteal` 未纳入本项范围。

**属性行宽度实测**（`tools/probe_board_*.gd`，解析式量真实层级，非手推）：

| 口径 | 数值 |
| --- | --- |
| 可用宽 | 桌面 561px ｜ 触屏 531px |
| 常显核心极端位数 | **417px**（稳进最窄触屏） |
| 真实出装（满攻/满AP/满防） | 503–555px，**全部 fits**，顺序与改动前逐字一致 |
| 合成极端（全字段拉满） | 桌面 547 fits ｜ 触屏降级后 480 fits（改前会 547 > 531 **裁尾**） |

**节奏连带影响**（单样本，不作标定结论）：5v5 时长 14m57s → **9m33s**，首塔 1m57s → 2m19s。
装备给减伤后 bot 对战推进更快，落进差距文档 §1 想要的 8–12 分钟区间。这是**观察到的副作用**，不等于节奏已标定（项 6 的范围）。

## 6. 过程中被实测否掉的做法（记录以免重犯）

1. **"直接把三个防御字段追加进属性行"**——实测最坏 678px > 561/531，会被 `clip_text` 静默裁掉尾部的 `输出/承伤/推塔`。字符串断言全绿而界面坏。改为按实测预算贪心装填。
2. **"加第三行显示防御属性"**——实测 `need3=582 > teams_avail=419`，垂直空间放不下。
3. **把法强/暴击挪到行尾**——会改变既有显示顺序，属无关回归。改为原位候选、按显示顺序装填。
4. **往 sim 里加 `check_*` 测试脚手架**——违反硬规则 2（sim 纯逻辑）。撤回，改用测试侧源码守卫。
5. **用应用壳离屏截图**——`main._arena` 在 SubViewport 里分帧构建未完成即取值，报 nil 并挂死。改为直接渲染 Scoreboard 面板。
6. **`--headless` 下 `await frame_post_draw`**——dummy 渲染器不触发，探针永久挂起。有渲染路径才可用。

## 7. 遗留（不计入本项达成）

- **G4 真机**：设备离线，需重导 APK + `device_checks.py` + 人工 `MAN-01/09`。
- `penetration` / `lifesteal` 两属性未做（差距文档 §3.1 列出，但本项验收标准未含）。
- 触屏极端行会少显示 `魔抗`——是设计取舍（保决策字段），非缺陷；若要全显需重排面板列宽（属项 16）。
