# 07 · 多杀播报与打击顿帧反馈规范 (Announcements & Hit-Stop)

## 1. 目标与设计
参考《王者荣耀》核心打击爽感与视听反馈系统，大幅提升竞技爽快感与高光时刻激励：
- **战场多杀与连杀播报系统（Combat Announcer）**：
  - **First Blood（第一滴血 / 一血）**：全场首次击杀英雄，播发一血事件与全屏横幅。
  - **多杀时刻（Multi-Kill 连杀判定）**：
    - 10 秒时间窗口内连续斩获人头：
      - 2杀：Double Kill（二连击破）
      - 3杀：Triple Kill（三连决胜）
      - 4杀：Quadra Kill（四连超凡）
      - 5杀：Penta Kill（五连绝世）
  - **单命连杀荣耀头衔（Kill Streaks）**：
    - 单命未死累计：3杀（Killing Spree 大杀特杀）、5杀（Rampage 杀人如麻）、7杀（Godlike 横扫千军）、8杀+（Legendary 天下无双）。
  - **终结机制（Shutdown）**：成功击杀连续斩获 3 个人头以上的敌方英雄时，播发 Shutdown 终结激励，压制敌方滚雪球。
  - **团灭播报（Ace）**：某一方全体存活英雄归零时，触发震撼全场的 Ace 团灭通告。
- **打击顿帧与微震反馈（Hit-Stop & Screen Shake Manager）**：
  - **打击顿帧（Hit-stop / Frame Freeze）**：重击、暴击或技能命中瞬间，受击目标与攻击者动画微小冻结（约 0.05~0.08 秒），营造刀刀入肉的扎实钝感。
  - **相机微震（Screen Shake）**：依打击力度激发不同振幅的相机震动，并在 250ms 内平滑衰减归零，杜绝头晕，兼顾打击反馈。

## 2. 产出文件
- `godot/sim/combat_announcer.gd`：多杀时间窗口追踪、连杀头衔、终结判定、全队团灭检测。
- `godot/scripts/view/hit_stop_manager.gd`：冻结定时器、震动偏移计算与衰减模型。
- `godot/tests/test_kill_and_combat_feedback.gd`：4 大专项测试用例全部绿灯通过。
