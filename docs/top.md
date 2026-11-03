# F10 大键 TopN

从仓库根目录运行：

```powershell
moon run cmd/main --target native -- top fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb --by serialized-bytes --limit 20
```

默认按序列化体积排名，limit 默认 20，接受 1..10000 的严格正十进制整数；大于键数时返回全部记录，空库返回 0 行。只支持 `--by serialized-bytes`，不支持按 Redis RAM 或解压后长度排名。`--max-input-bytes`、`--`、只读文件、完整校验和退出码沿用 [inspect](inspect.md)。重复 limit/by、未知排序项、越界值及其他命令专用参数会以 2 退出。

## 输出

每行含 rank、数据库、`key_base64`、原始记录序列化体积、逻辑类型、编码、元素数量及记录偏移。Base64 使用标准字母表和填充，空键表示为 `key_base64=`；不直接输出键字节或值。Hash 显示字段对数，List 显示元素数，Set／Sorted Set 显示成员数；String 显示解码后的 value_bytes，不能把它视为集合成员数。

编码字段展示 String 值编码、Hash／Set／Sorted Set 的容器编码或 List 的 Quicklist2。它不是全部内部编码明细：List 每个节点的 plain／packed 和紧凑容器外层 LZF 信息仍在库模型中，当前报表不逐项展开。Set 的 Intset(n) 中 n 为元素字节宽度。

排序规则：序列化体积降序；同体积依次按数据库编号升序、键的无符号字节字典序、原始记录偏移升序。完全相同的记录最后按输入数组位置排序。用显式字节比较保证不同长度键的字典序，不依赖 Bytes 的默认 Compare。原始记录保留，不按键名去重，也不依当前时间过滤过期记录。

体积包含记录元信息、类型、键和值，保留文件中的压缩表示，不含全局开销；它不是 Redis 运行时内存。返回的“大键”指快照中记录体积排名靠前的键，不代表 Redis 官方阈值诊断或运行时阻塞风险测量。

## 选择与资源

使用大小最多 N 的最大堆，根节点为当前候选中排名最差的记录。扫描时只替换更优候选，最后对至多 N 项排序；保留候选为 O(min(N,R))，不对全部 R 条记录排序。比较会访问键字节，因此成本还取决于相同排名前缀的键长度。读取与解析仍持有整个输入及全部解码记录，不能称为流式或恒定总内存处理；未做性能基准。

完整解析成功后才生成输出，最后报告 CRC64 valid／disabled 和 status: complete。不支持、损坏、截断、尾随数据等仍失败，不输出部分 TopN 成功结果。

## 验证

F10 交付时 Windows native：153 项 MoonBit 测试与 85 项 CLI 进程检查通过。七份真实快照的全部小 limit 与全量排序参考结果对照；另测同体积数据库／二进制键／重复键的顺序、候选替换、不同长度键字典序、300 条合成记录、边界和非法参数。原生命令行还由 Python 解码 Base64，独立全量排序核对真实样本结果及 limit 子集，并验证失败时 stdout 为空。

完整检查为 `./scripts/ci.ps1`。本地检查不代表远端 Actions 已运行；F11 JSONL 导出已实现；F12 发布／独立消费者验收留待后续阶段。
