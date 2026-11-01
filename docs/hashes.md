# F4 通用快照与 Hash 解码

## API 与数据模型

`parse` 返回 `Snapshot`，其中 `records` 是按文件顺序保存的 `Array[RdbRecord]`，包含 `String(StringRecord)`、`Hash(HashRecord)`，F5 又增加 `List(ListRecord)`。本页描述 Hash 类型 4 / 16，List 类型 18 详见 [lists.md](lists.md)；未列出的类型、函数、模块仍明确失败。原 `read_header`、`parse_empty` 和 `parse_strings` 的签名及支持边界保持不变。

`HashRecord` 与 String 记录一样保存数据库、原始键字节、键存储编码、到期／空闲／频率元信息、原文件记录区间及序列化体积。`storage` 为 `Hashtable`（RDB 类型 4，普通字段／值序列）或 `Listpack`（类型 16）；这描述文件表示，不是运行时内存测量。`packed_storage` 仅对 listpack 存在，记录外层 RDB 字符串为 Raw 或 Lzf 等表示。`entries` 是 `HashEntry { field, value }` 数组，保持文件顺序；Hash 语义无序，比较或迁移时不应依赖该顺序。

字段和值按字节保留，允许空字段、空值及非 UTF-8 内容。整数表示规范化为精确有符号十进制字节，含 Int64 极值。重复字段明确失败，包括整数编码字段与相同十进制文本字段；空 Hash 也被拒绝。这些是明确的严格输入约定，不承诺复现 Redis 对所有畸形输入的宽容行为。

## 编码依据与完整性

固定上游提交 `f60370ce28b946c1146dcea77c9c399d39601aaa` 的 [rdb.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c) 和 [listpack.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/listpack.c) 为格式依据。按规则独立实现，未纳入上游 C 源码或二进制。

普通 Hash 使用有界长度计数，逐字段／值调用已验证的字符串解码，支持普通、整数与 LZF 表示。listpack 的外层 RDB 字符串可经 LZF 解压；随后验证：

- 六字节头部的 32 位小端总长度必须等于解码容器的实际长度，尾部必须是 `0xff`。
- 元素编码支持 6 / 12 / 32 位字符串长度，7 位无符号整数与 13 / 16 / 24 / 32 / 64 位有符号整数。
- 每项反向长度必须与该项实际编码字节数和规定的宽度一致。宽度遵循固定 Redis 版本的边界：127 包含在单字节范围，16383 / 2097151 / 268435455 分别开始使用 3 / 4 / 5 字节。
- 头部元素数不是 65535 时必须与扫描结果相同；65535 表示未知计数，仍逐项检查实际内容和限制。
- Hash 元素必须成字段／值对，拒绝奇数元素、提前终止、保留编码、截断、错误反向长度和重复字段。不会猜测跳过非法项。

`InvalidListpack` 的 `offset` 是原文件中外层 RDB 字符串编码起点，`inner_offset` 是解码后 listpack 内的零基偏移。容器可能经过压缩，因此不能把二者简单相加当作原文件的精确字节位置。其他错误继续采用原始输入偏移。整份文件仍须完成 EOF、尾随字节和 CRC64 检查后才返回成功，无部分成功返回值。

## 资源与体积

通用入口保留输入、单字符串、全局元信息、记录数与累计解码字节限制，默认值与 F3 相同。另有 `max_hash_entries`（每个 Hash 的字段对数量，默认 100000）和 `max_packed_bytes`（单个 listpack 容器解码后的大小，默认 4 MiB）。计数在缩窄为数组索引和分配／追加之前检查，未知元素计数也不能绕过限制。

listpack 容器使用独立暂存预算，原始或 LZF 解压均受容器上限约束；不能把压缩后的较小体积当成解压上限。单字段／值仍受 `max_string_bytes` 约束，解码结果与 AUX、键及 String 值共同计入 `max_decoded_bytes`。暂存容器不重复计入逻辑结果预算，但其缓冲、对象及数组仍占额外内存；这些参数不代表精确进程峰值内存限制，也不表示恒定内存扫描。

Hash 记录区间包含全部前置键元信息、类型、键与对象内容，采用原文件的压缩表示。通用快照中 String / Hash 的序列化体积之和加全局开销必须等于文件字节数，不将其称作 Redis RAM 占用。

## 真实样本与测试范围

F4 交付时 native 测试共 76 项（4 项文档测试），F5 中全部保留，当前完整测试为 91 项。502 字节真实快照包含 8 个 Hash 和 1 个 String，分布在 DB 0 / 2。固定 `hash-max-listpack-entries=4`、`hash-max-listpack-value=64`，覆盖：小 Hash、超过条目阈值、超过字段长度阈值、超过值长度阈值、二进制／空字段、整数极值、LZF 键与值以及 LZF 压缩 listpack。策略设为 allkeys-lfu，另有真实频率字段和绝对到期时间。

样本生成后由 Redis 工具确认完整性，再在隔离 Redis 中重新加载，逐键核对 HLEN、HGET、String GET 和 PEXPIRETIME；MoonBit 测试独立比较语义和实际 RDB 类型，按无序字段比较，不从运行时 OBJECT ENCODING 推断文件类型。样本与预期数据的哈希见 [fixtures/README.md](../fixtures/README.md)。

新增合成测试覆盖所有整数宽度、字符串长度表示、反向长度边界、未知元素计数、头部／终止符损坏、奇数元素、重复字段和预算边界；真实 Hash 文件的每个短前缀及每个字节最低位修改均被拒绝。历史 Hash zipmap / ziplist、其他逻辑类型、CLI 命令及性能测量不在本阶段范围内。
