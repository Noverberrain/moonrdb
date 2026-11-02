# MoonRDB

计划使用 MoonBit 实现 Redis RDB 解析库与离线快照分析 CLI。

## 当前状态

已完成 F0 工程骨架、F1 基础读取、F2 空库解析、F3 String 与 LZF、F4 Hash、F5 List，F6 Set 三种表示，F7 Sorted Set 两种表示解码，以及 F8 inspect CLI 与最小库示例。
公开 API `read_header` 只读取头部，**不验证剩余文件内容、EOF 或 CRC64**。
公开 API `parse_empty` 可完整检查支持范围内的无对象快照，保留 AUX、数据库选择和容量提示，并区分校验通过与关闭校验和。
`parse_strings` 保留只接受 String 的边界。通用 `parse` 返回 `Snapshot`，其 `RdbRecord` 可为 String、Hash、List、Set 或 SortedSet。Set 支持类型 2 普通成员序列、11 intset 和 20 listpack；检查成员唯一性与编码完整性，受全文件累计成员数限制。
Sorted Set 支持类型 5 二进制 double 与 17 listpack，返回原始成员和 Double 分数，拒绝 NaN、重复成员与损坏结构。`inspect` 已可检查格式版本、数据库、键数和完整性；stats / top / export 尚未实现。

## 本地开发

已验证 Windows x64 native 后端：`moonc 0.10.18+6c83a7f62`，`moon 0.1.20261028`。native 编译需要可用的 MSVC 工具链，样本脚本需要 Python 3.10 或以上。本阶段没有第三方 MoonBit 包依赖。

在仓库根目录运行：

```powershell
moon check --target native
moon build --target native
moon test --target native
moon run cmd/main --target native -- --help
moon run cmd/main --target native -- inspect fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb
moon run examples/parse --target native
python -X utf8 scripts/verify_fixtures.py
```

当前 `moon test --target native` 为 **142 项测试**（含 7 项文档测试），覆盖七份真实快照及合成异常输入。有键快照覆盖 String、Hash、List、Set、Sorted Set，包含数据库切换、LRU / LFU 和到期时间，并经隔离 Redis 重新加载逐键核对。Set 样本覆盖三种表示及所有 intset 宽度；新增 Sorted Set 样本含 6 个 Sorted Set 与两个混合类型键，覆盖两种表示及分数边界。List 的 plain 节点使用官方 DEBUG 命令降低阈值生成，不代表默认阈值下的大数据验收。旧秒编码仍只有合成测试。文件读取放在 native CLI 与测试中，库本身不依赖文件系统。
Python 离线检查核对七份样本及预期数据的身份，完整解析与 CRC64 由 MoonBit 测试验证。另有 37 项原生 CLI 进程检查，覆盖退出码、标准输出／错误流、异常文件、路径和输入上限。

## inspect 用法

```powershell
moon run cmd/main --target native -- inspect fixtures/redis-7.2.5/empty.rdb --max-input-bytes 67108864
```

默认只读普通文件，输入上限为 64 MiB，在分配完整输入前检查文件大小。成功摘要最后显示 `status: complete`；CRC64 有效与关闭校验和分别报告。原生程序退出码：成功 0，读取／解析失败 1，参数错误 2。完整命令、输出示例与限制见 [inspect 文档](docs/inspect.md)。

## 库调用示例

消费项目的 `moon.pkg` 导入 `"Noverberrain/moonrdb"` 后，可以调用：

```moonbit
let version = @moonrdb.read_header(b"REDIS0011") // 返回 11；调用方需要处理 ParseError
let result = @moonrdb.parse_empty(bytes) // bytes 是调用方读取的快照；可能抛出 ParseError
let strings = @moonrdb.parse_strings(bytes) // StringSnapshot，含 records 与校验状态
let snapshot = @moonrdb.parse(bytes) // Snapshot，records 中的 String / Hash / List / Set / SortedSet 可模式匹配
```

所有 API 均接收完整 `Bytes`，默认限制输入为 64 MiB，可通过 `max_input_bytes` 调整；限制不会撤销调用方已分配的输入。仅支持格式版本 11，其他版本返回明确错误。[读取约定](docs/reader.md)、[空库约定](docs/empty-snapshot.md)、[String 约定](docs/strings.md)、[Hash 约定](docs/hashes.md)、[List 约定](docs/lists.md)、[Set 约定](docs/sets.md) 和 [Sorted Set 约定](docs/sorted-sets.md) 说明具体边界。当前 API 会保留所有解码记录，不是恒定内存的分块文件读取。

可运行 `moon run examples/parse --target native` 验证只依赖解析库的最小示例。它在仓库内构建，独立消费项目验证留待 F12。

完整本地检查可执行 `./scripts/ci.ps1`。GitHub Actions 固定编译器、core 和第三方 Action 提交，运行 native check / build / test、格式检查、样本核验和 CLI 进程检查；远端运行结果以实际 Actions 记录为准。

## 格式与样本

参考 Redis **7.2.5**，固定上游提交 `f60370ce28b946c1146dcea77c9c399d39601aaa`，对应 RDB 格式版本 **11**。当前支持明确列出的文件结构、String、Hash、quicklist2 List、Set 和 Sorted Set，不代表支持该产品版本的所有数据类型。

- [兼容矩阵与格式依据](docs/compatibility.md)
- [真实样本来源、哈希、生成和核验](fixtures/README.md)
- [Apache-2.0 许可证](LICENSE)

## 计划范围

- 固定 Redis 7.2 的具体补丁版本及上游提交，逐项验证 RDB 编码。
- 提供可复用解析 API，以及 inspect、stats、top 和 export 命令。
- 统计快照中的序列化体积；该数值不代表 Redis 运行时内存占用。

下一阶段为 F9：stats 统计。当前版本尚未发布到 Mooncakes；上述导入示例需先使用本地源码，不能直接从 Mooncakes 安装本项目。
