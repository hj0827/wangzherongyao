# 04 · 精准锁敌与攻击键分立规范 (Targeting & Attack Modes)

## 1. 目标与设计
参考《王者荣耀》核心手感设计，解决移动端 MOBA 团战中的误操作痛点：
- **头像锁定（Avatar Target Lock）**：
  - 屏幕右侧动态呈现视野范围内的敌方英雄头像。
  - 点击头像或选中特定英雄后，优先打击该目标，无视就近原则。
  - 目标死亡或超出最大追击范围（14m）时，自动解除锁定，避免人物被带入敌阵。
- **轮盘索敌（Wheel Directional Aiming）**：
  - 拖拽普攻或技能轮盘时，捕获摇杆朝向向量，与周围所有敌方实体计算夹角点积。
  - 精准高亮与优先选定拖拽射线方向上的敌方单位。
- **攻击按键三键分立（Attack Mode Separation）**：
  - **常规普攻键（Default Attack）**：智能判定：英雄 > 小兵/野怪 > 防御塔。
  - **补刀键（Minion Priority Button）**：强制打击周围小兵或野怪，绝不攻击敌方英雄或建筑。
  - **推塔键（Tower Priority Button）**：强制打击射程内防御塔或主堡，团战塔下强推不被敌方英雄分流普攻。

## 2. 产出文件
- `godot/scripts/ui/targeting_system.gd`：锁定状态机、轮盘扇区投影、三模式目标仲裁。
- `godot/tests/test_targeting_and_attack_modes.gd`：6 大专项单元测试全部绿灯通过。
