// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

import "forge-std/Test.sol";
import "v3-core/contracts/libraries/TickMath.sol";

contract TickMathInvariantTest is Test {
    function invariantTickMath(uint24 tick) public {
        vm.assume(tick < 887272);
        int128 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(tick));
        int24 recoveredTick = TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX96));
        assertEq(recoveredTick, int24(tick));
    }
}
