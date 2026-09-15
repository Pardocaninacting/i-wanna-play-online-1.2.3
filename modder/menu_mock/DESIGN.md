# 菜单 UI 设计 v4：主从式（master–detail），详情列按行类型自适应

> 状态：**HTML 原型已迭代到 v4，待确认后落 GML**。预览：`node _workspace/tmp/cloud/serve_mock.mjs 8791 modder/menu_mock`
> → http://127.0.0.1:8791/ （仅本地预览用，不是产品的一部分）

## 0. v4 相对 v3 的改动

1. **详情列不再"一宽一用"**：v3 的详情面板对简单行是"标题+说明+重复按钮+空预览框"，既冗余又显空。
   v4 改为**按行类型出内容**（见 §2），简单行紧凑、富行充分利用。
2. **选择器控件**：散开的 `value ‹›` 两个 pill 收进**单框 `‹ value ›`**（与 GML 里已实装的样式一致）。
3. **取消一切复制**：详情里不再出现与列表行相同的按钮；不再出现与值卡片相同的字段预览（Name/Key 处）。
4. **每页数据模型补内容**：Saves 改事实表（房间/类型/时间/死亡数）、Keys 加大键帽、Skins 加精灵占位+事实、
   Rating/Sync 各行补全（此前详情对所选行是空的）。
5. **滚动证明可用**：+40 行压测通过——选择自动滚动跟随、详情联动、页脚不动、永不溢出。

## 1. 要解决的问题（v3 已有，沿用）

| 问题 | 现状 | 后果 |
|---|---|---|
| 选项只会越来越多 | 单列 → 双列（600×460 塞 16 行）| 双列**迟早也会满**；再挤就只能缩字号/缩行高，可读性崩 |
| 只有 Settings 面板重做过 | Saves/Rating/Keys/Sync/Skins 仍是各自手写坐标 | 5 个面板风格不统一、排版各自为政、同样会溢出 |
| 溢出无出口 | 面板高度固定 460px | 多一行就直接压到页脚/越界 |

## 2. 布局

```
┌──────────────────────────────────────────────────────────────┐
│ [Settings] [Saves(3)] [Rating] [Keys] [Sync] [Skins]         │ 26px 标签栏
├──────────────────────┬───────────────────────────────────────┤
│ CONNECTION           │  Lerp                                  │
│  ● Online   1.2.3.4  │  ┌────────┐                            │
│  Reconnect now       │  │  ON    │ ← 值卡片（开关绿/灰边）    │
│  Apply & Reconnect   │  └────────┘                            │
│ ACCOUNT              │  GAMEPLAY · 6 OPTIONS ← 分区上下文     │
│ ▸Name      QoLFirst  │  Interpolate remote players between    │
│  Session key ******  │  network updates (smoother, slightly   │ ← 说明
│  Store in  ‹Global›  │  delayed).                             │
│ GAMEPLAY             │                                        │
│  Team      ‹0 None›  │  ┌ 事实表 / 预览（按行类型，仅富行）┐  │
│  Lerp         ON     │  └─────────────────────────────────┘  │
│  …（超出即滚动）     │                        [ Edit… ] [Clear]│ ← 动作（仅富行）
├──────────────────────┴───────────────────────────────────────┤
│ 说明行（跟随选中项）                        ↑↓ Wheel  [Close] │ 28px 页脚
└──────────────────────────────────────────────────────────────┘
        268px                              372px            = 640×460
```

## 3. 详情列按行类型出内容（v4 核心）

| 行类型 | 详情内容 | 理由 |
|---|---|---|
| toggle / select | 值卡片（开关带色边）+ 分区上下文 + 说明 + 事实表(若有) | 改值就在行上（←→），详情只补"它是什么" |
| text（Name/Key/Comment） | 值卡片 + 分区 + 说明 + 事实表 + **[Edit…] [Clear]** | 账户类才有真正的动作，详情给足 |
| button（Reconnect/Clear/Reset） | 分区 + 说明 + 警示(若有) | 列表行本身就是触发器，详情不再放重复按钮 |
| entry（Saves/Skins/Sync/Rating-game） | 预览（Skins 精灵框）或事实表 + 类型动作（Load/Fav/Delete、Apply/Remove） | 看内容再决定 |
| status（连接状态行） | 状态卡片 + Server/延迟 事实表 | 状态行本身就是信息 |

## 4. 几何常量（与 GML 保持同一套数字）

| 常量 | 值 | 说明 |
|---|---|---|
| 面板 | 640×460（clamp 视口−16） | 比 GML 现版 600×460 宽 40px 给详情列 |
| 标签栏 | 26px | 活动 tab：白字 + 底部 2px 琥珀下划线 |
| 行高 / 分区标题 | 22 / 15 | |
| 列表列 | 268px（含 8px 内边距 + 5px 滚动条） | 标签左、控件右（‹ value › 单框、ON/OFF pill） |
| 详情列 | 372px（10/12px 内边距） | 见 §3 |
| 页脚 | 28px | 左侧说明行（跟随选中），右侧按键提示 + Close |

配色沿用 GML 现版：底 `#0b0b0d`、边 `#5a5a60`、正文白、次要 `#9aa0a6`、分区标题 `#96c8e6`、
选中琥珀 `#e1cd5a`、开 `#32aa50`、关 `#5a5a5a`、警示黄 `#dcc83c`、错误红 `#dc5a5a`。

## 5. 交互模型（与现版一致）

- **键盘**：↑↓ 移动（自动滚动跟随）、PgUp/PgDn 翻页、Home/End 首末、←→ 改值、Enter 执行/编辑、O 或 F1 关闭
- **鼠标**：点标签切页、点行选中、点值/箭头改值、滚轮滚动、点详情里的按钮执行
- **窄窗口**：`@spW/@spH` 按视口 clamp；若宽度 < 520 则**详情折叠**（只留列表 + 页脚说明行）

## 6. 已拍板的设计点（v3 的开放问题）

1. **面板尺寸 640×460**：接受。详情列现在每行都有内容，40px 花得值。
2. **详情列**：**永远显示、按行类型自适应**。不做按需展开——布局稳定不跳动，简单行的留白读作"干净"。
3. **行高**：**22px**。紧凑且与现有 GML 24px 差异不大，移植时按 22 走。
4. **Close**：留在页脚右侧，页脚左侧放说明行。
5. **滚动 vs 分页**：**滚动**（键盘/滚轮/选择跟随），压测已证可行。GML 无裁剪 API，用"视口外跳过绘制"实现。

## 7. 唯一遗留待你确认

- **简单 toggle/select 行的详情列下部留白**（如 Lerp：标题+ON 卡片+说明后约 200px 空）：
  (a) 接受留白（干净、不拥挤）——我倾向这个；
  (b) 详情列从 372px 收到 ~300px，列表加宽；
  (c) 给简单行也塞内容（如"相关选项"）——凑数感强，不推荐。

## 8. 移植到 GML 的计划（按可机械化程度排序）

1. `settingsLib` 行表扩展为 `{kind,label,value,desc,act,section,facts}` + **视口/滚动**（`@stgScroll`、`@stgVisibleRows`，
   行 y = 累计高 − 滚动量，越界不绘制——GM8 无裁剪 API，跳过即裁剪）
2. 详情渲染器 `@stg_draw_detail(row)`：按 kind 出值卡片/说明/事实表/预览/动作按钮（全部 draw_rectangle + draw_text）
3. 滚动条与 `▲/▼ more` 提示（纯矩形）
4. 每个 tab 改为"提供行数组 + 详情内容"（Saves/Skins 复用列表+预览；Rating/Keys/Sync 复用行+详情）
5. 门的断言：**布局不变式**改为"视口外不绘制"（内容可超，绘制必须被裁剪）+ 每 tab 行模型合法性

---

# 9. 字段核实清单（v5，2026-09-15）——**本文件的事实以此节为准**

> 起因：v4 的 mock 里出现了**不存在**的功能（存档 `Deaths`、评分 `Comment`）。按 maintainer 要求：
> **所有涉及的资源必须真实可用，所有陈述的事实必须经过代码核查**。下面每一条都注明出处（文件:行）。

## 9.1 存档（Saves）— 真实字段 **比之前展示的更多**

来源：写入侧 `saveGame.gml:136-144`；初始化 `worldCreate.gml:214-222`；网络读取 `worldCreate.gml:670-705`

| 字段 | 数组 | 说明 |
|---|---|---|
| 收藏 | `saveHistFav[i]` | 0/1 |
| **热键槽** | `saveHistHotkey[i]` | **0 = 无，1..8 = 数字键**（读取后钳制，`worldCreate.gml:704`） |
| **重力符号** | `saveHistGrav[i]` | ±1（线上格式 `uint8*2-1`，`worldCreate.gml:677`） |
| **X / Y 坐标** | `saveHistX[i]` / `saveHistY[i]` | 保存时玩家坐标（`@p.x` / `@p.y`） |
| 房间 | `saveHistRoom[i]` + `saveHistRoomName[i]` | 房间索引 + 名称 |
| 玩家名 | `saveHistName[i]` | 保存时的 `@name` |
| 时间 | `saveHistTime[i]` | `date_current_datetime()` |

⇒ **maintainer 提议的"X/Y 坐标、重力参数"无需新增功能，数据早就有** ✓（当前菜单没显示而已 ✓）。

**真实动作**：`Enter` = 应用/加载（`@saveHistApply`，`worldEndStep.gml` tab1 块）✓；收藏切换 ✓；
`Shift+F` = 只看收藏（`@saveHistFilter`）✓；`Shift+Delete` = **清除所有非收藏存档**（`@saveHistClearFiles`）✓ ✗**没有单条删除** ✗。
**列表形态**：分页 8 条/页、行高 38px、过滤（全部/仅收藏）✓。

## 9.2 评分（Rating）— **没有 Comment**

来源：`worldCreate.gml:172-178`

| 真实字段 | 说明 |
|---|---|
| `rStars` | 星级（列表里显示 ★★★★☆） |
| `rCleared` | 是否通关 |
| `ratingSubmitting` / `ratingSubmit` | 提交中 / 请求提交 |
| `ratingResult` / `ratingResultTimer` | 服务器返回结果 + 显示计时 |
| `ratingCooldown` | **冷却**（重复提交限制） |

⇒ 删除 mock 的 `Comment` ✗；改为展示 **结果 + 冷却** ✓（真实且有用 ✓）。

## 9.3 同步（Sync）— 条目是"全局变量位图"

来源：`worldCreate.gml:291-292`（`syncEnabled`/`syncEntryCount`，上限 **16** ✓）；`worldCreate.gml:609-613`（ini 持久化）;`saveGame.gml:155-175`（发送循环）

| 真实字段 | 说明 |
|---|---|
| `syncName[i]` | **被同步的全局变量名** |
| `syncCount[i]` | 位数（bits） |
| `syncSlotCount[i]` | 32 位槽数量 |
| — | 发送时若 `!variable_global_exists(syncName[i])` 则**跳过**（"本游戏无此变量"是可展示的真实状态 ✓） |

⇒ mock 的 `#12 / x14 / bitfield` 方向正确 ✓，但应写成 **全局名 / bits / 槽数 / 是否存在** ✓；
"Reset local cache" 是虚构 ✗ 删除 ✓。

## 9.4 皮肤（Skins）— 元数据只有三项 + 预览精灵

来源：`skinLib.gml:175-177`（`info.ini` 读取）；`skinLib.gml:709-728`（预览精灵）；`worldEndStep.gml` tab5 块（`skin_select()`、`@skinAutoDL`）

| 真实字段 | 说明 |
|---|---|
| `skinName[i]` | `info.ini [skin] name`（缺省 = 目录名） |
| `skinMaker[i]` / `skinSource[i]` | `maker` / `source`（**没有 version 字段** ✗） |
| `skinFrames[i, n]` / `skinOx[i, n]` | 帧数 / 原点 |
| `skinPrevSpr[n]` + `skinPrevLoaded` | **预览精灵**（真实存在 ✓ ⇒ 详情里的预览框是合理的 ✓） |
| `skinAutoDL` | 自动下载开关（真实 ✓） |

**真实动作**：`Enter` = `skin_select(i)` 应用 ✓；自动下载开关 ✓。
**maintainer 提议的管理/搜索**：搜索（按 name/maker/source 过滤）**可行** ✓（注册表就是目录扫描 + 三个字符串 ✓，
`string_pos` 即可 ✓）；删除皮肤目录**需要新代码** ✓（skinLib 里已有下载/清理逻辑，可复用 ✓）——标为 **[new]** ✓。

## 9.5 键位（Keys）— 11 项，标签固定

来源：`worldDrawGui.gml:983-993`：`Visibility, Toggle Save, Spectate, Chat Log, Indicator, Options, Player List, Chat, Here, Fast Load, Canvas`
（mock 之前列的"Settings menu / Notes canvas / Share bullets"是**编造** ✗，已改）

**真实动作**：逐项重绑（"Press a key…" ✓）+ `Reset Keys` ✓。

## 9.6 设置/账户（Settings）

已核查（见第 6 节与 `check_qol_account.js` 的 184 断言）：Name / Session key（掩码）/ Store in（Global|This folder）/
Reconnect now / Apply & Reconnect ✓；连接状态来自 `@connected`/`@tcpState`/`@reconnecting`/`@socketConnectResult` ✓。
**没有延迟（latency）测量** ✗ ⇒ mock 里的 `Latency: -` 已删除 ✓。

## 9.7 窄窗口 / 小房间（现实问题，必须实现）

**根因**：HUD 用 **view-port 像素**绘制（`worldDrawGui.gml` 设置 `ortho(0,0,@hudWinW,@hudWinH)`，
`@hudWinW = view_wport[view_current]`）⇒ 端口只有 320×240 的游戏里，640px 面板**根本放不下** ✗。

**三档布局**（mock 已实现，`?mode=full|narrow|tiny` 可直接看）：

| 条件 | 面板 | 布局 |
|---|---|---|
| `@hudWinW ≥ 660` | 640×460 | 列表 + 详情（完整） |
| `480 ≤ @hudWinW < 660` | 480×420 | **仅列表**；详情内容折进**页脚说明行**；行高 20px |
| `@hudWinW < 480` | 320×300 | 仅列表；行高 18px；分区标题 13px；滚动条换成 `▲/▼ more` 计数；页脚单行 |

（纵向同理：`@hudWinH < 340` 时页脚压到 24px、去掉按键提示 ✓）

## 9.8 待 maintainer 拍板的新增项（均标 [new]，需新代码）

| 面板 | 新增项 | 可行性 |
|---|---|---|
| Saves | 单条删除 | 需新代码（当前只有"清除全部非收藏"）✓ 可行：删文件 + 重建历史 |
| Saves | 热键分配（1..8）| 字段已在 ✓，分配 UI 需新代码 ✓ |
| Saves | 显示 X/Y/重力/房间/时间 | **无需新代码** ✓（数据已在 ✓） |
| Skins | 关键词搜索 | 可行 ✓（三字符串过滤） |
| Skins | 删除皮肤 / 打开目录 | 需新代码 ✓（下载/清理逻辑可复用） |
| Sync | 逐条启用/禁用 | 需新代码（当前只有全局开关）✓ |
| Rating | 显示冷却/结果 | **无需新代码** ✓（字段已在 ✓） |
---

# 10. 决策记录 + **在现有菜单实现上扩展**的方案（2026-09-15）

## 10.1 maintainer 决策（本轮）

| 议题 | 决策 |
|---|---|
| 布局档位 | **只保留 full + narrow**；**narrow 就沿用现在线上这套 UI（600×460）** ✓ tiny 取消 ✓ |
| Saves | 单条删除：**不做** ✓；**热键分配：保留** ✓；**增强显示：做** ✓（X/Y、重力、房间、时间、玩家名、热键槽 ✓ 全部是已有数据 ✓） |
| Skins | **加搜索** ✓；删除皮肤、打开目录：**不做** ✓ |
| Sync | 维持现状 ✓ |
| Rating | 冷却**已显示** ✓ 但数字不对 + 走时偏快 ⇒ 本轮已修（见 10.2）|
| 实施路线 | **分析并沿用既有菜单实现，在其上添加功能**（不重写）✓ |

## 10.2 本轮修掉的真 bug：评分冷却既显示错、走时也偏快

**证据链**：
- `worldEndStep.gml:447` 冷却 = `room_speed * 10`（**帧**数 ✓ 60fps = 10 秒 ✓）
- `worldDrawGui.gml:958` 显示 `ceil(@ratingCooldown / 30)` —— **除数是硬编码 30** ✗ ⇒ 60fps 游戏显示 **20 秒** ✓（正是你看到的"20秒？"）
- 且它是**按帧递减**（每 End Step 减 1）✗ ⇒ 实际帧率高于 `room_speed` 的引擎里，冷却**真的会提前结束** ✓（"流速稍快"）

**修法**（9 处，已全部一致化并实机冒烟通过）：
- 冷却/结果改为**挂钟截止时间**：`@ratingCooldown = current_time + 10000`、`@ratingResultTimer = current_time + 3000` ✓
- 判定统一为 `> current_time` / `<= current_time` ✓（worldEndStep 2 处 + worldDrawGui 3 处）
- **删除两行按帧递减** ✓（deadline 自己到期 ✓）
- 显示改为 `max(1, ceil((@ratingCooldown - current_time) / 1000))` 秒 ✓ ⇒ **真实 10 秒、按真实秒数倒数** ✓
- 与帧率**完全无关** ✓（`current_time` 是毫秒 ✓ GM8/GMS 都有 ✓）

## 10.3 现有菜单的骨架（分析结论，**要复用的部分**）

| 构件 | 位置 | 复用方式 |
|---|---|---|
| 面板底板 / 标签栏 / 页脚（hint + Close） | `worldDrawGui.gml` ~455-500、641-660、1301-1313 | **原样保留** ✓（full 模式只加宽右边界 ✓） |
| 标签页切换（点击 + 左右键） | 同上 ~460-486、输入侧 `kbFocus = 0` | 原样保留 ✓ |
| 每面板绘制块 | TAB 0..5（`// TAB n:` 注释分段 ✓，138/197/118/75/52/571 行） | **原样保留** ✓ |
| 每面板输入块 | `worldEndStep.gml` 的 `@kbRow[0..5]`（每 tab 一套光标/翻页/确认） | 原样保留 ✓ |
| 行表机制（仅 tab 0） | `settingsLib.gml`（`@stg_build_rows/@stg_value/@stg_act` ✓ 25 段） | 作为 **full 模式详情列的数据源** ✓ |
| 键盘捕获（键位） | TAB 3 + `@kbKeys/@kbLabels`（11 项 ✓） | 原样保留 ✓ |
| 分页（存档 8/页、皮肤） | TAB 1 / TAB 5 | 原样保留 ✓ |
| 存档过滤（`@saveHistFilter`，Shift+F） | TAB 1 | **作为 skins 搜索的现成范例** ✓ |

**改动面实测**：6 个面板对 `@spW` 的依赖合计 **23 处**；绝对 x（≥200）**14 处**（10 处在 TAB 5）
⇒ 引入"内容列宽"变量是**机械小改** ✓ 不必重写 ✓。

## 10.4 实施方案（增量，按落地顺序）

**第 1 步：引入内容列宽/详情列宽（不改行为）**
- `settingsLib` 增加 `@colW`（内容列宽，narrow=600 ✓ full=420 ✓）、`@detW`（0=narrow ✓ 220=full ✓）、`@spW = @colW + @detW` ✓
- 把 6 个面板绘制块里的 `@spW` 换成 `@colW` ✓（23 处 ✓ 机械替换 ✓），并修 14 处超宽绝对 x ✓
- **验收**：narrow 下画面与现在**逐像素一致** ✓（这是"不重写"的硬指标 ✓）

**第 2 步：详情列（仅在 full）**
- 新增 `@stg_draw_detail(x, w, row)` ✓：值卡片/分区/说明/事实表/动作按钮，全部矩形+文本 ✓
- 数据源：每个 tab 增加一个**描述函数** ✓（tab 0 直接读行表 ✓；TAB 1..5 各写一个 `@tabN_desc(idx)` ✓，
  字段严格按第 9 节已核实清单 ✓）
- 鼠标/键盘焦点**不变** ✓（详情列只读 ✓ 唯一例外：text 行的 Edit/Clear 复用 TAB 0 已有动作 ✓）

**第 3 步：Saves 增强（真实数据 + 热键分配）**
- 列表行增加第二行小字：`房间名 · X,Y · 重力±1 · 玩家名 · 热键n` ✓（数据已在 ✓ 只加绘制 ✓）
- 详情列显示完整事实表 ✓
- 热键分配：在 TAB 1 输入块加一个"按数字 1..8 指定 / Del 清除"的状态 ✓（写入 `saveHistHotkey[i]` ✓ 含 1..8 钳制 ✓ 与 `worldCreate.gml:704` 的既有约束一致 ✓）

**第 4 步：Skins 搜索（照搬存档过滤的既有范式）**
- 在 TAB 5 顶部加一个搜索框（文本输入用既有 `wd_input_box` ✓ 与账户行同源 ✓）
- 过滤条件：`string_pos(关键词, skinName)` 或 `skinMaker` / `skinSource` ✓（三者都是已核实字段 ✓）
- 与既有 `@skinVisCount/@skinPage` 分页逻辑串联 ✓（改的是可见集合，不动分页 ✓）

**第 5 步：门禁**
- 布局断言升级为"**视口不变式**"：narrow 下内容不得超出 `@colW` ✓；full 下详情列不得超出 `@detW` ✓
- 新增断言：详情列用到的每个字段都在第 9 节的**已核实清单**里 ✓（防止再次出现 `Deaths`/`Comment` 这类虚构字段 ✓✓）

## 10.5 为什么这样做风险最低

1. **narrow 完全等于现状** ⇒ 小窗口/老引擎玩家零回归 ✓（这是 maintainer 明确的路线 ✓）
2. 新增内容**全部是加分枝**（`@detW > 0` 才画 ✓），不改既有绘制顺序 ✓
3. 唯一被触碰的既有代码是 `@spW → @colW` 的机械替换 ✓，且有"逐像素一致"的验收标准 ✓
4. 详情列只读 ⇒ 不改任何输入语义 ✓（热键分配/搜索是明确批准的例外 ✓）