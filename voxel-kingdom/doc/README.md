# Voxel Kingdom 文档索引

> 更新：2026-10-15 · 第一阶段本机/局域网版本已实施，已追加公网 IP HTTPS/WSS 部署。

| 范围 | 玩法文档 | 技术文档 |
| --- | --- | --- |
| 完整目标 | [完整玩法流程](game-design-overview.md) | [完整技术文档](technical-overview.md) |
| 第一阶段 | [玩法与验证](stage-01-gameplay.md) | [技术实施计划](stage-01-implementation.md) |

玩法文档描述玩家流程和可观察结果；技术文档集中描述架构、格式、接口、渲染、网络和实现检查。原 `game-design-overview.md` 已简化为完整玩法文档，技术内容迁入 `technical-overview.md`。

第一阶段确定范围：Compatibility、上帝视角、DeepSeek 每次调用附带规则、服务器验证命令、自定义体素形状与逐方块颜色、己方建筑操作、多人连接和网页验证。暂不加入移动单位与战斗。

后续阶段只保留路线方向，开始该阶段时新增成对的玩法与技术文档。当前已完成第一阶段实施，提供运行说明与完成验收报告。

文档中的具体容量与性能数字均为初始提案，实施时先验证再调整；功能和协议不应被理解为已经可用。

- [第一阶段完成情况与验收报告](stage-01-completion-report.md)

- [运行与接口说明](stage-01-operation.md)

- [项目启动说明](../README.md)

## 公网 IP 部署补充

- [逐批修改与结果记录](public-ip-deployment-log.md)
- [公网使用与维护](public-ip-operation.md)
- [公网完成情况与验收报告](public-ip-acceptance-report.md)
- [刷新登录恢复与场景缓存分析](refresh-session-cache-analysis.md)
- [体素传输格式与数据量分析](voxel-protocol-size-analysis.md)
- [会话恢复、传输优化与分项目实施方案](session-sync-project-plan.md)
- [自动恢复与同步优化逐批实施记录](session-sync-implementation-log.md)
- [自动恢复、同步优化与分项目验收报告](session-sync-completion-report.md)
