# 技能特效升级（FX-03 技能签名）验收证据

日期：2026-11-11 ｜ 基线 commit：`8c03c03`（本次改动未提交）｜ Godot：4.7.2 stable ｜ 窗口：1600×900
任务卡：[`../../视觉升级开发文档.md`](../../视觉升级开发文档.md) §3.6 FX-03 ｜ 差距来源：[`../../视觉差距分析-对标王者荣耀.md`](../../视觉差距分析-对标王者荣耀.md) §8

## 1. 这次做了什么

把差距文档 §8.3 的「**17 个技能 → 5 类配方**」补成「每个技能有自己的形状/节奏」：

| 轴 | 配方键 | 渲染层消费点 |
| --- | --- | --- |
| 粒子贴图 | `burst.texture` | `arena._spawn_particles()` → `quad.material.albedo_texture` |
| 粒子尺寸 | `burst.size` | `arena._spawn_particles()` → `quad.size` |
| 延迟二次爆 | `burst.delay` | `arena._queue_fx_burst()` / `_update_fx_queue()` |
| 竖直环 | `ring.tilt` | `arena._spawn_ring()` → `ring.rotation` |
| 落点刀光 | `arc` | `arena._spawn_slash()` |
| 地面残留 | `decal` / `decal_scale` | `arena._spawn_decal()` |
| 渐宽光束 | `beam_taper` | `arena._spawn_skill_beam()` → 3 × `_spawn_lance()` |

### 17 个 kind 的实际指纹（`SkillFx.signature_axes()` 实测输出）

`unique_signatures=17  unique_axes=17`，两两不同。`/v` = 竖直环，`/f` = 平放环；
`p:位置:数量:延迟:贴图:尺寸`；`d:残留贴图:缩放`；`a:弧角:长度`；`b:taper` = 渐宽光束。

```
slash           裂空刃    r:aim:0.50-2.60/f|p:aim:22:0.00:spark:0.16|d:slash:1.00|a:118:2.6
spin            旋风壁    r:self:0.40-3.40/v|r:self:0.30-2.00/f|p:self:26:0.00:slash:0.14
dash            疾风残影  r:self:0.40-1.60/f|p:self:8:0.00:smoke:0.20
leap_slam       跳斩震地  r:aim:0.80-5.00/f|r:aim:0.40-2.40/v|p:aim:30:0.00:shock:0.20|p:aim:12:0.16:shock:0.10|a:150:3.4
burst           法球迟爆  r:aim:0.50-2.80/f|p:aim:20:0.00:glow:0.13|p:aim:10:0.20:shock:0.09|d:glow:1.15
line            虚空织流  r:aim:0.40-2.20/f|p:aim:14:0.00:rune:0.10|d:rune:1.25|b:taper
slow            星界禁锢  r:aim:0.40-3.00/v|p:aim:16:0.00:smoke:0.19|d:rune:1.35
meteor_storm    星河倾落  r:aim:1.00-6.00/f|r:aim:0.50-3.20/v|p:aim:36:0.00:shock:0.22|p:aim:16:0.15:shock:0.14|p:aim:12:0.30:rune:0.10|a:200:4.2
quake           震地裂土  r:self:0.50-4.20/f|p:self:20:0.00:smoke:0.21|d:shock:1.10
charge          铁壁冲撞  r:aim:0.40-2.20/f|p:aim:14:0.00:spark:0.12|a:96:2.2
shield          守护壁垒  r:self:0.50-2.60/v|p:self:18:0.00:glow:0.15|d:glow:0.85
taunt_aura      不破要塞  r:self:0.60-5.00/f|r:self:0.40-3.00/v|p:self:24:0.00:shock:0.17
arrow           穿云箭    p:aim:8:0.00:glow:0.08|d:slash:0.80
aoe_shot        爆裂疾射  r:aim:0.50-3.00/f|p:aim:18:0.00:shock:0.13|p:aim:9:0.12:shock:0.08|d:shock:1.30
haste           鹰眼疾行  r:self:0.40-2.20/f|p:self:14:0.00:glow:0.11
arrow_barrage   万箭归宗  r:aim:0.80-5.20/f|r:aim:0.40-2.60/v|p:aim:34:0.00:spark:0.12|p:aim:14:0.14:spark:0.10|p:aim:10:0.28:glow:0.08|a:140:3.8
evade           匿踪烟幕  r:self:0.30-1.80/f|p:self:12:0.06:smoke:0.23|d:smoke:0.70
```

读表要点：`spin` 与 `taunt_aura` 同为「双环 + 自身」，但一个竖环在前、一个竖环在后，
且粒子贴图和数量不同；`burst` 与 `aoe_shot` 都是「爆 + 延迟补爆」，但贴图、延迟时刻、
残留都不同 —— 这正是差距文档要的「不看颜色也能分辨」。

### 顺带修掉的三处既有缺陷

1. **`size` 是空参数**：配方写了、`_spawn_particles()` 也收下了，函数体从没读过 —— 所有粒子一样大。这种失效不报错、测试也不红。
2. **违反硬规则 4**：`_spawn_projectile()` / `_spawn_beam()` 在战斗期 `MeshInstance3D.new()` + `queue_free()`，技能与 `projectile_spawned` 两条链路都在用。已删除，改走 `_tracer_pool` / `_lance_pool`（池化、自带拖尾、池空抢占）。
3. **W/R 技能弹道画两次**：`SkillSystem.cast_skill()` 已经为远程技能在 sim 里生成真实弹道并发 `projectile_spawned`，配方又画一颗 = 两颗粒子并排飞（升级后两颗都带拖尾，重影明显）。用 `_slot_fires_a_real_projectile()` 按 **slot** 判定 —— slot 在 `_sanitize_event` 白名单里、客机拿得到；`owner_id` 不在，客机上恒为 0。

## 2. G0 基线关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

| | 用例数 | 失败 |
| --- | --- | --- |
| 改动前 | 1033 | 0 |
| 改动后 | 1048 | 0 |

`.tmp/baseline_tests.log` / `.tmp/tests_fx03_full.log`。

## 3. G1 机器关

末行 `TESTS: 1048  PASSED: 1048  FAILED: 0`。

`ERROR:` 扫描（排除 `leaked at exit` / `still in use` / `PagedAllocator` 这类引擎退出噪音）后只剩两类**改动前就有**的：

- `Parameter "material" is null` ×4 —— 无头渲染器下 `monster_kit` 的材质查询（既有，`test_hero_silhouette` 触发）；
- `Parse JSON failed` —— 负数用例故意坏包。

本次新增的 15 条用例**没有**任何 `ERROR:`，也没有出现「断言求值前抛错 → 记 PASS」的假绿。

## 4. G2 变异关

对每条新守卫做「故意改错 → 红 → 改回 → 绿」。改完都用 `Get-Content -Raw` 与备份逐字符比对，确认恢复成原样。

| # | 变异点 | 文件 | 结果 |
| --- | --- | --- | --- |
| 1 | 竖环不再立起：`ring.rotation = ... if tilt else ...` → `Vector3.ZERO` | `arena.gd` | 🔴 `test_tilted_ring_is_vertical_and_flat_ring_resets_the_pose` expected 1.571 got 0.000 |
| 2 | 粒子尺寸写死：`clampf(size, ...)` → `0.12` | `arena.gd` | 🔴 `test_particle_texture_and_size_reach_the_emitter` expected 0.090 got 0.120（**这就是历史上那个静默失效的参数**） |
| 3 | 去重判据放宽：`slot == "w" or "r"` → 再加 `"q"` | `arena.gd` | 🔴 2 条：`test_skill_projectile_and_beam_go_through_the_pools` + `test_hitscan_q_and_e_still_draw_their_own_projectile`（双向守卫） |
| 4 | 残留忽略配方贴图：`material.albedo_texture = art` → `FxTextures.rune()` | `arena.gd` | 🔴 `test_decal_texture_and_scale_follow_the_recipe`（shock vs rune） |
| 5 | 指纹不认延迟：`signature_axes` 里 `float(delay)` → `0.0` | `skill_fx.gd` | 🔴 `test_axes_helper_notices_real_parameter_changes`（"加延迟二次爆必须改变签名轴"） |

## 5. G3 接线关

```bash
grep -rn "signature_axes\|_fx_queue\|_update_fx_queue\|file_texture(" --include="*.gd" godot/scripts godot/sim godot/net
```

生产引用（非 `tests/`）：`arena.gd:382/1012/4748/4759/4760/4762/4765/5153/5312`、`fx_textures.gd`、`skill_fx.gd:34/358`。

硬规则 4 复查：`arena.gd` 4600–5500 行内所有 `.new()` 全部位于 `_init_vfx_pools()`（预热）与 `_make_fx_material()`，**战斗路径零分配**。

## 6. G4 视觉关

```cmd
godot --path godot --script res://tools/skill_fx_shot.gd
```

产物（`godot/shots/`，不入库）：`skill_fx_<kind>.png` × 17、`skill_fx_sheet.png`（5×4 总览）、`skill_fx_control.png`。

| 检查 | 结论 |
| --- | --- |
| 17 张两两可分 | ✅ 环姿态 / 残留贴图 / 环形数量与颜色分明 |
| 对照组（不放技能） | ✅ 英雄周围干净，确认画面上多出来的环确实来自技能 |
| 竖直环可见 | `spin` / `leap_slam` / `slow` / `shield` / `taunt_aura` / `arrow_barrage` / `cleanse` |
| 渐宽光束可见 | `line`（3 段由细到粗） |
| 落点刀光可见 | `slash` / `leap_slam` / `charge` / `meteor_storm` / `arrow_barrage` |

**画廊工具本身踩过的坑（已修，写进 `05-ui-and-feel.md` §4.1）**：
① 手工摆相机会被 `_process` 的 `_update_camera()` 每帧覆盖 → 17 张全是同一块空地；
② 只 `clear()` 活动数组不隐藏节点 → 每张图叠着前几个技能的鬼影环；
③ `_decal_active` 存的是 `Dictionary`（键 `node`），当节点用不报错但一张都没藏住 → 表现为"七八圈同心圆"，很容易误读成特效画多了。

## 7. G5 联机关

**不新增协议字段、不新增事件**：`skill_cast` / `summoner_cast` 的 `slot`、`hero_type`、`kind`、`aim_*` 本来就在 `_sanitize_event` 白名单里，本次只改渲染层消费方式。客机拿到的 `recipe` 由 `skill_fx.recipe(kind)` 纯函数重建，两端一致。

去重判据特意避开 `owner_id`（**不在**白名单，客机上恒为 0）而用 `slot`，否则客机会多画一颗。

## 8. G6 性能关

- 战斗路径新增分配：**0**（延迟爆走字典队列，不建节点）。
- 池容量不变：粒子 24 / 拖尾 12 / 弹丸 24 / 光束 8 / 环 16 / 刀光 12 / 残留 12。
- **净减少**：`_spawn_projectile()` 每次施法 1 球 + 1 球体网格 + 1 材质，现全部复用。
- `line` 的渐宽光束一次借 3 个 `_lance`（池 8 个），5v5 同帧多技能时有抢占风险，但抢占策略是既有行为（不静默丢弃）。

未在真机复测 fps：本次只改表现层内部实现，draw call 数量与材质种类未增加（贴图从 1 张 spark 变为 6 张共享）。

## 9. G7 资产合规

**没有新增任何位图/模型资产**：6 张 VFX 贴图是既有资产（已在 `docs/art-credits.md` 登记为程序化生成），本次只把它们按技能分配到不同配方。

## 10. G8 真机

**未做**。本次改动不影响 Android 可见行为的入口（无 UI 布局、无输入、无视频），但严格按 `08-delivery-checklist.md` §8，涉及对局内可见表现仍应重导 APK 复测 —— 记为未完成项。

## 11. 未完成项与后续

- **序列帧/UV 动画**仍缺（差距 §8.3 "资产"层残余）。
- 同族技能仍共用基本体（环/球/方片），靠贴图 + 节奏 + 环姿态区分；要做"完全独立的技能特效"需要序列帧与专属网格（P1 后半）。
- FX-05 前摇预警仍然**不适用**：sim 无施法前摇，硬加会与伤害时序不一致。
- 真机 fps 未复测（见 §10）。

## 12. 签字

| 项 | 结论 | 证据 | 日期 |
| --- | --- | --- | --- |
| G0 基线 | 通过 | `.tmp/baseline_tests.log`（1033/0） | 2026-11-11 |
| G1 机器 | 通过 | `.tmp/tests_fx03_full.log`（1048/0） | 2026-11-11 |
| G2 变异 | 通过 | 本文 §4（5 条变异全部转红） | 2026-11-11 |
| G3 接线 | 通过 | 本文 §5 grep 输出 | 2026-11-11 |
| G4 视觉 | 通过 | `godot/shots/skill_fx_sheet.png` + 对照组 | 2026-11-11 |
| G5 联机 | 通过（无协议改动） | 本文 §7 | 2026-11-11 |
| G6 性能 | 部分通过 | 池/分配已核；真机 fps 未复测 | 2026-11-11 |
| G7 合规 | 通过 | 无新增资产 | 2026-11-11 |
| G8 真机 | **未做** | — | — |
