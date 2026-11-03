# 兼容矩阵（F11）

通用 `parse` 支持文件结构、String、Hash、quicklist2 List、Set 与 Sorted Set。`parse_strings` 仍只接受 String；原 `parse_empty` 保留 F2 边界：拒绝对象及 AUX LZF。Stream、Module 等仍不支持。

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
| String | 0 | STRING；rdbSaveObjectType / rdbSaveObject | F3 | 已实现 / 真实普通、二进制、空值、INT8/16/32、LZF 键与值通过 |
| Hash | 4 | HASH，普通键值对 | F4 | 已实现 / 真实超条目阈值、长字段与长值样本通过 |
| Hash | 16 | HASH_LISTPACK | F4 | 已实现 / 真实紧凑 Hash、整数／二进制、LZF 容器样本通过 |
| List | 18 | LIST_QUICKLIST_2；节点区分 plain / packed，packed 为 listpack | F5 | 已实现 / 真实单／多节点、混合 plain / packed、二进制、空元素与 LZF 节点通过 |
| Set | 2 | SET，普通元素序列 | F6 | 已实现 / 真实超整数与 listpack 阈值、长成员样本通过 |
| Set | 11 | SET_INTSET | F6 | 已实现 / 真实 16 / 32 / 64 位有符号整数样本通过 |
| Set | 20 | SET_LISTPACK | F6 | 已实现 / 真实二进制、空成员、整数及 LZF 容器样本通过 |
| Sorted Set | 5 | ZSET_2，二进制 double 分值 | F7 | 已实现 / 真实二进制成员、分数边界、LZF 与元信息样本通过 |
| Sorted Set | 17 | ZSET_LISTPACK | F7 | 已实现 / 真实二进制成员、分数边界、LZF 与元信息样本通过 |
| Stream | 21 | STREAM_LISTPACKS_3，此版本的保存分支 | 首版范围外 | 未实现 / 无 |
| Module | 7 | MODULE_2，此版本的保存分支 | 首版范围外 | 未实现 / 无 |
| 历史表示 | 1、3、6、9、10、12、13、14、15、19 | 上游加载器仍有分支：LIST、ZSET、MODULE_PRE_GA、ZIPMAP、ZIPLIST、QUICKLIST、旧 STREAM | 首版不承诺 | 未实现 / 无 |

F1 的长度／整数测试保留。F3 已验证 String 完整解码、LZF 字面量与重叠／非重叠回引用、扩展长度、最大回溯距离，以及解压和累计解码预算。详情见 [strings.md](strings.md)。

F4 已验证 listpack 字符串长度表示、7 位无符号及 13 / 16 / 24 / 32 / 64 位有符号整数、总字节数、元素数（含未知计数 65535）、反向长度和 EOF。Hash 还检查配对、重复字段及资源限制；历史 zipmap / ziplist 不在支持范围。详见 [hashes.md](hashes.md)。

F5 复用 listpack 的头部与元素校验，但 List 允许奇数元素和重复值，严格保留顺序。节点数和元素数按整份快照累计限制。plain 的默认生成阈值为 1 GiB，本项目真实小样本通过隔离实例的官方 DEBUG 阈值命令构造，不宣称验证过 1 GiB 元素。历史 List 类型 1 / 10 / 14 不支持。详见 [lists.md](lists.md)。

F6 检查 Set 成员唯一性及全文件成员预算。intset 核对 2 / 4 / 8 字节宽度、精确总长度及严格有符号递增顺序；listpack 核对结构、计数和重复成员。三个表示共享解码字节预算，容器暂存单独受限。详见 [sets.md](sets.md)。

F7 支持二进制 double 与 listpack Sorted Set，核对配对、成员唯一性、NaN、紧凑顺序与全文件条目预算；不保证统一输出排序。详见 [sorted-sets.md](sorted-sets.md)。

## 文件结构

| 内容 | 标记 / 定义 | 计划 | 当前状态 |
|---|---|---|---|
| 文件头 | `REDIS` + 四位格式版本 | F1 | 已实现；真实空库头部通过，格式仅接受 11 |
| AUX 辅助字段 | 250 | F2/F3 | 普通／整数有真实样本；LZF 仅 parse_strings 支持，合成测试通过 |
| SELECTDB / RESIZEDB | 254 / 251 | F2/F3 | 合成测试与真实 DB 0 / 2 的 String 样本通过 |
| EXPIRETIME / EXPIRETIME_MS | 253 / 252 | F2/F3 | 毫秒时间有真实 String 样本；旧秒编码仅有小端合成测试 |
| IDLE / FREQ | 248 / 249 | F2/F3/F4 | IDLE 有真实 String 样本；FREQ 有真实 Hash 样本 |
| EOF 与 CRC64 | 255 + 8 字节校验和 | F2—F7 | 七份真实快照通过；有效与关闭状态可区分，损坏／截断被拒绝 |
| FUNCTION2 / FUNCTION_PRE_GA / MODULE_AUX | 245 / 246 / 247 | 首版范围外 | 未实现；暂无样本 |

样本来源、SHA256 和复现方式见 [fixtures/README.md](../fixtures/README.md)。Python 离线验证核对样本身份和预期数据；MoonBit 测试解析两份空库与五份有键快照，检查语义、实际编码及校验状态。

## 工具链与执行环境

F0 在 Windows x64、`moonc 0.10.18+6c83a7f62`、`moon 0.1.20261028` 下验证 native 后端。CI 固定同版本编译器与 core，归档 SHA256 写在安装脚本中。未验证其他后端或 Linux / macOS 构建。

## inspect CLI

F8 已实现 Windows native `inspect`，使用同一解析 API 检查整个文件并显示版本、数据库、键数和校验状态；参数和退出行为见 [inspect.md](inspect.md)。stats 已实现，含前缀汇总和指定时刻的 TTL 分布，见 [stats.md](stats.md)；top 已实现，见 [top.md](top.md)；export 已实现，见 [export.md](export.md)。解析库根包 API 保持 F7 不变，新增系统依赖仅位于 CLI 包。
