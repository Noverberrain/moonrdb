# F5 List quicklist2 解码

## API 与有序元素

通用 `parse` 支持 RDB 类型 18 `LIST_QUICKLIST_2`，返回 `RdbRecord::List(ListRecord)`。`parse_empty` 和 `parse_strings` 仍拒绝 List。F6 又增加 Set 分支，消费者对 `RdbRecord` 做穷举匹配时应覆盖全部支持类型。

`ListRecord` 保存数据库、键字节和键存储编码，原始到期／空闲／频率元信息，记录的半开字节区间与序列化体积。`items` 是严格按节点顺序和节点内部顺序拼接的二进制数组，保留重复值、空元素和整数的精确十进制字节。不会排序、去重、读取时钟或过滤过期键。

`nodes` 记录每个节点的容器 `Plain` / `Packed`、RDB 字符串存储形式，以及 `item_start..item_end` 在本条 List 的 items 数组中的半开范围；不重复保存元素。`node_start..node_end` 是原文件字节区间，包含容器标记和其后的 RDB 字符串，不包含 List 键或节点总数。记录整体区间则包含键前置元信息、类型、键、节点总数和全部节点。体积采用原文件压缩表示，不是 Redis RAM 占用。

## 编码与严格校验

格式依据固定 Redis 提交的 [rdb.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c)、[quicklist.h](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/quicklist.h) 和 [listpack.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/listpack.c)。按规则独立实现，未纳入上游 C 源码或二进制。

quicklist2 以普通 RDB 长度表示节点数，每个节点先读取普通长度编码的容器编号，然后读取一个 RDB 字符串：

- 容器 1（plain）：解码为单个元素，支持普通、整数或 LZF 的 RDB 字符串表示。
- 容器 2（packed）：将字符串视为 listpack，可使用 LZF 外层压缩，依次解码所有元素。

其他容器编号、编码字符串形式的节点数或容器编号均失败；不猜测跳过未知表示。历史 List 类型 1（旧普通序列）、10（ziplist）、14（旧 quicklist）仍不支持。

packed 节点复用 Hash 已验证的 listpack 头部与元素读取：核对总长度、终止符、元素编码、反向长度和计数；65535 表示未知元素数，仍逐项扫描。List 允许奇数个元素和重复值，不应用 Hash 的配对或唯一字段规则。`InvalidListpack.offset` 是原文件中节点 RDB 字符串的编码起点，`inner_offset` 是解压后 listpack 内的偏移，不能简单相加当作压缩文件位置。

节点数为零、空 plain 节点和空 packed 节点均返回 `InvalidList`。这是本项目的严格输入规则；上游对部分空节点可容错跳过，本项目不声称复制这种畸形数据行为。节点及元素成功读取不等于文件成功，仍须通过 EOF、尾随字节和 CRC64 检查后才返回完整快照。

## 资源限制

`parse` 新增 `max_list_nodes` 与 `max_list_items`，默认均为 100000，**分别约束整份快照的 List 节点总数和元素总数**，不是单个 List。空字符串也占一个元素名额，未知 listpack 计数不能绕过累计检查。计数先与限制比较，再求累计值和缩窄为数组索引，极大 UInt64 节点数不会回绕成小数。零限制可用于只允许无 List 数据的快照，负数配置失败。

plain 元素受 `max_string_bytes` 约束；packed 容器受 `max_packed_bytes`（默认 4 MiB）约束，其解压长度在分配前检查。容器内每个元素仍受单字符串限制，解码结果与 AUX、键、String 和 Hash 字段共同计入 `max_decoded_bytes`。packed 暂存缓冲独立于逻辑结果预算，不能用较小的压缩体积绕过解压上限。

输入、记录对象、数组和暂存缓冲另占内存，限制不是精确峰值 RAM 测量。当前实现持有完整输入并保留所有记录，没有恒定内存或任意大文件处理承诺。

## 真实样本条件与验证

新增 737 字节真实快照含 DB 0 / 2 的 6 个 List、1 个 String 和 1 个 Hash。List 覆盖单 packed 节点、多节点、plain / packed 混合、LZF 节点、非 UTF-8 二进制、重复元素、空元素、精确 Int64 文本、压缩键、LRU 和绝对到期时间。

固定配置为 `list-max-listpack-size=2`、`list-compress-depth=1`。Redis 7.2.5 的 plain 元素默认阈值是 1 GiB，见固定提交的 [quicklist.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/quicklist.c)。为生成小型真实 plain 节点，专用回环实例开启本地 DEBUG，并执行官方 [DEBUG QUICKLIST-PACKED-THRESHOLD](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/debug.c) 将阈值设为 64 字节；未修改服务器源码或二进制，未修改已有实例。该条件写入 manifest，不构成默认阈值下 1 GiB 元素的规模或内存验收。LZF 测试验证文件表示，不据此宣称运行时压缩效率。

生成流程经 SAVE、Redis 完整性检查和第二个隔离 Redis 进程加载，逐项核对 LLEN、LINDEX、标记键及 PEXPIRETIME。MoonBit 测试再按原顺序比较全部字节、节点容器与存储形式、节点索引／字节范围和总文件体积。

F5 交付时 native 测试共 91 项（含 5 项文档测试），相关回归在 F6 中保留，当前完整测试为 153 项。List 用例覆盖跨节点顺序、奇数与重复元素、空节点、未知容器、非法计数、旧格式拒绝、全文件节点／元素累计限制、共享解码预算、LZF 扩展上限及 listpack 内部错误。真实 List 文件的每个短前缀与每个字节最低位修改均被拒绝；未进行默认阈值大文件、其他 Redis 版本或性能验收。
