# F8 inspect CLI

`inspect` 使用通用 `parse` 完整读取支持矩阵内的 RDB 格式 11 快照。它检查所有对象、EOF、尾随数据及 CRC64；遇到不支持的对象或版本会失败，不跳过未知内容。输出是面向人的文本摘要，尚未承诺稳定的机器协议。支持范围见 [兼容矩阵](compatibility.md)。

## 可复制命令

从仓库根目录运行：

```powershell
moon run cmd/main --target native -- --help
moon run cmd/main --target native -- inspect fixtures/redis-7.2.5-sorted-sets/sorted-sets.rdb
moon run cmd/main --target native -- inspect fixtures/redis-7.2.5-no-checksum/empty.rdb
moon run examples/parse --target native
```

第二条命令的实际摘要：

```text
MoonRDB inspect
format_version: 11
file_bytes: 486
keys: 8
aux_fields: 5
databases: 2
db 0: keys=5
db 2: keys=3
checksum: valid (CRC64)
status: complete
```

关闭校验和的样本输出 `checksum: disabled (CRC64 not validated)`，结构成功仍以 0 退出，不能视为 CRC64 已验证。数据库按编号升序列出，保留被 SELECTDB 选中过的空数据库；第一条 SELECTDB 前的记录属于 DB 0。没有选择或对象的空库显示 0 个数据库。`keys` 统计解析记录数，不按键名去重，也不按当前时间过滤过期记录。AUX 仅输出数量，原始键、值、AUX 内容和路径均不打印，避免二进制替换和终端控制字符泄漏。

构建后可直接运行原生程序；直接调用时能获得程序自己的精确退出码：

```powershell
moon build --target native
& './_build/native/debug/build/cmd/main/main.exe' inspect './fixtures/redis-7.2.5/empty.rdb'
$LASTEXITCODE
```

`main.exe` 是当前构建产物名，尚未安装为系统命令 `moonrdb`。最小库示例位于 [examples/parse/main.mbt](../examples/parse/main.mbt)，只导入解析库并接收内置 Bytes；它不依赖文件系统或 CLI。该示例在仓库内构建验证，不能替代 F12 的独立消费项目验收。

## 参数与文件限制

```text
moonrdb inspect <file.rdb> [--max-input-bytes <bytes>]
moonrdb inspect --max-input-bytes <bytes> -- <file.rdb>
moonrdb --help
```

只接受一个文件；未知命令、未知选项、多文件、重复大小选项及缺少参数均为参数错误。输入上限为严格正十进制整数，范围 1..2147483647，默认 67108864（64 MiB），不接受符号、下划线、小数或十六进制。选项可在文件名前或后，`--` 终止选项解析，用于以 `-` 开头的文件名；路径含空格时应加引号。不接受标准输入 `-`。

仅支持普通文件（允许指向普通文件的符号链接），使用只读句柄；打开前检查类型，打开后再次检查，并在分配输入前读取句柄大小、核对上限。精确读取该大小后探测额外字节，发现增长则失败；读取时缩短会作为读取错误处理。未承诺对并发修改提供原子快照，应输入稳定的快照副本；同长度变更也无法仅通过大小检测确认。这是有界整文件读取，仍持有完整输入及所有解码记录，不是流式解析或进程总内存限额。

CLI 目前只开放输入大小调整；其他库限制维持默认值：单个字符串 1 MiB，解码字节累计 64 MiB，元信息 4096，记录 100000，Hash 条目每对象 100000，List 节点／元素全文件各 100000，Set 成员和 Sorted Set 条目全文件各 100000，单个紧凑容器 4 MiB。相关语义见各类型文档。增大输入上限不会自动提高解码或容器预算。

## 输出和退出

| 退出码 | 意义 | 输出 |
|---|---|---|
| 0 | 帮助，或完整解析成功 | stdout；解析成功最后有 `status: complete` |
| 1 | 读取、输入上限、格式、不支持项、资源限制、校验或输出错误 | stderr；不报告成功 |
| 2 | 参数错误 | stderr 参数提示及用法 |

格式错误保留 `ParseError` 类型及零基字节偏移。路径／权限等读取错误输出通用提示，不回显原始文件名。解析完成之前不向 stdout 写摘要；完整摘要生成后才写出。输出设备故障可能留下无法撤回的前缀，但进程仍失败；不能仅凭已有前缀认定成功。`moon run` 本身可能调整子程序的失败退出码，自动化应直接运行构建产物。

## 验证

Windows native：142 项 MoonBit 测试（含 7 项文档测试）；新增 7 项覆盖参数、溢出、数据库列表、空库、隐式 DB 0、二进制不展示及真实快照摘要。`scripts/test_cli.py` 另做 37 项真实进程检查，断言 stdout、stderr 和退出码，覆盖七份真实快照、关闭校验和、损坏／截断、未知版本／对象／操作码、尾随数据、读取失败、目录、输入上限边界、超过默认上限文件、中文／空格／短横线文件名，以及从临时工作目录运行最小库示例。

完整检查已接入 `scripts/ci.ps1`；不把本地运行结果当作远端 Actions 或其他系统验收。F9 stats、F10 top、F11 export 和 F12 发布／独立消费验证留待后续阶段。
