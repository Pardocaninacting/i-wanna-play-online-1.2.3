# Custom Data Sync (v2) — GML 修改指南

本文档说明如何通过 TCP case 7 自定义数据通道（v2 命名条目格式），将游戏内的 `global.*` 布尔数组同步给所有在线玩家。

> 本文档描述 **v2 格式**（v2flag=1，命名条目）。v1 单 slot 格式已废弃。

---

## 原理

系统预留 **TCP 消息 ID 7** 用于自定义数据同步。数据按**命名条目（entry）**组织：每个条目对应游戏中的一个 `global.<name>[1..count]` 布尔数组，打包为若干 UINT32 位域 slot。仅在值发生变化时发送。服务端按条目名存储并转发给同队玩家，接收方对收到的位执行 **OR 合并**——任意玩家将某位设为 1 后，所有同队玩家都会获得该状态。

新玩家加入或进入房间时，服务端会将该队伍当前已知的完整快照回放给他（`encodeSyncSnapshot` / `replaySyncTo`），因此后加入的玩家也能同步到历史状态。

### 协议格式

```
客户端→服务端:  u8(7) + u8(v2flag=1) + u8(entryCount)
                + [ stringNT(name) + u16(count) + u16(slotCount) + u32 × slotCount ] × entryCount
服务端→客户端:  u8(7) + u8(v2flag=1) + stringNT(ownerID) + u8(entryCount)
                + [ stringNT(name) + u16(count) + u16(slotCount) + u32 × slotCount ] × entryCount
```

- `name`：条目名，即 `global.` 后的数组名（如 `boss`），上限 32 字节
- `count`：该条目同步的数组元素个数（下标 1..count），上限 512
- `slotCount`：`ceil(count / 32)`，每 slot 32 个布尔位，单条目上限 16 slot
- `ownerID`：服务端附加的发送者 playerID；快照回放时为空字符串

### 服务端限制（`server/src/config.ts`）

| 常量 | 值 | 含义 |
|------|----|------|
| `MAX_SYNC_ENTRIES` | 16 | 每队伍不同条目名上限 |
| `MAX_PER_ENTRY_SLOTS` | 16 | 单条目 slot 上限（= 512 位） |
| `MAX_CUSTOM_SLOTS` | 128 | 每队伍所有条目 slot 总数上限 |
| `MAX_SYNC_NAME_LEN` | 32 | 条目名字节数上限 |

超出限制的条目/数据会被服务端拒绝或截断。

---

## 配置方式（推荐）

v2 的条目通过配置文件声明，**无需修改 GML 代码**。在游戏目录下的 `__ONLINE_config.ini` 中添加 `[sync]` 段：

```ini
[sync]
sync_enabled=1
entryCount=2
sync0_name=boss
sync0_count=8
sync1_name=item
sync1_count=8
```

- `sync_enabled`：总开关，0 时接收端忽略所有自定义数据
- `entryCount`：条目数量（0–16）
- `syncN_name` / `syncN_count`：第 N 个条目的数组名与元素个数

加载逻辑见 `worldCreate.gml` / `worldCreateGMS.gml` 的 SYNC 段（支持分层配置：exe 旁默认层 + 工作目录用户层，用户层覆盖同名字段）。

配置后，**存档时**（`saveGame.gml`）客户端自动读取各条目对应的 `global.<name>[1..count]`，打包为位域，仅在相对上次发送有变化时发出。

---

## 发送端行为（`saveGame.gml`，无需修改）

1. 遍历所有已配置条目，按位读取 `global.<name>[idx]`（GM8 用 `execute_string`，GMS 用 `variable_global_get`），打包为 slot 位域
2. 对每个条目计算签名，与 `@syncLastSig` 比较，无变化且非脏标记则跳过
3. 有变化的条目合并为一个 case 7 消息发出

## 接收端行为（`worldEndStep.gml` case 7，无需修改）

1. 校验 `v2flag == 1`，读取 `ownerID` 与条目列表
2. 逐条目在本地配置中按名字匹配；未配置 / `sync_enabled=0` / 游戏中不存在该 global 数组的条目被忽略
3. 对匹配的条目逐位 OR 合并：仅把为 1 的位写入 `global.<name>[idx] = 1`（GM8 用 `execute_string`，GMS 用 `variable_global_get`/`variable_global_set`）

---

## 手动代码方式（备选）

如果需要同步的不是简单的 `global` 布尔数组（例如需要打包自定义位布局），可以在 `saveGame.gml` 的 CUSTOM DATA SYNC 段自行填充 `@scSlotVal` 并设置 `@syncDirty`，接收端对应在 case 7 分支的匹配条目处理中自行解包。注意保持 wire 格式与上述协议一致。

---

## 注意事项

1. **OR-only 语义**：位一旦被设为 1 就无法被远程重置为 0。适用于 Boss 击败、道具拾取等不可逆事件
2. **同队广播**：数据按队伍隔离转发，team=0 的玩家相互广播，不同非零队伍之间不传递
3. **按需发送**：仅在存档时检查并发送有变化的条目，高频变化的数据不适合此系统
4. **`@` 前缀**：GML 源码中所有 `@` 前缀在构建时会被替换为 `__ONLINE_`，避免与游戏原有变量冲突
5. **`#if GMNET` / `#if STUDIO`**：GM8.2（GMNET）使用不同的 buffer 函数名，GMS（STUDIO）使用不同的 global 访问方式，相关代码均需提供对应分支
6. **变量不存在的游戏**：GM8 转换器默认强制开启 `zeroUninitializedVars`，未初始化的数组元素返回 0；GMS 接收端在写入前会检查 `variable_global_exists`
