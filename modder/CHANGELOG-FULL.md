# IWPO 完整功能总结 — v1.1.9 之后的所有新增内容

本文档对 v1.1.9 之后（截至当前 HEAD 未提交的全部改动）引入的所有新功能、系统和改进进行全面梳理。

---

## 一、游戏内可见功能

### 1. 队伍系统 (Team System)

**作用**：玩家可选择 8 个队伍之一（0=无 / 1=红 / 2=蓝 / 3=黄 / 4=紫 / 5=绿 / 6=橙 / 7=青）。队伍颜色将反映在玩家列表、聊天气泡名字、箭头指示器和通知消息中。不同队伍之间的存档不互通（队伍 0 可收到所有人的存档）。

**涉及文件**：
- `worldCreate.gml` — 初始化 `@team=0`、`@teamColors[0..7]`、`@teamMap`（ds_map）
- `worldEndStep.gml` — TCP case 8 接收队伍更新；写入 `@oPlayer.@team`
- `onlinePlayerEndStep.gml` — `@prevTeam` 变更检测，生成 playerSaved 通知
- `onlinePlayerDraw.gml` — 使用 `@teamColors` 渲染玩家名字颜色
- `worldDraw.gml` — 设置面板 Tab 0 队伍选择器 `< / >`；玩家列表中名字带队伍色
- `playerSavedDraw.gml` — `@teamColor` 支持通知消息染色

**网络协议**：
- TCP 消息 ID=8（TEAM）
- 客户端发送：`[8, team_u8]`
- 服务器广播：`[8, playerID_str, team_u8]`（`broadcastFrom`，全游戏广播）
- 玩家加入时：服务器为新玩家补发所有已有玩家的队伍（`team > 0` 的）
- 存档发送使用 `broadcastFromSameTeam()`，仅转发给同队或队伍 0 的玩家

**配置持久化**：`@config.ini` 中 `team=N`，每次在设置面板修改后立即写入。

---

### 2. 存档历史系统 (Save History)

**作用**：记录所有收到的和自己的存档到本地文件，上限 500 条（GMS 目前仍为 50）。支持收藏（上限 100 条）、按收藏过滤、分页浏览（每页 8 条，最新的在前）、清除非收藏项、应用历史存档（将玩家传送到记录的位置）。

**涉及文件**：
- `worldCreate.gml` — 初始化所有变量；从文件加载存档历史（V1/V2 格式自动识别）
- `saveGame.gml` — 自身存档后追加到历史（不受 `@race` 限制），设置 dirty 标志
- `worldEndStep.gml` — case 5 接收他人存档时追加到历史；清除处理器（保留收藏）；延迟写入处理器（含时间密度稀疏算法）；应用存档处理器（`@saveHistApply`）
- `worldDraw.gml` — Tab 1 绘制存档列表 UI（分页、收藏标记、相对时间、按钮）
- `worldGameEnd.gml` — 游戏退出时将未写入的脏数据刷盘

**文件格式**：
- V2（当前）：`[magic_u16=0xFFFF, version_u8=1, count_u16, 每条: fav_u8, grav_u8, x_i32, y_f64, room_i16, time_f64, name_str, roomName_str]`
- V1（旧版）：`[count_u16, 每条: grav_u8, x_i32, y_f64, room_i16, name_str, roomName_str, time_str]`（通过 magic 判断：首字 < 0xFFFF 即为 V1）
- V1→V2 迁移：加载时自动赋予合成时间戳（每条间隔 1 分钟，最新的在最后）

**稀疏算法**（仅在延迟写入时运行）：
| 存档年龄 | 保留间隔 |
|---|---|
| < 1 小时 | 全部保留 |
| 1–24 小时 | ≥ 5 分钟 |
| 1–7 天 | ≥ 2 小时 |
| > 7 天 | ≥ 12 小时 |

收藏条目不受稀疏影响。若稀疏后仍超上限，逐条删除最旧的非收藏条目。

**延迟写入**：首次标记 dirty 时设置 3 秒计时器。计时器每帧递减，到 0 后执行稀疏+写入+清除标志。避免频繁 I/O。

**时间显示**：使用 `date_current_datetime()`（Delphi TDateTime，浮点天数）。显示格式：`now`（<1min）、`Xm`、`Xh`、`Xd`、`M/D`（超 30 天）。无时间的旧数据显示 `?`。

**UI 按钮**：
| 按钮 | 位置 | 功能 |
|---|---|---|
| `<<` | 左上 | 首页 |
| `<` | 偏左 | 上一页 |
| `>` | 偏右 | 下一页 |
| `>>` | 右缘 | 末页 |
| `*`（头部） | 过滤器 | 切换仅显示收藏 |
| Clear | 右上 | 清除所有非收藏 |
| `*`（每行） | 行首 | 切换收藏状态 |
| Apply | 行尾 | 应用该条存档 |

---

### 3. 观战模式 (Spectator Mode)

**作用**：长按 Y 键进入观战，本地玩家被销毁，摄像机跟随一名在线玩家。左右箭头切换目标，上下箭头切换摄像机模式。再次长按 Y 退出并恢复原始位置。

**涉及文件**：
- `worldEndStep.gml` — 核心逻辑（进入/退出/目标跟踪/摄像机/自动退出）
- `worldDraw.gml` — HUD（目标名字、`< >`切换、编号如 "2/5"、进度条、摄像机模式标签）

**关键变量**：
- `@spectating`、`@specProgress`（0→1 进度条）、`@specHoldFrames`
- `@specX/Y/Room/Grav/Obj` — 退出时恢复用
- `@specTargetID/Name/Idx`、`@specCamX/Y`、`@specSnapCamera`
- `@specCamMode`（0=平滑跟随 `lerp 0.35`，1=屏幕对齐到视窗网格）
- `@specGraceFrames`（目标消失后 3 秒宽限期，避免立即退出）

**行为细节**：
- 观战期间持续销毁任何新生成的本地玩家（防止 playerStart 重新创建）
- 清除 `view_object[0]`，由代码手动控制视窗位置
- 支持跨房间跟随（`room_goto` 目标所在房间），跨房间时使用 snap 而非 lerp
- 自动退出条件：宽限期耗尽 + 0 名在线玩家
- 退出时：恢复位置、重力翻转、`view_object` 恢复

---

### 4. 聊天日志面板 (Chat Log)

**作用**：按 U 键打开/关闭。显示持续的聊天历史（上限 30 条），支持鼠标滚轮滚动，带比例滚动条指示器。名字显示为队伍颜色。

**涉及文件**：
- `worldCreate.gml` — `@chatHistMax=30`、`@chatLogOpen`、`@chatLogScroll`
- `worldDraw.gml` — 面板绘制、自动换行、滚动
- `worldEndStep.gml` — case 4 接收消息时写入 `@chatHistName/Msg/Team[]`

**自动换行**：字符级逐字测量宽度，GM8.0 使用 `fw_string_width` 处理 GBK 双字节字符。面板 300×240px，固定在屏幕左下角。

**持久化**：通过 `tempOnlineChat` 文件在房间切换时保留聊天历史。

---

### 5. 聊天气泡系统 (Chat Bubble)

**作用**：消息以动画气泡形式悬浮在说话玩家头顶，6 秒后消失。具有弹簧物理效果（jelly overshoot）、挤压拉伸、浮动和淡出动画。

**涉及文件**：
- `chatboxCreate.gml` — 初始化弹簧参数、清除同一说话者的旧气泡
- `chatboxEndStep.gml` — 弹簧物理 `@springX/Y`、缩放弹簧 `@scale/scaleVel`、浮动 `@bobTime`
- `chatboxDraw.gml` — 圆角矩形+三角尾巴+描边；自动换行；接近本地玩家时淡出

**最大宽度**：200px。超出自动换行。

---

### 6. 评分系统 (Rating System)

**作用**：设置面板 Tab 2 提供 1-5 星评分 + "已通关"复选框。提交到服务器，服务器持久化到 JSON 文件。

**涉及文件**：
- `worldCreate.gml` — 初始化 `@rStars=0`、`@rCleared=0` 等
- `worldDraw.gml` — Tab 2 绘制星星、通关按钮、提交按钮和结果文字
- `worldEndStep.gml` — `@ratingSubmit` 发送 TCP 9；接收结果
- `server/index.ts` — 评分存储、冷却、JSON 文件 I/O

**协议**：TCP ID=9。客户端发送 `[9, stars_u8, cleared_u8]`。服务器回复 `[9, ok_u8]`。

**服务器存储**：`./data/ratings/<gameID>.json`。每游戏上限 500 条。同一玩家覆盖旧评分。冷却 300 秒。

**通关警告**：若 `global.clear` 不存在或为假，勾选"已通关"时显示 5 秒警告。

---

### 7. 键位绑定系统 (Keybind System)

**作用**：设置面板 Tab 3 显示 8 个可rebind 的键位。点击按钮进入编辑模式，按任意键绑定（Esc 取消）。支持重置为默认值。

**键位及默认值**：
| 功能 | 变量 | 默认键 |
|---|---|---|
| 聊天 | `@keyChat` | Space (32) |
| 可见性 | `@keyVis` | V (86) |
| 存档 | `@keySave` | T (84) |
| 玩家列表 | `@keyPlayerList` | L (76) |
| 设置 | `@keySettings` | O (79) |
| 聊天日志 | `@keyChatLog` | U (85) |
| 观战 | `@keySpectate` | Y (89) |
| 指示器 | `@keyArrows` | I (73) |

**持久化**：所有键位保存在 `@config.ini` 中，以 `key_chat`、`key_visibility` 等键名写入。

---

### 8. 屏幕外玩家指示器 (Off-Screen Arrows)

**作用**：按 I 切换。在屏幕边缘绘制带队伍颜色的箭头，指向同房间但在屏幕外的在线玩家，并显示名字标签。

**算法**：从屏幕中心向玩家位置发射射线，裁剪到屏幕矩形（留 16px 边距）。透明度随距离衰减（`1.2 - dist/1250`）。箭头用黑色描边 + 队伍色填充绘制。

---

### 9. 玩家列表叠加层 (Player List)

**作用**：按 L 切换。屏幕右侧显示当前房间在线玩家数量和名单，第一行显示自己带"(YOU)"标记。所有名字使用队伍颜色渲染。

---

### 10. 通知系统 (Notifications)

**作用**：屏幕左上角的浮动堆叠通知。包括：存档通知、设置切换通知、重连通知、队伍变更通知。

**状态码**：`-1` = "X saved!"、`-2` = 自定义文本、`0-2` = 可见模式、`3-4` = 存档开关、`5-6` = 平滑开关

**动画**：`image_alpha -= 0.01`，持续约 3.3 秒（100 帧 @30fps）。

---

## 二、隐式/系统级功能

### 11. 重连系统 (Reconnection)

**作用**：TCP 断开（state 4/5）后自动重连。指数退避（2s, 4s, 6s... 上限 10s），最多尝试 10 次。重连成功后重新发送身份信息（NAME + TEAM）并重建 UDP。

**UDP 恢复**：UDP 失败 3 次后（每次 3 秒宽限），触发完整 TCP 重连流程（同时重建 UDP）。

---

### 12. 跨房间状态持久化 (Tempfile Persistence)

**预处理标志**：`#if TEMPFILE`

**作用**：将连接状态（`tempOnline`）、待加载存档（`tempOnline2`）和聊天历史（`tempOnlineChat`）序列化到磁盘。允许游戏在切换房间（会重建 world 对象）时保持在线连接。

**过期检测**：恢复时检查 `socket_get_state()`，若 socket 已死则进入重连流程而非重新要求输入名字/密码。

---

### 13. 中文/CJK 文本支持 (GM8.0)

**作用**：GM8.0 使用 ANSI 编码（中文 Windows 为 GBK）。通过 NativeAOT x86 DLL 在 DLL 边界进行 ANSI↔UTF-8 转换。若游戏有 NoisyFox Writing 扩展，注册两种字体（Berlin 英文 / YaHei 中文）并动态切换。

**注入的辅助脚本**：
- `__ONLINE_gbk_trunc(str, maxBytes, suffix)` — GBK 安全截断（不切断双字节字符）
- `__ONLINE_has_cjk(str)` — 检测 GBK 高位字节
- `__ONLINE_fw_use_font(str)` — NoisyFox Writing 字体选择器

---

### 14. 非 BMP 字符/Emoji 防护

**客户端**：`strip_non_bmp(@message)` 在 `#if not GM80` 路径下调用，移除无法显示的代理对字符。

**服务器**：`text.replace(/[\uD800-\uDFFF]/g, "")` 在 CHAT 处理器中移除代理对，防止转发导致其他客户端崩溃。

---

### 15. 外部 DLL 系统 (GM8)

**作用**：不再捆绑旧的 `http_dll8` 扩展。改用 `external_define`/`external_call` 加载 NativeAOT 编译的 x86 DLL。自动生成初始化脚本和每个函数的包装脚本。

**两种映射模式**：
- `gm82net` 游戏：包装名匹配 gm82net 别名（如 `buffer_read_u8` → DLL 的 `buffer_read_uint8`）
- 标准 GM8 游戏：包装名直接匹配 DLL 导出名

**自动构建**：若 `lib/` 中没有预编译 DLL，工具从 `native/http_dll_2_3_x86/` 自动 `dotnet publish` 构建。

---

### 16. GMS 转换管线

**作用**：检测 GMS 游戏（解包或定位 `data.win`），识别 x86/x64 架构（PE 头 machine 字段），委托给外部 `converterGMS2.exe` 修改 `data.win`。

**x64 支持**：单独的 NativeAOT x64 项目（`http_dll_2_3_x64`）用于 GMS x64 游戏。

---

### 17. 网络协议完整表

#### TCP 消息（客户端→服务器）

| ID | 名称 | 负载 |
|---|---|---|
| 0 | CREATED | 空 |
| 1 | DESTROYED | 空 |
| 2 | HEARTBEAT | 空 |
| 3 | NAME | `name, gameID, gameName, version, hasPassword_u8, protocolVersion_u8` |
| 4 | CHAT | `text_str` |
| 5 | SAVE | `gravity_u8, x_i32, y_f64, room_i16` |
| 7 | CUSTOM_DATA | `slotCount_u16, [slot_i32...]` |
| 8 | TEAM | `team_u8` |
| 9 | RATING | `stars_u8, cleared_u8` |

#### TCP 消息（服务器→客户端）

| ID | 名称 | 负载 |
|---|---|---|
| 0 | CREATED | `playerID, playerName` |
| 1 | DESTROYED | `playerID` |
| 2 | INCOMPATIBLE | `minVersion_str` |
| 4 | CHAT | `playerID, text` |
| 5 | SAVE | `gravity_u8, senderName, x_i32, y_f64, room_i16` |
| 6 | SELF_ID | `playerID` |
| 7 | CUSTOM_DATA | `playerID, slotCount_u16, [slot_i32...]` |
| 8 | TEAM | `playerID, team_u8` |
| 9 | RATING | `ok_u8` |

#### UDP 消息

| ID | 方向 | 负载 |
|---|---|---|
| 0 | C→S | INIT（空） |
| 1 | 双向 | POSITION: `selfID, gameID, room_u16, currentTime_u64, x_i32, y_i32, sprite_i32, imageSpeed_f32, xscale_f32, yscale_f32, angle_f32, name_str` |

#### TCP 帧格式 (VarInt)
可变长度整数编码。1-4 字节，`bit0=1` → 1 字节，`bit1=1` → 2 字节，`bit2=1` → 3 字节，否则 4 字节。

---

### 18. 服务器架构

**端口**：TCP 8002、UDP 8003、HTTP 8001

**速率限制**：TCP 20 条/秒/玩家，UDP 100 条/秒/端点。超限断开。

**心跳**：客户端每 3 秒发送，服务器 20 秒超时。

**每 IP 上限**：8 个连接。

**UDP 清理**：每 2 分钟清除 5 分钟无活动的端点。

**HTTP API**：
- `GET /` 和 `GET /api/games` — 活跃游戏列表（含玩家数、密码状态）
- `GET /api/ratings` — 所有游戏评分
- `GET /api/ratings/:gameID` — 指定游戏评分

**部署**：Docker Compose + Node 21 Alpine。`./data` 卷挂载用于评分持久化。

---

### 19. 预处理标志一览

| 标志 | 条件 |
|---|---|
| `GM8` | GM8 游戏 |
| `GM80` | GM 8.0（非 8.1） |
| `STUDIO` | GMS1/GMS2 |
| `GMS2` | GMS2 |
| `GMNET` | 有 gm82net 或 gm82buf 扩展 |
| `GM82NET` | 有 gm82net |
| `TEMPFILE` | GM8（始终启用） |
| `PLAYER2` | 存在 player2 对象 |
| `RENEX` | 存在 `save_save` 或 `player_air_jump` 脚本 |
| `GM8YY` | world 对象名为 `objWorld` |
| `GMSND` | 有 gm82snd 扩展 |
| `NIKAPLE` | 存在 `audio_togglesoundmuted` 脚本 |
| `SCR_FLIP_GRAV` | GMS 端翻转重力脚本存在 |
| `GLOBAL_PLAYER_XSCALE` | 使用 `global.player_xscale` |
| `PLAYER_XSCALE` | 使用 `@p.xScale` |
| `PLAYER_XSCALE_LOWER` | 使用 `@p.xscale` |

---

### 20. 工具配置

**iwpo-settings.ini**（工具所在目录的父目录）：支持 `server`、`tcp_port`、`udp_port`、`force_external_dll` 键。

**命令行参数**：`server=IP,TCP,UDP` 覆盖 INI 配置。

---

### 21. Player2/重力交换系统

**预处理标志**：`#if PLAYER2`

**作用**：有 `player2` 对象的游戏（用于反转重力）在读取存档时根据重力值交换 `player` ↔ `player2`。

**各引擎重力编码**：
- STUDIO：`global.grav`（0 或 1），通过 `scrFlipGrav()` 或 `event_user(0)` 翻转
- GM8YY / RENEX：`(global.grav+1)/2`（映射 -1/1 到 0/1）
- 普通 GM8：通过当前存在哪个玩家对象判断重力状态

---

## 三、可以优化的地方

### P1: GMS 存档系统未同步升级
`worldCreateGMS.gml` 仍使用旧的 V1 格式（`saveHistMax=50`），缺少收藏、时间戳、延迟写入、稀疏算法等全部 V2 功能。若需要在 GMS 游戏中提供同等体验，需要同步升级。

### P2: 稀疏+写入逻辑重复
`worldEndStep.gml` 的延迟写入处理器和 `worldGameEnd.gml` 的退出刷盘包含完全相同的 ~70 行稀疏+V2 写入代码。可以考虑提取为脚本以减少维护负担（但 GML 模板注入的限制可能不允许）。

### P3: 服务器 UDP 广播 O(n²)
每个 UDP 位置消息都遍历所有端点。当同一游戏在线人数较多时，可以用 `Map<game, endpoint[]>` 优化为 O(n) 广播。

### P4: 评分文件同步 I/O
`writeFileSync` 在高流量下会阻塞事件循环。可改为异步写入或批量延迟写入。

### P5: CUSTOM_DATA 系统 (case 7) 为死代码
`@customSlot` 硬编码为 0，变更检测逻辑永远不会触发。作为预留扩展点目前没有实际功能，但每帧都在执行比较和分支。

### P6: 聊天消息服务器端无字符数限制
客户端限制 300 字符，但服务器仅检查 TCP 消息总长度 ≤ 990 字节。恶意客户端可以发送超长消息。建议服务器端也加上字符数限制。

### P7: 队伍名字数组在多处重复定义
`@teamNames[0..7]` 在 `worldEndStep.gml`（已移除）、`worldDraw.gml` 和 `onlinePlayerEndStep.gml` 中各定义一次。若将来修改队伍名称需要改多处。可以考虑在 `worldCreate.gml` 中初始化一次。

### P8: 观战模式在小房间中摄像机夹紧异常
`view_xview >= 0` 和 `<= room_width - view_wview` 在房间尺寸小于视窗时可能导致闪烁或负值。可加上 `max(0, ...)` 保护。

### P9: 无加密/认证
玩家身份基于 `remoteAddress + remotePort`。`selfGameID` 含密码但明文传输。非关键问题（局域网级安全足够），但如需公网部署可考虑简单的 HMAC 或 token 机制。

### P10: `@teamMap` 条目从不清理
断开玩家的 ID 留在 map 中直到游戏退出。不是真正的泄漏（单次会话内有界），但长时间运行的 session 中可能积累。
