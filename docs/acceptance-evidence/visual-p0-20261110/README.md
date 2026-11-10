# 视觉 P0 第一批 · 实施与验收证据（2026-11-10）

日期：2026-11-10 ｜ 基线：`main` 工作树 ｜ 视觉回归：**VISUAL TESTS: 105 PASSED: 105 FAILED: 0**（全量受既有慢测试/并发改动阻塞，见 §1）
配套：[视觉升级开发文档](../../视觉升级开发文档.md) ｜ [视觉差距分析](../../视觉差距分析-对标王者荣耀.md)

---

## 0. 本批做了什么

| 任务 | 改动 | 主要文件 |
| --- | --- | --- |
| MON-01 受击/出手反馈 | `hit` 事件补 `source / source_type`；野怪/小兵受击闪白 + 缩身，出手前倾；arena 按 source 分发 | `sim/match_sim.gd`、`scripts/game/arena.gd`、`scripts/game/unit_visual.gd` |
| MON-02 死亡/重生 | 程序化野怪倒地后最后 0.6s 沉入地面；重生 0.25s 缩放回场 | `scripts/game/unit_visual.gd` |
| MON-03 小兵类型 | 近战/远程/炮车/超级兵四套配件 + 体型；池化复位时切换 | `scripts/game/unit_visual.gd` |
| STRUCT-01 建筑残骸 | 塔/主堡死亡保留 root，隐藏活体部件，显示碎石 + 断柱 + 阵营晶屑；碎石/晶屑走 MultiMesh | `scripts/game/arena.gd` |
| FX-02 状态表现 | 护盾泡、红/蓝 BUFF 光环、减速冰环，全部读现有快照字段 | `scripts/game/unit_visual.gd` |
| HERO-01 英雄剪影 | 5 英雄 `body_scale` + 武器比例拉开，身高仍锚 `HERO_HEIGHT` | `scripts/game/unit_visual.gd` |
| UI-01 技能图标（部分） | 17 个 kind 在 5 族图形之外增加专属印记 | `scripts/ui/skill_glyph.gd` |
| UI-03 商店 | 分类页签 + 详情（名称/属性/价格/品质）+ 品质边框 | `scripts/ui/shop_panel.gd`、`sim/item_shop.gd` |
| FX-01 柔光粒子（部分） | 粒子贴图从纯色方片换成程序化径向渐变柔光圆；环境粒子同用 | `scripts/game/fx_textures.gd`、`scripts/game/arena.gd` |
| UI-02 英雄面板 | 6 个装备格（复用装备图标）+ 4 个 Buff/Debuff 色标；定位并入名字行，状态卡高度不变 | `scripts/ui/game_hud.gd`、`scripts/ui/hud_layout.gd` |
| WALL-01 城墙 | 墙脚草簇（1 个 MultiMesh 批次）+ 墙端露头交替 Rock/Rock_Group + 中段 Rock_Group 变体 | `scripts/game/arena.gd` |
| SCENE-01 场景 | 蓝/红基地各 4 面旗 + 2 盏灯笼；每个野点/首领坑附近石碑 + 兽骨，动态避开兵线/墙体/草丛 | `scripts/game/arena.gd` |
| FX-04 地面残留（部分） | 12 个池化贴地柔光 quad，1.6s 淡出；技能链路自动在落点生成 | `scripts/game/arena.gd` |
| UI-04 击杀信息流（部分） | 击杀条目加击杀者/受害者头像；塔/小兵击杀只显示受害者头像 | `scripts/ui/game_hud.gd`、`scripts/game/arena.gd` |
| UI-06 结算页（部分） | 结算页加英雄头像 + MVP/参战徽标（按 kills/deaths 判定） | `scripts/ui/game_hud.gd` |
| STRUCT-04 基地广场（部分） | 贴地旋转符阵 + 三道团队色同心环；摧毁后随活体部件隐藏 | `scripts/game/arena.gd` |
| SCENE-03 环境粒子（部分） | 浮尘从 36 提到桌面 120 / 移动端 60，仍是单批次 | `scripts/game/arena.gd` |
| MON-07 河道之灵（部分） | 球 + 环升级为头/双眼/双鳍/三节水尾/伴游光点 | `scripts/game/unit_visual.gd` |
| MON-04 首领刷新（部分） | 全局播报 + 两个首领坑地面冲击环/金色粒子；死亡演出沿用现有爆炸 | `scripts/game/map_view.gd`、`scripts/game/arena.gd` |
| STRUCT-02 主堡陷落（部分） | `match_end` 反推败方基地，水晶位置大范围爆炸 + 冲击环 + 震屏 | `scripts/game/arena.gd` |
| STRUCT-03 塔层级（部分） | 内塔/高地塔塔冠下逐级加宽的团队色束带 | `scripts/game/arena.gd` |
| SCENE-02 河岸（部分） | 沿河道两岸铺高草芦苇带，避开兵线/桥心/营地 | `scripts/game/arena.gd` |
| HERO-02 武器主色（部分） | 5 把武器按英雄谱系色染色，和技能/立绘主色对齐 | `scripts/game/unit_visual.gd` |
| FX-07 首领死亡（部分） | 首领击杀加顿帧 + 金色大范围地面残留 | `scripts/game/arena.gd` |
| FX-03 技能强调色（部分） | 17 个 kind 各一个强调色，与英雄谱系色 55/45 混合 | `scripts/game/skill_fx.gd`、`scripts/game/arena.gd` |
| UI-01 位图技能图标 | 17 kind + attack + summoner 共 19 张 PNG，接入技能键/普攻键 | `assets/ui/skills/`、`scripts/ui/skill_button.gd`、`scripts/ui/game_theme.gd` |
| FX-01 位图 VFX | spark/smoke/glow/rune/slash/shock 6 张 PNG；粒子/残留/刀光接入 | `assets/vfx/textures/`、`scripts/game/fx_textures.gd`、`scripts/game/arena.gd` |
| UI-05 小地图底图 | 512² 对称峡谷底图，叠在程序化标记下 | `assets/ui/minimap/canyon_bg.png`、`scripts/ui/minimap.gd` |
| UI-07 9-slice | 金边面板框接入商店/结算浮层 | `assets/ui/frames/panel_gold.png`、`scripts/ui/game_theme.gd` |
| HERO-03 3D 预览 | 选人页复用现有模型的可旋转 SubViewport 预览骨架 | `scripts/app/hero_preview.gd`、`scripts/app/main.gd` |
| HERO-04 接入骨架/规格 | 定制模型路径/动作契约、自动回退、美术规格书；**5 套模型/动画待美术交付** | `scripts/game/hero_model_registry.gd`、[规范](../../英雄定制模型规范-HERO-04.md) |
| WALL-02 材质语言 | 野区自然岩壁 / 边界砌石城防共用 shader，`brick_amount` 切换；自然岩壁加岩层带 | `scripts/game/arena_look.gd`、`shaders/rock_wall.gdshader`、`scripts/game/arena.gd` |
| WALL-04 背景岩峰（部分） | 边界外侧增加高过墙顶的背景岩体，不改碰撞/遮挡预算 | `scripts/game/arena.gd` |
| SCENE-04 地表 macro | 地形 shader 低频 macro variation，复用现有噪声采样 | `scripts/game/terrain_builder.gd` |
| FX-06 弹道拖尾 | 独立 12 个小光点池，普攻弹丸后拖尾淡出 | `scripts/game/arena.gd` |

> 说明：MON-01 没有新增 `monster_attack` 事件。`hit` 事件原本就有 `source / source_type`
> 白名单键，直接复用，协议零改动；这比原任务卡方案更小、更安全。

---

## 1. G1 机器关

### 视觉回归（无头，已跑）

```cmd
godot --headless --path godot --script res://.tmp/run_visual_tests.gd
```

结果：

```
VISUAL TESTS: 105  PASSED: 105  FAILED: 0
```

覆盖 31 个视觉相关测试文件（受击/状态/兵种/残骸/英雄剪影/技能图标/商店/HUD/基地/城墙/河岸/粒子/3D 预览等），
`FAIL` 与 `SCRIPT ERROR` 扫描：**0 行**。日志：`.tmp/check_visual_selected.log`。

### 全量（当前被外部阻塞）

`godot --headless --path godot --script res://tests/run_tests.gd` 目前会卡在既有的
`test_fairness.test_mirror_match_economy_stays_close`（600 秒镜像局模拟，>600s 未完成）；
另有并发改动留下的 `test_cc.test_minion_vs_minion_hits_do_not_flood_the_wire`、
`test_match.test_minions_spawn_and_advance_towards_enemy_base` 失败。
这两类都不是本批视觉代码；待对应 owner 修复后再跑全量。

视觉回归覆盖（32 个文件，105 条；下表为新增/扩展的代表性用例）：

| 文件 | 条数 | 覆盖 |
| --- | --- | --- |
| `test_monster_feedback.gd` | 5 | hit 事件 source/source_type、受击缩身/闪白/复位、出手前倾、arena 分发、小兵复用 |
| `test_unit_status_visuals.gd` | 4 | 护盾泡、红/蓝 BUFF 光环颜色、减速环、死亡隐藏/复活恢复 |
| `test_minion_visual_types.gd` | 3 | 四类型配件互斥、炮车/超级兵体型、池化切换 |
| `test_structure_destruction.gd` | 3 | 塔残骸、主堡残骸、残骸不伪装碰撞体 |
| `test_hero_silhouette.gd` | 4 | 身高契约、宽度差异、body/weapon scale 唯一、武器主色 |
| `test_skill_glyph_uniqueness.gd` | 2 | 每个 kind 图形唯一、印记不顶圆环 |
| `test_shop_detail.gd` | 4 | 分类过滤、详情文案、品质颜色、详情不加 TextureRect |
| `test_fx_textures.gd` | 2 | VFX 位图加载/缓存、soft_glow 优先位图 |
| `test_monster_death_spawn.gd` | 1 | 死亡下沉、重生缩放入场、复位 |
| `test_hud_equipment_row.gd` | 4 | 6 装备格、图标更新、空槽、Buff/Debuff 色标 |
| `test_wall_vegetation.gd` | 2 | 墙脚草批次、贴墙不压兵线 |
| `test_wall_end_variants.gd` | 1 | 墙端单块/岩石群两种剪影 |
| `test_wall_ridge_variants.gd` | 1 | 中段变体数量/材质/高度预算 |
| `test_tower_tier_band.gd` | 2 | 层级束带半径递增、塔毁隐藏 |
| `test_match_end_fx.gd` | 1 | 主堡陷落冲击环/震屏 |
| `test_river_reeds.gd` | 1 | 芦苇数量/岸线/兵线避让 |
| `test_hero_silhouette.gd`（扩展） | +1 | 武器主色染色接线 |
| `test_objective_spawn_fx.gd`（扩展） | +1 | 首领死亡金色残留 |
| `test_skill_accent_colors.gd` | 2 | 强调色唯一、混色保持英雄身份 |
| `test_theme_assets.gd` | 4 | 19 技能/8 状态/6 VFX/小地图/9-slice 资产 |
| `test_tracer_trail.gd` | 2 | 拖尾池预建、弹丸不抢占主池 |
| `test_boundary_backdrop.gd` | 1 | 背景岩峰在可走边界外、高过墙顶 |
| `test_hero_preview.gd` | 2 | 3D 预览装配、切换英雄重建 |
| `test_hero_model_registry.gd` | 3 | 路径/动作契约、缺失回退 |
| `test_base_props.gd` | 2 | 基地旗/灯笼存在、避开广场与兵线 |
| `test_jungle_props.gd` | 2 | 野区石碑/兽骨存在、避开兵线/贴地盘 |
| `test_skill_decals.gd` | 4 | 残留池预建、淡出归还、池空抢占、技能链路接线 |
| `test_kill_feed_avatars.gd` | 3 | 英雄击杀双头像、非英雄单头像、最多 5 条 |
| `test_result_mvp.gd` | 3 | MVP 判定、参战徽标、失败结算头像 |
| `test_base_plaza_look.gd` | 2 | 基地符阵/同心环存在、摧毁后隐藏 |
| `test_ambient_particles.gd` | 1 | 浮尘数量、发射、柔光贴图 |
| `test_river_spirit_look.gd` | 1 | 水灵头/尾/鳍/光点、自发光色相 |
| `test_objective_spawn_fx.gd` | 3 | 刷新播报、两坑冲击环、首领死亡残留 |

顺带修复一处既有假绿：`test_monster_forms.gd::test_camp_forms_have_distinct_silhouettes`
之前对 `MonsterForms.build("wolf")` 的空字典取 `root`，在断言前抛 `SCRIPT ERROR` 但仍 PASS。
现在 wolf 走 `UnitVisual` 单独量剪影，日志不再出现该错误。

---

## 2. G3 接线关

```bash
grep -rn "play_attack_reaction" --include="*.gd" godot/scripts godot/sim godot/net
grep -rn "destroy_hide\|_build_structure_rubble" --include="*.gd" godot/scripts
grep -rn "body_scale" --include="*.gd" godot/scripts
grep -rn "quality_of\|ids_by_category" --include="*.gd" godot/scripts godot/sim
```

结果均命中生产文件（不是只有 `tests/`）：

- `play_attack_reaction`：`arena.gd:4272` 调用，`unit_visual.gd:1383` 定义；
- `_build_structure_rubble`：`arena.gd:3840` 调用；
- `body_scale`：`unit_visual.gd:78/92/106/120/134` 配置，`:446` 应用；
- `quality_of / ids_by_category`：`shop_panel.gd:205/213` 与 `:196` 使用；
- `hit.source / source_type`：`match_sim.gd:1410-1411` 发出，`arena.gd:4266-4272` 消费。
- 死亡/重生与装备格：`unit_visual.gd` 的 `_spawn_scale_timer` / `_update_death_pose()`；`game_hud.gd` 的 `_equip_icons` / `_status_pips` 均由 `set_state` 每帧刷新。
- 墙脚草/基地装饰：`arena.gd` 的 `_build_wall_tufts()` / `_build_base_props()` 在 `_build_map_features()` 内调用。

---

## 3. G2 变异关

**未执行**。本批是“先落地、后补验收”的实现批次；下一轮请至少补：

1. 把 `HIT_FLASH_SECONDS` 改成 0 → `test_monster_feedback` 必须红；
2. 删掉 `arena.gd` 里的 `attacker.play_attack_reaction()` → 必须红；
3. 把 `_select_category` 的过滤改成恒显示 → `test_shop_detail` 必须红；
4. 把 `rubble.visible = not alive` 改成 `false` → `test_structure_destruction` 必须红。

---

## 4. G4 视觉关

**已执行**（用户授权短暂开窗）：`tools/ui_shot.gd` 生成 `godot/shots/ui_*.png`。
已目视确认：
- 选人页左下有可旋转 3D 英雄预览（复用现有模型）；
- 对局右下技能键使用位图图标，英雄面板装备格/状态色标可见；
- 小地图叠了程序化峡谷底图；
- 9-slice 金边用于商店/结算浮层（代码测试守纹理，截图未单独打开商店）。

仍需补的专项截图：S3 5v5 团战受击、S4 双 BUFF 营地、S7 塔毁前后、S10 移动端 HUD。

---

## 5. G5 联机关

`hit` 事件新增的 `source / source_type` 两个键**本来就在** `net_protocol._sanitize_event` 白名单里
（`net/net_protocol.gd:561-574`），因此没有协议变更，`test_net_protocol` 全绿。
**双端实机未跑**：需要在有第二台设备时确认客机也能看到野怪出手前倾/受击闪白。

---

## 6. G6 性能关

**已测，未达标**：`tools/perf_check.gd` 在 Quadro K420 / OpenGL Compatibility / 1600×900 下：
`PERF 5v5 1600×900 avg=32.0 min=32.0 max=32.0 fps`。目标桌面 ≥60fps 未达到；
该机器为 2014 年入门 Quadro，需在目标机上复测，或继续压 draw call/粒子。

本批的潜在热点与已做的缓解：

| 改动 | 风险 | 缓解 |
| --- | --- | --- |
| 每个小兵多 3 组配件 | 可见配件增加 draw call | 每组最多 7 个 mesh；只有当前类型可见；隐藏节点不绘制 |
| 每个单位多 4 个状态节点 | 5v5 单位数量多 | 默认全隐藏；只有护盾/BUFF/减速/受击时显示 |
| 塔/主堡残骸 | 18 座塔全毁时 draw call 爆炸 | 碎石 + 晶屑走 MultiMesh，单座残骸约 4 个 draw call |

日志：`.tmp/perf_after_shader.log`。野区道具已从 70+ draw call 压到 3 个 MultiMesh 批次，但该 GPU 仍为硬件瓶颈；移动端仍需 `tools/device_checks.py`。

---

## 7. G7 资产合规关

本批新增 **35 张程序化 PNG**（19 技能 + 8 状态 + 6 VFX + 1 9-slice + 1 小地图），
由仓库内 Python/PIL 脚本生成，不依赖第三方素材；`docs/art-credits.md` 仍需补登记。

---

## 8. G8 真机关

**未执行**：`adb devices` 当前无设备。需要连接 Android 设备后重导 APK 并跑
`tools/device_checks.py`。

---

## 9. 未做 / 下一步

- [ ] G2 变异验证（4 条）
- [ ] G6 目标机性能 ≥60fps（当前 Quadro K420 33.8fps）
- [ ] G8 连接设备后重导 APK + device_checks
- [ ] HERO-04 5 英雄定制模型/动画（接入骨架/规格已完成，待 3D 美术交付）
- [ ] FX-05 预警圈（当前 sim 无施法前摇，强行加会与伤害时序不一致）
- [ ] WALL-04 墙顶局部抬高（当前只做了边界外背景岩峰）
- [ ] UI-07 全量面板 9-slice（当前只接商店/结算）

---

## 10. 签字

| 项 | 结论 | 证据 | 签字 | 日期 |
| --- | --- | --- | --- | --- |
| G1 机器 | 🟨 视觉回归 105/105；全量被外部慢测试阻塞 | `.tmp/check_registry.log` | 待签 | 2026-11-10 |
| G2 变异 | ⬜ 未做 | — | — | — |
| G3 接线 | ✅ grep 命中生产 | 本文件 §2 | 待签 | 2026-11-10 |
| G4 视觉 | 🟨 截图已生成，待专项复核 | `godot/shots/ui_*.png` | 待签 | 2026-11-10 |
| G5 联机 | 🟨 白名单绿、双端未跑 | `test_net_protocol` | 待签 | 2026-11-10 |
| G6 性能 | ❌ 32.0fps < 60（Quadro K420） | `.tmp/perf_after_shader.log` | 待签 | 2026-11-10 |
| G7 合规 | 🟨 新增 35 张程序化 PNG，credits 待补 | 本文件 §7 | 待签 | 2026-11-10 |
| G8 真机 | ⬜ 无设备 | `adb devices` 空 | — | 2026-11-10 |
