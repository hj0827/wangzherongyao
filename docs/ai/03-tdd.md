# 测试与 TDD 流程

> 只在"写测试 / 修 bug / 改数值"时读这份。

---

## 1. 跑测试

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

输出末尾一行是关键：

```
TESTS: 255  PASSED: 255  FAILED: 0
```

（255 是 2026-10-23 的实测值，会随开发变化。**以你跑出来的为准**，别把数字写进汇报里当结论。）

退出码：全绿 0，有红 1。

**动手改任何东西之前先跑一次**，确认基线是绿的。不然后面出现的红你分不清是谁造成的。

### 看到 `Cannot load test suite: res://tests/xxx.gd` 怎么办

这不是"测试逻辑失败"，是**这个文件压根没加载成功**（解析错误，或者文件正在被写入）。

```cmd
godot --headless --path godot --check-only --script res://tests/xxx.gd
```

- 有语法/类型错误 → 输出会指出来，修掉即可。
- 什么都不输出（正常退出）→ 说明文件本身没问题，多半是**另一个会话正在写这个文件**，等几秒重跑。

### 并发会话提醒

如果用例总数在你没改测试的情况下突然变了（比如 249 → 255），说明**有另一个会话在同一个仓库里干活**。

先跑 `git status --porcelain` 看清楚，别在别人的半成品上动手，也别把别人未完成的状态当成 bug 去修。

---

## 2. 新增测试文件

- 路径：`godot/tests/test_<功能>.gd`
- 首行：`extends "res://tests/test_base.gd"`
- **不需要注册**：`run_tests.gd` 会自动扫描 `res://tests/test_*.gd`，逐个实例化并调用所有 `test_*` 方法。
- `test_base.gd` 本身被排除（它是基类）。

最小骨架：

```gdscript
extends "res://tests/test_base.gd"

const MatchSim = preload("res://sim/match_sim.gd")

func test_hero_starts_at_full_hp() -> void:
	var sim := MatchSim.new({"mode": "duel", "humans": [{"id": "p1", "team": "blue"}]})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	eq(float(hero.hp), float(hero.max_hp), "hero spawns at full hp")
```

---

## 3. 断言 API（只有这 5 个）

| 断言 | 签名 | 说明 |
| --- | --- | --- |
| `check` | `check(cond: bool, msg: String)` | 通用布尔 |
| `eq` | `eq(actual, expected, msg)` | 相等（`!=` 比较，注意 int/float） |
| `near` | `near(actual, expected, epsilon, msg)` | 浮点近似 |
| `lt` | `lt(actual, expected, msg)` | actual < expected |
| `gt` | `gt(actual, expected, msg)` | actual > expected |

**没有 `ne`。** 根目录 README 里写的 `ne(a, b, msg)` 是错的，`test_base.gd` 里并没有这个方法——用了会在运行时报 "Invalid call"。

需要"不相等"就写 `check(a != b, "msg")`。

---

## 4. 测试代码的硬约束

- 测试类是 `RefCounted`，**不能实例化 Node / Node3D / Control**。
- 不能依赖渲染、音频、窗口尺寸、真实时间。
- 想测需要 tick 的逻辑，**手动调 `sim.tick(1.0/30.0)`** 若干次，不要等真实时间。

---

## 5. 三步法：红 → 绿 → 变异

缺一步都不算完成。

### 第 1 步：先写一个**会失败**的测试

跑一次，确认它真的红。**恒真的测试等于没有测试**——这一步是在证明"测试能抓到问题"。

### 第 2 步：写实现，跑到绿

### 第 3 步：变异验证（最容易偷懒的一步）

把关键代码**故意改错**，确认测试变红，再改回来。

例如测伤害公式：

```gdscript
# 正确
var damage := base * 1.0
# 变异
var damage := base * 0.9
```

跑测试 → 必须红 → 改回 `1.0` → 再跑 → 必须绿。

**为什么必须做**：静默失效的 bug（`tsc`/构建/渲染都不报错的那类）只能靠这一步兜住。

---

## 6. 测试抓不到的三类问题（要靠 `04-combat-chain.md`）

这三类**不会让测试变红**，因为它们不是逻辑错误，是"数据没流到位"：

1. **Dictionary 字段名拼错** —— 读不存在的键返回 `null`，`float(null)` 变 `0.0`，不报错。
2. **快照漏字段** —— `_snapshot_entity` 没输出，view/HUD 永远读到默认值。
3. **协议白名单漏字段** —— 单机全对，联机静默丢。

所以：**加字段时，测试绿了不代表做完了**，必须对照 `04-combat-chain.md` 的清单逐项勾。

---

## 7. 现有测试覆盖了哪些面

30+ 个 `test_*.gd`，大致分这几类，写新测试时先看看有没有现成的可扩展：

- 战斗核心：`test_match`、`test_skills_and_spells`、`test_economy_and_shop`
- 地图规则：`test_map_layout`、`test_map_towers`、`test_map_vision`、`test_map_recall`、`test_map_integration`
- 移动与输入：`test_click_move`、`test_motion_smoothing`、`test_mobile_input`、`test_mobile_ui`
- 联机：`test_net_protocol`、`test_net_session`、`test_net_team`、`test_room_manager`、`test_lan_discovery`
- 表现与性能：`test_hero_presentation_and_perf`、`test_global_integrity`

`test_global_integrity` 是全局一致性检查（比如资源引用是否都存在），改路径/改名后特别有用。
