# 兼容矩阵（F2）

当前完成工程骨架、底层读取和支持范围内的空库完整解析，**所有 RDB 键值对象解析项均未实现**。AUX 的普通与整数编码字符串可解码，LZF 尚不支持。

## 固定的格式依据

- Redis 产品版本：7.2.5；上游提交：`f60370ce28b946c1146dcea77c9c399d39601aaa`。
- RDB 文件格式版本：11，文件头为 `REDIS0011`。
- [rdb.h](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.h#L36-L105)：版本、长度、编码与操作码定义。
- [rdb.c 的 rdbSaveObjectType](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c#L661-L700)：此版本保存对象时选择的编码。
- [rdbSaveInfoAuxFields](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c#L1193-L1216) 与 [rdbSaveRio](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/rdb.c#L1376-L1414)：辅助字段、文件头、EOF 和校验和。
- [crc64.c](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/src/crc64.c)：CRC64 参数与公开校验向量依据；F2 已独立实现并用真实快照验证。

以下标记是 RDB 文件中的数值，不是 Redis 内存对象编码编号。计划支持不等于已经支持。

## 对象编码

| 逻辑类型 | RDB 标记 | 保存表示 / 上游依据 | 计划 | 当前解析 / 真实对象样本 |
|---|---|---|---|---|
| String | 0 | STRING；rdbSaveObjectType / rdbSaveObject | F3 | 未实现 / 无 |
| Hash | 4 | HASH，普通键值对 | F4 | 未实现 / 无 |
| Hash | 16 | HASH_LISTPACK | F4 | 未实现 / 无 |
| List | 18 | LIST_QUICKLIST_2；节点区分 plain / packed，packed 为 listpack | F5 | 未实现 / 无 |
| Set | 2 | SET，普通元素序列 | F6 | 未实现 / 无 |
| Set | 11 | SET_INTSET | F6 | 未实现 / 无 |
| Set | 20 | SET_LISTPACK | F6 | 未实现 / 无 |
| Sorted Set | 5 | ZSET_2，二进制 double 分值 | F7 | 未实现 / 无 |
| Sorted Set | 17 | ZSET_LISTPACK | F7 | 未实现 / 无 |
| Stream | 21 | STREAM_LISTPACKS_3，此版本的保存分支 | 首版范围外 | 未实现 / 无 |
| Module | 7 | MODULE_2，此版本的保存分支 | 首版范围外 | 未实现 / 无 |
| 历史表示 | 1、3、6、9、10、12、13、14、15、19 | 上游加载器仍有分支：LIST、ZSET、MODULE_PRE_GA、ZIPMAP、ZIPLIST、QUICKLIST、旧 STREAM | 首版不承诺 | 未实现 / 无 |

F1 已验证 6 / 14 / 32 / 64 位长度和 INT8 / INT16 / INT32 / LZF 标记识别，以及独立的有符号整数读取。编码字符串的完整解码与 LZF 解压仍留待 F3；不能据此宣称支持 String 对象。读取规则与测试边界见 [reader.md](reader.md)。

## 文件结构

| 内容 | 标记 / 定义 | 计划 | 当前状态 |
|---|---|---|---|
| 文件头 | `REDIS` + 四位格式版本 | F1 | 已实现；真实空库头部通过，格式仅接受 11 |
| AUX 辅助字段 | 250 | F2 | 普通／整数编码已实现且真实样本通过；LZF 留待 F3 |
| SELECTDB / RESIZEDB | 254 / 251 | F2 | 已实现，合成测试通过；空库不写这些操作码，暂无真实切换样本 |
| EXPIRETIME / EXPIRETIME_MS | 253 / 252 | F2 | 前置元信息已实现，合成测试通过；旧秒编码仅按小端解释；暂无真实对象样本 |
| IDLE / FREQ | 248 / 249 | F2 | 前置元信息已实现，合成测试通过；暂无真实对象样本 |
| EOF 与 CRC64 | 255 + 8 字节校验和 | F2 | 两份真实空库完整通过；有效与关闭状态可区分，损坏／截断被拒绝 |
| FUNCTION2 / FUNCTION_PRE_GA / MODULE_AUX | 245 / 246 / 247 | 首版范围外 | 未实现；暂无样本 |

样本来源、SHA256 和复现方式见 [fixtures/README.md](../fixtures/README.md)。Python 离线验证只核对样本身份和固定边界；MoonBit 测试完整解析两份真实空库，检查 CRC64 或关闭状态。完整边界见 [empty-snapshot.md](empty-snapshot.md)。

## 工具链与执行环境

F0 在 Windows x64、`moonc 0.10.18+6c83a7f62`、`moon 0.1.20261028` 下验证 native 后端。CI 固定同版本编译器与 core，归档 SHA256 写在安装脚本中。未验证其他后端或 Linux / macOS 构建。
