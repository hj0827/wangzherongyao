# 03 · 战争迷雾、野区生态与中立首领升级规范 (Fog of War & Jungle)

## 1. 目标与设计
参考《王者荣耀》视野与打野控图生态，为战局带来战术纵深与视野博弈：
- **战争迷雾与草丛机制（Vision & Brush）**：
  - 常规视线范围（约 12m），墙体阻断视线（Line of Sight 遮挡）。
  - 草丛（Bush）：进入草丛的单位对外部敌军隐形；只有当敌军同样进入该草丛或极近距离（<=2m）探测，或草丛单位发起攻击后（短暂暴露计时 `revealed_timer`），才会显形。
  - 快照权限过滤（Snapshot Vision Filtering）：服务端下发客机快照时，利用 `Vision.filter_snapshot` 剔除敌方视野外单位，彻底杜绝全图透视挂。
- **野区营地与双 Buff（Jungle Camps & Red/Blue Buffs）**：
  - 地图设立 4 处镜像野怪营地（蓝方野区两处、红方野区两处）。
  - 蓝 Buff 怪（霜狼）：击杀获得蓝 Buff，大幅缩减技能 CD（`BLUE_COOLDOWN_SCALE = 0.8`）。
  - 红 Buff 怪（赤狼）：击杀获得红 Buff，普攻附加减速与额外增伤（`RED_DAMAGE_SCALE = 1.15`）。
  - 野怪拥有脱战回巢（Leash Range）与 70 秒刷新机制。
- **中立战略首领（Boss Objectives）**：
  - 暴君（Tyrant）与主宰（Overlord）两处镜像龙坑，开局 2 分钟首刷，刷新间隔 3 分钟。
  - 首领为超高血量中立巨兽，击杀后为全队提供团队增伤 Buff（`TEAM_DAMAGE_SCALE = 1.2`），成为逼团与终结比赛的关键节点。
- **三塔防御机制与回城（Towers & Recall）**：
  - 外塔、内塔、高地塔三层防御保护；前 3 分钟防御塔享 50% 免伤。
  - 4 秒引导回城（Recall），移动、施法或受到伤害均会打断引导。

## 2. 产出文件
- `godot/sim/map/map_layout.gd`：静态地图布局唯一权威（塔位、墙体、草丛、营地、龙坑坐标）。
- `godot/sim/map/collision.gd`：墙体圆形阻挡、贴墙滑行判定。
- `godot/sim/map/vision.gd`：战争迷雾计算、草丛隐匿、快照视野过滤。
- `godot/sim/map/jungle.gd`：野怪数值、营地管理、红蓝 Buff 计时与加成。
- `godot/sim/map/objectives.gd`：中立首领刷新管理、击杀全队增伤。
- `godot/sim/map/tower_rules.gd`：塔序解锁、防越塔防御机制。
- `godot/sim/map/wave_rules.gd`：小兵波次、炮车、超级兵解锁。
- `godot/sim/map/recall.gd`：4秒回城引导、打断与传送。
- `godot/tests/test_map_*.gd`：对应十套专项测试全部绿灯通过。
