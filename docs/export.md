# F11 JSONL 导出

从仓库根目录运行：

```powershell
moon run cmd/main --target native -- export fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb --db 2 --prefix long- --format jsonl
moon run cmd/main --target native -- export fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb --output snapshot.jsonl
```

默认输出到 stdout。指定 `--output` 写文件，成功时 stdout 为空；完成信息始终写 stderr，例如 `moonrdb: export complete records=1 checksum=valid`。它与 inspect/stats/top 成功时 stderr 为空的约定不同。`--output -` 不接受，标准输出请省略 output。

## 参数与过滤

格式仅支持 jsonl，默认值同样为 jsonl；db、prefix、format、output 各最多一次。数据库编号接受无符号十进制 UInt64 全范围，含 0，不允许符号或下划线。前缀按 UTF-8 字节匹配，空前缀匹配全部；db 与 prefix 同时给定时为交集。不依赖当前时间，不丢弃过期记录。无匹配结果为成功，JSONL 为空。

`--max-input-bytes`、`--`、读取资源边界及失败退出码继承 [inspect](inspect.md)。`--at`、TopN 参数等不接受。传入非法选项以 2 退出；读取、解析或导出错误以 1 退出。输出目录必须已存在。

整份文件必须先通过通用 parse，未匹配到的记录也需要支持且合法，不能用过滤跳过损坏或不支持对象。之后按原始记录顺序逐条编码与写出。仍持有完整输入及解析结果，每条记录序列化还会分配 JSON／文本／Base64，不是恒定内存流式解析，也没有单独的输出字节预算。

## JSONL v1 约定

每行是一个 `schema: "moonrdb.record.v1"` 对象，无表头、尾部完成行或 BOM。属性顺序不是协议的一部分。

| 字段 | 约定 |
|---|---|
| database | 十进制字符串，无符号 UInt64 |
| key | `{ "encoding": "base64", "data": "..." }` |
| type | String / Hash / List / Set / SortedSet |
| storage、key_storage | 与库类型对应的编码名称，List 为 Quicklist2 |
| serialized_bytes、record_start、record_end | 十进制整数字符串，区间为原文件 `[start,end)` |
| expires_at_ms | 有符号 Unix 毫秒字符串或 null |
| idle_seconds、frequency | 十进制字符串或 null |

全部二进制键、值、字段、元素都使用上述 Base64 对象，包括合法 UTF-8 和空字节串，不做有损文本替换。数据库、时间、体积、偏移等整数均为 JSON 字符串，消费者应使用支持宽整数的类型解析，避免 JavaScript Number 精度损失。

各类型负载：

- String：value 为 Base64 对象。
- Hash：entries 为 `{field,value}` 数组，二者均为 Base64 对象。
- List：items 为有序 Base64 数组，保留重复和空元素；nodes 另存 container、storage、item_start/end、node_start/end，节点偏移与索引也是字符串。
- Set：members 为 Base64 数组，文件顺序不等于集合语义排序。
- SortedSet：entries 为 `{element,score,score_bits_u64}` 数组；element 为 Base64 对象，score 为展示字符串（含无穷），score_bits_u64 为 IEEE binary64 原始位模式的无符号十进制字符串。精确还原必须用位模式，尤其负零的展示字符串可能是 `0`。

Hash、Set、SortedSet 还有 packed_storage 字符串或 null，记录紧凑容器外层编码。List 节点另行保留其编码。数组保留库模型中的文件顺序，Hash／Set 消费者按无序语义处理；不保证跨两次独立 SAVE 的输出字节相同。

JSONL 只导出记录，不导出 AUX、数据库容量提示或全局字节开销；不用于逐字节重建原始 RDB。校验状态在 stderr 完成信息中报告：disabled 不等于校验通过。输出体积字段指原 RDB 序列化体积，不是 JSONL 字节数或 Redis RAM。

## 文件替换与失败

文件导出在目标同目录以随机后缀独占创建临时文件，逐条写入后 sync 并关闭，再通过一次 rename(replace=true) 替换目标。不会先清空旧目标。写入／编码／同步／重命名失败时尝试清理自己创建的临时文件，旧目标在替换前保留。实际测试覆盖损坏输入、目标目录导致的重命名失败、缺失父目录、已有文件替换、空匹配，以及临时文件清理。

输出不能指向输入快照的同一路径或可解析到输入的符号链接；Windows 路径比较忽略大小写。输出路径及父目录应在导出期间保持稳定。没有声称支持恶意并发路径替换、跨平台文件系统行为或断电持久性；未做崩溃注入测试。进程被强制终止可能遗留临时文件。完成信息写入 stderr 在文件替换后发生：若 stderr 此时故障，文件可能已完整替换，但进程仍失败。

stdout 无法事务回滚，输出失败时可能留下合法 JSONL 前缀；调用方必须检查退出码并读取 stderr 完成信息，不能仅凭若干可解析行认定全量成功。库 parse 失败在任何记录输出之前返回。当前版本不会重新导入 JSONL 或写回 RDB。

## 验证

Windows native 155 项 MoonBit 测试、85 项通用 CLI 进程检查、39 项导出进程检查通过。导出检查将七份真实快照的所有记录经 Python 标准库 JSON/Base64/IEEE 解码，与 expected.json 逐键核对，覆盖五种类型、二进制、宽整数、极端毫秒、负零及无穷、UTF-8 过滤、原始 List 顺序、Set／Hash 无序语义、stdout 与文件结果一致、失败保护和目录清理。

完整本地检查为 `./scripts/ci.ps1`。库根包公开接口未改变，仅 CLI 包增加功能；远端 Actions、Mooncakes 发布及仓库外消费者验收留待 F12。
