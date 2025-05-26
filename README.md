# Uniswap V3测试工具

这是一个用于测试Uniswap V3合约和相关DApp功能的工具。该工具通过与Uniswap V3 Subgraph集成，提供了用户友好的界面来可视化和测试Uniswap生态系统中的关键数据和交互。

## 功能

- 可视化顶级流动性池的总锁定量(TVL)和24小时交易量
- 分页显示代币列表，包含价格点、价格变化和TVL
- 分页显示交易历史，包含总价值、代币数量、链接账户和时间
- 支持手动刷新数据
- 直观的数据可视化图表和表格

## 技术栈

- React.js - 前端框架
- Apollo Client - GraphQL客户端
- Chart.js - 数据可视化
- Material UI - UI组件库
- Ethers.js - 以太坊交互

## 安装与使用

### 前提条件

- Node.js (v16+)
- npm 或 yarn

### 安装步骤

1. 克隆仓库
```bash
git clone https://github.com/yourusername/uni_testing.git
cd uni_testing
```

2. 安装依赖
```bash
npm install
# 或
yarn install
```

3. 启动开发服务器
```bash
npm start
# 或
yarn start
```

4. 在浏览器中访问 `http://localhost:3000`

## 项目结构

```
uni_testing/
├── public/                 # 静态文件
├── src/                    # 源代码
│   ├── components/         # React组件
│   │   ├── Dashboard/      # 仪表盘组件
│   │   ├── Pools/          # 流动性池组件
│   │   ├── Tokens/         # 代币组件
│   │   ├── Transactions/   # 交易组件
│   │   └── charts/         # 图表组件
│   ├── graphql/            # GraphQL查询
│   ├── utils/              # 工具函数
│   ├── App.jsx             # 主应用组件
│   └── index.js            # 入口文件
├── .env                    # 环境变量
├── package.json            # 项目依赖
└── README.md               # 项目文档
```

## 资源

- [Uniswap V3 Subgraph API](https://thegraph.com/hosted-service/subgraph/uniswap/uniswap-v3)
- [Uniswap Documentation](https://docs.uniswap.org/)
- [React Documentation](https://reactjs.org/docs/getting-started.html)

## 使用本地Anvil进行测试

### 步骤1：配置环境变量

首先复制环境变量模板并填入您的主网RPC URL：

```bash
cd core_suite
cp .env.example .env
# 编辑.env文件，填入您的MAINNET_RPC_URL
```

### 步骤2：启动本地Anvil

打开一个新的终端窗口，运行以下命令启动Anvil：

```bash
cd core_suite
./start_anvil.sh
```

这将启动一个本地Anvil节点，分叉自以太坊主网。

### 步骤3：运行测试

在另一个终端窗口中，运行测试：

```bash
cd core_suite
forge test --fork-url http://localhost:8545 -vv
```

或者使用环境变量模式：

```bash
export ANVIL_RPC_URL=http://localhost:8545
forge test -vv
```

### 步骤4：运行负载测试

```bash
cd core_suite
export ANVIL_RPC_URL=http://localhost:8545
export SWAP_ROUNDS=100
forge script scripts/spamSwaps.s.sol -vv
```

### 步骤5：生成覆盖率报告

```bash
cd core_suite
forge coverage --include-libs --fork-url http://localhost:8545
```

## 注意事项

1. 确保Anvil在运行测试时处于启动状态
2. 如果测试失败，请检查：
   - Anvil是否正常运行
   - MAINNET_RPC_URL是否有效
   - 是否有足够的请求配额
3. 所有测试默认使用本地Anvil节点的主网分叉环境
