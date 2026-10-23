# 联机同步与协议白名单

> 只在"改联机 / 同步 / 房间 / 协议 / 断线"时读这份。

---

## 1. 拓扑：主机权威（Listen Server）

- **主机**（`authoritative = true`）跑真实 `sim`，每 10Hz 广播快照。
- **客机**（`session != null`）**不跑 sim**，只上报输入、回放快照。
- 局域网发现走 UDP 广播，房间码 + 直连 IP 两种加入方式。

`arena.gd:_process()` 里三条分支：

```
authoritative && sim != null   → 跑 tick、生成快照、广播
session != null                → 只 submit_input，靠 jitter buffer 回放
else                           → 纯本地（无 session）
```

---

## 2. 频率（改任何一个都要同步改测试）

| 项 | 值 | 位置 |
| --- | --- | --- |
| 逻辑 tick | **30 Hz** | `match_sim.TICK_RATE` / `arena.TICK` |
| 快照广播 | **10 Hz**（0.1s） | `arena._snapshot_timer >= 0.1` |
| 输入上报 | **20 Hz**（0.05s） | `arena._input_timer >= 0.05` |
| 客机渲染延迟 | **0.16s** | `arena.NET_RENDER_DELAY` |
| 缓冲上限 | **16 帧** | `arena.NET_BUFFER_LIMIT` |

**注意**：`_input_timer` 的刷新条件里写死了 `or _local_input.skill_q or _local_input.skill_e`——加了新技能键，这里也要加，否则新技能按下后要等最多 50ms 才上报（手感发粘）。

---

## 3. 两套快照，别搞混

| 变量 | 用途 | 内容 |
| --- | --- | --- |
| `current_snapshot` | HUD / 小地图 / 瞄准 | **最新**快照 |
| `_render_snapshot` | 3D 单位位置 | 从 jitter buffer 回放的**延迟**快照 |

客机上：`_sync_units(_render_snapshot)`，但 `hud.update_snapshot(current_snapshot)`。这是故意的——HUD 要即时，位置要平滑。

---

## 4. 协议白名单（本项目最大的静默坑）

`net/net_protocol.gd` 里**所有入站数据都过白名单**，不在名单里的字段被静默丢弃。

### 4.1 输入白名单

```gdscript
const EMPTY_INPUT := {
    "move": Vector2.ZERO,
    "aim": Vector2.ZERO,
    "attack": false,
    "skill_q": false,
    "skill_e": false,
    "recall": false,
}
```

`sanitize_input()` 只清洗这 6 个键。**加 `skill_w` / `skill_r` / `summoner` 必须同时改 `EMPTY_INPUT` 和 `sanitize_input()`**，否则联机时按键被吞。

### 4.2 实体白名单（`_sanitize_entity`）

hero 分支逐字段列举并钳制范围。**当前欠账**：

| 字段 | 在 sim 里有 | 在白名单里 | 后果 |
| --- | --- | --- | --- |
| `skill_w_cd` | ✅ | ❌ | 联机看不到 W 冷却 |
| `skill_r_cd` | ✅ | ❌ | 联机看不到 R 冷却 |
| `summoner_cd` | ✅ | ❌ | 联机看不到召唤师技能冷却 |
| `summoner_spell` | ✅ | ❌ | 客机不知道队友带的是什么 |

其他字段（`recalling`、`buff_red_timer`、`buff_blue_timer`、`last_killer_name` 等）都在。

### 4.3 快照顶层白名单（`sanitize_snapshot`）

只放行：`time / winner / mode / bounds / ended / entities / scores / events / wave / objectives`。

**加新的顶层字段（比如 `gold` 汇总、`shop` 状态）必须改这里**，否则联机永远收不到。

### 4.4 事件白名单（`_sanitize_event`）

只放行固定键名列表：`type / hero / source / target / slot / hero_type / team / x / y / aim_x / aim_y / target_x / target_y / value / damage / wave / level / winner / entity_type / killer* / victim* / tier / buff / objective_id / name`。

**自定义事件里带的新键会被丢掉**——比如你想发 `{"type":"gold_gain","amount":50}`，`amount` 不在名单里，客机收到的事件里没有金额。

---

## 5. 战争迷雾只在客机生效

```gdscript
func snapshot() -> Dictionary:        # 全量，主机本地用
func snapshot_for(team: String):      # 按视野过滤，联机客机用
```

本地权威分支直接用 `sim.snapshot()`，**所以单机模式下你能看见全图敌人**，草丛和墙体遮挡完全不生效。

想让单机也有迷雾：把本地分支改成 `sim.snapshot_for(local_team)`，只过滤渲染层，sim 内部照常全算。

---

## 6. 联机不能暂停

```gdscript
# match_menu.gd
static func freezes_simulation(online: bool) -> bool:
    return not online
```

联机时打开菜单只是"看菜单"，模拟继续跑。写任何依赖"暂停"的逻辑（比如暂停时改设置、暂停时换装）都要考虑联机下不成立。

---

## 7. 改联机后的验收

1. 单机跑通（`test_net_*` 之外的常规测试）
2. `godot --headless --path godot --script res://tests/run_tests.gd` 全绿
3. **真机/双实例**开一局联机，验证：
   - 你加的字段在**客机**上真的变了（不是主机自己看自己）
   - 断线、退出、重进不会卡住
4. 如果只做了单机部分，**在交付说明里明确写"仅单机，联机未接"**——不要默认它联机也能用

---

## 8. 已知缺口

- **无客户端预测（未接线）**：`net/client_prediction.gd` 已实现、有测试（`tests/test_client_prediction.gd`），但 `arena.gd` 没有引用它。当前仍是"客机输入 → 主机 → 快照回放"，固定 0.16s 延迟。
- **无断线重连**：掉线即退出对局。
- **协议白名单欠账**：见 §4.2，`skill_w_cd` / `skill_r_cd` / `summoner_cd` / `summoner_spell` 四个字段联机收不到。

判断一个联机模块到底有没有生效，用 `01-repo-reality.md` §4 的引用检查命令——**测试绿不代表它在跑**。
