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
| 状态快照广播 | **10 Hz**（0.1s），**不可靠有序** | `arena._snapshot_timer >= 0.1` → `session.broadcast_team_snapshots` |
| 离散事件广播 | **10 Hz**，**可靠** | `session.broadcast_team_events` |
| 输入上报 | **20 Hz**（0.05s） | `arena._input_timer >= 0.05` |
| 客机渲染延迟 | **0.16s** | `arena.NET_RENDER_DELAY` |
| 缓冲上限 | **16 帧** | `arena.NET_BUFFER_LIMIT` |

**注意**：`_input_timer` 的刷新条件是把所有即时输入键逐个 `or` 起来的（Q/W/E/R、召唤师、回城、传送、`buy_item`/`sell_slot`）。新增任何即时键时，这里必须同步加，否则新键按下后最多要等 50ms 才上报（手感发粘）。

### 2.1 两条通道：状态走不可靠，事件走可靠

同一次 10Hz 广播拆成两个包：

| 包 | 通道 | 丢了会怎样 | 为什么 |
| --- | --- | --- | --- |
| `snapshot` | `TRANSFER_MODE_UNRELIABLE_ORDERED` | 下一格快照覆盖，无感 | 状态是幂等的；可靠通道一旦丢包会队头阻塞，把后面所有快照一起拖住 |
| `events` | `TRANSFER_MODE_RELIABLE` | 永久缺失：没有播报、没有击杀特效、结算时不放胜利/失败曲 | 事件是离散的一次性事实，丢了不会补 |

`game_session.last_send_mode` 记录最近一个包的通道（`"reliable"` / `"unreliable"`），`test_state_snapshot_and_events_use_separate_channels` 用它把"快照有没有走错通道"变成可断言的事实——环回网络上看不出这个回归。

事件包按队伍分别构造：`sim.events_for(team, events)` 只做视野过滤，不构造整份快照；与 `snapshot_for` 共用 `Vision` 同一套规则，避免两条路径对"敌人是否看得见"判断不一致。客机收到后走 `session.events_received` → `main._on_network_events` → `arena.receive_events`。

### 2.1.1 快照只构建一次，按队过滤复用

10Hz 广播要发两支队伍。如果每队各调一次 `snapshot_for(team)`，就会把"全实体 + 经济面板 + 河道"构建两遍——这是团战帧里最大的一笔分配。

现在主机每 tick 只构建一份全量 `sim.snapshot()`（`arena._last_world_shot`），供 `current_snapshot` 与广播共用：

- 本地视角：`sim.snapshot_for(local_team, null, _last_world_shot)`；
- 广播：`sim.snapshot_for(team, null, world_shot)`，两队复用同一份 base；
- `Vision.filter_snapshot()` 做**浅拷贝**（`duplicate(false)`）后只替换 `entities / events / river`，其余顶层字段共享；视觉层只读，不回写；
- 一次过滤内把观察者（英雄/兵/塔/基地）预建成 `{pos, radius_sq}` 列表，目标逐个用平方距离判断，不再每个目标重扫全表。

`test_combat_regressions.gd` 钉住了两点：传 `base` 不会改动 `base` 本身；带 base 的过滤结果与从头重建完全一致。基准脚本 `godot --headless --path godot --script res://tools/bench_combat.gd`（56 实体、10 英雄）：全量快照 ~0.53ms，两队广播 ~1.7ms（单份构建 + 两次过滤）；对局内这份构建已被本帧快照摊掉，广播只剩 ~1.16ms 的过滤成本（原先两队各建一次 ~2.2ms+）。**不要退回"每队各 snapshot() 一次"的写法。**

### 2.2 压缩帧

`NetProtocol.encode()` 在包 ≥ 512 字节时用 ZSTD 压一遍；压不小就原样发。

```
[1 字节 0x01][4 字节原始长度 u32][ZSTD 数据]
```

首字节是编解码标记。未压缩包的首字节是 `var_to_bytes` 的 Variant 类型号（Dictionary = 27），与标记 `1` 天然不冲突，两种格式在线上共存。`decode()` 先看标记，再校验谎报的原始长度（> `MAX_PACKET` 直接拒），最后核对解压后长度。

选 ZSTD 的依据（33KB 快照实测）：ZSTD 压 0.35ms / 解 0.04ms，FASTLZ 解压要 11ms、DEFLATE 压缩要 8.6ms——后两者会直接在 30Hz 主循环里露出毛刺。

实测带宽（团队模式满编、`probe_packet_size.gd`）：状态 3958 B/包（原 33270 B）+ 事件 311 B/包，合计 **41.7 KB/s/客户端**，压缩前仅状态就是 325 KB/s。

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
    "skill_w": false,
    "skill_e": false,
    "skill_r": false,
    "summoner": false,
    "recall": false,
    "teleport": false,
    "attack_mode": "default",
    "locked_target": -1,
    "buy_item": "",
    "sell_slot": -1,
    "seq": 0,
}
```

`sanitize_input()` 逐字段清洗这 15 个键。`buy_item` / `sell_slot` 与 `seq` 是商店链路：购买/出售走可靠通道，并按 `last_purchase_seq` 去重。

### 4.2 实体白名单（`_sanitize_entity`）

hero 分支逐字段列举并钳制范围。W/R/召唤师冷却、金币、装备、AP、暴击、`revealed_timer`、`last_input_seq` 均已收录：

| 字段 | 在 sim 里有 | 在白名单里 | 用途 |
| --- | --- | --- | --- |
| `skill_w_cd` / `skill_r_cd` | ✅ | ✅ | 客机按钮显示冷却 |
| `summoner_cd` / `summoner_spell` | ✅ | ✅ | 召唤师技能状态 |
| `gold` / `inventory` / `ability_power` / `crit_rate` | ✅ | ✅ | 商店与经济 UI |
| `revealed_timer` | ✅ | ✅ | 草丛交战后短暂显形 |
| `last_input_seq` | ✅ | ✅ | 客机预测对账 |

### 4.2.1 视野与事件过滤

`match_sim.snapshot_for(team, events_override, base)` 会调用 `Vision.filter_snapshot()`（后两个参数都可省；`base` 用于复用同一份全量快照，见 §2.1.1）：

- 实体：只保留友军、建筑与视野内敌人。
- 事件：`snapshot` 包里**不再携带事件**（联机时事件单独走 `events` 包，见 §2.1）；`events_for(team, events)` 用的是同一套 `Vision.filter_events()`：全局播报（兵线、首领刷新、塔毁、比赛结束等）照常下发；攻击/技能/受击/死亡等带坐标事件只有在本队视野内才下发，防止通过事件流透视。
- 河道视野：只下发本队掌握的眼位。
- 单机与主机同样使用 `snapshot_for(local_team)`，不再全图可见。

### 4.3 快照顶层白名单（`sanitize_snapshot`）

只放行：`time / winner / mode / bounds / ended / entities / scores / events / wave / objectives / river / board`。

`events` 字段仍保留在快照白名单里（单机与测试路径会用），但联机广播的状态快照不带事件。`river` 放河道之灵刷新计时与本队眼位；`board` 是计分板账本——只放公开统计（等级/人头/经济/装备），不放坐标，所以不算透视。

**加新的顶层字段（比如 `gold` 汇总、`shop` 状态）必须改这里**，否则联机永远收不到。

### 4.3.1 事件包白名单（`sanitize_events`）

`events` 包的载荷是 `{time, events}`，事件逐条复用 `_sanitize_event`，上限 `MAX_EVENTS`。两条路径共用同一个清洗函数，避免同一事件在快照与事件包里解析出不同结果。

### 4.4 事件白名单（`_sanitize_event`）

只放行固定键名列表：`type / hero / source / source_type / target / target_type / slot / hero_type / minion_type / team / x / y / aim_x / aim_y / target_x / target_y / value / damage / wave / level / winner / entity_type / killer* / victim* / tier / buff / objective_id / name`。

`minion_attack`（小兵普攻）与 `structure_attack`（塔/主堡开火）的表现靠 `minion_type / source_type / target_type / tier` 选刀光、弹丸或光束；漏掉任何一个，客机会退回默认特效。

**自定义事件里带的新键会被丢掉**——比如你想发 `{"type":"gold_gain","amount":50}`，`amount` 不在名单里，客机收到的事件里没有金额。

### 4.5 调试字段故意不入白名单

`debug_god / debug_infinite_mana / debug_no_cooldown` 只存在于主机的 `sim.state.entities` 里：

- 它们不参与快照构造（`_snapshot_entity` 是显式白名单），客机永远看不到；
- 客机没有 `sim`，所有 `Arena.debug_*` 方法在客机上直接 return；
- 全图视野（`debug_set_reveal`）也只替换**本机**的 `current_snapshot`，10Hz 广播仍走 `snapshot_for(team)`。

如果哪天要让调试状态跨机同步，必须同时改 `net_protocol.gd` 白名单和 `tests/test_net_protocol.gd`；**不要**把调试字段顺手塞进实体白名单。

---

## 5. 战争迷雾对所有本地视角生效

```gdscript
func snapshot() -> Dictionary:                                      # 全量：调试/服务端内部用
func snapshot_for(team, events_override = null, base = null):       # 按视野过滤：所有玩家视角
```

单机、主机、客机都只拿本队视角：

- 主机/单机：`arena.current_snapshot = sim.snapshot_for(local_team)`，sim 内部照常全算。
- 主机联网广播：状态用 `sim.snapshot_for(team, null, world_shot)`（复用同一份全量快照，按队伍过滤实体、河道眼位），事件用 `sim.events_for(team, outgoing_events)`（只过滤事件，不重建快照），分别走不可靠与可靠通道。`outgoing_events` 攒的是两次 10Hz 广播之间的全部 30Hz 事件，避免漏事件。
- 客机：服务端下发的已经是过滤后的快照，jitter buffer 直接回放；事件通过 `session.events_received` 单独到达。

`filter_snapshot()` 返回的是**浅拷贝**：顶层字典与 `scores / wave / objectives / board` 与传入的 base 共享引用，只有 `entities / events / river` 是过滤后重建的。视觉层只读这份数据；**谁要改快照内容，必须先自己深拷贝**，否则会改到主机的 `_last_world_shot`，下一队就看到被篡改的视野。

`_sync_units()` 会把离开视野的敌方英雄视图 `visible = false`，重新进入视野时直接落位，避免从旧位置滑入泄露动向。

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

- **无断线重连**：掉线即退出对局。
- **预测不含碰撞**：客机只按输入方向与速度外推，撞墙/被阻挡的误差靠服务端回执平滑纠正。
- **无服务端延迟补偿（lag compensation）**：命中判定仍以服务端当前世界为准，高延迟下技能需要预判。
- **事件过滤不做击杀播报降级**：雾中击杀的死亡事件会被过滤，敌方在视野外被击杀时本队看不到播报。

判断一个联机模块到底有没有生效，用 `01-repo-reality.md` §4 的引用检查命令——**测试绿不代表它在跑**。
