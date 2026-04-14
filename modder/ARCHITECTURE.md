# IWPO — 系统架构文档

> I Wanna Play Online (IWPO) 是一个将单机 GameMaker 同人游戏改造为多人联机的工具链。
> 本文档面向开源准备，描述整体架构、各组件职责、构建流程和部署方式。

---

## 目录

1. [架构总览](#1-架构总览)
2. [组件清单](#2-组件清单)
3. [构建流程与产物](#3-构建流程与产物)
4. [依赖关系图](#4-依赖关系图)
5. [数据流与协议](#5-数据流与协议)
6. [GML 模板系统](#6-gml-模板系统)
7. [引擎适配矩阵](#7-引擎适配矩阵)
8. [部署与运维](#8-部署与运维)
9. [目录结构说明](#9-目录结构说明)

---

## 1. 架构总览

```
┌──────────────────────────────────────────────────────────┐
│  用户拖放游戏 EXE / data.win 到 iwpo.exe                │
│  ┌────────────┐    ┌──────────────────┐                  │
│  │ launcher   │───>│ modder (Node.js) │                  │
│  │ (Rust)     │    │ TypeScript       │                  │
│  └────────────┘    └──────┬───────────┘                  │
│                           │                              │
│          ┌────────────────┼────────────────┐             │
│          ▼                ▼                ▼             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐       │
│  │converterGM8  │  │converterGMS  │  │ GML 模板 │       │
│  │(内置 TS)     │  │(外部 C# exe) │  │ + 资源   │       │
│  └──────────────┘  └──────────────┘  └──────────┘       │
│                                                          │
│  输出：已注入联机代码的新 EXE / data.win                 │
│  附带：http_dll_2_3.dll / config.ini / 音效文件          │
└──────────────────────────────────────────────────────────┘

              ┌──────────────────────────┐
              │  Server (Node.js/TS)     │
              │  TCP:8002  UDP:8003      │
              │  HTTP:8001 (API)         │
              └──────────────────────────┘
                        ▲
              ┌─────────┼─────────┐
              │   改造后的游戏     │
              │  http_dll (C# DLL)│
              │  → TCP/UDP 连接   │
              └───────────────────┘

              ┌──────────────────────────┐
              │  Website (Express.js)    │
              │  评分浏览页 + API 代理    │
              └──────────────────────────┘
```

### 工作原理

1. **转换阶段**（离线，用户本地）：modder 解析 GameMaker 游戏的二进制格式，注入联机 GML 脚本、网络 DLL 扩展、音效资源、配置文件，输出可直接运行的联机版游戏
2. **运行阶段**（在线）：改造后的游戏通过注入的 DLL 与中心服务器建立 TCP/UDP 连接，实现玩家位置同步、聊天、存档共享、评分等功能
3. **展示阶段**（Web）：网站提供评分浏览、游戏列表等公开信息

---

## 2. 组件清单

### 2.1 modder（主工具）

| 属性 | 值 |
|------|-----|
| 位置 | `modder/` |
| 语言 | TypeScript (Node.js) |
| 版本 | 1.1.9 (package.json) |
| 入口 | `index.ts` |
| 构建 | `npm run build` → `tsc -p . && node build.js` |
| 产物 | `build/iwpo {VERSION}.zip` |

核心模块：

| 文件 | 职责 |
|------|------|
| `index.ts` | 入口；检测游戏类型（GM8/GMS），分发到对应转换器 |
| `converterGM8.ts` | GM8/8.1/8.2 EXE 二进制转换（解密→修改→重加密） |
| `converterGMS.ts` | GMS1/2 data.win 转换（调用外部 converterGMS2.exe） |
| `getGMLCode.ts` | GML 模板预处理器（`@var`→`__ONLINE_`、`%arg`替换、`#if`编译） |
| `settings.ts` | GM8 Settings 块读写（分辨率、vSync 位域等） |
| `gamedata.ts` | GM8 加密/解密（GameData 层） |
| `gamedata/gm80.ts` | GM8.0 加密层（MD5-based swap table） |
| `gamedata/gm81.ts` | GM8.1 加密层 |
| `gamedata/antidec.ts` | antidec2 保护解密/重加密 |
| `icon.ts` | PE 图标资源提取 |
| `upx.ts` | UPX 解压算法实现 |
| `asset/*.ts` | 各资源类型（Sprite/Object/Script/Room/Extension 等）的序列化/反序列化 |
| `build.ts` | 发布构建编排（ncc 打包 + 资源复制 + 7z 压缩） |

### 2.2 converter-gms（GMS 转换引擎）

| 属性 | 值 |
|------|-----|
| 位置 | `converter-gms/` |
| 语言 | C# 11 (.NET 10) |
| 入口 | `Program.cs` |
| 构建 | `dotnet publish -c Release -o publish` |
| 产物 | `publish/converterGMS2.exe`（自包含、裁剪） |
| 分发位置 | 复制到 `modder/lib/converterGMS2/` |

功能：解析 GMS data.win（通过 UndertaleModLib），注入联机对象/脚本/扩展/CJK 字体，输出修改后的 data.win。

### 2.3 NativeAOT HTTP DLLs（网络库）

游戏运行时调用的网络 DLL，提供 TCP/UDP socket、二进制 buffer、字符串编码转换。

| 变体 | 框架 | 目标 | RID | 产物 | 分发位置 |
|------|------|------|-----|------|----------|
| x86 | .NET 10 | GM8 (32-bit) | `win-x86` | `http_dll_2_3.dll` | `modder/lib/http_dll_2_3.dll` |
| x64 | .NET 8 | GMS2 (64-bit) | `win-x64` | `http_dll_2_3_x64.dll` | `modder/lib/http_dll_2_3_x64.dll` |

两个项目共享同一份源码 `Exports.cs`（x86 通过 `<Compile Include>` 链接 x64 项目的文件）。

导出函数：`buffer_*`、`socket_*`、`udpsocket_*`、`set_utf8_mode`、`strip_non_bmp` 等 40+ 个 C ABI 函数。

### 2.4 server（游戏服务器）

| 属性 | 值 |
|------|-----|
| 位置 | `server/` |
| 语言 | TypeScript (Node.js) |
| 版本 | 1.1.0 |
| 构建 | `npm run build` → `tsc` |
| 启动 | `npm start` → `node dist/index.js` |
| 部署 | Docker 或独立 Node.js 进程 |

端口：TCP 8002（游戏协议）、UDP 8003（位置同步）、HTTP 8001（评分 API）

核心模块：`config.ts`（配置）、`protocol.ts`（协议编解码）、`index.ts`（主逻辑）

### 2.5 launcher（启动器）

| 属性 | 值 |
|------|-----|
| 位置 | `launcher/` |
| 语言 | Rust (2018 edition) |
| 构建 | `cargo build --release` |
| 产物 | `launcher.exe`（发布时重命名为 `iwpo.exe`） |

极简包装器：启动 `data/node-portable.exe index.js`，传递命令行参数。

### 2.6 website（项目网站）

| 属性 | 值 |
|------|-----|
| 位置 | `website/` |
| 语言 | TypeScript (Express.js) |
| 构建 | `npm run build` |
| 部署 | Docker 容器（端口 8007） |

提供评分浏览 SPA（`/ratings`）和服务端 API 代理路由。

### 2.7 辅助项目（不随工具分发）

| 项目 | 位置 | 用途 |
|------|------|------|
| OpenGMK | `OpenGMK/` | Rust GM8 引擎重实现，作为二进制格式参考 |
| UndertaleModTool | `UndertaleModTool/` | C# GMS 修改工具库，converter-gms 的依赖 |
| modder-gms | `modder-gms/` | 历史 UndertaleModTool 副本，已被 converter-gms 取代 |

---

## 3. 构建流程与产物

### 端到端构建步骤

```
1. (如有修改) 构建 NativeAOT x86 DLL
   cd modder/native/http_dll_2_3_x86
   dotnet publish -c Release
   → 复制 publish/http_dll_2_3.dll → modder/lib/http_dll_2_3.dll

2. (如有修改) 构建 NativeAOT x64 DLL
   cd modder/native/http_dll_2_3_x64
   dotnet publish -c Release
   → 复制 publish/http_dll_2_3_x64.dll → modder/lib/http_dll_2_3_x64.dll

3. (如有修改) 构建 converter-gms
   cd converter-gms
   dotnet publish -c Release -o publish
   → 复制 publish/* → modder/lib/converterGMS2/

4. 构建 modder 发布包
   cd modder
   npm run build
   → build/iwpo {VERSION}.zip

5. (如有修改) 构建服务端
   cd server
   npm run build
   → dist/index.js
```

> ⚠️ 步骤 1-3 的产物需手动复制到 `modder/lib/`，无自动化编排。

### 产物清单

| 产物 | 类型 | 大小 | 用途 |
|------|------|------|------|
| `iwpo {VERSION}.zip` | 压缩包 | ~25 MB | 发布给最终用户 |
| `dist/index.js` | JS 模块 | ~30 KB | 服务端运行文件 |

发布包内部结构：
```
iwpo.exe                     ← launcher (Rust)
data/
  node-portable.exe          ← Node.js 运行时
  index.js                   ← modder 打包后的单文件
  gml/                       ← GML 模板
  lib/
    http_dll_2_3.dll         ← x86 NativeAOT DLL
    http_dll_2_3_x64.dll     ← x64 NativeAOT DLL
    converterGMS2/            ← .NET 自包含转换器
    font_online8              ← GM8 字体资源 blob
    ChineseChatSupport8       ← GM8 中文聊天扩展 blob
    sound_chatbox8            ← 聊天提示音 blob
    sound_saved8              ← 存档提示音 blob
    __ONLINE_sndChatbox.wav   ← 聊天音效
    __ONLINE_sndSaved.wav     ← 存档音效
    ...
```

---

## 4. 依赖关系图

```
modder (TypeScript, 发布包核心)
├── lib/http_dll_2_3.dll ← native/http_dll_2_3_x86 (C# NativeAOT, .NET 10)
│                             └── Exports.cs ← native/http_dll_2_3_x64/Exports.cs (link)
├── lib/http_dll_2_3_x64.dll ← native/http_dll_2_3_x64 (C# NativeAOT, .NET 8)
│                                  └── Exports.cs (master copy)
├── lib/converterGMS2/ ← converter-gms (C# .NET 10)
│                           ├── UndertaleModLib (project ref)
│                           └── Underanalyzer (project ref)
├── gml/*.gml (GML 模板)
├── lib/*.8 (GM8 资源 blob)
└── launcher.exe ← launcher (Rust)

server (TypeScript, 独立部署)
├── smart-buffer
├── tslog
└── dotenv

website (TypeScript, 独立部署)
├── express
├── tslog
└── dotenv
```

---

## 5. 数据流与协议

### TCP 消息类型

| Case | 名称 | 方向 | 用途 |
|------|------|------|------|
| 0 | QUIT | C→S / S→C | 玩家退出 |
| 1 | CONNECTED | S→C | 连接确认 |
| 2 | CREATED | S→C | 新玩家加入通知 |
| 3 | NAME | C→S | 发送玩家名/游戏ID/版本/密码 |
| 4 | CHAT | C→S / S→C | 聊天消息 |
| 5 | SAVE | C→S / S→C | 存档位置广播 |
| 6 | GAMEDATA | C→S / S→C | 存档数据同步 |
| 7 | CUSTOM_DATA | C→S / S→C | Boss/Item 状态位域同步 |
| 8 | TEAM | C→S / S→C | 队伍设置 |
| 9 | RATING | C→S / S→C | 评分提交/确认 |

### UDP 消息格式

```
发送（每 3 帧）:
  string playerID
  uintv  room
  float  x, y
  u8     spriteIndex (packed)
  float  imageXScale, imageYScale
  u8     imageAngle (packed)
  u8     team

接收:
  string playerID
  [同上字段]
```

### 编码规则

- 整数：小端序
- 变长整数：`uintv`（类 VarInt，每字节低 7 位有效，高位续传标志）
- 字符串：null-terminated UTF-8
- GM8 ANSI 兼容：DLL 自动 ANSI↔UTF-8 转换（`UseAnsi` 标志）
- GMS x86 UTF-8 模式：通过 `set_utf8_mode(1)` 启用

---

## 6. GML 模板系统

位于 `modder/gml/*.gml`，通过 `getGMLCode.ts` 预处理后注入游戏。

### 预处理指令

| 语法 | 作用 | 示例 |
|------|------|------|
| `@varName` | 替换为 `__ONLINE_varName` | `@buffer` → `__ONLINE_buffer` |
| `%argN` | 替换为第 N 个参数值 | `%arg0` → `"objWorld"` |
| `#if FLAG` | 条件编译开始 | `#if GM80` |
| `#if not FLAG` | 反向条件编译 | `#if not STUDIO` |
| `#endif` | 条件块结束 | |

### 编译标志

| 标志 | 含义 |
|------|------|
| `GM8` | GM8.x 引擎 |
| `GM80` | GM8.0（支持中文聊天、NoisyFox 字体） |
| `STUDIO` | GameMaker Studio |
| `GMS2` | GameMaker Studio 2 |
| `GMNET` | 使用 GM8.2 风格函数名 |
| `GM82NET` | 需要 http_dll bypass 脚本 |
| `RENEX` | Verve/RENEX 引擎适配 |
| `GM8YY` | YoYo 风格命名 (objWorld) |
| `NIKAPLE` | Nikaple 引擎适配 |
| `TEMPFILE` | 使用临时文件持久化 |

### 模板文件

| 文件 | 注入目标 | 事件 |
|------|----------|------|
| `worldCreate.gml` | world 对象 | Create |
| `worldCreateGMS.gml` | world 对象 (GMS) | Create |
| `worldEndStep.gml` | world 对象 | End Step |
| `worldDraw.gml` | UI 对象 | Draw |
| `worldGameEnd.gml` | world 对象 | Game End |
| `chatboxCreate.gml` | chatbox 对象 | Create |
| `chatboxDraw.gml` | chatbox 对象 | Draw |
| `chatboxEndStep.gml` | chatbox 对象 | End Step |
| `onlinePlayerCreate.gml` | onlinePlayer 对象 | Create |
| `onlinePlayerDraw.gml` | onlinePlayer 对象 | Draw |
| `onlinePlayerEndStep.gml` | onlinePlayer 对象 | End Step |
| `playerSavedDraw.gml` | playerSaved 对象 | Draw |
| `playerSavedEndStep.gml` | playerSaved 对象 | End Step |
| `saveGame.gml` | saveGame 脚本 | (hook) |
| `saveGame2.gml` | world 对象 | (内部) |
| `loadGame.gml` | loadGame 脚本 | (hook) |

---

## 7. 引擎适配矩阵

| 引擎 | 检测方式 | 转换器 | DLL | 特殊处理 |
|------|----------|--------|-----|----------|
| GM8.0 | 版本号 | converterGM8 (TS) | x86 http_dll_2_3.dll | NoisyFox 中文字体、ANSI 编码 |
| GM8.1 | 版本号 | converterGM8 (TS) | x86 http_dll_2_3.dll | vSync 位域 |
| GM8.2 Buffer | 扩展名前缀 | converterGM8 (TS) | 内置于扩展 | GMNET 标志，不注入 DLL |
| GM8.2 Network | 扩展名前缀 | converterGM8 (TS) | x86 external_define | GMNET+GM82NET，bypass 脚本 |
| GMS 1.x (x86) | PE Machine Type | converter-gms (C#) | x86 http_dll_2_3.dll | `set_utf8_mode(1)`，CJK 字体嵌入 |
| GMS 2.x (x64) | PE Machine Type | converter-gms (C#) | x64 http_dll_2_3_x64.dll | `hbuffer_` 前缀映射 |

---

## 8. 部署与运维

### 服务器

| 服务 | 端口 | 部署方式 |
|------|------|----------|
| 游戏服务器 | TCP 8002, UDP 8003, HTTP 8001 | Docker / 直接 Node.js |
| 网站 | 8007 | Docker |
| Nginx | 80 | 系统服务，代理 `/ratings` → 8007 |

数据持久化：`./data/ratings/*.json`（Docker volume 挂载）

### 发布流程

1. 构建所有变更组件（DLL → converter-gms → modder）
2. `npm run build` 生成 `iwpo {VERSION}.zip`
3. 上传发布包到分发渠道
4. 如有服务端变更：`scp dist/*.js` → 重启进程

---

## 9. 目录结构说明

```
d:\lab\
├── modder/                    # 主工具（TypeScript）
│   ├── asset/                 # GM8 资源序列化
│   ├── gamedata/              # GM8 加密层
│   ├── gml/                   # GML 模板
│   ├── lib/                   # 预构建依赖（DLL、converter、资源 blob）
│   │   └── converterGMS2/     # .NET 自包含转换器
│   ├── native/                # NativeAOT DLL 源码
│   │   ├── http_dll_2_3_x64/  # x64 变体（.NET 8，master Exports.cs）
│   │   └── http_dll_2_3_x86/  # x86 变体（.NET 10，链接 Exports.cs）
│   └── build/                 # 构建输出
├── converter-gms/             # GMS 转换器（C# .NET 10）
├── server/                    # 游戏服务器（TypeScript）
├── website/                   # 项目网站（Express.js）
├── launcher/                  # 启动器（Rust）
├── OpenGMK/                   # GM8 引擎参考实现（Rust）
├── UndertaleModTool/          # GMS 修改工具库（C#）
└── modder-gms/                # 历史副本（已弃用）
```
