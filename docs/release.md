# F12 发布准备

候选版本为 `Noverberrain/moonrdb@0.1.0`。支持范围为 Redis 7.2.5 生成的 RDB 格式 11 中列出的对象编码。已验证 Windows native。详见 [兼容矩阵](compatibility.md)。

```powershell
./scripts/ci.ps1
python -X utf8 scripts/test_consumer.py
moon publish --dry-run
```

独立消费者脚本从本地发布归档解包，在仓库外创建临时 `moon.work`，以独立模块导入 `Noverberrain/moonrdb@0.1.0` 并运行解析示例。该检查验证归档内容和公开接口。发布后需在无本地工作区覆盖的独立项目中从 Mooncakes 安装并重复验证。

F11 提交 `d4fa5b8` 的 [GitHub Actions](https://github.com/Noverberrain/moonrdb/actions/runs/41579005023) 已通过。本地发布预检返回 `202 Accepted`。发布状态为待授权。

演示可使用 README 的 inspect、stats、top、export 命令，依次查看完整性、到期分布、大键排名和 JSONL 记录。样本使用仓库内的合成数据快照。
