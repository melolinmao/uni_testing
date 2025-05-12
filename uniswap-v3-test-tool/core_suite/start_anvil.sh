#!/bin/bash

# 设置默认的RPC URL
FORK_URL=${MAINNET_RPC_URL:-"https://eth-mainnet.g.alchemy.com/v2/HLxG7MT6fi-YGpW4zdupcUTlD6snFdvd"}
FORK_BLOCK=${FORK_BLOCK:-"17500000"}

echo "启动Anvil，分叉自: $FORK_URL，区块号: $FORK_BLOCK"

# 启动Anvil并分叉主网
anvil \
  --fork-url $FORK_URL \
  --fork-block-number $FORK_BLOCK \
  --chain-id 1337 \
  --block-time 2 \
  --host 0.0.0.0 \
  --port 8545 