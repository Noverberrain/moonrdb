# 真实快照样本（F0—F5）

`redis-7.2.5/empty.rdb` 是专用 Redis 7.2.5 实例执行 `SAVE` 的原始产物，未手工拼接或修改。

## 来源与身份

- 格式参考：Redis 7.2.5，上游提交 `f60370ce28b946c1146dcea77c9c399d39601aaa`，RDB 版本 11。
- 本次生成器：第三方 [redis-windows 7.2.5](https://github.com/redis-windows/redis-windows/releases/tag/7.2.5) 的 `Redis-7.2.5-Windows-x64-msys2.zip`，并非 Redis 官方 Windows 二进制发行版。
- [下载地址](https://github.com/redis-windows/redis-windows/releases/download/7.2.5/Redis-7.2.5-Windows-x64-msys2.zip)。下载后已核对发布页 SHA256：`be71a03d60d5719bacdad068ebbf22b17c6e7a125be42576a799406b2d058ca9`。
- [该构建的工作流](https://github.com/redis-windows/redis-windows/blob/ecccfc10d6cc40f5272299188b0de3797d2534fe/.github/workflows/ci-cron.yml) 从 Redis 官方 tag 下载源码，在 MSYS2 下编译，并修改启动图案和默认配置路径。这里记录源码依据和二进制来源，未声称自行验证该二进制与源码逐位一致。
- 大小：88 字节；SHA256：`3c870299286dd734f5d03f74ddf632467c55426c897f2999d776715a03aef092`。
- `manifest.json` 记录生成器版本、服务器二进制哈希、文件哈希和配置语义；`redis-check-rdb.txt` 是 Redis 自带工具的实际输出，确认 `Checksum OK` 和 `0 keys read`。

F2 新增 `redis-7.2.5-no-checksum/empty.rdb`，使用同一已核验 Windows 构建，以 `rdbchecksum no` 生成，仍为未修改的真实 SAVE 产物：88 字节，SHA256 为 `32f2a41679e6d1f6372958c03f378c9b956a2acb4cc092ffbb7b76815c5fb93e`。该目录单独保存 manifest 与 Redis 检查输出；后者明确报告 `checksum disabled: no check performed`、`0 keys read`，不能作为校验通过的证据。

F3 新增 `redis-7.2.5-strings/strings.rdb`，使用同一构建、开启压缩／校验和及 `allkeys-lru` 策略生成。463 字节，SHA256 为 `7182c11f636d36f690d3726ef9ee946f998684e55f829f4d61d4ce7840975181`。它包含 DB 0 / 2 的 15 个合成 String 键，覆盖普通、二进制、空值、三个整数编码、LZF 键与值、到期时间和 LRU 信息。`scripts/string_dataset.py` 是构造依据，`expected.json` 以 Base64 记录原始键值与绝对到期时间，其哈希另存 manifest。

String 生成流程在 SAVE 前核对键值，SAVE 后通过 `redis-check-rdb` 确认完整性，再启动第二个隔离进程加载同一文件，对所有键核对 GET 与 PEXPIRETIME。该流程验证真实持久化语义，MoonBit 测试另外检查解析结果及实际 RDB 编码；不能从 Redis 内存对象编码推断文件编码。

F4 新增 `redis-7.2.5-hashes/hashes.rdb`，502 字节，SHA256 为 `252fd1e57b9a5874298b869d2933cbea8a59fe12213f4a9af151e5613ebec440`。采用同一已核验构建，固定紧凑阈值为 4 个字段对／64 字节字段或值，使用 allkeys-lfu。8 个 Hash 覆盖小对象、超条目阈值、超字段／值长度阈值、普通与压缩 listpack、二进制／空字段、整数极值、到期时间；另有 1 个混合 String。构造依据是 `scripts/hash_dataset.py`；Base64 预期数据及其哈希保存在对应目录。

Hash 数据经过 SAVE、Redis 完整性检查、隔离重新加载与逐键 HLEN / HGET / GET / PEXPIRETIME 对照，现有样本也单独重新加载复核。MoonBit 再检查实际 RDB 编码、无序字段语义及记录体积。运行时 OBJECT ENCODING 只用于核对生成阈值效果，不能代替 RDB 类型验证。

F5 新增 `redis-7.2.5-lists/lists.rdb`，737 字节，SHA256 为 `83e7766b43309cad12db020388abc6005eea5935f1a2ce3a203cfb48af4c2214`，使用同一已核验 Windows 构建。含 DB 0 / 2 的 6 个 List 与 String / Hash 标记键，覆盖单／多节点、混合 plain / packed、LZF、顺序、重复与空元素、二进制、LRU 和到期时间。数据依据为 `scripts/list_dataset.py`，预期字节以 Base64 保存并记录哈希。

List 配置固定为 `list-max-listpack-size=2`、`list-compress-depth=1`。plain 默认需要很大的元素；小型真实 plain 样本是在专用回环实例中启用本地 DEBUG，并执行 `DEBUG QUICKLIST-PACKED-THRESHOLD 64` 生成，条件完整写在 manifest。它仍是 Redis SAVE 的未修改产物，不是手工拼接；未验证默认 1 GiB 阈值规模。第二个进程重新加载同一文件，按 LLEN / LINDEX 比较每个元素顺序，核对 String / Hash 标记及 PEXPIRETIME。细节见 [List 约定](../docs/lists.md)。

## 生成方法

下载、核对归档哈希并解压后，在仓库根目录运行（把路径换成实际位置）：

```powershell
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --output-dir .work/empty-regenerated
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --checksum disabled --output-dir .work/empty-no-checksum-regenerated
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --dataset strings --policy allkeys-lru --output-dir .work/strings-regenerated
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --dataset hashes --policy allkeys-lfu --output-dir .work/hashes-regenerated
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --dataset lists --policy allkeys-lru --output-dir .work/lists-regenerated
```

生成脚本使用 Python 标准库，不依赖 Python Redis 客户端。它启动临时实例，只绑定回环地址、使用随机端口及一次性密码，不安装服务，不连接已有 Redis，不执行 FLUSH。关键配置：16 个数据库、关闭定时保存和 AOF、开启 RDB 压缩，默认开启校验和，`--checksum disabled` 则关闭；`INFO keyspace` 确认空库后执行 `SAVE`，再调用同一套工具中的 `redis-check-rdb`。结束后清理实例和临时目录，已有输出目录会被拒绝覆盖。二进制需要 `redis-server` 和 `redis-check-rdb`；脚本也接受自行编译的 Linux Redis 7.2.5，但该路径尚未实测。

重新生成的 `ctime`、`used-mem` 等 AUX 字段可能不同，所以文件哈希不保证相同；重新生成用于重复语义验证，日常 CI 则核对已提交文件的固定哈希。两份空库覆盖校验开关，但不会覆盖对象编码、过期或数据库切换。

## 离线核验与许可

```powershell
python -X utf8 scripts/verify_fixtures.py
```

此检查对五份样本合计执行 36 项身份核验：文件大小、SHA256、头部、尾部、校验模式及预期数据等，不实现解析或 CRC64。MoonBit 的 `moon test --target native` 另外解析两份空库、String、混合 Hash 与混合 List 快照，验证语义、实际编码、元信息与校验状态；Redis 工具的原始输出也保留用于对照。

样本不含生产数据、密码或个人信息，作为本项目测试数据以 Apache-2.0 提供。仓库不分发 Redis 源码、Windows 工具或其动态库；Redis 7.2.5 的 [COPYING](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/COPYING) 单独适用。下载和重新分发第三方工具时应保留其各组件许可。
