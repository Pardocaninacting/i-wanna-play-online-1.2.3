# Custom Data Sync — GML 修改指南

本文档说明如何通过 TCP case 7 自定义数据通道，将游戏内的自定义变量同步给所有在线玩家。

---

## 原理

系统预留了 **TCP 消息 ID 7** 用于自定义变量同步。每帧将目标变量打包为 **UINT32 位域**，仅在值发生变化时发送。服务端原样转发给同队玩家，接收方对收到的值执行 **OR 合并**，即任意玩家将某位设为 1 后，所有同队玩家都会获得该状态。

默认实现中 `@customSlot` 硬编码为 0，不发送任何有意义的数据。你只需要修改打包和解包逻辑即可同步任意 `global.*` 布尔变量。

### 协议格式

```
客户端→服务端:  u8(7) + u16(slotCount) + [i32 × slotCount]
服务端→客户端:  u8(7) + string(playerID) + u16(slotCount) + [i32 × slotCount]
```

- 每个 slot 为一个 32 位整数，可容纳 32 个布尔位
- `slotCount` 上限 256，由服务端 `MAX_CUSTOM_SLOTS` 限制
- 服务端在转发时附加发送者的 `playerID`，并仅广播给同队玩家

---

## 需要编辑的文件

所有文件位于 `modder/gml/` 目录。编辑后需重新运行 `npm run build` 构建。

> **重要**：源码中所有 `@` 前缀在构建时会被替换为 `__ONLINE_`，避免与游戏原有变量冲突。下文示例中直接使用 `@` 前缀。

---

## 示例：同步 `global.boss[1-8]` 和 `global.item[1-8]`

16 个布尔变量打包到 1 个 UINT32 slot：

| 位 | 变量 |
|----|------|
| bit 0–7 | `global.item[1]` – `global.item[8]` |
| bit 8–15 | `global.boss[1]` – `global.boss[8]` |

---

### 第一步：修改发送端 — `worldEndStep.gml`

找到文件末尾的 CUSTOM DATA SYNC 段：

```gml
// CUSTOM DATA SYNC
@customSlot = 0;
if (@customSlot != @customSlotPrev) {
```

将 `@customSlot = 0;` 替换为位域打包代码：

```gml
// CUSTOM DATA SYNC
@customSlot = 0;
var @bi;
@bi = 0;
while (@bi < 8) {
    if (global.item[@bi + 1])
        @customSlot = @customSlot | (1 << @bi);
    if (global.boss[@bi + 1])
        @customSlot = @customSlot | (1 << (@bi + 8));
    @bi += 1;
}
if (@customSlot != @customSlotPrev) {
```

后续的变化检测、buffer 写入和发送代码已由模板提供，无需修改。

---

### 第二步：修改接收端 — `worldEndStep.gml`

找到 TCP 消息循环中的 case 7 分支：

```gml
case 7:
    // CUSTOM DATA
    @ID = buffer_read_string(@buffer);
    #if not GMNET
        @customSlotCount = buffer_read_uint16(@buffer);
        if (@customSlotCount >= 1)
            @receivedSlot = buffer_read_int32(@buffer);
    #endif
    #if GMNET
        @customSlotCount = buffer_read_u16(@buffer);
        if (@customSlotCount >= 1)
            @receivedSlot = buffer_read_i32(@buffer);
    #endif
    break;
```

在 `break;` 前添加 OR 合并和解包代码：

```gml
case 7:
    // CUSTOM DATA
    @ID = buffer_read_string(@buffer);
    #if not GMNET
        @customSlotCount = buffer_read_uint16(@buffer);
        if (@customSlotCount >= 1)
            @receivedSlot = buffer_read_int32(@buffer);
    #endif
    #if GMNET
        @customSlotCount = buffer_read_u16(@buffer);
        if (@customSlotCount >= 1)
            @receivedSlot = buffer_read_i32(@buffer);
    #endif
    if (@customSlotCount >= 1) {
        @receivedSlot = @receivedSlot | @customSlot;
        var @bi;
        @bi = 0;
        while (@bi < 8) {
            global.item[@bi + 1] = (@receivedSlot >> @bi) & 1;
            global.boss[@bi + 1] = (@receivedSlot >> (@bi + 8)) & 1;
            @bi += 1;
        }
        @customSlot = @receivedSlot;
        @customSlotPrev = @receivedSlot;
    }
    break;
```

关键点：

- `@receivedSlot | @customSlot` — OR 合并，确保本地已有的状态不被覆盖
- 解包后同步更新 `@customSlot` 和 `@customSlotPrev`，避免下一帧误判为变化而重复发送

---

### 初始化

`worldCreate.gml` 和 `worldCreateGMS.gml` 中已有以下初始化代码，无需修改：

```gml
@customSlot = 0;
@customSlotPrev = -1;
```

---

## 扩展到更多变量

### 使用多个 slot

如果需要同步超过 32 个布尔值，增加 slot 数量。例如同步 64 个变量需要 2 个 slot。

发送端将 `slotCount` 从 1 改为 2，写入两个 i32：

```gml
buffer_write_uint16(@buffer, 2);
buffer_write_int32(@buffer, @customSlot0);
buffer_write_int32(@buffer, @customSlot1);
```

接收端对应读取 2 个 slot。服务端无需任何改动，它会透明转发任意数量的 slot。

### 关于变量不存在的游戏

并非所有游戏都定义了 `global.boss` 或 `global.item`：

- **GM8**：转换器默认强制开启 `zeroUninitializedVars`，未初始化的 `global.boss[n]` 会返回 0 而不是报错
- **GMS**：GMS 默认对未初始化全局变量返回 0

---

## 注意事项

1. **OR-only 语义**：位一旦被设为 1 就无法被远程重置为 0。适用于 Boss 击败、道具拾取等不可逆事件
2. **同队广播**：数据使用 `broadcastFromSameTeam` 转发，team=0 的玩家相互广播，不同非零队伍之间不传递
3. **按需发送**：系统每帧检查变量是否变化，仅在有变更时发送。高频变化的数据不适合此系统
4. **`@` 前缀**：所有自定义变量必须使用 `@` 前缀
5. **`#if GMNET`**：GM8.2 游戏使用不同的 buffer 函数名，所有 buffer 读写操作都需要提供两个分支
6. **服务端无需修改**：服务端原样转发 slot 数组，不关心其含义
