# F6 Set 普通与紧凑表示

## API 和集合语义

通用 `parse` 新增 `RdbRecord::Set(SetRecord)`，支持 RDB 类型 2（普通成员序列）、11（intset）和 20（listpack）。`parse_empty` 与 `parse_strings` 仍拒绝 Set，其他专用入口签名不变。消费者对 `RdbRecord` 穷举匹配时需增加 Set 分支。

`SetRecord` 保存数据库、键字节与键存储编码、`members`、对象表示、外层容器存储形式、键前置元信息、原文件半开区间和序列化体积。`SetStorage` 为 `Hashtable`、`Intset(width)` 或 `Listpack`，其中 width 是每个整数的字节宽度 2 / 4 / 8。`packed_storage` 仅对 intset / listpack 存在，记录外层 Raw 或 Lzf 等 RDB 字符串形式；这些是文件表示，不是运行时内存测量。

members 保持文件顺序以便追溯，**Set 语义无序**，比较应按成员集合进行。派生 Eq 是结构和数组顺序比较，不是两个不同序列化文件的集合等价判断。二进制与空成员保留原始字节，整数表示转为精确十进制字节，不进行浮点转换；原始 `01` 与整数表示的 `1` 是不同成员。重复成员、空 Set 明确失败，不排序修复或静默去重。

## 格式与校验

依据固定提交的 [rdb.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c)、[intset.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/intset.c) 和 [listpack.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/listpack.c) 按规则独立实现，未纳入上游 C 源码或二进制。

- 普通序列先读取普通 RDB 长度计数，再逐成员使用字符串解码，支持普通、整数与 LZF。计数字段不接受编码字符串标记。
- intset 的外层是一个 RDB 字符串，可经 LZF 解压。内部头部是 32 位小端宽度和 32 位小端成员数，宽度只允许 2 / 4 / 8。按 UInt64 检查 `8 + count * width` 精确等于容器大小后再读取元素，避免 32 位乘法回绕。元素为有符号小端整数，必须严格递增；相等、降序或按无符号顺序排列的负数都失败。合法的较宽表示可用于较小整数，不根据当前值重新猜宽度。
- listpack 复用已验证的头部、元素、反向长度与终止符校验。允许奇数个成员，但不允许重复值。已知计数必须匹配，65535 未知计数仍逐项检查限额。整数项与相同十进制字节字符串被视为重复成员。

`InvalidIntset.offset` 是原文件外层 RDB 字符串编码起点，`inner_offset` 是解码后的容器偏移。`InvalidListpack` 沿用同样的双偏移约定；压缩时不能将两者相加冒充原文件精确位置。普通成员重复错误使用该成员在原文件中的起点；packed 重复错误使用容器起点。文件整体仍须完成 EOF、尾随字节和 CRC64 检查，没有部分成功返回值。

## 资源限制

`parse` 新增 `max_set_members`，默认 100000，约束**整份快照全部 Set 的成员总数**，三种表示共享一个计数。空成员也计数；不同 Set 中相同字节可分别存在、分别计数。请求先与上限比较，再计算累计值和缩窄索引，极大普通计数不能在已有记录之后回绕。零限制可用于不含 Set 的快照，负数配置明确失败。

单成员继续受 `max_string_bytes` 约束；成员解码字节与 AUX、键和其他类型结果共同计入 `max_decoded_bytes`。intset / listpack 暂存容器单独受 `max_packed_bytes`（默认 4 MiB）约束，LZF 输出声明在分配前检查；暂存不重复算作逻辑结果字节。整数的固定小型十进制转换同样检查最终字节长度。

这些是逻辑资源限制，不是精确峰值内存测量。当前实现持有完整输入并保留解码记录，原输入、对象、数组及暂存缓冲另占空间；没有恒定内存、大文件性能或跨版本全覆盖承诺。

## 真实样本与测试

新增 560 字节真实样本含 DB 0 / 2 的 10 个 Set，共 36 个成员，以及 String / Hash / List 标记键。固定 `set-max-intset-entries=4`、`set-max-listpack-entries=4`、`set-max-listpack-value=64`，使用 allkeys-lfu。覆盖 16 / 32 / 64 位 intset 极值、非 UTF-8 与空成员、前导零文本、混合整数 listpack、超过紧凑计数阈值、长成员、LZF 容器、压缩键和绝对到期时间。

样本经 SAVE 与 Redis 完整性检查，再在第二个隔离 Redis 进程中加载，逐键用 SCARD 与每个成员的 SISMEMBER 核对无序语义，同时核对标记键及 PEXPIRETIME。OBJECT ENCODING 只检查造样本时的阈值效果；MoonBit 另行验证实际 RDB 编码、intset 宽度、精确字节、元信息与体积。来源及哈希见 [样本说明](../fixtures/README.md)。

当前 native 共 142 项测试（含 7 项文档测试）。新增合成用例覆盖 intset 所有宽度和极值、较宽合法表示、短头部、错误宽度、乘法边界、长度不符、重复与降序、listpack 计数与重复、空成员预算、跨记录和跨编码累计限制、解码预算及压缩错误偏移。真实 Set 文件的每个短前缀与每个字节最低位修改均被拒绝。Sorted Set 已在 F7 实现，inspect 已在 F8 实现；其他 CLI 命令和性能验收留待后续阶段。
