# 十条硬规则

> 每条都附了"违反了会怎样"。这些不是风格建议，是这个仓库当前状态下**会直接产出 bug 或死代码**的红线。

---

## 1. 目录以 `01-repo-reality.md` 为准，不以 `docs/ARCHITECTURE.md` 的树为准

ARCHITECTURE.md 描述的是**目标态**，其中 `scripts/core/`、`scripts/infra/` **只有 README.md，没有任何代码**；`scripts/view/` 目前只有 `hit_stop_manager.gd`（已接线）。

**违反了会怎样**：你把新逻辑写进 `scripts/core/`，它会成为死代码——全工程没有任何 `preload` 指向那里，游戏跑起来完全看不到你的改动，测试也不会覆盖。

---

## 2. `godot/sim/` 是纯逻辑，禁止任何引擎节点与渲染 API

不许出现：`extends Node/Node3D/Control`、`get_tree()`、`preload("*.tscn")`、`Mesh`、`Material`、`GPUParticles3D`、`AudioStreamPlayer`。

**违反了会怎样**：`--headless` 单测会直接崩或拿不到节点；确定性模拟被渲染帧率绑架，联机回放开始漂移。

---

## 3. 表现层与 UI 层不许改数值

`scripts/game/`（view）和 `scripts/ui/` 只能**读快照**、**发意图**。不许在 UI 回调里直接改 `hp`、直接触发结算、直接让英雄播动作。

**违反了会怎样**：单机看不出问题，联机立刻分叉——主机算的和客机显示的不是同一场战斗。

---

## 4. 战斗中禁止 `.new()` / `queue_free()`

高频对象（小兵、飘字、命中粒子、范围环、弹道光束）必须走池：`arena.gd` 里的 `_minion_pool_*`、`_damage_labels_pool`、`_hit_particles_pool`、`_ring_pool`、`_tracer_pool` / `_lance_pool`。

**违反了会怎样**：5v5 团战同一帧几十次分配，真机掉帧，而且这种卡顿在 PC 上复现不出来。

---

## 5. 给英雄加一个字段 = 要改 6 处

少改一处就静默失效（GDScript 读不存在的 Dictionary 键返回 `null`，`float(null)` 变 `0.0`，**不报错**）。完整清单见 `04-combat-chain.md`。

**违反了会怎样**：单机正常、联机丢数据；或者 HUD 上那个数字永远是 0，但没人报错。

---

## 6. 联机路径上有白名单，不加白名单 = 只在单机生效

`godot/net/net_protocol.gd` 的 `sanitize_input` / `_sanitize_entity` / `sanitize_snapshot` / `_sanitize_event` 全是**白名单**，不在名单里的字段会被静默丢弃。

**已知现状**：`skill_w_cd`、`skill_r_cd`、`summoner_cd`、`summoner_spell` **都不在实体白名单里**——联机客机永远看不到 W/R 冷却。详见 `06-net-sync.md`。

**违反了会怎样**：本地测试全绿，一联机就"我的技能按钮不转圈"。

---

## 7. 改任何东西前，先跑一次测试基线

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

**违反了会怎样**：你分不清后面出现的红是你改坏的，还是本来就红的——然后开始瞎改。

---

## 8. 新建文件前先判"入库还是过程文件"

判据只有一条：**队友 clone 下来需不需要它才能跑起来 / 复现问题**。不确定就丢 `.tmp/`（整目录被忽略）。见 `07-files-and-git.md`。

**违反了会怎样**：365MB 的验收截图、80MB 的 APK、一次性探针脚本被提交上去，仓库变胖且无法回滚干净。

---

## 9. "文件在 + 测试绿" ≠ "功能在跑"

本仓库曾出现 **8 个模块**处于"已实现、已测试、生产代码引用为 0"的状态（锁敌、指示器、取消施法、顿帧、播报、客户端预测、金币、装备）。**2026-10-23 已全部接线**，但这条规则永远成立：新模块写完必须验证生产引用。

**违反前必须做的事**：在说"已完成 / 已实现"之前，跑一次引用检查——

```bash
grep -rn "EconomySystem" --include="*.gd" godot/scripts godot/sim godot/net
```

如果结果里**只有 `tests/`**，它就没接线。要么接上，要么在汇报里写"已实现，未接入"。

**违反了会怎样**：你向用户汇报"顿帧和指示器做好了"，用户在游戏里一点感觉都没有——因为没有任何一行生产代码调用它们。历史清单与接线位置见 `01-repo-reality.md` §4。

---

## 10. 收尾必须跑 `08-delivery-checklist.md`

改完不等于交付完。清单里有 5 项，每项都能挡住一类"看起来完成"的假交付。
