# 双快照对比

```powershell
moon run cmd/main --target native -- diff yesterday.rdb today.rdb --db 0 --prefix user: --limit 20
```

两个文件均需完整解析。命令按数据库编号和原始键字节匹配，支持数据库与 UTF-8 前缀交集过滤。匹配范围内的重复键视为歧义并报错。

摘要统计新增、删除、已有键的类型、序列化体积、内容和到期时间变化。各项计数可以重叠。明细按体积增量降序排列，同增量按数据库与 Base64 键排序。新增或删除的一侧显示类型 `-` 和 0 字节。默认显示 20 行，limit 范围 1..10000，仅限制明细。

体积来自快照记录区间。同类型记录按解码后的值比较内容。String 比较原始字节，List 保留元素顺序，Hash、Set 和 Sorted Set 按字段或成员匹配。到期时间按快照存储的绝对毫秒比较，永久键与带到期时间的键也能区分。明细用 content_changed 和 expiry_changed 标记变化。每份输入默认上限 64 MiB，可用 `--max-input-bytes` 调整。当前实现保留两份解码结果，并排序变更明细。两个文件的校验状态分别报告，任一文件失败时退出非零且不输出报告。

明细字段 `before_expiry_ms` 和 `after_expiry_ms` 显示绝对 Unix 毫秒。永久键显示 `persistent`，缺少记录的一侧显示 `-`。

## 机器可读输出与分组

```powershell
moon run cmd/main --target native -- diff yesterday.rdb today.rdb --format jsonl --group-by-db --group-prefix user: --group-prefix order: --limit 20
```

默认输出文本。传入 --format jsonl 后，第一行是带 moonrdb.diff.v1 schema 的 summary，随后是可选的 group 行和按原有顺序排列的 change 行，最后一行是 kind 为 complete 的对象。两个快照均完整解析后才输出。数据库编号、字节数、增量和到期毫秒使用字符串，键使用 Base64。缺失的一侧使用 null 表示类型和到期时间，永久键的到期状态为 persistent。消费端应同时检查退出码和 complete 行。

--group-by-db 按数据库编号汇总有变化的键。--group-prefix 可重复指定最多 64 个互异的 UTF-8 前缀，空前缀匹配全部键。前缀组按参数顺序输出，零匹配也有一行。重叠前缀独立累计，同一个键可计入多个前缀组。

分组受 --db 和 --prefix 过滤约束，每组报告变化键数及这些键的前后序列化字节数和净增量。新增或删除只计存在的一侧。--limit 仅限制 change 行，摘要与分组覆盖筛选范围内的全部变化。Stream 内容对比使用现存消息，消费组与投递状态可通过 export 查看。
