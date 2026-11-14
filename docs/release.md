# MoonRDB 0.2.0 发布准备

Mooncakes 上的已发布版本为 `Noverberrain/moonrdb@0.1.0`。当前源码的候选版本为 `0.2.0`。支持范围见 [Redis 7.2.5／RDB 11 兼容矩阵](compatibility.md)。

## 相比 0.1.0 的变化

- `diff` 按数据库和原始键匹配两份快照，报告键的新增、删除、类型、内容、到期时间和序列化体积变化。[用法](diff.md)
- 解析 Redis 7.2.5 的 Stream listpacks 3 编码和 `FUNCTION2`。Stream 内容比较基于现存消息。函数库保存在 `Snapshot.function_libraries` 中。[兼容范围](compatibility.md#stream-与函数库)
- 校验现存 Stream 消息 ID 的严格递增顺序。

## 从 0.1.0 升级

穷举匹配 `RdbRecord` 和 `ParseError` 的代码需要处理新增的 `Stream` 和 `InvalidStream`。直接构造 `Snapshot` 的代码需要提供 `function_libraries`。使用 `parse` 的调用方可以从返回值获取该字段。

## 验证候选包

使用 CI 固定的 MoonBit 0.10.18 和 Windows native 工具链运行以下命令。

```powershell
./scripts/ci.ps1
python -X utf8 scripts/test_consumer.py
```

消费者脚本按 `moon.mod` 的版本创建归档。它在临时工作区通过 `moon.work` 引用解包后的模块，运行 String 示例，并验证真实 Stream 样本能通过公开 API 读取消息记录和函数库。发布后另在没有 `moon.work` 覆盖的独立项目中从 Mooncakes 安装并复查。
