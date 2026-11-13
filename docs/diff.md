# 双快照对比

```powershell
moon run cmd/main --target native -- diff yesterday.rdb today.rdb --db 0 --prefix user: --limit 20
```

两个文件均需完整解析。命令按数据库编号和原始键字节匹配，支持数据库与 UTF-8 前缀交集过滤。匹配范围内的重复键视为歧义并报错。

摘要统计新增、删除、已有键的类型、序列化体积、内容和到期时间变化。各项计数可以重叠。明细按体积增量降序排列，同增量按数据库与 Base64 键排序。新增或删除的一侧显示类型 `-` 和 0 字节。默认显示 20 行，limit 范围 1..10000，仅限制明细。

体积来自快照记录区间。同类型记录按解码后的值比较内容。String 比较原始字节，List 保留元素顺序，Hash、Set 和 Sorted Set 按字段或成员匹配。到期时间按快照存储的绝对毫秒比较，永久键与带到期时间的键也能区分。明细用 content_changed 和 expiry_changed 标记变化。每份输入默认上限 64 MiB，可用 `--max-input-bytes` 调整。当前实现保留两份解码结果，并排序变更明细。两个文件的校验状态分别报告，任一文件失败时退出非零且不输出报告。

明细字段 `before_expiry_ms` 和 `after_expiry_ms` 显示绝对 Unix 毫秒。永久键显示 `persistent`，缺少记录的一侧显示 `-`。
