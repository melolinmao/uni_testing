// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/libraries/TickMath.sol";

contract TickMathInvariantTest is Test {
    function setUp() public {
        // 使用本地Anvil节点进行主网分叉测试
        string memory forkRpc = vm.envOr("ANVIL_RPC_URL", string("http://localhost:8545"));
        vm.createSelectFork(forkRpc);
    }
    
    // 测试TickMath库的不变量
    function testTickMathInvariant(int24 tick) public {
        // 限制tick在有效范围内
        vm.assume(tick >= TickMath.MIN_TICK);
        vm.assume(tick <= TickMath.MAX_TICK);
        
        // 从tick获取sqrtPriceX96
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        
        // 从sqrtPriceX96恢复tick
        int24 recoveredTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        
        // 验证输入与输出相等 - 使用明确的类型转换避免函数重载歧义
        assertEq(int256(recoveredTick), int256(tick), "tick -> price -> tick conversion should preserve the tick value");
    }
    
    // 测试价格范围边界
    function testTickMathBoundaries() public {
        // 测试最小tick
        uint160 minPrice = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK);
        uint256 min1 = uint256(minPrice);
        uint256 min2 = uint256(TickMath.MIN_SQRT_RATIO);
        assertEq(min1, min2, "Min tick should map to MIN_SQRT_RATIO");
        
        // 测试最大tick
        uint160 maxPrice = TickMath.getSqrtRatioAtTick(TickMath.MAX_TICK);
        uint256 max1 = uint256(maxPrice);
        uint256 max2 = uint256(TickMath.MAX_SQRT_RATIO);
        assertEq(max1, max2, "Max tick should map to MAX_SQRT_RATIO");
    }
}
