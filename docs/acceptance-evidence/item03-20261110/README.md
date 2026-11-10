# 项 3 验收证据 · 弹道飞行（投射物实体）

日期：2026-11-10 ｜ 新增 `test_projectiles.gd` 14 条 ｜ 全量 903 用例
配套：[验收表 项3](../../acceptance-vs-honor-of-kings.md) ｜ [差距文档 §3.2](../../gap-analysis-vs-honor-of-kings.md)

---

## 0. 本项解决了什么

差距文档 §3.2 把这条列为"**操作上限层面最根本的差距**"：

> 施放那个 tick 就直接 `_damage`，**没有弹道飞行时间**……表现层画了个弹丸，
> 但逻辑早已结算完毕——**"走位躲非指向技能"在这个游戏里物理上不可能**。

改造后：远程技能在 sim 里生成**真实实体**，飞行途中才结算命中，目标可以靠走位规避。

## 1. 设计边界（刻意收窄）

只把"真的飞出去"的技能弹道化，其余保持瞬发：

| 弹道化（6 种） | 保持瞬发（8 种） |
| --- | --- |
| `arrow` 贯穿箭 / `burst` 爆发弹 / `aoe_shot` 范围弹 / `line` 直线冲击 / `arrow_barrage` 扇形箭雨 / `meteor_storm` 陨星 | `dash` 位移 / `charge` 冲锋 / `leap_slam` 跃击 / `spin` 旋风 / `shield` 护盾 / `haste` 加速 / `evade` 匿踪 / `taunt_aura` 嘲讽光环 |

理由：位移/自身增益/近战范围**本来就没有飞行过程**，硬做成弹道会让"按了立刻生效"的操作手感消失（`test_instant_kinds_stay_instant` 钉住这一点）。

## 2. 关键技术决策

### 2.1 伤害仍走 `match_sim._damage`

投射物只负责"飞"和"判定谁被扫到"，`_damage` 仍是唯一结算入口。
所以护甲/魔抗/减伤/暴击/护盾**只有一份实现**，弹道不复制它。

### 2.2 用线段扫掠而不是单点判定

一步走 `26/30 ≈ 0.87m`。若只检测落点，薄目标会被整段跳过（tunneling），
表现为"偶尔不掉血"——这类 bug 最难复现。所以判定的是 from→to 的**线段距离**。

### 2.3 方向缺失时不猜

协议端 `dir_x` 的默认值**必须是 0 而不是 1**。默认 1 时归一化会得到一个
"看起来合理"的方向：实测真实方向是 `(0.936, 0.351)`，而缺失 dir_x 后猜出 `(0.943, 0.331)`——
dot 相似度 0.999，于是"快照漏发方向"在联机上伪装成"弹道略歪"，断言全绿。
现在缺失输出零向量，可被断言直接抓住（W2 变异为证）。

### 2.4 表现时长与 sim 同源

`arena._handle_projectile_spawned` 用 `距离 / 26.0` 算飞行时长，而不是写死一个
"看起来差不多"的值。否则玩家看到的命中会明显晚于真实掉血，手感立刻不对。

---

## 3. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

项 3 相关 7 个套件 **129 条全绿、0 脚本错误**（逐套件隔离运行）：

| 套件 | 条数 | 结果 |
| --- | --- | --- |
| `test_projectiles.gd`（新） | 14 | ✅ |
| `test_damage_types.gd` | 36 | ✅ |
| `test_skill_levels.gd` | 44 | ✅ |
| `test_hero_roster.gd` | 10 | ✅ |
| `test_skills_and_spells.gd` | 9 | ✅ |
| `test_targeting_and_attack_modes.gd` | 6 | ✅ |
| `test_net_session.gd` | 10 | ✅ |

> **全量 903 绿**，但运行期间另一个会话正在改写 `unit_visual.gd` /
> `monster_kit.gd` / `test_debug_mode.gd`，出现过 1 条瞬时失败
> （单跑该套件 11/11 通过，确认是并发编辑的中间态）。本项结论以隔离运行为准。

## 4. G2 变异关

| # | 变异点 | 变红用例 |
| --- | --- | --- |
| P1 | `arrow` 改回当场结算 | 3 条（含"施放当 tick 不扣血"） |
| P2 | 线段判定改单点 | `test_fast_projectile_never_tunnels_through_a_thin_target` |
| P3 | 超寿命不置死亡标志 | `test_expired_projectile_is_marked_dead` |
| P3b | 单体弹命中不销毁 | `test_single_target_projectile_is_destroyed_on_hit` |
| P5 | 位移技能也弹道化 | `test_dash_skill_still_moves_the_caster_immediately` |
| W1 | 白名单去掉 projectile | 2 条联机用例 |
| W2 | 快照漏 `dir_x` | `test_projectile_survives_the_wire` |
| W3 | 快照漏 `speed` | 同上 |
| W4 | 协议下发 `damage` | `test_wire_never_carries_projectile_damage` |

### 变异验证抓出的 4 个真实缺陷

1. **P2 逃逸** → 原测试没覆盖 tunneling，补线段判定的单元级用例。
2. **P3/P3b 逃逸** → 原"回收"断言是**恒真**的：cleanup 在 tick 末尾无条件清扫，
   即使 `alive` 没被置 false 也会变 0。改为直接断言 `alive` 标志。
3. **W2 逃逸** → 协议猜方向（见 §2.3），改默认值 + 加零向量断言。
4. **索敌选中投射物** → 投射物带 `team/pos/alive/radius`，能通过所有距离与阵营检查，
   被选成目标后 `_damage` 刷 56 条脚本错误、普攻"打在弹道上"。修法是把判定收进
   `TargetingRules.is_combat_unit` 一处，让新增索敌路径自动继承。

> **踩过的坑（值得记）**：我第一版把它写成 `type in [hero,minion,monster]` 白名单，
> 直接把"推塔键"废掉了（`test_tower_button_forces_tower_priority` 变红 10→-1）。
> 塔必须能被普攻/推塔键选中。正确写法是**只排除 projectile**，其余放行。

## 5. G3 接线关

| 链路 | 位置 | 状态 |
| --- | --- | --- |
| 1 实体创建 | `match_sim.spawn_projectile` + `ProjectileSystem.build` | ✅ |
| 2 tick 推进 | `_update_projectiles`（在小兵/野怪之后，看到本 tick 最终位置） | ✅ |
| 3 快照输出 | `_snapshot_entity` 的 `projectile` 分支（方向拍平成 `dir_x/dir_y`） | ✅ W2/W3 红 |
| 4 协议白名单 | `ENTITY_TYPES` + `_sanitize_entity` 专用分支，带钳制 | ✅ W1/W4 红 |
| 5 索敌排除 | `TargetingRules.is_combat_unit`，被 5 处索敌共用 | ✅ P4b 红 |
| 6 表现层 | `arena` 的 `projectile_spawned` / `projectile_hit` 分支 | ✅ |

**信任根不变**：协议**不下发** `damage` / `hit_ids` / `target_mode` —— 客机不结算伤害，
只画弹道（`test_wire_never_carries_projectile_damage` 钉住）。

## 6. G4 表现关

- 表现层已接线：`projectile_spawned` → `_spawn_projectile`（复用既有 VFX），
  `projectile_hit` → `_spawn_particles`。
- **⬜ 截图与真机未做**：本轮被并发编辑占用工作区，`ui_shot` / `mobile_shot` 未重跑。
  需要在下一次干净基线上补：桌面 + 触屏双路截图，确认弹丸真的可见、飞行时长与掉血同步。
- **⬜ 客机双实例未验**：协议层已有离线守卫（W1/W2/W4），但"客机眼里弹道是否与主机一致"
  仍需双实例真机确认。

## 7. 遗留

- **G4 双路截图与真机**：见 §6，未完成。
- **前摇/后摇（3.3）未做**：本项只完成"投射物实体 + 可走位规避"。
  施法前摇、可被打断、主动取消仍属未实现（验收表 3.3 未勾）。
- **`_fire_projectile` 的退化路径**：`sim == null` 时退回当场结算。
  这只影响没有世界状态的工具级单元测试，真实对局（含 bot）都走实体路径。
  已在代码注释里写明，不是隐藏分支。
- **`is_combat_unit` 的 `has("hp")` 是不可达防御**：实测所有可选中单位都带 hp，
  变异验证也证实删掉它测试不变红。保留但**不为它写假覆盖**，原因写在代码注释里。
