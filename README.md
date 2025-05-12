# Uniswap V3 测试工具

![测试状态](https://github.com/yourusername/uniswap-v3-test-tool/workflows/Uniswap%20V3%20测试工具%20CI/badge.svg)
![代码覆盖率](https://github.com/yourusername/uniswap-v3-test-tool/workflows/代码覆盖率分析/badge.svg)
![安全审计](https://github.com/yourusername/uniswap-v3-test-tool/workflows/智能合约安全审计/badge.svg)

## 项目简介

这是一个针对Uniswap V3协议的测试工具集，用于验证和测试Uniswap V3合约的各种功能。

主要功能包括：

- 模拟测试流动性功能（添加、移除流动性）
- 模拟测试交换功能（精确输入、精确输出、滑点保护）
- 测试不变量条件（恒定乘积、价格-tick映射）
- 模糊测试各种边界条件
- 静态分析安全性问题

## 项目结构

```
uniswap-v3-test-tool/
├── core_suite/              # 测试套件核心目录
│   ├── tests/               # 测试用例文件
│   ├── run_tests.sh         # 测试运行脚本
│   ├── run_slither.sh       # Slither静态分析脚本
│   ├── coverage.sh          # 代码覆盖率分析脚本
│   └── .slither.config.json # Slither配置
├── .github/                 # GitHub配置
│   └── workflows/           # GitHub Actions工作流配置
│       ├── test.yml         # 测试工作流
│       ├── coverage.yml     # 覆盖率工作流 
│       └── audit.yml        # 安全审计工作流
└── README.md                # 项目说明文档
```

## 测试用例说明

- **SimpleInvariantTest.t.sol**: 测试各种不变量条件
- **SimpleMockSwapTest.t.sol**: 模拟测试交换功能
- **SimpleMockLiquidityTest.t.sol**: 模拟测试流动性管理
- **FuzzPoolTest.t.sol**: 针对池合约的模糊测试
- **SecurityTest.t.sol**: 安全性和异常情况测试

## 运行测试

安装依赖:

```bash
forge install
```

运行测试:

```bash
cd core_suite
./run_tests.sh
```

运行特定测试:

```bash
cd core_suite
./run_tests.sh SimpleMockSwapTest.t.sol
```

运行Slither分析:

```bash
cd core_suite
./run_slither.sh -a
```

生成覆盖率报告:

```bash
cd core_suite
./coverage.sh
```

## GitHub Actions工作流

项目配置了多个自动化工作流:

1. **测试工作流 (test.yml)**
   - 在代码推送和PR时自动运行测试
   - 使用Forge测试框架执行所有测试
   - 同时运行Slither静态分析

2. **覆盖率工作流 (coverage.yml)**
   - 生成代码覆盖率报告
   - 上传覆盖率结果作为构建产物
   - 将覆盖率报告发布到GitHub Pages

3. **安全审计工作流 (audit.yml)**
   - 定期(每周一)运行安全审计
   - 使用Slither和Mythril分析合约
   - 生成综合安全报告
   - 发现高危问题时自动创建Issue

## 功能特性

- **Foundry "CoreSuite" 合约级测试**：使用Foundry进行高性能的Solidity单元测试，覆盖mint、burn、swapExactIn、swapExactOut等核心函数
- **静态安全扫描**：集成Slither进行自动化安全漏洞检测
- **Swap-Flow 端到端流程测试**：通过Behave和Python自动化测试完整的Uniswap交互流程
- **轻量级负载测试**：基于Python asyncio实现的并发交易测试
- **时间模拟测试**：通过EVM时间操作测试长时间运行的合约行为
- **监控与可视化**：Prometheus + Grafana实时监控与指标展示
- **CI/CD一体化工作流**：通过GitHub Actions实现自动化测试与部署

## 快速开始

### 前提条件

- Python 3.8+
- Foundry (包含 Forge, Anvil, Cast)
- Docker & Docker Compose (用于Prometheus和Grafana)
- 以太坊RPC节点URL (Infura/Alchemy或本地节点)

### 安装

1. 克隆仓库
   ```bash
   git clone https://github.com/yourusername/uniswap-v3-test-tool.git
   cd uniswap-v3-test-tool
   ```

2. 安装依赖
   ```bash
   pip install -e .
   ```

3. 配置环境
   ```bash
   cp config/default.yaml config/local.yaml
   # 编辑local.yaml设置您的RPC URL和其他配置
   ```

### 运行测试

**运行所有测试**：
```bash
python scripts/run_all.py
```

**只运行合约测试**：
```bash
cd core_suite
forge test
```

**只运行E2E测试**：
```bash
cd e2e
behave
```

**只运行负载测试**：
```bash
cd e2e
behave -i load_test.feature
```

## 目录结构

```
uniswap-v3-test-tool/                # 根目录
├── README.md                       # 项目简介、快速上手、功能列表
├── pyproject.toml                  # Python 项目元数据、依赖配置
├── docker-compose.yml              # 启动 Anvil、Prometheus、Grafana 等服务
├── config/                         # 全局配置
│   ├── default.yaml                # 默认配置（RPC、私钥、指标端口等）
│   └── local.yaml                  # 本地开发覆盖配置
├── core_suite/                     # Foundry 合约测试模块
│   ├── contracts/                  # Solidity 合约源码（Forked 或本地）
│   ├── tests/                      # Foundry 测试 Case (.t.sol)
│   └── scripts/                    # Foundry 脚本（fuzz, spamSwaps）
├── e2e/                            # Swap-Flow E2E 测试模块
│   ├── features/                   # Behave Feature 文件
│   │   ├── core_suite.feature      # CoreSuite 校验场景（可选）
│   │   ├── swap_flow.feature       # 添加流动性、swap、移除流动性
│   │   ├── load_test.feature       # 轻量负载测试场景
│   │   └── time_warp.feature       # Time-Warp Chaos 加分场景
│   ├── steps/                      # Behave Steps 实现
│   │   ├── core_suite_steps.py
│   │   ├── swap_flow_steps.py
│   │   ├── load_test_steps.py
│   │   └── time_warp_steps.py
│   └── environment.py             # Behave 钩子（启动/停止 Anvil、Prometheus 等）
├── metrics/                        # Prometheus 指标导出器
│   └── exporter.py                 # prometheus_client HTTP exporter 实现
├── scripts/                        # Python "胶水层" 管理脚本
│   ├── run_all.py                  # 启动服务、执行 CoreSuite、Behave、Load Test 并收集报告
│   ├── generate_report.py          # 解析覆盖率、延迟数据，生成综合报告
│   └── deploy_dashboard.py         # 自动导入 Grafana Dashboard
└── ci/                             # CI/CD 配置
    └── github_actions.yml         # GitHub Actions Workflow 定义
```

## 报告与指标

测试执行后，您可以在以下位置找到报告：

- **Foundry 测试报告**: `./core_suite/out/report.json`
- **覆盖率报告**: `./core_suite/coverage/`
- **Behave 测试报告**: `./e2e/reports/`
- **性能指标**: http://localhost:3000 (Grafana Dashboard)

## 贡献指南

欢迎提交问题和PR！

1. Fork本仓库
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交您的更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开Pull Request

## 许可证

本项目采用 MIT 许可证 - 详情请参见 [LICENSE](LICENSE) 文件

## 环境设置

1. 确保已安装Docker和Docker Compose
2. 启动本地Anvil节点:

```bash
cd ..  # 回到项目根目录
docker-compose up -d anvil
```

3. 复制环境变量文件并根据需要修改:

```bash
cp .env.example .env
```

## 运行测试

使用以下命令运行所有测试:

```bash
forge test --fork-url http://localhost:8545 -vv
```

或者使用环境变量:

```bash
export ANVIL_RPC_URL=http://localhost:8545
forge test -vv
```

## 运行负载测试

使用以下命令运行交换负载测试:

```bash
export ANVIL_RPC_URL=http://localhost:8545
export SWAP_ROUNDS=100
forge script scripts/spamSwaps.s.sol -vv
```

## 覆盖率统计

使用以下命令生成覆盖率报告:

```bash
forge coverage --include-libs --fork-url http://localhost:8545
```

## 说明

1. 所有测试默认使用本地Anvil节点的主网分叉环境
2. 测试使用`vm.envOr("ANVIL_RPC_URL", string("http://localhost:8545"))`获取RPC URL
3. 可以设置环境变量`ANVIL_RPC_URL`来自定义Anvil节点URL

