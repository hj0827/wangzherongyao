# 项 2 验收证据 · 技能等级化 + 大招解锁门槛

日期：2026-11-09 ｜ 基线：783 → **827 用例全绿**（新增 44 条）
配套：[验收表 项2](../../acceptance-vs-honor-of-kings.md) ｜ [差距文档 §3.2](../../gap-analysis-vs-honor-of-kings.md)

---

## 0. 本项定身的规则（差距文档只说"要等级化"，具体口径在此确定）

| 项 | 取值 | 理由 |
| --- | --- | --- |
| Q/W/E | 出生 **1 级**，上限 6 级 | 已学，无需解锁提示 |
| R | 出生 **0 级 = 未学习**，上限 3 级 | 不用"1 级但锁住"：那会产生「等级 1 却放不出来」的歧义状态，`damage_grow*(lv-1)` 也要额外解释 |
| 技能点 | 每升 1 级 +1（1 级不给），满局 14 点 | 与 `MAX_LEVEL=15` 对齐 |
| 大招门槛 | 4 / 7 / 10 级学 R1/R2/R3 | 对标王者，是 MOBA 核心节奏器 |
| 伤害成长 | `damage + damage_grow * (技能等级 - 1)` | 两条施法路径（Q/E 走 match_sim、W/R 走 skill_system）共用 `HeroDefs.scaled_damage` |
| 加点方案 | `skill_plan` = **逐等级表**（14 项，第 i 项对应升到 i+2 级） | 不用"优先级 + 点最低合法技能"：那会和 4/7/10 门槛打架，表里排到 r 但等级不够时**点数被吞且不报错** |
| 常量真身 | 全部放 `HeroDefs` | sim 与 `net_protocol` 都 preload 它；避免 `crit_rate` 那种"两条路径各写一个上限"的漂移 |

---

## 1. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
TESTS: 827  PASSED: 827  FAILED: 0
```

假绿扫描（`03-tdd.md` §1）：`SCRIPT ERROR|Invalid call|Nonexistent|Cannot load|out of bounds` **命中 0 行**。

新套件 `godot/tests/test_skill_levels.gd`（44 条）+ 更新 4 个既有套件。

### 有意破坏并显式更新的既有测试（规则变更，不是回归）

大招从"1 级可放"变成"4 级解锁"，以下 4 处在 1 级放大招的旧测试必须更新，每处都写明了理由：

| 文件 | 用例 | 处理 |
| --- | --- | --- |
| `test_hero_roster.gd` | `test_every_skill_produces_an_observable_effect` | 放 R 前先 `skill_r_level=1`（本用例测"技能生效"，门槛由新套件专测） |
| `test_skills_and_spells.gd` | `test_cast_skill_w_and_r_...` | 同上 |
| `test_skill_vfx.gd` | `test_w_and_r_emit_renderable_payload` | 同上 |
| `test_damage_types.gd`（项 1 自写） | `test_cast_skill_path_also_applies_cdr` | 改用 W（同样走 skill_system 路径且出生已学），语义不变 |

> 这四处的共同点：**测试意图仍然成立**，只是前置条件变了。没有一条断言被删弱。

---

## 2. G2 变异关（30 条，全部变红后字节级还原）

| # | 变异点 | 变红用例 |
| --- | --- | --- |
| N1 | 升级不发技能点 | 8 条 |
| N2 | 自动加点整体关闭 | 4 条 |
| N3 | 大招门槛不校验 | 3 条 |
| N4 | 技能上限不校验 | 1 条 |
| N5 | 无点也能加（吞点守卫失效） | 1 条 |
| N6 | 等级不参与伤害 | 2 条 |
| N7 | 未学大招也能施放 | 1 条 |
| N8 | Q 路径不读等级 | 1 条 |
| N9 | `EMPTY_INPUT` 删 `upgrade_slot` | **首版逃过** → 补 schema 守卫后红 |
| N10 | 非法槽位不清洗 | 1 条 |
| N11 | 快照漏等级 | 1 条 |
| N12 | 白名单漏点数 | 1 条 |
| N13 | 加点意图不清（会重放） | 1 条 |
| N14 | 门槛表写成 [4,6,9] | 2 条 |
| N15 | HUD 不传等级给按钮 | 1 条 |
| N16 | slot 反推写错 | 1 条 |
| N17 | 状态行不显示点数 | 1 条 |
| N18/N19 | 文字读数方案（后被图形方案取代） | 各 1 条 |
| N20 | 按钮默认等级改 1 | **等价变异**，见 §7 |
| N21 | 0 点也显示文案 | 1 条 |
| N22 | `composed_name` 忽略等级 | **首版逃过** → 补文案守卫后红 |
| N23 | 触屏不表达未学 | 1 条 |
| N25 | 斜杠比例越界 | 1 条 |
| N26 | 线宽 0.62（几何安全但糊） | **首版逃过** → 补视觉上限守卫后红 |
| N27 | 已学也画锁标 | **首版逃过** → 抽纯函数后红 |
| N28 | 亮线粗过描边 | 1 条 |
| N29 | 负等级也画锁标 | 1 条 |
| N30 | 把 `_skill_block_reason` 调用注释掉 | 1 条（`has_live_line` 抓到，`contains` 会假绿） |

### 变异验证抓出的 5 个真实缺陷（不是形式测试）

1. **N9**：删掉 `EMPTY_INPUT` 里的键，功能照常（GDScript 动态建键）→ 声明与实际脱节，下一个人照 `EMPTY_INPUT` 读输入形状会漏键。补 `test_input_schema_declares_every_key_that_gets_sanitized`，判据用**结构不变量**（桌面可用宽必须 > 触屏），而不是断言"等于 561"那种会随布局变化的魔数。
2. **N22**：只验 `button.level` 字段够——字段对了但没被组合进键面文案，玩家照样看不到。补 `test_composed_name_actually_prints_the_level`。
3. **N26**：线宽 0.62r 在几何上"没越界"，但会把图标糊成一条色带。**几何安全 ≠ 视觉可用**，补 `test_lock_mark_stroke_stays_readable_not_a_wall`。
4. **N27**：判定写在 `_draw` 里就测不到。抽成 `SkillButton.shows_lock_mark(level)` 纯函数后才能钉住。
5. **N30**：`skill_block_reason` 有真身、有测试，但**生产代码零调用**——正是仓库警告的"函数在、测试绿、引用 0"。用 `has_live_line`（非 `contains`）接进 `arena._on_skill_button`。

---

## 3. G3 接线关（6 处链路）

`04-combat-chain.md` §A/B 逐处：

| 链路 | 位置 | 状态 |
| --- | --- | --- |
| 1 出生初始化 | `match_sim._spawn_hero`：`skill_*_level`（q/w/e=1、r=0）+ `skill_points` | ✅ |
| 2 每 tick / 输入键 | `_add_xp` 发点 + `_auto_spend`；`_apply_human_inputs` 消费 `upgrade_slot`（取走即清）；`set_input` 合并保留该离散意图；`arena` 强制发送条件 + `_consume_skill_queue` 清除 | ✅ |
| 3 快照输出 | `_snapshot_entity` 五个键 | ✅ |
| 4 协议白名单 | `EMPTY_INPUT` + `sanitize_input`（非法槽位清空）+ `_sanitize_entity`（钳制引用 `HeroDefs` 常量，不另写字面量） | ✅ |
| 5 表现层 | `SkillButton` 桌面"技能名+等级"同行、触屏纯图形锁标 | ✅ |
| 6 UI 消费 | `game_hud._apply_skill_state` 传等级、`role_text` 显示剩余点数、`_on_skill_button` 播报"需要 4 级解锁大招" | ✅ |

死代码核查：12 个新函数**全部有生产调用方**；已删常量（`TOUCH_LEVEL_*`/`show_level`）无悬空引用。

### 键盘加点的键位选择（有意的取舍）

用 **Ctrl + 技能键**，而不是新占 2/3/4/5：数字 1 已经是 W 技能，再排加点会让键位表变成"1 是技能、2 是加点"的无规律组合。
按住 Ctrl 时该次按键**只加点、不施法**（并吞掉待发的施法锁存），避免一次按键同时耗蓝又耗点。
已同步进 `KEY_HINT_LINES` 与 `KEY_HINTS`（两处原本内容不一致，这次一并对齐）。

---

## 4. G4 表现关

**离线双路（已完成）**

| 手段 | 结果 |
| --- | --- |
| `tools/ui_shot.gd`（桌面） | 10 张全产出，脚本错误 0 |
| `tools/mobile_shot.gd`（触屏） | 50 项：47 通过 / 3 失败 |
| `tools/probe_lock_render.gd`（像素差） | 触屏未学vs已学 diff=**0.136**（锁标真的画出来了）；桌面 diff=0.047（文案可见）；召唤师键 vs 已学 diff=**0.000**（正确地不画锁标） |
| 实拍 | `shots/skill_desktop_ready.png` 显示 `裂地崩山 4级` 完整未裁、Q 角标保留；`shots/skill_touch_locked.png` 显示红斜杠压过灰暗图标，清晰可读 |

**3 条 FAIL 非本项引入**：与项 1 基线（`.tmp/mobile_after.txt`）**名称与数量完全一致**（同为 47/50）。
且这 3 条测的是 **Q**（出生即 1 级，不受解锁门槛影响），不存在"被新规则掩盖"的可能。

**真机（未完成）**：`adb devices` 列表为空。本项改了 `arena.gd`/`game_hud.gd`/`skill_button.gd`（Android 可见行为），按 `08-delivery-checklist.md` 第 8 项必须重导 APK 后真机复验，**设备离线不算通过**。

---

## 5. 实测：本项让对局节奏**回退**了（必须报告）

`tools/pacing_report.gd`（bot vs bot，同种子同阵容）：

| 指标 | 项1 前 | 项1 后 | **项2 后** |
| --- | --- | --- | --- |
| 5v5 时长 | 14m57s | 9m33s | **15m00s 未分胜负** ⚠️ |
| 5v5 首塔 | 1m57s | 2m19s | 2m36s |
| 1v1 时长 | 15m00s 平 | 15m00s 平 | 15m00s 平 |
| 事件峰值/上限 | 22/32 | 22/32 | **25/32**（仍 0 溢出） |

**归因**：项 1 给装备加了减伤，bot 变肉；项 2 又把大招从 1 级推到 4 级，前期 380 点爆发消失 → **两头叠加把 5v5 推回 15 分钟僵局**。

这是"解锁门槛"的**真实代价**，不是 bug——王者也是 4 级才有大招。但它说明：**项 2 不能单独上线**，必须与项 6（节奏标定）一起收口。可选方向（留给项 6 决策，本项不越界实施）：延长兵线成长、降低塔前期保护、或给 4 级前的小兵/塔伤害加成。

> 单样本、bot 对 bot，不构成标定结论。要下判断需按验收表 6.1 扩成多阵容 × 多 seed。

---

## 6. 遗留（不计入本项达成）

- **G4 真机**：设备离线，需重导 APK + `device_checks.py` + 人工 `MAN-02/03/09`。
- **2.4 的"设置里可选手动"无玩家入口**：`auto_skill_points` 目前只有 sim 与测试读取，生产端从不设置 → 实际永远走默认自动。手动路径本身已实现（配置 + Ctrl 组合键 + 输入链路），但**开关 UI 属项 8（设置界面 + 持久化）**，本项无法单独完成。
- **大招未学的 HUD 播报只在主机侧**：客机走同一函数判定，但 `announce` 需要双实例真机确认。
- **节奏回退**：见 §5，交项 6。

---

## 7. 一处诚实标注：N20 是等价变异，不是测试缺口

把 `SkillButton.level` 默认值从 `-1` 改成 `1`，测试仍全绿。原因：HUD 每帧都通过 `set_state` **显式传 level**，字段初值在生产路径上永不生效。

我没有为它补测试——那会是为不可达分支写断言。但保留 `-1` 默认是有意的：`set_state` 的 `new_level` 参数默认 `-1`，**若将来有人新增一条不传 level 的调用路径，键面会退回"只有技能名"，而不是显示一个看起来正确、其实是假的"1级"**。这个防御性设计写在注释里，不伪装成"已验证"。
