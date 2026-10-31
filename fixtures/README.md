# 真实空库样本（F0 / F2）

`redis-7.2.5/empty.rdb` 是专用 Redis 7.2.5 实例执行 `SAVE` 的原始产物，未手工拼接或修改。

## 来源与身份

- 格式参考：Redis 7.2.5，上游提交 `f60370ce28b946c1146dcea77c9c399d39601aaa`，RDB 版本 11。
- 本次生成器：第三方 [redis-windows 7.2.5](https://github.com/redis-windows/redis-windows/releases/tag/7.2.5) 的 `Redis-7.2.5-Windows-x64-msys2.zip`，并非 Redis 官方 Windows 二进制发行版。
- [下载地址](https://github.com/redis-windows/redis-windows/releases/download/7.2.5/Redis-7.2.5-Windows-x64-msys2.zip)。下载后已核对发布页 SHA256：`be71a03d60d5719bacdad068ebbf22b17c6e7a125be42576a799406b2d058ca9`。
- [该构建的工作流](https://github.com/redis-windows/redis-windows/blob/ecccfc10d6cc40f5272299188b0de3797d2534fe/.github/workflows/ci-cron.yml) 从 Redis 官方 tag 下载源码，在 MSYS2 下编译，并修改启动图案和默认配置路径。这里记录源码依据和二进制来源，未声称自行验证该二进制与源码逐位一致。
- 大小：88 字节；SHA256：`3c870299286dd734f5d03f74ddf632467c55426c897f2999d776715a03aef092`。
- `manifest.json` 记录生成器版本、服务器二进制哈希、文件哈希和配置语义；`redis-check-rdb.txt` 是 Redis 自带工具的实际输出，确认 `Checksum OK` 和 `0 keys read`。

F2 新增 `redis-7.2.5-no-checksum/empty.rdb`，使用同一已核验 Windows 构建，以 `rdbchecksum no` 生成，仍为未修改的真实 SAVE 产物：88 字节，SHA256 为 `32f2a41679e6d1f6372958c03f378c9b956a2acb4cc092ffbb7b76815c5fb93e`。该目录单独保存 manifest 与 Redis 检查输出；后者明确报告 `checksum disabled: no check performed`、`0 keys read`，不能作为校验通过的证据。

## 生成方法

下载、核对归档哈希并解压后，在仓库根目录运行（把路径换成实际位置）：

```powershell
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --output-dir .work/empty-regenerated
python -X utf8 scripts/generate_empty_fixture.py --redis-bin 'C:/tools/Redis-7.2.5-Windows-x64-msys2' --checksum disabled --output-dir .work/empty-no-checksum-regenerated
```

生成脚本使用 Python 标准库，不依赖 Python Redis 客户端。它启动临时实例，只绑定回环地址、使用随机端口及一次性密码，不安装服务，不连接已有 Redis，不执行 FLUSH。关键配置：16 个数据库、关闭定时保存和 AOF、开启 RDB 压缩，默认开启校验和，`--checksum disabled` 则关闭；`INFO keyspace` 确认空库后执行 `SAVE`，再调用同一套工具中的 `redis-check-rdb`。结束后清理实例和临时目录，已有输出目录会被拒绝覆盖。二进制需要 `redis-server` 和 `redis-check-rdb`；脚本也接受自行编译的 Linux Redis 7.2.5，但该路径尚未实测。

重新生成的 `ctime`、`used-mem` 等 AUX 字段可能不同，所以文件哈希不保证相同；重新生成用于重复语义验证，日常 CI 则核对已提交文件的固定哈希。两份空库覆盖校验开关，但不会覆盖对象编码、过期或数据库切换。

## 离线核验与许可

```powershell
python -X utf8 scripts/verify_fixtures.py
```

此检查对两份样本合计执行 12 项身份核验：文件大小、SHA256、头部、尾部与校验模式等，不实现解析或 CRC64。MoonBit 的 `moon test --target native` 另外执行完整无对象快照解析，并验证启用样本的 CRC64 与关闭样本的状态；Redis 工具的原始输出也保留用于对照。

样本不含生产数据、密码或个人信息，作为本项目测试数据以 Apache-2.0 提供。仓库不分发 Redis 源码、Windows 工具或其动态库；Redis 7.2.5 的 [COPYING](https://github.com/redis/redis/blob/f60370ce28b946c1146dcea77c9c399d39601aaa/COPYING) 单独适用。下载和重新分发第三方工具时应保留其各组件许可。
