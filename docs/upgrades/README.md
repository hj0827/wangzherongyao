# 烽火峡谷 · 王者荣耀工业化升级路线与功能归档目录

本目录系统记录以《王者荣耀》为标杆对《烽火峡谷》进行的核心玩法与工程架构升级。
所有功能均严格遵循 **TDD（先写测试，验证红灯 -> 动手实现 -> 验证全量绿灯）** 与 **Clean Game Architecture（Core 确定性逻辑与 View/UI 表现严格解耦）**。

> **接线状态（2026-10-23）**：下表模块均已接入生产代码，接线位置见 [`docs/ai/01-repo-reality.md`](../ai/01-repo-reality.md) §4。本表不再把"文件存在 + 测试绿"当作完成标准。

---

## 升级模块总览

| 模块序号 | 功能分类 | 核心产物文件 | 对应测试套件 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| **01** | **技能体系升级** | `godot/sim/hero_defs.gd`, `godot/sim/skill_system.gd` | `godot/tests/test_skills_and_spells.gd` | 补充被动、Q/W/E/R四技能、召唤师技能（闪现、斩杀、净化、治疗） |
| **02** | **经济与装备商城** | `godot/sim/economy_system.gd`, `godot/sim/item_shop.gd`, `godot/scripts/ui/shop_panel.gd` | `godot/tests/test_economy_and_shop.gd` | 局内自然跳钱、补刀收益、装备树、属性加成计算、商店买卖 UI 与快速预购 |
| **03** | **战争迷雾与野区Buff** | `godot/sim/map/vision.gd`, `godot/sim/map/jungle.gd`, `godot/sim/map/objectives.gd` | `godot/tests/test_map_vision.gd`, `test_map_jungle.gd`, `test_map_objectives.gd` | 视野范围与草丛隐藏判定、红蓝Buff怪、中立主宰/暴君增益判定 |
| **04** | **精准锁定与攻击键分离** | `godot/sim/targeting_rules.gd`, `godot/scripts/ui/targeting_system.gd`, `godot/scripts/ui/attack_cluster.gd` | `godot/tests/test_targeting_and_attack_modes.gd` | 头像快速锁敌、智能轮盘拖拽索敌、补刀（小兵优先）与推塔（建筑优先）按键分工 |
| **05** | **技能指示器与取消施法** | `godot/scripts/ui/skill_indicator.gd`, `godot/scripts/ui/cancel_cast_zone.gd` | `godot/tests/test_indicators_and_cancel.gd` | 圆形/弹道/扇形毫秒级范围指示器、右上角滑动取消施法红区捕获与视觉变化 |
| **06** | **客户端预测与平滑纠错** | `godot/net/client_prediction.gd` | `godot/tests/test_client_prediction.gd` | 客户端本地输入即时预测、服务器权威状态差异比对与带衰减的轻量平滑纠错 |
| **07** | **战斗播报与打击顿帧** | `godot/sim/combat_announcer.gd`, `godot/scripts/view/hit_stop_manager.gd` | `godot/tests/test_kill_and_combat_feedback.gd` | 一血/双杀/三杀/四杀/五杀/团灭事件广播、打击顿帧（Hit-stop）与视听震屏反馈 |
| **08** | **地图地形与三线攻防** | `godot/sim/map/map_layout.gd`、`collision.gd`、`tower_rules.gd`、`wave_rules.gd`、`crystal.gd`、`river.gd`、`teleport.gd`、`godot/scripts/game/map_view.gd`、`bush_feedback.gd`、`audio_cues.gd` | `godot/tests/test_map_layout.gd` 等 14 个地图套件 | 三线分塔解锁、墙体碰撞与草丛视野、野区/首领、高地双子塔与水晶护盾、河道之灵与传送阵、草丛镜头/音效反馈、兵种成长、回城、小地图与事件播报，详见 [08_map_and_terrain.md](08_map_and_terrain.md) |
