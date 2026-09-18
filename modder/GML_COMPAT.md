# GML 引擎兼容性参考（iwpo modder 专用）

> 本文是**本项目**的 GML 兼容性知识库，来源：真实引擎实机验证 + 踩坑记录 + `gamemaker-mcp`
> 的 snippet 校验器实测结论。目标引擎面很宽：**GM8.0 / GM8.1 / GM8.2 / GMS1.4 / GMS2.3(2024)**，
> 而 `modder/gml/*.gml` 是**共享模板**——同一份源码要塞进上述所有运行时，所以只能使用**交集**。

## 0. 一句话结论

**我们的共享模板不是现代 GML**。`gamemaker-mcp` / `gms-mcp` 那类工具的规则（Feather、命名参数、struct、
`??`、静态方法…）面向 **GMS 2024 的 .yyp 工程**，对我们是**反向知识**：照做会直接让 GM8 编译失败。
我们真实的约束是"**GM8.0 语法下限 + GMS2.3 编译路径上限**"。

## 1. 硬性禁止（一票否决，已全部进 `check_qol_account.js` 断言）

| 构造 | 后果 | 处置 |
|---|---|---|
| `#else` | GM8 渲染管线（`getGMLCode.parseGML`）只认 `#if` / `#if not` / `#endif`，`#else` 不被剥离 ⇒ 游戏内 `COMPILATION ERROR` | 用两个独立 `#if` 块 |
| `globalvar X;` | **GMS2.3 编译路径直接拒绝**该语句（每个 section 报 `Failed to find a valid statement`）。既有包（skinLib/notesLib）从不使用它 | 状态一律走 `global.__ONLINE_x`（GM8 与 GMS 都支持） |
| `point_in_rectangle` | **GM8.0 无此函数**（8.1+ 才有）⇒ 运行期 `Unknown function or script` | 自写 `@stg_in_rect` 之类的辅助 |
| `string_trim` / `string_lower` / `string_upper` / `string_ends_with` | GM8.0 无 | 自写 trim/lower |
| `ini_key_first` / `ini_key_next` | GM8.0 无 | 手写 `file_text_*` 解析 |
| `array_create` / `array_length_1d` 等数组函数族 | GM8.0 无 | 逐步赋值 / 自维护长度 |
| 未声明 `_x` 局部变量 | 漏 `@` 前缀会静默变成**另一个变量**（`_cjkLineN` / `_accGlobalDir` 两次事故） | `var` 显式声明 + 门禁扫描 |
| 读未初始化变量 | **GM8 静默返回 0，GMS 直接崩**（`Variable objWorld.__ONLINE_my not set`） | 每帧在使用前赋值（鼠标映射放绘制前奏） |
| 调用方自有变量进 `globalvar` | 几何/身份变量被写进全局，绘制端读实例变量 ⇒ 面板整块消失（`@spW=0`） | 只在脚本内部声明"自己的"全局 |

## 2. 引擎差异速查

| 主题 | GM8.0 | GM8.1/8.2 | GMS1.4 | GMS2.3/2024 |
|---|---|---|---|---|
| 字符串编码 | ANSI(GBK) | **UTF-8** | UTF-8 | UTF-8 |
| 账号文件键 | `name_gbk` | `name_utf8` | `name_utf8` | `name_utf8` |
| 目录变量尾斜杠 | 不定 ⇒ 一律用 `@account_dir()` 归一化 | 同 | 同 | 同 |
| `file_text_*` | ✓ | ✓ | ✓ | ✓ |
| `ini_*` 基准 | `working_directory` | 同 | 同 | 同（**与 `program_directory` 不一致，故统一用绝对路径**） |
| `globalvar` | ✓ | ✓ | ✓ | ✗ |
| `buffer_*` | ✗（用 DLL 包装 `__ONLINE_buffer_*`） | ✗ | ✓ | ✓（`RenderTemplate` 映射 `__ONLINE_buffer_` → `hbuffer_`） |
| 命名参数 / `function` 关键字 | ✗ | ✗ | ✗ | ✓ |
| 沙箱 | 无 | 无 | 有（绝对路径可能受限） | 有 |
| 重启语义 | `game_restart` **清空所有 global** | 同 | 同 | 同 |

## 3. 工具能帮我们什么 / 帮不了什么

| 工具 | 能力 | 对我们的价值 |
|---|---|---|
| `gamemaker-mcp`（Node，225 工具） | 面向 `.yyp` 工程：资产/房间/事件检查、GML 静态分析、校验、Igor 编译 | 只对**工程源码**有效（本机工程：`_workspace/I-Wanna-Start-A-Party`）。对 `modder/gml/*.gml` 模板**不适用**（它们不是工程资产，且带 `@` 占位符） |
| `gms-mcp`（Python，本机 venv） | 资产操作、Igor 构建、可选运行时 bridge | 同上；本机已发现 Igor 运行时 `2024.14.4.268`，但缺 GameMaker license 登录 |
| `gm_gml_validate_snippet`（实测） | 分隔符平衡 + **弃用特性告警** | ✅ 提示 `globalvar`、`argument0`；❌ **看不见** `point_in_rectangle`/`string_trim`（版本可用性）、`#else`（我们的管线）⇒ 仍需本文第 1 节门禁 |
| UndertaleModTool（`D:\lab\UndertaleModTool`） | **反编译/改写 data.win**（GMS 编译产物） | ★ 我们真正的主力：GMS 侧改包靠它（`converter-gms` 即基于 UndertaleModLib） |
| modder 自身的 GM8 解析/写回（`gamedata/gm80.ts` 等） | GM8 exe 解密/结构 | ★ GM8 侧主力 |

## 4. 新增函数前的自检清单

1. 该函数在 **GM8.0** 存在吗？（查 GM8 官方手册的 Functions 列表；不确定就自写等价实现）
2. 该语句在 **GMS2.3 编译路径**合法吗？（`globalvar` ✗ / `argument0` ✓ / 无类型标注 ✓）
3. 是否依赖未初始化变量？（GMS 会崩）
4. 是否写在 `#if` 分支里且用了 `#else`？（✗）
5. 跑 `node _workspace/tmp/cloud/check_qol_account.js`（173+ 断言，含上述黑名单）

## 5. 相关文档

- `DEVNOTES.md` —— 每个坑的现场记录与证据链
- `converterGM8.ts` / `converterGMS.ts` —— 渲染管线（`@` 替换、`#if` 剥离、GMS 前缀映射）
- `_workspace/tools/README.md` —— 本机已装的 GameMaker MCP 工具与用法

## 6. GM8/GMS1 资料库与函数可用性检查（2026-09-15）

### 6.1 关键机制：GM8 的注入代码是**运行期编译**的

`modder/asset/codeaction.ts` 的 `CodeAction.pieceOfCode(GML)` 把模板 GML 作为 GM8 的
**"execute a piece of code" action（libID=1, id=603, paramStrings[0]=源码）** 注入 ⇒ **由 GM8 runner 自带的
GML 编译器在运行期编译**。

后果（重要）：
- **未知函数/脚本不会在转换期报错**，而是在**运行到那一行时**崩：「Unknown function or script」——这正是
  `point_in_rectangle` 在 GM8.0 上"转换成功、进游戏才炸"的原因。
- 也解释了为什么 modder 里**没有任何内置函数名表**：它不需要（名字由 runner 解析）。
- ⇒ **函数可用性只能靠静态清单 + 实机验证**，这也是下面这个检查器存在的原因。

### 6.2 数据集与检查器

| 资产 | 说明 |
|---|---|
| `_workspace/reference/opengmk/*` | OpenGMK 源码快照（**我们的 GM8 上游**：`gamedata/gm80.rs`/`gm81.rs`/`antidec.rs` 与我们 modder 同名同源） |
| `_workspace/reference/derived/gm81_functions.json` | **1268 个 GM8 Classic 内置函数名**（取自 OpenGMK 的 `FUNCTIONS` 有序表；顺序即字节码 function id 顺序） |
| `_workspace/tmp/cloud/extract_gm8_table.js` | 重新生成上面这份数据集的脚本 |
| `_workspace/tools/check_gml_functions.mjs` | **函数可用性检查器**：扫描 31 个模板的全部调用点，比对 GM8.1 表并感知 `#if` 门控 |

当前基线：**2605 处调用点 / 0 处不可用 / 202 处被正确门控**（`GMSND`=GM8.2 音效、`STUDIO`=GMS、`GM8GUI`=GM8.2 GUI 等）。

实测校正（对表的信任度）：
- `draw_self` **在表内** ⇒ 与"8.1 新增"的史料一致 ⇒ **该表是 GM8.1 级** ✓
- `buffer_create` / `array_create` / `string_trim` / `string_ends_with` / `ini_key_first` / `md5_string_utf8` /
  `http_request` / `point_in_rectangle` **全部不在表内** ⇒ 都是 GMS 时代才有 ✓（与我们两次实机踩坑一致 ✓）
- 真阳性示例：`worldCreate.gml:986` 的 `sound_add_included()`（GM8.2 音效 API）——检查器标红，人工核对确认它**已被
  `#if GMSND` 正确门控**（`hasGm82snd` 时才置位）⇒ 已把 `GMSND` 纳入门控旗标。

### 6.3 仍缺的一块：GM8.0 与 8.1 的差集

OpenGMK 的表是 **GM8.1 级**（8.0 是它的子集），因此它**能**拦住"GMS 时代函数"，**不能**拦住"8.1 新增函数用在 8.0"。
已知差异示例：`draw_self`（8.1 新增）。

补齐途径（按可行性排序）：
1. **GM8.0 官方手册**（`documentation.help/Game-Maker-8/` 被 Cloudflare 拦 403 ✗；GM8 安装目录里的 `.chm` 最权威）
   —— 如果你机器上有 GM8/8.1 安装，把 `GameMaker8.chm`（或 Help 目录）给我，我可以直接解出函数索引并入表。
2. **GM8.1 安装包/手册的 "What's New"** 章节（archive.org 上有 GM8.1 安装包）。
3. **实机差分探测**：GM8.0 与 GM8.1 各转一个探针游戏，对候选函数逐个调用并捕获 "Unknown function or script"
   （每次运行只能测一个 ⇒ 1268 个函数不可行，仅适合验证少量可疑项）。
4. 社区清单（GMCLAN / gmc 存档）——可信度低于 1、2。

### 6.4 其他 GM8/GMS1 资料线索

- **OpenGMK**（Rust，GPL-2.0）★：GM8/GM8.1 的**完整 runner 重写** + `gm8exe`（exe 结构）+ `gm8decompiler`
  （字节码→GML）+ `gml-parser`。查"某条 GM8 语义到底是什么"（`draw_*` 的混合规则、`instance_*` 顺序、
  `file_*` 基准目录、`game_restart` 行为）时，这里是**行为级**权威。
- **gm82core / GM82Project**：GM8.2 是社区引擎分支（新增 GUI/音效/网络等），`#if GM8GUI`/`GMSND`/`GM82NET` 都是它。
- **GMS1.4 手册**（docs2.yoyogames.com）与 **GMS2.3 手册**（manual.gamemaker.io）可在线取；
  本机已装 `gamemaker-mcp`（面向 .yyp 工程）与 `gms-mcp`，对**工程源码**有用，对已编译游戏无用。
### 6.5 GM8.0 基线补齐（2026-09-15，maintainer 提供 `D:\gm8.0\Game_Maker.chm`）

**收获远大于一个手册**：`D:\gm8.0\` 是完整的 **GM8.0 IDE 安装**，其中 **`fnames`**（41,560 B，1826 行）就是
**IDE 自己的符号表**——语法高亮/自动补全/编译器解析用的名字清单，格式为 `name(args)` / `变量名` / `name#`(常量) /
`name*`，并按 `// Chapter 401|402|403…` 章节分组 ⇒ 这是"**GM8.0 编译器认识什么**"的权威数据 ✓✓
（CHM 已解包到 `_workspace/reference/gm80_manual/`，含 `Game_Maker.hhk` 索引，392 个文件）。

**三方对照结果**：

| 集合 | 数量 | 来源 |
|---|---|---|
| GM8.0 符号（fnames 全部条目） | 1475 | `D:\gm8.0\fnames` |
| GM8.0 **GML 函数**（过滤 D&D `action_*` 与纯变量后） | **1052** | 派生出 `gm80_functions.json` |
| GM8 Classic（GM8.1 级）运行期函数表 | 1268 | OpenGMK `mappings.rs` |
| **GM8.1 新增（GM8.0 没有）** | **71** | `gm81_only.json` |

**71 个 8.1 新增函数**（完整清单在 `_workspace/reference/derived/gm81_only.json`）：
`draw_self`、`clamp`、`lerp`、`make_color`、`max3`/`min3`、`dot_product`/`_3d`、`point_distance_3d`、
`file_open_read/write/append`、`file_read_*`/`file_write_*`/`file_readln`/`file_writeln`/`file_close`/`file_eof`/`file_eoln`、
`external_define0..8`/`external_call0..8`、`object_name`/`sprite_name`/`room_name`/`sound_name`/`font_name`/
`path_name`/`timeline_name`/`background_name`/`script_name`、`show_text`/`show_image`/`show_video`、
`surface_create_ext`、`texture_exists`、`sprite_set_cache_size[_ext]`、`move_bounce`、`move_contact`、
`tile_find`/`tile_delete_at`、`instance_sprite`、`string_byte_at`/`string_byte_length`、`ansi_char`、
`message_text_charset`、`get_function_address`、`part_type_alpha`/`part_type_color` 等。

**同时修正了两条既有认知**（此前靠猜的）：
- `string_lower` / `string_upper` **GM8.0 就有**（fnames 在册）⇒ 早先"8.1+ 黑名单"里列它们是**过严**，已从门禁移除 ✓
- `point_in_rectangle` / `string_trim` / `buffer_*` / `array_create` / `ini_key_*` / `md5_string_utf8` **GM8.0 与 GM8.1 都没有**
  ⇒ 是 **GMS 时代**函数 ✓（与两次实机踩坑一致 ✓）

**检查器升级**（`_workspace/tools/check_gml_functions.mjs`）现在是三层判定：
1. `MISSING`：不在 GM8.1 表内且未被 `#if` 门控 ⇒ **GMS-only / 拼写错误**（硬失败）
2. `GM81ONLY`：在 71 清单内且未门控 ⇒ **GM8.0 目标会崩**（提示用 `#if not GM80` 门控；`GM80` 仅 8.0 目标置位，故 `#if not GM80` 被识别为门控 ✓）
3. `gated`：位于现代分支（`STUDIO`/`GMSND`/`GM8GUI`/`GM82*`/`GMS2`/`NIKAPLE`）⇒ 合法

**全量审计结论**：31 个模板、**2605 处调用点 → 0 处 MISSING、0 处 GM81ONLY、202 处正确门控** ✓
即当前模板集**严格满足 GM8.0 下限**，同时兼容 8.1/8.2/GMS ✓。
## 7. 中文（CJK）绘制机制（2026-09-18 源码级梳理）

结论先行：**三种引擎的中文绘制是三条完全不同的路径**，由预处理器变量 `GM80` / `CJKTEXT` 选择。
界面代码必须**三分支门控**，任何一条路径都不能无条件调用——直接调 `__ONLINE_cjk_draw_text` 会在
未开 CJK 的 GMS 构建里编译期报 `Failed to find function`，在 GM8 里运行期报同样的错。

### 7.1 后端选择（唯一决定处）

`modder/converterGM8.ts:916-925`：

```ts
const cjkBackend = version === GameMaker80 ? 'fw' : (loadedGM ? 'gm' : 'none');
const useUtf8    = version !== GameMaker80;
```

| 引擎 | 后端 | 绘制调用 | 字符串编码 | 资源来源 |
|---|---|---|---|---|
| **GM8.0** | `fw` | `fw_draw_text_ext` 等 `fw_*` | **ANSI / GBK** | **两条路，同一套 `fw_*` API**：原生 FoxWriting 扩展（`ChineseChatSupport8`）；**当 FoxWriting 不可用时**（插件本身不稳定，UPX+Antidec 宿主是其中一种成因——其 GMAPI 层版本锁死、无法初始化）改由 `modder/gml/cjkAtlas.gml` 提供纯 GML 位图图集实现，即与 GMS 类似的"读 `__ONLINE_font.png` 字体集"方案（资源为 `__ONLINE_font.png` + `__ONLINE_font.gbk`） |
| **GM8.1+** | `gm` | `__ONLINE_cjk_draw_text` | **UTF-8**（`set_utf8_mode(1)`）| `converterGM8.ts` 合成的脚本，内部调用 GaseousMarble（`gm_set_font` / `gm_set_color` / `gm_set_halign`）；需要 `gaseous_marble8` 在位，否则退化为 `none` |
| **GMS（Studio 1.4 / GMS2.x）** | 无（`CJKTEXT` 不设置）| `draw_text` / `draw_text_ext` | **UTF-8** | 转换器把 CJK 字体**嵌入 data.win**（`converter-gms/Program.cs` 的 `EmbedCjkFont()`，12px，取自系统 CJK 字体，含 ASCII），并用 `onlineFontIndex` 作为 mod UI 的字体 |

补充事实：
- `CJKTEXT` **只由 GM8 转换器添加**（`converterGM8.ts:1168`）；GMS 侧从不设置，因此 GMS 构建里所有 `#if CJKTEXT` 块都被剥掉。
- `gm` 后端不可用时转换器打印 `CJK backend: none`，中文经 `draw_text` 输出为乱码（已知退化）。
- GM8.0 的纯 GML 图集（`cjkAtlas.gml` 头部）自带资源格式说明：`__ONLINE_font.png` + `__ONLINE_font.gbk`
  （`CGA1` 头 12B + 每条记录 12B；key 为 ASCII 字节值，或 GBK 压缩键 `1000 + (b0-0x81)*191 + (b1-0x40)`，
  以规避 GM8 的数组下标上限）。

### 7.2 代码中的标准三分支写法

现有调用点一律如此（`notesLib.gml:1149-1186` 玩家名、`chatboxDraw.gml:107-122` 聊天气泡）：

```gml
#if GM80
    fw_draw_text_ext(x, y, text, 9999);        // GM8.0：FoxWriting（原生或纯 GML 图集）
#endif
#if CJKTEXT
    __ONLINE_cjk_draw_text(x, y, text, 9999);  // GM8.1+：GaseousMarble 包装
#endif
#if not GM80
#if not CJKTEXT
    draw_text(x, y, text);                     // GMS：字体已内嵌 CJK，直接画
#endif
#endif
```

`fw_*` 与 `__ONLINE_cjk_draw_text` **在 GMS 侧不是"存在但退化"，而是编译期根本不存在的符号**。

### 7.3 宽高测量

| 引擎 | 测量方式 |
|---|---|
| GM8.0 | `fw_string_width` / `fw_string_width_ext`（图集实现按字形 advance 累加）|
| GM8.1+ | GaseousMarble 的字体度量（合成脚本内部使用）|
| GMS | `string_width` / `string_width_ext`（内嵌字体）|

ASCII 文本用 `string_width` 在各引擎都成立；含中文的文本要用各自的度量，布局代码不要跨引擎共用。

### 7.4 界面代码约定

1. 可能出现用户文本的位置（账号名、存档玩家名）统一用 `settingsLib.gml` 的 `@stg_text_cjk(x, y, text, halign)`：
   纯 ASCII 走 `draw_text`（**保证面板字体不变**），非 ASCII 按 7.2 三分支。
2. 不要为了中文把整片界面切到图集 / `fw_*`：那会换掉整个面板的字体（此前已回退过一次）。
3. 新增 `fw_*` / `__ONLINE_cjk_*` 调用必须放进 7.2 的门控；`check_qol_account.js` 会检查 `#else` 未被使用等硬性规则。
4. 文件里的中文编码与绘制无关：账号存储统一用系统 ANSI 代码页（见第 2 节与 accountLib 注释），
   才能让 GM8.0 与 GMS 互相读取。
