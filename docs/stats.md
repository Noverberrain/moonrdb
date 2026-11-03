# F9 stats：前缀、到期时间与体积

从仓库根目录运行：

```powershell
moon run cmd/main --target native -- stats fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb
moon run cmd/main --target native -- stats fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb --at 2100-01-01T00:00:00.123Z --prefix long- --prefix ""
```

stats 使用与 inspect 相同的完整解析、资源限制、只读文件和退出码约定；读取或解析失败时没有成功摘要。`--max-input-bytes` 同样可用。报表统计记录数量，不按键名去重，不删除到期记录。数据库／类型行按编号、类型名排序；只列有记录的分组。

## 体积

数据库／类型行包含键数、序列化字节数、带到期时间及永久键数。`record_bytes + global_overhead_bytes == file_bytes` 应使 `accounting_matches: true`。记录体积包括该记录的元信息、类型、键和值，使用原始压缩表示；文件头、AUX、数据库选择、EOF、CRC64 等计入全局开销。它不是 Redis RAM 占用。

## 前缀

`--prefix <text>` 按 UTF-8 编码后的字节匹配键开头，不解码或替换原始键。最多 64 个不同前缀，重复值为参数错误。空前缀匹配全部键，重复选项产生多行独立汇总；重叠前缀会重复计数，不能把所有前缀行加起来当作全文件总量。每行含匹配键数、序列化体积、到期／永久数量，不改变数据库／类型统计或体积核对。行顺序为参数顺序，前缀以转义的调试字符串输出，避免终端控制字符。

该功能是用户指定业务前缀的汇总，尚不自动发现或推断业务前缀。二进制前缀选项未实现。

## 指定时间与 TTL

只有传入 `--at` 才计算过期状态；默认输出 `expiry_evaluation: not_requested`，不读取系统当前时间。接受严格 UTC 格式 `YYYY-MM-DDTHH:MM:SSZ` 或 `YYYY-MM-DDTHH:MM:SS.sssZ`，年份 0001..9999；不接受时区偏移、闰秒或其他小数位数。日历日期按公历校验。输出 `at_ms` 为有符号 Unix 毫秒，支持 1970 年之前的时刻。

TTL 汇总覆盖全文件；无到期时间为 permanent，有到期时间且 `expires_at_ms <= at_ms` 为 expired。未来到期的记录按差值归入互斥区间：

| 输出 | TTL 区间 |
|---|---|
| ttl_le_1h | (0, 1小时] |
| ttl_1h_to_24h | (1小时, 24小时] |
| ttl_24h_to_7d | (24小时, 7天] |
| ttl_7d_to_30d | (7天, 30天] |
| ttl_gt_30d | 大于30天 |

所有 TTL 区间加 expired、permanent 应等于 keys。各档位是概览，可用于查看指定时刻附近的到期分布，不是精确到期时间的直方图。时间差使用有界的无符号运算处理完整 Int64 范围，不发生有符号减法溢出。`--at` 和 `--prefix` 只允许用于 stats，inspect 仍拒绝它们。

## 验证与范围

F9 交付时 Windows native：148 项 MoonBit 测试与 56 项 CLI 进程检查通过。覆盖真实快照的到期毫秒边界、前缀重叠／空匹配、Unicode 与二进制字节匹配、严格日期与闰年、TTL 所有区间端点、极端时间差、稳定默认结果和失败输出。完整检查为 `./scripts/ci.ps1`，不等于远端 Actions 已通过。

F9 已完成上述统计；F10 大键 TopN 已实现；F11 导出已实现；F12 发布／独立消费者验收尚待实现。
