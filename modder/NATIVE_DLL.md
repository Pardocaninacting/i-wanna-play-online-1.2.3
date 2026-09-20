# http_dll 能力盘点与原生化评估（2026-09-18）

对 `modder/native/http_dll_2_3_x86|x64`（C# NativeAOT 重写）做一次能力清点，并评估当前纯 GML
实现里哪些可以用原生替代。**所有数字都来自源码**（导出 = `Exports.cs` 的
`[UnmanagedCallersOnly(EntryPoint=...)]`；可调用性 = `converter-gms/Program.cs` 的 `DefineNative`；
使用量 = `modder/gml/*.gml` 的引用计数）。

## 1. DLL 提供了什么

共 **54 个导出**，按家族：

| 家族 | 数量 | 说明 | GML 引用 |
|---|---|---|---|
| `buffer_*` | 29 | 创建/销毁/读写（int8..float64/string）/文件读写/长度/字符串化 | **930 处** |
| `socket_*`（TCP） | 10 | create/connect/update_read/write/read/write_message/reset/state/shut_down | 107 处 |
| `udpsocket_*` | 8 | create/start/set_destination/send/receive/state/exists/destroy | 38 处 |
| `md5_dir` | 1 | 目录内容哈希（原生包指纹快速路径） | 3 处 |
| `strip_non_bmp` | 1 | 去除 BMP 外码点 | 4 处 |
| `set_utf8_mode` | 1 | 切换 C 字符串编码模式 | 2 处 |
| `ansi_to_utf8` | 1 | 原生编码转换 | 见发现 1 |
| `input_box` | 1 | 原生输入框 | 见发现 1 |
| `file_read_text` / `file_write_text` | 2 | 整文件读写（本次新增，共享账号存储用） | 各 1 处 |

**没有**的（C++ 原版有、C# 重写未移植）：zlib 压缩/解压、RC4、base64、字符串/文件 MD5、
HTTP 请求客户端。

## 2. 发现

### 发现 1：7 个导出 GML **调用不到**（未注册）

`DefineNative` 的两处列表加起来注册了 **47 项**，因此这些导出是死代码：

```
ansi_to_utf8, input_box, socket_shut_down,
buffer_read_int8, buffer_write_int8, buffer_read_int64, buffer_write_int64
```

`ansi_to_utf8` 尤其值得注意：模板里有 **6 处** `__ONLINE_ansi_to_utf8(...)` 调用（全部包着
`wd_input_box`，用于 GM8.1+ 的 CJK 输入转换），但：

- 这 6 处**都在 `#if CJKTEXT` 分支内**，而 `CJKTEXT` 只有 GM8 转换器会设置 ⇒ **GMS 构建把它们整段剥掉**，
  所以 GMS 侧编译不到它（这也解释了为什么 GMS 一直没暴露问题）；
- x86 扩展定义文件 `modder/lib/http_dll` 里**没有** `ansi_to_utf8`（经核实：`MISSING`，同文件里有
  `socket_shut_down`）；
- GMS 转换器也没有注册它。

结论：DLL 的原生 `ansi_to_utf8` 当前**没有任何路径能调用**。如果将来 GMS 或其他引擎需要 ANSI→UTF-8
转换，注册一行即可直接使用。

处置建议：**注册**（一行一项，零风险）或**删除**（减小二进制）。二者都比现状好。

### 发现 2：纯 GML 的 MD5 是最大的可原生化目标

`modder/gml/md5.gml` = **423 行纯 GML**、**102 处引用**（皮肤与包指纹）。DLL 只有 `md5_dir`
（目录），没有字符串/缓冲区哈希。按 4 KB 块做 GML 循环是典型的 CPU 热点。

建议：新增 `md5_string` / `md5_buffer` 导出 → 一处调用替换 → 保留 GML 实现作为无 DLL 时的回退。

### 发现 3：共享存档 blob 未压缩

全仓库没有任何 zlib/compress 调用。共享存档按原样上线，体积直接等于数据量。
C++ 原版有 `buffer_zlib_compress/uncompress`，C# 重写没移植。

建议：加回 zlib（写入侧压缩、读取侧按魔数兼容旧格式），并把 blob 版本号 +1。收益是网络与磁盘
体积，代价是一次格式兼容处理。

### 发现 4：CJK 图集是逐字形 GML 绘制

`cjkAtlas.gml`（382 行）在 GM8.0 上按字形查表、逐个 `draw_sprite_part`。作为"FoxWriting 不可用
时的回退"完全合理，但长中文串（聊天气泡、笔记）会逐字循环。

建议：**先测再决定**。用一次性计时（把一段中文渲染 N 次并记录 `current_time`）判断它是否真的
进入热点；只有在明显占用时才考虑原生文本渲染器（工作量大，且要维护字形缓存）。

### 发现 5：注册列表有两份，容易漂移

x64 走 `AddNativeX64ExtensionIfMissing` 的 `DefineNative` 列表，x86 走扩展定义文件 +
`AddSetUtf8ModeToExtension` 增补。同一个函数要写两处，漏一处就表现为转换期
`Failed to find function`（本次开发中已经踩过一次）。

建议：把"新增函数清单"提成单一数据源（一个数组），两处循环注册；`check_qol_account.js` 已有
"两条路径都存在"的断言，可以再加"两处列表长度一致"。

## 3. 原生已经带来明显收益的地方

- **网络栈**：TCP/UDP 全原生（107 + 38 处引用），GML 无法企及的性能与稳定性。
- **缓冲区序列化**：存档/聊天/笔记/皮肤缓存全部走 `buffer_*`（930 处），这是整个 mod 的数据层。
- **编码与字符串**：`set_utf8_mode`、`strip_non_bmp` 把引擎间差异收敛到一处。
- **文件访问**：新加的 `file_read_text`/`file_write_text` 让 GMS 也能读写沙箱外的共享账号文件——
  这是纯 GML 完全做不到的（GMS 的文件函数被限制在存档区）。

## 4. 建议的优先级

| 优先级 | 事项 | 成本 | 收益 |
|---|---|---|---|
| 高 | 注册或删除那 7 个死导出；确认 `__ONLINE_ansi_to_utf8` 的实现来源 | 低 | 去掉死代码 / 可能白拿一个原生转换 |
| 高 | 注册列表单一数据源 | 低 | 消除"漏一条路径"的整类故障 |
| 中 | 原生 `md5_string`/`md5_buffer` | 中 | 皮肤与包指纹明显提速 |
| 中 | 原生 zlib（共享存档 blob 压缩 + 版本号） | 中 | 网络/磁盘体积 |
| 低 | 原生 CJK 文本渲染 | 高 | 仅在实测证明是热点时做 |

## 5. 如何用数据决策

这些判断都还不该凭感觉定优先级：`md5.gml`、图集绘制、blob 写入都**没有实测耗时**。
下一步是在一个真实会话里加一次性计时（把各自的调用包在 `current_time` 差值里，累积到全局计数器，
再在菜单详情里显示），拿到数字后再决定投入哪一个。本次评估的价值是把"候选清单与成本"钉死，
把"该不该做"留给数据。
