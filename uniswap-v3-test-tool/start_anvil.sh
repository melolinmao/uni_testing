#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}启动本地Anvil节点...${NC}"

# 设置网络参数
FORK_URL=${FORK_URL:-"https://mainnet.infura.io/v3/YOUR_INFURA_KEY"}
CHAIN_ID=1
BLOCK_NUMBER=16593278  # 使用特定区块以确保测试的一致性

# 启动anvil，配置为主网分叉模式
if ! command -v anvil &> /dev/null; then
    echo -e "${RED}错误: 找不到 anvil 命令${NC}"
    echo -e "${YELLOW}请安装 Foundry: https://getfoundry.sh${NC}"
    exit 1
fi

# 导出环境变量，让测试使用
export ANVIL_RPC_URL="http://localhost:8545"

# 在后台启动anvil节点
anvil --fork-url $FORK_URL \
      --chain-id $CHAIN_ID \
      --fork-block-number $BLOCK_NUMBER \
      --auto-impersonate \
      --port 8545 \
      --silent &

ANVIL_PID=$!

# 等待anvil启动
echo -e "${YELLOW}等待Anvil启动...${NC}"
sleep 2

# 检查anvil是否已启动
if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
    echo -e "${GREEN}Anvil节点已启动，正在运行于 http://localhost:8545${NC}"
    echo -e "${YELLOW}配置信息:${NC}"
    echo -e "  分叉链: 主网 (Ethereum Mainnet)"
    echo -e "  分叉区块: ${BLOCK_NUMBER}"
    echo -e "  链ID: ${CHAIN_ID}"
    echo -e ""
    echo -e "${YELLOW}使用 Ctrl+C 关闭节点${NC}"
else
    echo -e "${RED}错误: Anvil节点启动失败${NC}"
    kill $ANVIL_PID
    exit 1
fi

# 监听Ctrl+C信号以清理进程
trap "echo -e '\n${YELLOW}正在关闭Anvil节点...${NC}'; kill $ANVIL_PID; echo -e '${GREEN}已关闭!${NC}'; exit 0" INT

# 保持脚本运行
wait $ANVIL_PID 