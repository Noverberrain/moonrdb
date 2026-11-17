# MoonRDB 0.2.0

Mooncakes 已发布 `Noverberrain/moonrdb@0.2.0`，对应 GitHub 提交 `4c292f7`。支持范围见 [Redis 7.2.5／RDB 11 兼容矩阵](compatibility.md)。

## 相比 0.1.0 的变化

- `diff` 按数据库和原始键匹配两份快照，报告键的新增、删除、类型、内容、到期时间和序列化体积变化。[用法](diff.md)
- 解析 Redis 7.2.5 的 Stream listpacks 3 编码和 `FUNCTION2`。Stream 内容比较基于现存消息。函数库保存在 `Snapshot.function_libraries` 中。[兼容范围](compatibility.md#stream-与函数库)
- 校验现存 Stream 消息 ID 的严格递增顺序。

## 从 0.1.0 升级

穷举匹配 `RdbRecord` 和 `ParseError` 的代码需要处理新增的 `Stream` 和 `InvalidStream`。直接构造 `Snapshot` 的代码需要提供 `function_libraries`。使用 `parse` 的调用方可以从返回值获取该字段。

## 复验发布包

使用 CI 固定的 MoonBit 0.10.18 和 Windows native 工具链运行以下命令。

```powershell
./scripts/ci.ps1
python -X utf8 scripts/test_consumer.py --registry 0.2.0
```

已在没有本地工作区覆盖的独立项目中从 Mooncakes 下载 0.2.0，运行 String 示例，并用真实 Redis 7.2.5 混合快照验证 Stream 消息、FUNCTION2 和 DB 2 的普通键。省略 --registry 时，脚本会测试当前源码打包后的本地归档。

结构化 Stream 消费状态与 diff JSONL 分组属于发布后的源码扩展。
