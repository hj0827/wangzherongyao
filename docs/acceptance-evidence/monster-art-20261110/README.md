# 野怪形象重做 · 红蓝 BUFF 与野区野怪（2026-11-10）

日期：2026-11-10 ｜ 基线：`TESTS: 899 PASSED: 898 FAILED: 1`
（**唯一那条红不是本项** —— 见 §5「并发会话」）
本项新增用例 `godot/tests/test_monster_forms.gd` **15/15 全绿**，`test_monster_ui.gd` 5/5 全绿。

配套：[`docs/ai/05-ui-and-feel.md` §7 / §7.1](../../ai/05-ui-and-feel.md)

---

## 0. 玩家反馈 → 实测到的真问题

玩家原话：「红蓝buff和野怪的形象还是不够好看，要继续优化，可以参考王者荣耀等游戏的野怪设计」。

改前实测（`tools/monster_gallery.gd` 的第一版输出）：

| 野点 | 改前形象 |
| --- | --- |
| 霜狼（蓝 BUFF）/ 赤狼（红 BUFF） | `Wolf.glb`，与双狼**完全同一只模型** |
| 双狼 / 蜥蜴 / 三猪 / 红鸟 | 全是同一只 `Wolf.glb`（AABB 都是 h=1.40 w=0.56 d=2.90） |
| 暴君 / 主宰 | 同一只 `Orc.glb`，只有大小不同（w=5.11 / 5.65） |

也就是说：**12 个野点只有 1 种剪影**，玩家区分它们只能靠头顶那行小字。
王者的野区是「红蓝石像 + 蜥蜴/野猪/鸟/狼」，每种一眼可辨 —— 这是本项对标的口径。

---

## 1. 改后（真实对局截图，非画廊）

`godot/shots/` 下的过程图不入库，这里记录可复现命令与要看什么：

```cmd
godot --path godot --script res://tools/monster_gallery.gd          :: monster_sheet.png / monster_field.png
godot --path godot --script res://tools/probe_monster_camp.gd       :: camp_<camp_id>.png（真对局，一次性探针）
```

- `monster_sheet.png`：8 种形象各一张特写（4×2）。狼/蜥蜴/三猪/红鸟/蓝石像/红石像/暴君/主宰**两两剪影与配色都不同**。
- `monster_field.png`：51° 俯角 / zoom 21 的实战取景，与英雄同框看比例。
- `camp_blue_buff_blue_side.png`：**真实对局里**站在蓝 BUFF 营地旁 —— 蔚蓝石像（石板躯干 + 胸口青色晶簇）
  坐在蓝色符阵上；同一帧左侧草地上是绿色蜥蜴。这证明链路走的是生产路径
  （sim 营地 → 快照 `camp_id` → `Arena._create_unit_view` → `UnitVisual`），不是只在工具里好看。

实测尺寸（`tools/monster_gallery.gd` 打印）：

| 形态 | 高 | 宽 | 深 | 网格数 |
| --- | --- | --- | --- | --- |
| wolf（双狼） | 1.45 | 0.58 | 3.00 | 1（glb） |
| lizard（蜥蜴） | 1.15 | 1.51 | 3.68 | 32 |
| boar（三猪） | 1.40 | 0.90 | 2.45 | 31 |
| bird（红鸟） | 1.75 | 2.82 | 2.05 | 27 |
| blue_sentinel（霜狼） | 2.45 | 2.33 | 1.22 | 33 |
| red_sentinel（赤狼） | 2.60 | 2.99 | 2.90 | 35 |
| tyrant（暴君） | 3.80 | **5.14** | 5.83 | 55 |
| overlord（主宰） | 4.20 | **5.27** | 6.27 | 60 |

首领宽度与模拟层碰撞直径 5.6 同量级（旧版 5.11 / 5.65），不会读成「身板小、打得远」。

---

## 2. 怎么改的（为什么是程序化拼模型）

新增 4 个文件 + 1 个画廊工具（行数见 §4），**没有引入任何二进制资产**：

| 文件 | 职责 |
| --- | --- |
| `scripts/game/monster_kit.gd` | 材质/网格静态缓存、基本体（box/ball/rod/spike/shard/ring/leg）、`fit_height()` 量体、`finish()` 收尾 |
| `scripts/game/monster_forms_jungle.gd` | 蔚蓝石像 / 猩红石像 / 蜥蜴 / 三猪 / 红鸟 |
| `scripts/game/monster_forms_boss.gd` | 暴君 / 主宰（共用 `_beast` 骨架，靠配色 + 角数 + 甲刺长度分开） |
| `scripts/game/monster_forms.gd` | `CAMP_FORMS`/`form_key`/`build`/`ring_radius` + 程序化动画 `animate` |
| `tools/monster_gallery.gd` | 入库工具：特写对照图 + 实战取景图 |

三条理由（写进 §7.1，供后来者判断能不能推翻）：

1. **授权留痕**：现成包的 glb 连 `license` 字段都没有（差距文档 §5.1），再引一套资产 = 再加一处合规风险；
2. **包体/显存**：基本体 + 共享材质，移动端没有额外贴图与骨骼开销；
3. **识别度**：俯视 20 米机位读的是剪影 + 配色，不是面数。

**动画不走骨骼**：`MonsterForms.animate()` 每帧驱动关节（腿摆 / 翅扇 / 尾摇 / 肩甲与火星绕体转 / 晶体呼吸），
`moving` 与 `unit_speed` 决定步频幅度；程序化形态在被击杀时由 `UnitVisual._update_death_pose()` 向前倒地、
复活时 `_restore_model_rest_pose()` 收回。**倒地只叠加在静止姿态上** —— 直接写 `model_root.scale` 会覆盖
`fit_height()` 的结果（第一版就是这样，野怪一死变大）。

---

## 3. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
TESTS: 899  PASSED: 898  FAILED: 1
```

新增 `test_monster_forms.gd` 15 条，覆盖 6 个面：

| 面 | 用例 |
| --- | --- |
| 每个野点都有形象（不许隐形野怪） | `test_every_camp_resolves_to_a_buildable_form`、`test_camp_forms_table_covers_every_camp_and_nothing_else`、`test_objective_pits_build_their_own_beast`、`test_unknown_monster_type_falls_back_to_wolf_instead_of_nothing` |
| 剪影/配色两两可分 | `test_camp_forms_have_distinct_silhouettes`、`test_buff_sentinels_differ_in_both_silhouette_and_colour` |
| 体型对得上碰撞半径 | `test_form_footprint_tracks_the_collision_radius`、`test_objective_beasts_fill_their_hit_circle` |
| 程序化动画真的在动 | `test_procedural_animation_moves_legs_tail_and_orbit`、`test_bird_wings_flap_and_buff_orbit_spins`、`test_moving_swings_legs_harder_than_standing` |
| 接线（UnitVisual / 快照） | `test_unit_visual_builds_the_form_named_by_the_snapshot`、`test_arena_passes_buff_and_objective_identity_into_the_form` |
| 死亡倒地 + 复活复位 / 材质复用 | `test_death_tips_a_boneless_monster_over_and_respawn_stands_it_back_up`、`test_monster_view_reuses_shared_materials_across_spawns` |

配套修改了 `test_monster_ui.gd` 里两条**语义已过时**的断言：旧版要求「普通兽人营地身高 2.4」
（兽人形象已不存在），改为断言小野点身高 1.4 + 血条贴头顶；首领那条从「Orc 宽 5.1」改成
「程序化首领宽度仍在 4.4~5.8」——**门限没放宽**。

---

## 4. G2 变异关（4 条，全部变红后字节级还原）

单文件快跑器：`godot/.tmp/run_one.gd`（`.tmp` 整目录被忽略）。

| # | 变异点 | 结果 |
| --- | --- | --- |
| M1 | `form_key()` 一律 `return "wolf"`（= 改前状态） | 红 3 条：`test_unknown_monster_type_...`（spirit 分支）、`test_unit_visual_builds_...`（8 个野点全变 wolf） |
| M2 | `animate()` 的 `swing = 0.0`（走路不摆腿） | 红 2 条：`test_procedural_animation_moves_legs_tail_and_orbit`、`test_moving_swings_legs_harder_than_standing` |
| M3 | `_update_death_pose()` 整段跳过（死亡站着不动） | 红 1 条：`test_death_tips_a_boneless_monster_over_...`（`expected < -0.2, got 0.0`） |
| M4 | `UnitVisual` 不再把 `camp_id` 传给 `form_key()` | 红 1 条（8 处野点）：`test_unit_visual_builds_the_form_named_by_the_snapshot` |

---

## 5. G3 接线关

```cmd
grep -rn "MonsterForms" --include="*.gd" godot/scripts godot/sim godot/net
```

生产引用（不是只有 tests）：

- `unit_visual.gd:6` preload；`:448` `form_key(...)`；`:451` `build(...)`；`:473/:497` `ring_radius(...)`；`:1058` `animate(...)`
- `arena.gd:3325` 把快照里的 `camp_id` 作为第 9 个参数传给 `UnitVisual.setup()`

**形象来源刻意放在表现层**（`MonsterForms.CAMP_FORMS`），没有给 `MapLayout.CAMPS` 加字段、
更没有动 `net_protocol` 白名单 —— `camp_id` 本来就在快照与 `_sanitize_entity` 白名单里，
主机与客机自动一致。代价是多一张表，由 `test_camp_forms_table_covers_every_camp_and_nothing_else`
钉住「`CAMP_FORMS` 与 `CAMPS` 一一对应」：以后新增野点忘了登记会直接红。

---

## 6. G4 表现关（截图已核，产物不入库）

| 图 | 看什么 |
| --- | --- |
| `shots/monster_sheet.png` | 8 种形态各自的特写，剪影/配色两两可分 |
| `shots/monster_field.png` | 51° 俯角实战取景：蓝色石像、红色石像、蜥蜴、鸟、狼、猪、暴君与英雄同框 |
| `shots/camp_blue_buff_blue_side.png` | **真对局**：蔚蓝石像 + 蓝色符阵 + 左侧草地上的蜥蜴 |

画廊的**环境与主光直接吃 `ArenaLook`**（`apply_environment` / `apply_sun`），
所以挑颜色时看到的就是游戏里的颜色；自己另写一套光照（尤其不开 bloom）判断不了「晶体亮不亮」。

---

## 7. 诚实的遗留与风险

1. **并发会话**：本次会话进行中，另一个会话在同一工作区推 项 3（投射物）——
   它执行过一次 `git stash -u -m item3-temp` + `git reset`，把本项当时**未提交**的
   `monster_kit.gd` / `tools/monster_gallery.gd` 一起卷进了它的 stash（本项已从
   `stash@{0}^3` 取回）。因此本项刻意**不再修改任何共享文件的数据**：
   形象表在自己的文件里，`sim/` 与协议一行没动。`map_layout.gd` 里只剩它自己的改动。
2. **唯一那条红不是本项**：`test_targeting_and_attack_modes.gd :: test_tower_button_forces_tower_priority`
   （`expected 10, got -1`）由另一个会话正在改的 `sim/targeting_rules.gd::is_combat_unit()`
   引起（新增 `has("hp")` 判定后，测试夹具里的塔被排除出索敌）。本项未触碰该文件。
3. **首领包围盒纵深偏大**（5.83 / 6.27 > 碰撞直径 5.6）：来自环绕光点轨道。横向（玩家正对看到的
   那一面）是 5.14 / 5.27，已由测试卡住；纵深只做了上限守卫（< 6.8）。
4. **`Orc.glb` 现在没有生产引用**（旧版首领模型）。保留为素材，`test_global_integrity` 仍断言它能加载。
5. **程序化形态没有骨骼攻击动作** —— 但野怪本来就不播攻击动作（`UnitVisual.play_attack()` 只处理英雄与小兵），
   所以这不是回退。狼仍保留 glb 的 Idle/Walk/Gallop/Death。
6. 真机（Android）未复验：本项只改表现层几何与材质，不涉及输入/网络；按 `09-device-testing.md`
   仍建议在下一轮真机验收里带上「野区一眼分辨」这一条人工用例（低端机上多出的 draw call：
   单个野点 27~60 个 `MeshInstance3D`，共用材质、关闭投影）。
