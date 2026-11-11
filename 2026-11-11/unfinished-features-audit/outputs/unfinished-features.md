# 未完成功能盘点（2026-11-11）

## 0. 口径与方法

- 事实基线：`docs/ai/README.md`、`00-hard-rules.md`、`01-repo-reality.md`；`docs/ARCHITECTURE.md` 只当目标态。
- 代码事实：对 `godot/` 全量 `grep`，并用脚本统计「生产代码引用数」；只有测试引用的模块单独列出。
- 文档事实：`docs/acceptance-vs-honor-of-kings.md`（逐项验收）、`docs/gap-analysis-vs-honor-of-kings.md`（内容缺口）、`docs/视觉升级开发文档.md`、`docs/特效升级-对标王者荣耀.md`、`docs/英雄定制模型规范-HERO-04.md`。
- 基线测试：`godot --headless --path godot --script res://tests/run_tests.gd`。盘点时为 **1061 PASS / 0 FAIL**；P0 批次完成后为 **1096 PASS / 0 FAIL**（日志见 `work/baseline-tests.log`、`work/full-after-p0.log`；退出时有 ObjectDB 泄漏告警，但不影响用例结果）。`run_tests.gd` 没有 skip/only 机制，不存在被静默跳过的测试；缺的是覆盖，见第 4 节。

状态定义：

- **A 完全没做**：生产代码与可用资源都不存在。
- **B 有代码但没接线 / 静默失效**：能力代码存在，生产路径不调用，或调用后字段被丢弃。
- **C 做了但不完整**：主链能跑，缺分支、缺字段、缺白名单、缺参数或未达标。

规模：**A 类 13 项，B 类 7 项，C 类 18 项**；其中 P0 阻塞 9 项，P1 体验/联机 14 项，P2 内容/对标 15 项。

> 本次已修复 9 项：B2、C1、C2、C3、A5、A4、A6、A7、B1（详见第 6 节）。下列分类保留原始编号，便于和验收表对照。

---

## 1. A 类：完全没做

| ID | 功能 | 证据 | 玩家可感知的缺失 | 优先级 |
| --- | --- | --- | --- | --- |
| A1 | 装备穿透 / 吸血，以及攻速、暴伤、CDR 的实际装备 | [item_shop.gd](file:///d:/Aproject/wangzherongyao/godot/sim/item_shop.gd#L3-L98) 只有 8 件装备；`recalculate_stats` 会聚合 `cooldown_reduction/attack_speed/crit_damage`（L203-L224），但没有一件装备提供这些字段；全仓生产代码 `grep penetration/lifesteal` 为 0 | 所有 AD 英雄都买同一套「铁剑→无尽→防装」，坦克/刺客/射手出装趋同，没有穿透打坦、吸血续航的博弈 | P1 |
| A2 | 装备合成树 / 出装方案 | [item_shop.gd](file:///d:/Aproject/wangzherongyao/godot/sim/item_shop.gd#L100-L106) 只有 5 条自动购买顺序，没有组件、配方、价格合成、预设方案；验收项 11.2 明确未做 | 商店只能一件件买整件，不能先买小件过渡，也没有「一键出装」 | P1 |
| A3 | 技能前摇 / 后摇 / 打断 | 全仓生产代码 `grep windup|cast_time|中断施法` 无命中；[acceptance](file:///d:/Aproject/wangzherongyao/docs/acceptance-vs-honor-of-kings.md#L65-L94) 项 3.3 标注未做；FX 文档也把「前摇特效」标为不适用 | 技能按下即结算，无法被控制打断，「看到起手再交控」的对抗不存在 | P1 |
| A4 | 设置界面 + 持久化（音量/画质/加点模式） | 生产代码 `grep ConfigFile|user://|设置|画质|音量` 为 0；[acceptance](file:///d:/Aproject/wangzherongyao/docs/acceptance-vs-honor-of-kings.md#L178-L186) 项 8 未做 | 不能调音量、不能降画质救帧率；重启后所有偏好丢失；自动加点也没有开关 | P0 |
| A5 | 异形屏安全区适配 | 全仓 `grep get_display_safe_area|safe_area` 为 0；[acceptance](file:///d:/Aproject/wangzherongyao/docs/acceptance-vs-honor-of-kings.md#L169-L177) 项 7 未做 | 刘海/挖孔机上技能键或小地图可能被遮住、误触 | P0 |
| A6 | 断线重连 | [game_session.gd](file:///d:/Aproject/wangzherongyao/godot/net/game_session.gd#L239-L245) 断线直接 `_drop_peer` 广播 `peer_left`，没有重连 token、没有重连窗口；验收项 9.3 未做 | 网络抖一下/切后台就永久掉线，只能重开一局 | P0 |
| A7 | RTT 显示 / 自适应缓冲 | 主机收到 `ping` 只回 `pong`（[game_session.gd](file:///d:/Aproject/wangzherongyao/godot/net/game_session.gd#L248-L291)），客机没有 `pong` 分支、不计算 RTT；没有延迟显示或动态缓冲；验收项 9.1/9.2 未做 | 玩家看不到延迟，弱网下卡顿无法感知原因，也不会自动加缓冲 | P0 |
| A8 | 快捷信号 / 聊天 / 语音 | 全仓生产代码 `grep ping_mark|chat|聊天|语音` 无相关实现；验收项 11.1 未做 | 联机时无法打信号沟通，等于只能各打各的 | P1 |
| A9 | FX-08 粒子预算 + FX-09 特效强度滑杆 | [arena.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/arena.gd#L5493) 的 `take_particle_slot(pool, active)` 没有优先级参数；生产代码无 `fx_intensity`/`fx_budget_tick`；FX 文档 FX-08/09 标 ⬜ | 团战同屏特效没有总量上限，低端机掉帧；玩家也不能把特效调弱 | P1 |
| A10 | 5 个定制英雄模型（HERO-04） | [hero_model_registry.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/hero_model_registry.gd) 已写好 `MODEL_PATHS`，但 `godot/assets/characters/hero_models/` 目录不存在，5 个 `.glb` 全缺；HERO-04 文档要求 5 个模型 | 5 个英雄仍是拼装体，轮廓和辨识度达不到「英雄感」 | P1（依赖美术） |
| A11 | 纹理压缩全量开启 | `godot/assets/ui/*.import` 的 `vram_texture` 全部为 `false`；验收项 12 未做 | 移动端显存/带宽浪费，低端机更容易掉帧 | P1 |
| A12 | 账号 / 匹配 / 房间列表 / 社交 / 战绩 / 回放 / 观战 / 新手引导 | `docs/gap-analysis-vs-honor-of-kings.md` 明确列为 0；生产代码无 `rank/mmr/matchmaking/replay/spectat/tutorial` 实现；验收项 13 未做 | 只能靠局域网/手输房间码开局，没有账号、段位、战绩、回放、教学 | P2 |
| A13 | 皮肤系统 | gap 文档明确 0；生产代码无 `skin` 实现；视觉文档把皮肤列为不做 | 英雄只有默认外观，没有商业化/收集内容 | P2（明确非目标） |

补充：CI 与本地化也属于完全没做——仓库无 `.github/workflows`，`project.godot` 无 internationalization 配置，生产代码无 `tr()` 文案层；`LICENSES.md` 缺失（`art-credits.md` 已有）。验收项 15。

---

## 2. B 类：有代码但没接线 / 静默失效

| ID | 功能 | 证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| B1 | 召唤师技能选择 | `SkillSystem` 支持多种召唤师技能，但 [match_sim.gd](file:///d:/Aproject/wangzherongyao/godot/sim/match_sim.gd#L504) 固定 `"summoner_spell": "flash"`；`main.gd`/`game_hud.gd` 没有任何选择入口；验收项 5 未完成 | 所有人永远只有闪现，英雄/分路无法靠召唤师技能做差异 | P1 |
| B2 | `sanitize_hello` 死接口 | 定义在 [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L177-L188)，生产代码 0 引用；[game_session.gd](file:///d:/Aproject/wangzherongyao/godot/net/game_session.gd#L332-L360) 的 `_on_hello` 直接读原始 payload | hello 路径的 hero/mode/name 校验与协议层不一致；后续加字段容易再次出现「测试绿、线上没走」 | P0（低成本） |
| B3 | `peer_joined` 死消息 | [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L44) 的 `TYPES` 有 `peer_joined`，全仓无任何发送点 | 客机只能靠 `room_state` 间接感知新玩家；协议表里有一条永远不来的消息 | P1 |
| B4 | `map_intel.gd` 仅测试引用 | 生产代码 0 引用（脚本扫描 + grep），只有 `test_map_intel.gd` 引用；HUD 的情报面板已被移除 | 死代码增加维护成本；若原意是保留地图情报能力，则玩家侧能力已丢失 | P2 |
| B5 | `targeting_system.gd` 仅测试引用 | 生产代码 0 引用；仿真直接走 `targeting_rules.gd`，UI 没有用这个包装层 | 「UI 与 sim 共用规则」的设计没有真正接线，后续改瞄准容易两边分叉 | P2 |
| B6 | `OBJECTIVE_BAR_WIDTH` 死常量 | [unit_visual.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/unit_visual.gd#L68) 定义后全文件 0 引用（`monster_forms_boss.gd` 有同名但独立使用） | 无玩家影响；属于 FX-12 的遗留清理 | P2 |
| B7 | 自动加点只能靠默认值 | [match_sim.gd](file:///d:/Aproject/wangzherongyao/godot/sim/match_sim.gd) 读取 `auto_skill_points` 配置，但生产代码没有写入入口（`main.gd`/HUD 均无）；桌面只能 `Ctrl+技能` 手动点，触屏无手动点 | 触屏玩家实际被锁死在自动加点；想做「手动加点」教学也无法演示 | P2 |

---

## 3. C 类：做了但不完整

### 3.1 联机正确性（优先修）

| ID | 功能 | 证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| C1 | 事件白名单缺 `kind` / `id` / `owner_id` | [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L561-L584) 的 `_sanitize_event` 白名单没有 `kind`、`id`、`owner_id`；FX 文档 FX-10 标 ⬜ | 联机时技能事件丢失 `kind`，客户端只能靠 `hero_type+slot` 猜特效；投射物/多段技能的 `id/owner_id` 也无法透传，单机与联机表现不一致 | P0 |
| C2 | `crit_rate` 两套钳制 | 记分板 [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L348) 钳到 `5.0`，实体快照 [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L440) 钳到 `1.0`；验收项 10.2 | 客机记分板可能显示 >100% 暴击，实体结算却是另一套上限，数值观感不一致 | P0（低成本） |
| C3 | 事件容量 32 且静默截断 | [net_protocol.gd](file:///d:/Aproject/wangzherongyao/godot/net/net_protocol.gd#L12) `MAX_EVENTS := 32`；超限在 L244/L279 直接 `break`，没有 dropped 计数或日志；验收项 10.4 | 团战/多杀瞬间事件被丢，客机少播击杀播报或特效，且无法定位 | P1 |
| C4 | 1v1 胜率仍偏 | [acceptance](file:///d:/Aproject/wangzherongyao/docs/acceptance-vs-honor-of-kings.md#L134-L166) 记录 3:9，目标 45–55%；`test_fairness.gd` 只覆盖经济差/不卡死，没有整局胜率采样 | 红蓝方体感不公平，1v1 模式说服力不足 | P0（需调参决策） |
| C5 | 1v1 未采样 | 验收项 6.4 明确「未采样」；没有对应测试或脚本 | 不知道 1v1 是否达标，无法 regression | P1 |
| C6 | 首塔时间 2m27s | 验收项 6.3，目标 3–5 分钟；代码没有节奏标定测试 | 推塔过快，对线期被压缩，玩家感觉「还没打就掉塔」 | P1（需调参决策） |
| C7 | 5v5 节奏回归风险 | 验收项 6.2 记录：加入装备后曾回到 15:00，靠项 4 才压到 8:04；当前没有持续节奏断言 | 后续改数值很容易再次把局时推长 | P2 |

### 3.2 战斗与内容深度

| ID | 功能 | 证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| C8 | 装备属性空转 | [item_shop.gd](file:///d:/Aproject/wangzherongyao/godot/sim/item_shop.gd#L203-L224) 聚合 CDR/攻速/暴伤，但 8 件装备无一提供；穿透/吸血连字段都没有 | 属性系统「支持」但玩家摸不到，出装没有分支 | P1 |
| C9 | FX-11 状态可视不全 | [unit_visual.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/unit_visual.gd#L1454) 只把 `haste_timer` 变成布尔；无免控光环、无加速风线；[arena.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/arena.gd#L5410) 只有伤害飘字，没有护盾吸收/治疗飘字、低血量屏幕红晕 | 玩家看不清「我加速了/我免控了/护盾吃了多少」，战斗信息靠猜 | P1 |
| C10 | FX-07 击杀慢动作 / 低血红晕 | FX 文档 FX-07 标 🟨；生产代码无 `time_scale` 击杀慢放、无低血红晕 | 击杀缺少「爽感」峰值，残血没有紧张感 | P2 |
| C11 | UI-06 结算数据条/点赞 | 视觉文档 UI-06 标 🟨；结算只有结果与 MVP，没有输出/承伤/参团条与点赞 | 结算页信息量低，缺少赛后反馈 | P2 |
| C12 | MON-04 出生演出 / 技能预警 | 视觉文档 MON-04 标 🟨；无出生运镜、无技能预警圈 | 开局没有仪式感，敌方大招预警不足 | P2 |
| C13 | HERO-02 发型/服装色一致 + 攻击动作区分 | 视觉文档 HERO-02 标 🟨；5 英雄共用拼装件，攻击动作区分有限 | 英雄辨识度低，换英雄像换颜色 | P2 |
| C14 | WALL-03 藤蔓 / WALL-04 墙顶盖面 | 视觉文档对应项标 🟨；墙体有几何但缺植被与顶面 | 野区墙体偏「灰盒子」，场景完成度不足 | P2 |
| C15 | 场景密度 120/60 | 视觉文档 SCENE 目标 200/400，当前 120/60 | 地图偏空，远景重复感强 | P2 |
| C16 | UI-07 大厅/小地图金框 | 视觉文档 UI-07 标 🟨 | 与王者式金框 UI 仍有差距 | P2 |

### 3.3 工程与性能

| ID | 功能 | 证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| C17 | `arena.gd` 巨石未拆 | [arena.gd](file:///d:/Aproject/wangzherongyao/godot/scripts/game/arena.gd) 当前 **5519 行**，验收项 16 的目标是 4298（目标值本身也已过时）；`scripts/core/`、`scripts/infra/` 仍只有 README | 任何战斗/表现改动都在同一个文件里冲突，回归面巨大 | P1 |
| C18 | 移动端 60fps 未达标 | 验收项 6/7 记录：Quadro K420 上 1080p 约 32fps；没有画质分级可降 | 低端机/移动端帧率不达标，手感直接受影响 | P0（需设备验证） |

---

## 4. 测试覆盖缺口（不是「跳过」，是「没写」）

`run_tests.gd` 会无条件跑完收集到的所有 `test_*.gd`，没有 skip/only。缺失的覆盖：

- 断线重连、RTT/pong、自适应缓冲：无测试。
- 安全区、设置持久化、画质分级：无测试。
- 召唤师技能选择：无测试。
- 穿透/吸血、装备配方、出装预设：无测试。
- 1v1 整局胜率采样、首塔时间标定：无测试（`test_fairness.gd` 只测经济差/路径/不卡死）。
- Android 真机 60 分钟联机/触摸/视频：验收 G7/G8 未执行。

---

## 5. 建议排期顺序

### P0（先修正确性与可发货性，成本低）

1. **C1 事件白名单补 `kind/id/owner_id`**：联机技能特效正确性，改动集中在 `net_protocol.gd`，风险低。
2. **C2 统一 `crit_rate` 钳制**：把记分板 5.0 改成与实体一致的 1.0（或统一常量），加一条协议测试。
3. **B2 接线 `sanitize_hello`**：让 `_on_hello` 走协议层清洗，消除死接口。
4. **C3 事件截断可观测**：保留 32 上限，但记录 dropped 计数并暴露到调试指标。
5. **A4 设置页 + 持久化**、**A5 安全区**、**A11 纹理压缩**、**C18 画质分级**：移动端可发货的最低组合。
6. **A6 断线重连 + A7 RTT/自适应缓冲**：联机可靠性。
7. **C4/C6 数值标定**：1v1 胜率与首塔时间需要产品/数值决策，先出采样脚本再调。

### P1（玩法深度与表现）

8. **A1/C8 装备分支**：先补穿透/吸血字段与 6–10 件装备，再补合成树（A2）。
9. **B1 召唤师技能选择 UI**：协议已有 `spell_id`，主要缺大厅/HUD 入口。
10. **C9 状态可视 + A9 特效预算/强度**。
11. **A10 定制英雄模型**：依赖美术产出，代码侧已就绪。
12. **A8 快捷信号**。

### P2（对标内容/长期）

13. 账号/匹配/社交/战绩/回放/观战/新手引导（A12）。
14. 皮肤（A13）、本地化/CI（验收 15）、场景/UI 细节（C11–C16）。
15. `arena.gd` 拆分（C17）随下一次大改一起做，避免单独重构。

---

## 6. 本次已修复（2026-11-11）

| ID | 改动 | 文件 | 验证 |
| --- | --- | --- | --- |
| B2 | `_on_hello` 改走 `NetProtocol.sanitize_hello`，取 `name/hero_type` | `godot/net/game_session.gd:342-353` | `test_net_session.gd` 10/10 PASS；`grep sanitize_hello` 生产调用点 1 处 |
| C1 | 事件白名单补 `kind/id/owner_id`，联机技能特效可拿到真实种类与归属 | `godot/net/net_protocol.gd:566-578`；`arena.gd:4947` 注释同步 | `test_event_packet_sanitizer_keeps_whitelisted_fields_only` PASS |
| C2 | 记分板 `crit_rate` 上限 5.0 → 1.0，与实体快照统一 | `godot/net/net_protocol.gd:348-351` | `test_board_stats_survive_the_wire` PASS |
| C3 | 事件超限返回 `dropped_events`，`GameSession.dropped_events` 累计并首次告警 | `godot/net/net_protocol.gd:249-251,265-291`；`godot/net/game_session.gd:36-38,318-326,335-341` | `test_event_packet_*` 2/2 PASS；`test_net_session.gd` 10/10 PASS |
| A5 | 安全区：`HudLayout.safe_insets/safe_center`，`zones` 全部按 insets 收缩；HUD 在移动端读取系统安全区并缩放；极端 inset 下提示行横移避让小地图 | `godot/scripts/ui/hud_layout.gd`；`godot/scripts/ui/game_hud.gd` | `test_hud_layout.gd` 23/23 PASS；`test_mobile_ui.gd` 15/15 PASS |
| A4 | 设置系统：音量三轨 / 画质四档 / 自动加点开关；`user://settings.cfg` 往返；Music/SFX 总线；大厅与暂停菜单入口；关闭自动加点只影响人类，bot 仍成长 | 新增 `godot/scripts/app/settings.gd`、`godot/scripts/ui/settings_panel.gd`；接入 `audio_director.gd`、`main.gd`、`game_hud.gd`、`match_sim.gd` | 新增 `test_settings.gd` 9/9 PASS；`test_skill_levels.gd` 46/46 PASS；`test_audio_system.gd` PASS |
| A6 | 断线重连：60 秒窗口、凭证只驻留内存、槽位/英雄保留、掉线期间 AI 托管、重连成功交还操作；主动退出先发 leave 再延迟 300ms 断开，避免幽灵玩家 | `godot/net/game_session.gd`、`godot/net/net_protocol.gd`、`godot/net/room_manager.gd`、`godot/scripts/app/main.gd`、`godot/scripts/game/arena.gd` | `test_net_session.gd` 14/14 PASS（含重连回到原槽位、输入/快照双向恢复、凭证不落盘守卫） |
| A7 | RTT：客机处理 pong、采样每个心跳更新、展示值 2 秒刷新；小地图下方金币行右侧显示，<80 绿 / <160 黄 / ≥160 红；主机与单机不显示 | `godot/net/game_session.gd`、`godot/scripts/ui/game_hud.gd`、`godot/scripts/game/arena.gd` | `test_net_session.gd`（采样 + 2 秒节流）PASS；`test_mobile_ui.gd::test_rtt_readout_sits_next_to_gold_and_colors_by_latency` PASS |
| B1 | 四个召唤师技能可在大厅选择：闪现 / 治疗 / 疾跑 / 净化；单机与联机（hello + set_summoner）同步；对局 HUD 显示当前技能；疾跑走既有加速计时器，终结退役 | `godot/sim/skill_system.gd`、`godot/sim/match_sim.gd`、`godot/net/net_protocol.gd`、`godot/net/game_session.gd`、`godot/net/room_manager.gd`、`godot/scripts/app/main.gd`、`godot/scripts/game/skill_fx.gd` | `test_skills_and_spells.gd` 10/10 PASS；`test_net_session.gd::test_lobby_summoner_choice_reaches_the_match_config` PASS；全量 1096 PASS / 0 FAIL |

## 7. 在飞改动（排期时不要重复立项）

当前工作区有未提交改动，属于「正在做、未收口」，不是「完全没做」：

- `scripts/game/arena.gd`（已暂存 + 又修改）
- `scripts/game/skill_fx.gd`（已暂存）
- `scripts/game/tower_visual.gd`（已暂存 + 又修改）
- `tests/test_skill_fx.gd`、`tests/test_tower_upgrade.gd`（已暂存 + 又修改）
- `scripts/game/preview.gd`、`tests/test_skill_fx_preview.gd`（未跟踪）

对应视觉文档 FX-03/04 与「防御塔升级可视化」；先确认这批改动能全绿再并入排期。
