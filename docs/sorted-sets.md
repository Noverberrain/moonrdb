# F7 Sorted Set 普通与紧凑表示

通用 `parse` 支持格式 11 中的类型 5（ZSET_2）和 17（ZSET_LISTPACK）。`parse_strings` 与 `parse_empty` 保持原边界。历史类型 3（文本分数 ZSET）和 12（ziplist）不支持。

## 返回模型

`RdbRecord::SortedSet(SortedSetRecord)` 保存数据库、原始二进制键、键编码、条目、绝对到期时间、LRU / LFU 元信息、记录起止偏移和序列化字节数。条目为 `SortedSetEntry { element : Bytes, score : Double }`，成员允许二进制和空值。`SortedSetStorage` 区分 `BinaryDouble` 与 `Listpack`；紧凑表示另存外层 RDB 字符串编码（含 LZF）。

数组保留文件顺序，不承诺为所有编码统一排序。类型 5 在 Redis SAVE 中可能按逆序写出，因此调用方按需排序。listpack 必须按分数递增，同分按原始成员字节递增；解码时核对该约束。所有表示拒绝重复成员及空集合；同分的不同成员合法。

## 分数与校验

类型 5 的每个成员后读取 8 字节小端 IEEE binary64，直接按位解释为 Double，不通过十进制中转。保留正负无穷、次正规数和负零；所有 NaN 位模式拒绝。

类型 17 复用 listpack 总长度、元素计数、EOF、整数及反向长度校验；元素必须成对出现，未知计数 65535 逐对扫描并限制。分数可以是 listpack 整数或 ASCII 十进制文本（含指数），显式 `inf` / `+inf` / `-inf` 表示无穷。拒绝 NaN、非 ASCII、空串、空白、NUL、下划线和溢出为无穷的数字文本。每个分数文本固定最多 128 字节，覆盖固定 Redis 版本写出的表示，不承诺接受其他加载器可接受的任意长文本。

依据固定 Redis 7.2.5 提交的 [rdb.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c) 中 `rdbSaveObjectType`、`rdbSaveBinaryDoubleValue`、`rdbLoadBinaryDoubleValue` 与 Sorted Set 保存／加载分支，按格式独立实现。

## 资源边界

- `max_sorted_set_entries` 默认 100000，按整份文件累计，跨两种表示；空成员仍计一个条目。在 UInt64 窄化和累计前分别检查，拒绝溢出计数。
- `max_string_bytes` 限制键和每个解码成员；`max_decoded_bytes` 共享累计 AUX、键和成员等逻辑字节。分数最终为固定大小 Double，文本分数使用独立的 128 字节临时预算，不重复计入返回字节预算。
- `max_packed_bytes` 单独限制每个 listpack 外层字符串与 LZF 解压结果。主预算不会重复计算容器暂存；限制不代表进程总内存上限。
- 记录体积含元信息、类型、键及值，与其他类型共用 EOF / CRC64 完整性验证。错误后不返回部分快照。

错误使用 `InvalidSortedSet`、共享 `InvalidListpack` 及既有资源／截断错误。listpack 结构错误的 `offset` 指向原始 RDB 容器字符串，`inner_offset` 指向解压后容器字节；语义分数错误只记录容器偏移。

## 验证与边界

当前 Windows native 完整测试为 135 项（含 7 项文档测试）。新增用例覆盖分数位模式、二进制和空成员、重复成员、空集合、同分排序、未知／错误计数、奇数配对、非法文本、预算与溢出、旧 API 边界、压缩容器错误偏移，以及真实文件全部短前缀和逐字节单比特损坏。

真实样本 `fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb` 为未修改的 Redis SAVE 产物：486 字节，6 个 Sorted Set（20 个条目）、String / Set 标记键，分布于 DB 0 / 2。固定 listpack 阈值 4 条目／64 字节，覆盖两种表示、±∞、极小次正规数、最大有限数、十进制与指数、同分、LZF 键与容器、LFU 和绝对到期时间。合成负零位测试独立于 Redis 是否在保存中归一化零。

使用与前几阶段相同的已核验第三方 Windows Redis 7.2.5 构建。生成器 SAVE 前核对 ZCARD / ZSCORE，SAVE 后运行 redis-check-rdb，再由第二个隔离进程加载同一文件并逐键核对分数及 PEXPIRETIME。MoonBit 测试另外核对实际 RDB 类型、所有成员分数、元信息、压缩标记和字节区间；没有用内存 OBJECT ENCODING 代替文件编码验证。来源和复现步骤见 [样本说明](../fixtures/README.md)。

本阶段只验证 Windows native 和这些明确编码，不代表支持所有 Redis 版本、所有类型或性能规模。inspect / stats / top / export 留待后续阶段。
