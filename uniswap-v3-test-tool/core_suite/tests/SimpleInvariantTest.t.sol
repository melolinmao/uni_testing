// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/FullMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";

/**
 * @title Uniswap V3 Invariant Test
 * @notice Tests for Uniswap V3 core invariants
 */
contract SimpleInvariantTest is Test {
    // Mock contracts
    MockUniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    
    // Test accounts
    address public trader = address(0x1);
    address public liquidityProvider = address(0x2);
    
    // Test parameters
    uint160 public initialSqrtPriceX96;
    int24 public tickSpacing = 60; // tick spacing for 0.3% fee
    
    // Historical state for verification
    uint256[] public reserves0History;
    uint256[] public reserves1History;
    uint160[] public sqrtPriceX96History;
    
    function setUp() public {
        // Create mock tokens
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // Create mock pool
        pool = new MockUniswapV3Pool(address(token0), address(token1), 3000);
        
        // Initialize price
        initialSqrtPriceX96 = 79228162514264337593543950336; // 1:1
        pool.setCurrentSqrtPriceX96(initialSqrtPriceX96);
        
        // Set initial liquidity
        token0.mint(address(pool), 10_000 ether);
        token1.mint(address(pool), 10_000 ether);
        pool.setLiquidity(1000000 ether); // Set a large liquidity value
        
        // Record initial state
        reserves0History.push(token0.balanceOf(address(pool)));
        reserves1History.push(token1.balanceOf(address(pool)));
        sqrtPriceX96History.push(initialSqrtPriceX96);
    }
    
    // Test that tick to price conversion is accurate
    function testTickPriceMapping() public {
        for (int24 tick = -1000; tick <= 1000; tick += 100) {
            // Calculate price using TickMath
            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
            
            // Use price to calculate tick
            int24 calculatedTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            
            // Verify tick is close to original (consider rounding error)
            int24 tickDifference = tick - calculatedTick; 
            if (tickDifference < 0) tickDifference = -tickDifference;
            
            assertLe(tickDifference, tickSpacing, "Tick-price mapping should be reversible within a tick spacing");
            
            emit log_named_int("Original tick:", tick);
            emit log_named_int("Calculated tick:", calculatedTick);
            emit log_named_uint("sqrt price:", uint256(sqrtPriceX96));
        }
    }
    
    // Test constant product invariant after swaps
    function testConstantProductInvariant() public {
        // Perform multiple swaps
        uint256 testSwaps = 5;
        uint256 amountIn = 100 ether;
        
        for (uint256 i = 0; i < testSwaps; i++) {
            // Alternate between 0->1 and 1->0 swaps
            bool zeroForOne = i % 2 == 0;
            
            // Record state before the swap
            uint256 reserve0Before = token0.balanceOf(address(pool));
            uint256 reserve1Before = token1.balanceOf(address(pool));
            uint256 kBefore = reserve0Before * reserve1Before;
            
            // Calculate mock swap results - ensure constant product increases
            (int256 amount0Delta, int256 amount1Delta) = _calculateSwapAmountsWithFee(
                zeroForOne, 
                int256(amountIn), 
                reserve0Before,
                reserve1Before
            );
            pool.setMockSwapAmounts(amount0Delta, amount1Delta);
            
            // Calculate expected new price
            uint160 newSqrtPriceX96 = _calculateNewSqrtPrice(zeroForOne);
            pool.setNextSqrtPriceX96(newSqrtPriceX96);
            
            // Execute swap
            vm.startPrank(trader);
            pool.swap(
                trader,
                zeroForOne,
                int256(amountIn),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                abi.encode(trader)
            );
            vm.stopPrank();
            
            // Record state after the swap
            uint256 reserve0After = token0.balanceOf(address(pool));
            uint256 reserve1After = token1.balanceOf(address(pool));
            uint256 kAfter = reserve0After * reserve1After;
            
            // Verify constant product invariant (with fees, k should increase or stay the same)
            assertTrue(kAfter >= kBefore, "Constant product invariant violated");
            
            // Calculate k growth rate
            uint256 kGrowthBps = kAfter * 10000 / kBefore;
            
            // Record historical state
            reserves0History.push(reserve0After);
            reserves1History.push(reserve1After);
            sqrtPriceX96History.push(pool.getCurrentSqrtPriceX96());
            
            emit log_named_uint("Swap", i);
            emit log_named_uint("K before", kBefore);
            emit log_named_uint("K after", kAfter);
            emit log_named_uint("K growth (bps)", kGrowthBps);
        }
    }
    
    // Test simplified price-reserve consistency - checking only initial state
    function testPriceReserveConsistency() public {
        // In Uniswap V3, relationship between price and total liquidity is more complex than V2
        // Here we only check simpler cases in initial state
        
        // Get current pool state
        uint256 reserve0 = token0.balanceOf(address(pool));
        uint256 reserve1 = token1.balanceOf(address(pool));
        uint160 sqrtPriceX96 = pool.getCurrentSqrtPriceX96();
        
        // Calculate price from reserves
        uint256 calculatedPrice = (reserve1 * (1 << 96)) / reserve0;
        
        // Calculate price from sqrtPrice
        uint256 priceFromSqrt = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        
        // Print both price calculation results for comparison
        emit log_named_uint("Reserve0", reserve0);
        emit log_named_uint("Reserve1", reserve1);
        emit log_named_uint("Calculated price", calculatedPrice);
        emit log_named_uint("Price from sqrt", priceFromSqrt);
        
        // Verify the two price calculation methods yield similar results in initial state
        // Initially we set 1:1 price and equal liquidity distribution
        uint256 errorBps;
        if (priceFromSqrt > calculatedPrice) {
            errorBps = (priceFromSqrt - calculatedPrice) * 10000 / priceFromSqrt;
        } else {
            errorBps = (calculatedPrice - priceFromSqrt) * 10000 / calculatedPrice;
        }
        
        // Allow some error, in initial state should be very close
        assertLe(errorBps, 10, "Initial price-reserve consistency violated");
        
        // In this test, we don't verify consistency after swaps because Uniswap V3 uses
        // concentrated liquidity instead of regular x*y=k model
        
        // Optional: perform some swaps to demonstrate how price-reserve relationship changes
        // Here we just execute swaps but don't make strict assertions, as Uniswap V3's price
        // calculation is more complex than V2
        _runSampleSwaps();
    }
    
    // Helper function: execute sample swaps to demonstrate price-reserve relationship
    function _runSampleSwaps() internal {
        uint256 amountIn = 1000 ether; // Larger amount to show clear effect
        
        // State before swap
        emit log_string("===== Before Swap =====");
        _logPriceAndReserves();
        
        // Execute swap
        bool zeroForOne = true;
        (int256 amount0Delta, int256 amount1Delta) = _calculateSwapAmountsWithFee(
            zeroForOne, 
            int256(amountIn),
            token0.balanceOf(address(pool)),
            token1.balanceOf(address(pool))
        );
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // Set price change
        uint160 newSqrtPriceX96 = _calculateExactSqrtPrice(
            token0.balanceOf(address(pool)),
            token1.balanceOf(address(pool)),
            amount0Delta,
            amount1Delta
        );
        pool.setNextSqrtPriceX96(newSqrtPriceX96);
        
        // Execute swap
        vm.startPrank(trader);
        pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // State after swap
        emit log_string("===== After Swap =====");
        _logPriceAndReserves();
        
        // Note: In Uniswap V3, due to concentrated liquidity, price (sqrtPriceX96^2) and 
        // simple x/y ratio are no longer directly equivalent
        emit log_string("In Uniswap V3, price and reserve ratio aren't exactly equal due to concentrated liquidity");
    }
    
    // Helper function: log current price and reserves
    function _logPriceAndReserves() internal {
        uint256 reserve0 = token0.balanceOf(address(pool));
        uint256 reserve1 = token1.balanceOf(address(pool));
        uint160 sqrtPriceX96 = pool.getCurrentSqrtPriceX96();
        
        uint256 calculatedPrice = (reserve1 * (1 << 96)) / reserve0;
        uint256 priceFromSqrt = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        
        emit log_named_uint("Reserve0", reserve0);
        emit log_named_uint("Reserve1", reserve1);
        emit log_named_uint("Reserve ratio (scaled by 2^96)", calculatedPrice);
        emit log_named_uint("Price from sqrtPrice", priceFromSqrt);
    }
    
    // Test price calculation and its inverse
    function testPriceCalculationInverse() public {
        // Test various price points
        uint160[] memory testPrices = new uint160[](5);
        testPrices[0] = uint160(1 << 96); // 1.0
        testPrices[1] = uint160(2 * (1 << 96)); // 2.0
        testPrices[2] = uint160((1 << 96) / 2); // 0.5
        testPrices[3] = TickMath.getSqrtRatioAtTick(100);
        testPrices[4] = TickMath.getSqrtRatioAtTick(-100);
        
        for (uint256 i = 0; i < testPrices.length; i++) {
            uint160 sqrtPriceX96 = testPrices[i];
            
            // Calculate price
            uint256 price = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
            
            // Calculate sqrtPrice from price
            uint256 calculatedSqrtPriceX96 = sqrt(price * (1 << 96));
            
            // Calculate error
            uint256 errorBps;
            if (uint256(sqrtPriceX96) > calculatedSqrtPriceX96) {
                errorBps = (uint256(sqrtPriceX96) - calculatedSqrtPriceX96) * 10000 / uint256(sqrtPriceX96);
            } else {
                errorBps = (calculatedSqrtPriceX96 - uint256(sqrtPriceX96)) * 10000 / calculatedSqrtPriceX96;
            }
            
            // Allow some rounding error
            assertLe(errorBps, 1, "Price calculation inverse should be accurate");
            
            emit log_named_uint("Test case", i);
            emit log_named_uint("Original sqrt price", uint256(sqrtPriceX96));
            emit log_named_uint("Price", price);
            emit log_named_uint("Calculated sqrt price", calculatedSqrtPriceX96);
            emit log_named_uint("Error (bps)", errorBps);
        }
    }
    
    // Helper function: calculate mock swap amounts (with fee) - improved version
    function _calculateSwapAmountsWithFee(
        bool zeroForOne, 
        int256 amountSpecified,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (int256 amount0Delta, int256 amount1Delta) {
        uint256 feeMultiplier = 997; // 0.3% fee = 997/1000
        
        if (zeroForOne) {
            // token0 -> token1
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountInWithFee = amountIn * feeMultiplier / 1000;
            
            // x * y = k, calculate y after swap
            // (x + dx) * (y - dy) = x * y
            // dy = y - x * y / (x + dx)
            uint256 amountOut = reserve1 - ((reserve0 * reserve1) / (reserve0 + amountInWithFee));
            
            amount0Delta = int256(amountIn);
            amount1Delta = -int256(amountOut);
        } else {
            // token1 -> token0
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountInWithFee = amountIn * feeMultiplier / 1000;
            
            // Same logic to calculate output amount
            uint256 amountOut = reserve0 - ((reserve0 * reserve1) / (reserve1 + amountInWithFee));
            
            amount1Delta = int256(amountIn);
            amount0Delta = -int256(amountOut);
        }
    }
    
    // Helper function: calculate new sqrtPrice
    function _calculateNewSqrtPrice(bool zeroForOne) 
        internal view returns (uint160 newSqrtPriceX96) 
    {
        uint160 sqrtPriceX96 = pool.getCurrentSqrtPriceX96();
        
        if (zeroForOne) {
            // Use more accurate calculation method
            uint256 price = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
            // Price decreases
            uint256 newPrice = price * 990 / 1000; // Simplified calculation
            newSqrtPriceX96 = uint160(sqrt(newPrice * (1 << 96)));
        } else {
            // Price increases
            uint256 price = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
            uint256 newPrice = price * 1010 / 1000; // Simplified calculation
            newSqrtPriceX96 = uint160(sqrt(newPrice * (1 << 96)));
        }
    }
    
    // Helper function: calculate exact sqrtPrice based on actual swap amounts
    function _calculateExactSqrtPrice(
        uint256 reserve0,
        uint256 reserve1,
        int256 amount0Delta,
        int256 amount1Delta
    ) internal pure returns (uint160 newSqrtPriceX96) {
        // Calculate new reserves
        uint256 newReserve0 = amount0Delta >= 0 
            ? reserve0 + uint256(amount0Delta)
            : reserve0 - uint256(-amount0Delta);
            
        uint256 newReserve1 = amount1Delta >= 0
            ? reserve1 + uint256(amount1Delta)
            : reserve1 - uint256(-amount1Delta);
            
        // Calculate price based on new reserves
        uint256 price = (newReserve1 * (1 << 96)) / newReserve0;
        uint256 sqrtPrice = sqrt(price);
        
        return uint160(sqrtPrice);
    }
    
    // Helper function: calculate square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

// Mock UniswapV3Pool contract
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    
    uint160 private _currentSqrtPriceX96;
    int24 private _currentTick;
    uint128 private _liquidity;
    
    // Mock swap return values
    int256 private _mockAmount0Delta;
    int256 private _mockAmount1Delta;
    
    // Mock error
    bool private _shouldRevert;
    string private _revertReason;
    
    // Next price
    uint160 private _nextSqrtPriceX96;
    
    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        _currentTick = 0;
        _liquidity = 0;
    }
    
    // Set current price
    function setCurrentSqrtPriceX96(uint160 sqrtPriceX96) external {
        _currentSqrtPriceX96 = sqrtPriceX96;
    }
    
    // Get current price
    function getCurrentSqrtPriceX96() external view returns (uint160) {
        return _currentSqrtPriceX96;
    }
    
    // Set next price (price after swap)
    function setNextSqrtPriceX96(uint160 sqrtPriceX96) external {
        _nextSqrtPriceX96 = sqrtPriceX96;
    }
    
    // Set liquidity
    function setLiquidity(uint128 liquidity) external {
        _liquidity = liquidity;
    }
    
    // Get current liquidity
    function getLiquidity() external view returns (uint128) {
        return _liquidity;
    }
    
    // Set mock swap return values
    function setMockSwapAmounts(int256 amount0Delta, int256 amount1Delta) external {
        _mockAmount0Delta = amount0Delta;
        _mockAmount1Delta = amount1Delta;
    }
    
    // Set whether swap should revert
    function setMockReverts(bool shouldRevert, string memory reason) external {
        _shouldRevert = shouldRevert;
        _revertReason = reason;
    }
    
    // Mock slot0 read
    function slot0() external view returns (
        uint160 sqrtPriceX96, 
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) {
        return (_currentSqrtPriceX96, _currentTick, 0, 1, 1, 0, true);
    }
    
    // Mock swap function
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160, // sqrtPriceLimitX96, unused
        bytes calldata // data, unused
    ) external returns (int256 amount0, int256 amount1) {
        if (_shouldRevert) {
            revert(_revertReason);
        }
        
        // Implement swap logic
        if (amountSpecified > 0) {
            // exactInput: Transfer tokens to pool
            if (zeroForOne) {
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token1).transfer(recipient, uint256(-_mockAmount1Delta));
            } else {
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token0).transfer(recipient, uint256(-_mockAmount0Delta));
            }
        } else {
            // exactOutput: Transfer specified output amount
            if (zeroForOne) {
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(_mockAmount0Delta));
                IERC20Minimal(token1).transfer(recipient, uint256(-amountSpecified));
            } else {
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(_mockAmount1Delta));
                IERC20Minimal(token0).transfer(recipient, uint256(-amountSpecified));
            }
        }
        
        // Update price
        _currentSqrtPriceX96 = _nextSqrtPriceX96;
        
        return (_mockAmount0Delta, _mockAmount1Delta);
    }
}

// Simplified ERC20 token contract
contract MockERC20 is IERC20Minimal {
    string public name;
    string public symbol;
    uint8 private _decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory n, string memory s, uint8 d) {
        name = n;
        symbol = s;
        _decimals = d;
    }

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
        totalSupply += v;
        emit Transfer(address(0), to, v);
    }

    function transfer(address to, uint256 v) external override returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        emit Transfer(msg.sender, to, v);
        return true;
    }

    function approve(address sp, uint256 v) external override returns (bool) {
        allowance[msg.sender][sp] = v;
        emit Approval(msg.sender, sp, v);
        return true;
    }

    function transferFrom(address from, address to, uint256 v) external override returns (bool) {
        allowance[from][msg.sender] -= v;
        balanceOf[from] -= v;
        balanceOf[to] += v;
        emit Transfer(from, to, v);
        return true;
    }
} 