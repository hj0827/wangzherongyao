# 资产来源与授权登记（art credits）

> 规则来源：[`视觉升级开发文档.md`](视觉升级开发文档.md) §5.3、验收表项 15.2 / 视觉 G7。
> 每新增一张图、一个模型、一套动作，**同一次提交**里在本文件加一行。
> 没有作者 / 来源 / 许可 / 日期的资产，按"未登记"处理，不得计入验收。

状态标记：✅ 已登记并核实 · 🟨 已登记但证据待补 · ⬜ 未登记

---

## 1. 程序化生成资产（本仓库自有）

来源是仓库内的生成器脚本：**代码即来源**，产物可逐字节复现（重跑哈希一致，已验证 15/15 且与生成顺序无关）。
许可：项目自有（Project-owned），无第三方权利负担。

生成命令见 [`视觉升级开发文档.md`](视觉升级开发文档.md) 附录 B；实现见 [`godot/tools/make_ui_assets.gd`](../godot/tools/make_ui_assets.gd)。

| 文件 | 作者 | 来源 | 许可 | 生成日期 / 工具 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `godot/assets/ui/frames/panel_gold.png` | 仓库（程序化） | `tools/make_ui_assets.gd` | 项目自有 | 2026-11-11 / Godot 4.7.2 Image API | ✅ |
| `godot/assets/ui/frames/button_gold.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/frames/slot_quality_basic.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/frames/slot_quality_rare.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/frames/slot_quality_epic.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/frames/slot_quality_legendary.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/kill_banner.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/streak_first.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/streak_double.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/streak_triple.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/streak_quadra.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/banners/streak_penta.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/mvp/mvp_bg.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/mvp/medal_mvp.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |
| `godot/assets/ui/mvp/medal_participation.png` | 仓库（程序化） | 同上 | 项目自有 | 2026-11-11 / 同上 | ✅ |

> 说明：本批 15 张是**骨架 / 占位**。后续用手绘或 AI 位图替换同名文件时，
> 必须把本表对应行改成新资产的真实作者与许可，并把旧行的"程序化"结论划掉。

---

## 2. 待登记：第三方 3D / 环境资产（⬜ 未核实）

差异文档 §5.1 已点名：现有模型基本来自通用低模包，glb 内**没有 `copyright` / `license` 字段**，
仓库此前也没有任何声明文件。下列条目**必须**在项 15.2 收口前补上作者、来源 URL、许可全文与取得日期；
无法证明可商用的，替换或移除。

| 资产族 | 目录 | 疑似来源 | 许可证据 | 状态 |
| --- | --- | --- | --- | --- |
| 身体 / 发型 / 服装（`hero_warrior.glb`、`hair_*.glb`、`outfit_*.glb`） | `godot/assets/characters/` | Kenney / Quaternius 系通用包（导出器签名 `Khronos glTF Blender I/O`） | 无 | ⬜ |
| 骨骼 / 小兵 / 兽人（`Orc.glb`、`Skeleton_*.glb`） | `godot/assets/characters/` | 导出器签名 `glTF-Transform` | 无 | ⬜ |
| 环境建筑 / 树木 / 岩石（`TownCenter_*`、`WatchTower_*`、`Resource_*`） | `godot/assets/environment/` | 导出器签名 `FBX2glTF` | 无 | ⬜ |
| 武器（`Claymore.glb`、`Scythe.glb`、`Bow_*.glb` 等） | `godot/assets/weapons/` | 导出器签名 `trimesh` | 无 | ⬜ |
| 动作库（`ual1.glb` / `ual2.glb` → `AnimationLibrary_Godot_Standard.bin`） | `godot/assets/animations/` | Universal Animation Library | 无 | ⬜ |
| VFX 贴图（`spark/smoke/glow/rune/slash/shock.png`） | `godot/assets/vfx/textures/` | 待确认（程序化 or 第三方） | 无 | ⬜ |

## 3. 待登记：AI 生成资产（🟨 证据只在本机）

| 资产族 | 目录 | 生成方式 | 许可证据 | 状态 |
| --- | --- | --- | --- | --- |
| 英雄立绘（5 张 1024² PNG） | `godot/assets/ui/portraits/` | AI 生成（写实国风） | 提示词/生成记录在 `.video_gen/**/.cache.json`（**被 `.gitignore` 忽略，未入库**） | 🟨 |
| 英雄展示视频（`hero_*.ogv`） | `godot/assets/ui/hero_videos/` | AI 生成 | 同上 | 🟨 |
| 主菜单背景视频 | `godot/assets/ui/`（`menu_bg.ogv`） | AI 生成 | 同上 | 🟨 |
| 技能 / 装备 / 状态 / 小地图图标 | `godot/assets/ui/{skills,items,status,minimap}/` | AI 生成或程序化（**逐张未标注**） | 无逐张记录 | ⬜ |

> 风险（差距文档 §5.1 原文）：AI 链路的原始凭证只存在于本机，
> 一旦换机或清理 `.video_gen/`，立绘与视频的生成来源就无法举证。
> 建议：把 `.video_gen/**/storyboard-*.json` 与 `.cache.json` 的**索引**（不含大文件）导出到
> `docs/art-credits/`，仓库只存索引与哈希。

## 4. 字体

| 文件 | 来源 | 许可 | 状态 |
| --- | --- | --- | --- |
| `godot/assets/fonts/NotoSansSC.ttf` | Google Fonts（思源黑体） | SIL OFL 1.1（**仓库内无许可证文件**） | 🟨 |
| `godot/assets/fonts/MaShanZheng.ttf` | Google Fonts（马善政毛笔） | SIL OFL 1.1（**仓库内无许可证文件**） | 🟨 |

---

## 5. 还缺的自动化（对应项 15.2 / 视觉 G7）

- [ ] `tools/art_credits_audit.py`：遍历 `godot/assets/**`，比对本文件，缺登记即非零退出（进 CI 静态段）。
- [ ] 第三方包的 `LICENSE` 原文入 `docs/art-credits/licenses/`。
- [ ] `.video_gen` 提示词索引导出（见 §3 建议）。
- [ ] glb 写入 `asset.copyright` / `asset.extras.license` 字段（Blender glTF 导出器支持），或导出清单旁挂。
