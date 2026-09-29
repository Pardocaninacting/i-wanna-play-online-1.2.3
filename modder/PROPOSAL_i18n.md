# PROPOSAL：UI 多语言（i18n）设计方案 v3（定稿）

状态：**已实施完成（P0-P5 全部落地）** · 2026-09-29 · 取代 v2
实施记录：P0 解耦+测量（55000d5）→ P1 机制（ae786dc）→ P2 菜单迁移+性能 spike（13fc5cd）→
P3 HUD/播报（e22c3f5）→ 对话框 CJK 修复+译文核对（18c08f6/fd31e4c/b378beb）→ P4 语言切换（77febc3）→ P5 sourceHash 校验。
决议（maintainer 确认）：**首发 zh-CN（默认）+ en（备选）**；默认语言经 `iwpo-settings.ini [iwpo] lang=` 可配，不做系统区域 auto 检测；纳入 sourceHash 过期校验；GM8.0+atlas 性能实测接受（列为 P2 前置门禁）；语言系统按"体系化、可扩展"目标设计（键命名空间 + 注册表 + 校验，见 §3.2/§3.7）。
v2 说明：v1 写于菜单重写之前，字符串统计与"渲染层零改动"的结论均已过期。本版基于对当前代码（菜单重写后）的逐行核查，修正统计、纠正两个关键误判，并补齐 v1 完全遗漏的**测量分路**与**插值层**两个最大工程项。

---

## 1. 目标与非目标

**目标**：菜单/HUD 的全部自有文字可按语言在**运行期**切换；缺翻译自动回落英文；新增语言 = 加一个数据文件，零代码改动。

**非目标**：不翻译游戏自身文字；不做 RTL/词形变化等级别的本地化；不引入字体包机制（首发语言受现有字形覆盖约束，见 §5）。

---

## 2. 现状调研（v2 核查，均带行号证据）

### 2.1 翻译面规模（v1 数字作废）

菜单重写后字符串量约翻倍。当前用户可见文字 **约 350 条**：

| 区域 | 数量 | 说明 |
|---|---|---|
| settingsLib.gml（菜单主体） | ~300 | 表头 15 · 行标签 ~40 · 值/枚举 ~60 · 详情描述 39 · 底部 hint 41 · facts 键值 ~34 · toast ~24 · 对话框 ~10 · 状态/空态/按钮等余量 |
| worldDrawGui.gml（HUD+tab 条） | ~24 | tab 名 6、"Close"、"Chat Log"、"Players Online:"、"(YOU)"、"Spectating..." 等 |
| worldEndStep.gml | ~15 | 弹窗、playerSaved 播报、聊天/便签输入框提示、皮肤下载失败播报 |
| playerSavedDraw.gml | 10（其中 5 条死分支） | 状态播报 |
| accountLib / skinLib / notesLib | ~11 | 存储标签、"Anonymous"、皮肤播报、便签提示 |

**可立即剔除的死文字**（降低首发工作量 ~25 条）：`@stg_toast` 是 no-op stub（settingsLib.gml:2063-2067），菜单内 ~20 条 toast 永不显示；playerSaved 状态 5-10 无写入方；`@stg_plural`（:645）与 `@stg_source_text`（:1524）无调用点。

### 2.2 纠正 v1 的两个误判

**误判一："翻译文本一律经 @stg_text_cjk 输出，渲染层零改动"。**
实际：`@stg_text_cjk` 只有 **6 个调用点**（settingsLib.gml:409/456/613/858/897/945），仅覆盖 entry 行与详情列。所有 UI chrome——表头（:821）、普通行标签（:860）、按钮值（:870/883/915/935）、tab 名与 Close（worldDrawGui.gml:504-509/586）、页脚 hint（:1009/1011）、状态行——全是裸 `draw_text`。GM8 面板字体 `__ONLINE_ftOnlinePlayerName` 字形范围仅 0x20-0x7F，**中文标签在 GM8 上根本画不出来**。结论修正为：渲染*函数*零新增，但**几乎全部绘制调用点要换路**到 `@stg_text_cjk`（其逐串 ASCII 检测已能自动分派，这正是 GML_COMPAT.md:237 约定的用法）。

**误判二："已有 @stg_wrap/@stg_fit_text，长语言有基础保障"。**
实际：这是**本方案最大的隐藏工程量**。面板全部布局测量用裸 `string_width`（settingsLib.gml 内 :303/309/318/418/454/463/594/656/823/831/836/844 等十余处），测的是 Berlin 位图字体；中文串实际由 fw/atlas（GM8）或内嵌雅黑（GMS）绘制，宽度完全不同——GMS 同源没问题，**GM8/GM8.1 上中文标签的测量值全错**（截断点、值卡框宽、表头分隔线、状态行排布全部错位）。必须新增三向 `@stg_text_width`（先例：chatboxDraw.gml:11-25 的逐引擎测量块），并把 `@stg_wrap`、`@stg_fit_text`、详情值卡、表头分隔线全部改走它。

### 2.3 v1 未覆盖的硬约束

1. **模板 .gml 必须纯 ASCII**（getGMLCode.ts:41-44，latin1 读取保字节）——译文**永远不能内联进 .gml**，只能走外部文件。英文兜底原文可留代码（ASCII 安全）。
2. **插值必须先于翻译落地**。现状全是 `+` 拼接，共 8 种模式（句中嵌数字 `"Reconnecting ("+n+"/10)..."`、计数表头 `"Saves("+n+")"`、复数 `" - N options"`、前后缀拼接、键帽格式化、存档行复合标签、相对时间等）。中文语序不同（"还有 10 次"vs"10 remaining"），硬编码语序无法直译 ⇒ 全部改为 `@str_fmt(template, a1, a2)` = string_replace 链 + `%1/%2` 占位（GM8.0 有 string_replace）。译文含 `#` 必须转义（GM 串内换行符）。复数入模板（中文模板不含复数段即可）。
3. **两处逻辑/显示耦合，翻译前必须解耦**：`_val == "ON"` 字面量比较决定绿色高亮（settingsLib.gml:449/921/927）——"ON" 不能直接翻，需改为逻辑值与显示值分离；`@stg_skin_state_name` 的 7 个状态名**兼作 png 文件名**（:1238 注释、:1288 拼路径）——永不翻译，显示层另起译名。
4. **数组必须全下标预初始化**（GMS 读未建下标即崩，GML_COMPAT.md:28-37）；`globalvar` 在 GMS2.3 被拒，字符串表必须写 `global.__ONLINE_L[i]` 全前缀。

---

## 3. 关键设计决策（v2）

### 3.1 运行期切换，而非转换期定死

v1 即定为运行期，v2 维持并补充理由：转换期定语言（照 iwpo.probe→PROBE 抄 defines→flag→#if）机制零新增，但切语言要重新转换、QA 矩阵翻倍、且玩家无法自助。运行期的成本是字符串表+加载器+编码分派三件新机制，全部有在役先例可循（见下）。

### 3.2 字符串表：常量索引 + 英文原文兜底

```gml
// 调用点：key 为常量索引，英文原文作兜底与可读性来源
draw_text_x = @L(STR_PANEL_NAME, "Name");
```

- 存储：`global.__ONLINE_L[0..N]` 一维数组，**worldCreate 双侧模板全下标预初始化**（GMS 安全，先例 `@stgArg` 预建 settingsLib.gml:76-81）。300-500 条远低于 32000 下标上限。
- 查不到/文件缺失 → 返回英文原文 ⇒ 缺翻译永远不会白屏，允许逐块迁移。
- **键注册表（体系化）**：所有键集中在 `langKeys` 登记段，按命名空间分层：`menu.<tab>.<item>`（菜单行/值/表头）、`menu.desc.<item>` / `menu.hint.<item>`（详情与底部提示，与 act id 对齐）、`hud.<element>`（HUD 文字）、`prompt.<dialog>`（对话框）、`notify.<event>`（播报）、`skin.<item>` / `account.<item>`。新增字符串必须先登记命名空间键再使用；登记段同时是 sourceHash 校验的输入（转换期比对英文原文与语言文件里的 hash，过期即警告）。

### 3.3 数据文件与编码：`lang/<code>.ini`，UTF-8 源 + GM8 用 GBK 副本

- 转换器把 `lang/zh-CN.ini`（UTF-8，版本管理友好）部署到 exe 旁 `lang/`；**GM8.0 另生成 GBK 字节副本** `zh-CN.gbk.ini`。
- **编码要点（v1 表述有误，此处修正）**：GM8.0 副本是**固定 GBK**，与转换机器/玩家机器的系统区域无关——cjkAtlas 按字节以压缩 GBK 码查字（cjkAtlas.gml:114-117），FoxWriting 同样吃 GBK 字节，GM8 字符串只是字节容器，不经区域解释。因此 GBK 副本在任何区域的玩家机器上都正确。
- GMS（1.4/2.x）直接读 UTF-8。
- 加载器：手写 file_text 解析，照抄 accountLib.gml:134-207 的现成模式（GM8.0 无 ini_key_* 且 ini_* 走 WD，语言文件在 exe 旁 PD，所以必须手写）。
- 覆盖链：`lang/` 下用户文件 > 转换器部署文件 > 代码内英文兜底。
- Language 选项用 `file_find_first("lang/*.ini")` 动态枚举可用语言，新语言丢文件即出现。

### 3.4 插值层（P0 前置）

`@str_fmt(template, a1, a2, a3)`：string_replace 链替换 `%1/%2/%3`，并对参数做 `#` → `\#` 转义（先例 accountLib.gml:393）。迁移时所有拼接点改模板：

```
"Reconnecting (" + string(n) + "/10)..."   →  @str_fmt(@L(K,"Reconnecting (%1/10)..."), n)
" - " + string(n) + " options"             →  @str_fmt(@L(K," - %1 options"), n)   // 中文模板：" - 共 %1 条"
```

### 3.5 绘制与测量（核心工程项）

- **绘制**：菜单/HUD 所有自有文字调用点改走 `@stg_text_cjk`（逐串 ASCII 检测自动分派；ASCII 保持面板字体不变 ⇒ 英文用户视觉上零差异）。
- **测量**：新增三向 `@stg_text_width(text)`——ASCII→`string_width`；GM80→`fw_string_width`；CJKTEXT→`__ONLINE_cjk_string_width`；GMS→`string_width`（内嵌字体同源）。`@stg_wrap`、`@stg_fit_text`、详情值卡框宽（:454/463）、表头分隔线（:823/831/836）、状态行排布（:844）、存档行尾宽（:1056）、键帽框（:418）全部改走它。
- **几何不动**：控制宽 130px、行高 22、tab 宽 = spW/6 维持现状；中文普遍更短，超长语言由 fit_text 截断兜底（前提是测量已修对）。

### 3.6 选择界面、默认值与持久化（已定稿）

- DISPLAY 段新增 `Language  < 简体中文 >` 滚动行（现有 `@stg_act_dir` 模式，行表每帧重建 ⇒ 切换即时生效），用 `file_find_first("lang/*.ini")` 动态枚举可用语言。
- **默认语言 = zh-CN**；优先级链：玩家运行期选择（`__ONLINE_config.ini [config] lang=`）> 转换期默认（`iwpo-settings.ini [iwpo] lang=`，经 defines 注入为常量 `%arg`）> 内置 zh-CN。
- 玩家选择写入 mod 自己的 `__ONLINE_config.ini`（不放游戏 config）；两个 worldCreate 模板加默认值与读取行；worldEndStep 加 `@langChanged` 写块；两个转换器的出厂 ini 各加一键。
- **不做 auto 区域检测**（决议）——默认 zh-CN 已覆盖目标玩家群，en 用户一行切换即可。

### 3.7 语言文件格式与过期校验（已定稿）

```ini
[meta]
name = 简体中文        ; 语言在选项行里的显示名（可含 CJK）
code = zh-CN
font = cjk            ; cjk | latin —— 声明字形需求，供启动校验

[menu.settings.name]
hash = a1b2c3          ; 英文原文的 sourceHash（转换期生成/校验）
text = 名称
```

- 英文**不落文件**：代码内兜底原文即英文，en 用户语言文件缺失时界面完整可用。
- sourceHash 纳入（决议）：转换器构建时对语言文件逐键校验，hash 与当前英文原文不符即警告"译文已过期"；校验工具放在转换器侧（Node/C# 均可读同一登记段）。

---

## 4. 迁移阶段（每阶段独立可停）

| 阶段 | 内容 | 产出 |
|---|---|---|
| P0 | 前置解耦：ON 高亮逻辑值分离、skin 状态名显示层分离、删死代码（stg_plural/stg_source_text/死 toast 文案）、`@str_fmt` + `#` 转义、`@stg_text_width` 三向测量并接管 wrap/fit/表头/值卡 | 行为不变，门禁全绿 |
| P1 | `langLib.gml`：`global.__ONLINE_L[]` 预建 + GBK/UTF-8 分路加载器 + `@L(idx, fallback)`；转换器部署 lang/ 与 GBK 副本；`en` 不建文件（代码兜底即英文） | 机制可用，界面零变化 |
| P2 | **前置门禁：GM8.0+atlas 性能 spike 通过**（见下）。迁移 settingsLib.gml（~300 条：表头→行标签→值→desc 39→hint 41→facts→对话框） | 菜单全可翻译 |
| P3 | 迁移 worldDrawGui.gml / worldEndStep.gml / playerSaved / notesLib / skinLib / accountLib（~50 条，剔除死分支） | HUD 全可翻译 |
| P4 | Language 行 + 配置持久化 + 动态枚举 + `iwpo-settings.ini lang=` 默认值注入 + "如何新增语言"文档 | 用户可切换 |
| P5 | 发布 `zh-CN` 校对稿 + sourceHash 校验接入转换器 + 门禁断言 | 双语上线，zh-CN 默认 |

**性能门禁（已接受，P2 前做一次 spike）**：GM8.0+atlas 宿主全中文菜单 ≈ 300-450 glyph/帧 = 同数 `draw_sprite_part_ext` + 每次绘制重排 wrap（cjkAtlas 无缓存），仅菜单打开期间。真 FoxWriting 宿主无此问题；GMS 无此问题。若实测卡，优化方向是按行缓存 wrap/测量结果（行表一帧内不变），不动图集。

**门禁**：除字面量断言外，新脚本包须在 converterGM8.ts 的 pack 列表与 Program.cs 双侧登记；模板保持纯 ASCII；过 `check_qol_account.js` 与 `check_gml_functions.mjs`。

---

## 5. 字体约束与首发语言

| 引擎 | 现有字形覆盖 | 可支持 |
|---|---|---|
| GMS | 转换器内嵌 Microsoft YaHei（ASCII+假名+0x4E00-9FFF+全角） | en / zh-CN / ja |
| GM8.0 | FoxWriting 或纯 GML 图集（GB2312+假名+全角；日文特有字形缺，DEVNOTES.md:2173） | en / zh-CN（ja 缺个别字） |
| GM8.1+ | GaseousMarble 字体 | 取决于宿主 |

⇒ **首发 `zh-CN`（默认）+ `en`（备选，不落文件——代码兜底即英文）**；`ja` 预留，繁中/西里尔等需字体包，本方案不做。

---

## 6. 决议记录（2026-09-28 maintainer 确认）

1. **首发范围**：zh-CN + en，**zh-CN 为默认语言**，en 为备选。ja 预留。
2. **默认语言可配**：`iwpo-settings.ini [iwpo] lang=` 控制转换出厂默认；不做 auto 区域检测。
3. **过期校验**：纳入 sourceHash（转换期校验译文是否对应当前英文原文）。语言系统按体系化目标设计：命名空间键注册表 + 动态文件枚举 + 校验工具。
4. **性能 spike**：接受，列为 P2 前置门禁（GM8.0+纯图集宿主实测全中文菜单帧率）。
