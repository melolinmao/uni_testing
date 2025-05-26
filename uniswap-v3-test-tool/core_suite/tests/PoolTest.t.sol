// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/UniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";

/**
 * @title UniswapV3Pool 核心功能单元测试
 */
contract PoolTest is Test {
    // 使用主网上已部署的池合约
    address constant USDC_WETH_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    UniswapV3Pool pool;
    
    function setUp() public {
        // 使用本地Anvil节点进行主网分叉测试
        // 注意：需要先启动docker-compose中的anvil服务
        string memory forkRpc = vm.envOr("ANVIL_RPC_URL", string("http://localhost:8545"));
        vm.createSelectFork(forkRpc);
        
        // 获取已部署的池合约实例
        pool = UniswapV3Pool(USDC_WETH_POOL);
        
        // 输出一些信息
        console.log("Pool address: ", address(pool));
        console.log("Token0: ", pool.token0());
        console.log("Token1: ", pool.token1());
        console.log("Fee: ", uint256(pool.fee()));
    }

    // 测试获取池信息
    function testPoolInfo() public {
        // 验证池合约信息
        assertTrue(address(pool) != address(0));
        assertTrue(pool.token0() != address(0));
        assertTrue(pool.token1() != address(0));
        
        // 获取当前价格
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        console.log("Current sqrtPriceX96: ", uint256(sqrtPriceX96));
        console.log("Current tick: ", int256(tick));
        
        // 获取当前流动性
        uint128 liquidity = pool.liquidity();
        console.log("Current liquidity: ", uint256(liquidity));
        assertTrue(liquidity > 0);
    }
    
    // 测试查询tick数据
    function testTickInfo() public {
        // 获取当前tick
        (, int24 currentTick, , , , , ) = pool.slot0();
        
        // 查询当前tick的信息
        (uint128 liquidityGross, int128 liquidityNet, , , , , , ) = pool.ticks(currentTick);
        console.log("Current tick: ", int256(currentTick));
        console.log("Current tick liquidity gross: ", uint256(liquidityGross));
        console.log("Current tick liquidity net: ", int256(liquidityNet));
    }
    
    // 测试观察累积器
    function testObservations() public {
        // 根据实际合约调整返回值类型
        (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized) = pool.observations(0);
        
        console.log("Observation blockTimestamp: ", uint256(blockTimestamp));
        console.log("Observation tickCumulative: ", int256(tickCumulative));
        console.log("Observation initialized: ", initialized ? uint256(1) : uint256(0));
    }
    
    // 测试池的基本参数
    function testPoolParameters() public {
        uint24 fee = pool.fee();
        int24 tickSpacing = pool.tickSpacing();
        uint128 maxLiquidityPerTick = pool.maxLiquidityPerTick();
        
        console.log("Fee (in 1/1000000): ", uint256(fee));
        console.log("Tick spacing: ", int256(tickSpacing));
        console.log("Max liquidity per tick: ", uint256(maxLiquidityPerTick));
        
        assertTrue(fee > 0);
        assertTrue(tickSpacing > 0);
        assertTrue(maxLiquidityPerTick > 0);
    }
}
