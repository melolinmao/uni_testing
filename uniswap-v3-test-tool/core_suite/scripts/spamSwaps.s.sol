// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Script.sol";
import "v3-core/contracts/UniswapV3Pool.sol";

contract SpamSwaps is Script {
    // Uniswap v3 USDC/WETH 0.3% 池合约地址
    address constant USDC_WETH_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    
    function run() external {
        // 使用本地Anvil节点进行主网分叉测试
        string memory forkRpc = vm.envOr("ANVIL_RPC_URL", string("http://localhost:8545"));
        vm.createSelectFork(forkRpc);
        
        UniswapV3Pool pool = UniswapV3Pool(USDC_WETH_POOL); // 使用主网上的实际池合约

        // 设置默认轮数为10，除非环境变量有指定
        uint256 rounds;
        try vm.envUint("SWAP_ROUNDS") returns (uint256 value) {
            rounds = value;
        } catch {
            rounds = 10; // 默认值
        }
        
        // 限制最大轮数为100，避免过长时间运行
        if (rounds > 100) {
            console.log("限制轮数从", rounds, "到 100");
            rounds = 100;
        }
        
        console.log("开始执行", rounds, "轮交换");
        
        for (uint256 i = 0; i < rounds; i++) {
            // 每10轮输出一次状态
            if (i % 10 == 0 || i == rounds - 1) {
                console.log("完成交换轮数:", i);
            }
            
            // 执行交换
            try this.performSwap(pool) {
                // 交换成功
            } catch {
                // 如果交换失败，记录并跳过
                console.log("交换失败:", i);
                continue;
            }
        }
        
        console.log("所有交换完成");
    }
    
    // 分离交换逻辑，便于try-catch处理异常
    function performSwap(UniswapV3Pool pool) external {
        pool.swap(address(this), true, 1 ether, 0, bytes(""));
    }
}
