// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";

/**
 * @title UniswapV3Pool Mock交换测试
 * @notice 使用模拟对象测试Swap接口
 */
contract SimpleMockSwapTest is Test {
    // 模拟合约
    MockUniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    
    // 测试账户
    address public trader = address(0x1);
    
    // 测试参数
    uint160 public initialSqrtPriceX96;
    
    function setUp() public {
        // 创建模拟代币
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // 给交易者铸造代币
        token0.mint(trader, 1_000_000 ether);
        token1.mint(trader, 1_000_000 ether);
        
        // 创建模拟池
        pool = new MockUniswapV3Pool(address(token0), address(token1), 3000);
        
        // 初始化价格
        initialSqrtPriceX96 = 79228162514264337593543950336; // 1:1
        pool.setCurrentSqrtPriceX96(initialSqrtPriceX96);
        
        // 设置初始余额
        token0.mint(address(pool), 10_000 ether);
        token1.mint(address(pool), 10_000 ether);
        
        // 授权
        vm.startPrank(trader);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    // 测试固定输入量交换
    function testExactInputSwap() public {
        uint256 amountIn = 100 ether;
        bool zeroForOne = true; // token0 -> token1
        
        // 使用局部存储记录初始余额
        TradeData memory data;
        data.trader0Before = token0.balanceOf(trader);
        data.trader1Before = token1.balanceOf(trader);
        data.pool0Before = token0.balanceOf(address(pool));
        data.pool1Before = token1.balanceOf(address(pool));
        
        // 设置模拟返回值以模拟交换
        data.amount0Delta = int256(amountIn);
        data.amount1Delta = -int256(95 ether); // 假设获得95 token1（考虑0.3%手续费）
        pool.setMockSwapAmounts(data.amount0Delta, data.amount1Delta);
        
        // 计算期望的新价格
        data.expectedNewPrice = uint160(uint256(initialSqrtPriceX96) * 95 / 100);
        pool.setNextSqrtPriceX96(data.expectedNewPrice);
        
        // 执行交换
        vm.startPrank(trader);
        (int256 returnedAmount0Delta, int256 returnedAmount1Delta) = pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // 验证返回值
        assertEq(returnedAmount0Delta, data.amount0Delta, "Return value amount0Delta should match expected");
        assertEq(returnedAmount1Delta, data.amount1Delta, "Return value amount1Delta should match expected");
        
        // 验证余额变化和其他条件
        _verifyExactInputSwapResults(data, amountIn);
    }
    
    // 测试固定输出量交换
    function testExactOutputSwap() public {
        uint256 amountOut = 50 ether; // 想要获得的token1精确数量
        bool zeroForOne = true; // token0 -> token1
        
        // 使用局部存储记录初始余额
        TradeData memory data;
        data.trader0Before = token0.balanceOf(trader);
        data.trader1Before = token1.balanceOf(trader);
        data.pool0Before = token0.balanceOf(address(pool));
        data.pool1Before = token1.balanceOf(address(pool));
        
        // 设置模拟返回值以模拟交换
        data.amount0Delta = int256(53 ether); // 假设需要支付53 token0（考虑0.3%手续费）
        data.amount1Delta = -int256(amountOut);
        pool.setMockSwapAmounts(data.amount0Delta, data.amount1Delta);
        
        // 计算期望的新价格
        data.expectedNewPrice = uint160(uint256(initialSqrtPriceX96) * 95 / 100);
        pool.setNextSqrtPriceX96(data.expectedNewPrice);
        
        // 执行交换
        vm.startPrank(trader);
        (int256 returnedAmount0Delta, int256 returnedAmount1Delta) = pool.swap(
            trader,
            zeroForOne,
            -int256(amountOut), // 负值表示精确输出
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // 验证返回值
        assertEq(returnedAmount0Delta, data.amount0Delta, "Return value amount0Delta should match expected");
        assertEq(returnedAmount1Delta, data.amount1Delta, "Return value amount1Delta should match expected");
        
        // 验证余额变化和其他条件
        _verifyExactOutputSwapResults(data, amountOut);
    }
    
    // 测试滑点保护
    function testSlippageProtection() public {
        uint256 amountIn = 1_000 ether;
        bool zeroForOne = true;
        
        // 计算当前价格
        uint160 currentPrice = pool.getCurrentSqrtPriceX96();
        
        // 设置一个接近当前价格的限制（几乎没有滑点空间）
        uint160 slippageLimit = uint160(uint256(currentPrice) * 99 / 100);
        
        // 模拟滑点错误
        pool.setMockReverts(true, "SPL");
        
        // 尝试执行交换但应该失败
        vm.startPrank(trader);
        vm.expectRevert(bytes("SPL")); // "SPL"是Uniswap V3中的"SlippagePriceLimitReached"错误
        pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            slippageLimit, // 价格限制太高，应该失败
            abi.encode(trader)
        );
        vm.stopPrank();
    }
    
    // 测试手续费收取
    function testSwapFeeCollection() public {
        // 执行一次较大的交换以产生显著手续费
        uint256 amountIn = 10_000 ether;
        bool zeroForOne = true;
        
        // 记录池初始手续费
        uint256 feesBefore = pool.getMockCollectedFees();
        
        // 设置模拟返回值以模拟交换
        int256 amount0Delta = int256(amountIn);
        int256 amount1Delta = -int256(9_950 ether); // 0.3% = 30 token0 of fees
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // 指定预期收取的手续费
        uint256 expectedFees = 30 ether;
        pool.setMockFeeToCollect(expectedFees);
        
        // 执行交换
        vm.startPrank(trader);
        pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // 验证手续费增长
        uint256 feesAfter = pool.getMockCollectedFees();
        assertEq(feesAfter - feesBefore, expectedFees, "Fees should increase by expected amount");
        
        emit log_named_uint("Fees collected:", feesAfter - feesBefore);
    }
    
    // 辅助函数: 验证ExactInputSwap的结果
    function _verifyExactInputSwapResults(TradeData memory data, uint256 amountIn) internal {
        // 获取交易后的余额
        uint256 traderToken0After = token0.balanceOf(trader);
        uint256 traderToken1After = token1.balanceOf(trader);
        uint256 poolToken0After = token0.balanceOf(address(pool));
        uint256 poolToken1After = token1.balanceOf(address(pool));
        
        // 验证交易者余额变化
        assertEq(data.trader0Before - traderToken0After, amountIn, "Trader should spend exact amount of token0");
        assertEq(traderToken1After - data.trader1Before, uint256(-data.amount1Delta), "Trader should receive correct amount of token1");
        
        // 验证池余额变化
        assertEq(poolToken0After - data.pool0Before, amountIn, "Pool should receive exact amount of token0");
        assertEq(data.pool1Before - poolToken1After, uint256(-data.amount1Delta), "Pool should send correct amount of token1");
        
        // 验证价格变化
        uint160 newPrice = pool.getCurrentSqrtPriceX96();
        assertEq(uint256(newPrice), uint256(data.expectedNewPrice), "Price should update as expected");
        
        // 验证恒定乘积不变量（考虑手续费）
        uint256 k1 = data.pool0Before * data.pool1Before;
        uint256 k2 = poolToken0After * poolToken1After;
        assertTrue(k2 >= k1, "Constant product invariant should hold or increase due to fees");
        
        emit log_named_uint("exactInput - token0 spent:", amountIn);
        emit log_named_uint("exactInput - token1 received:", uint256(-data.amount1Delta));
    }
    
    // 辅助函数: 验证ExactOutputSwap的结果
    function _verifyExactOutputSwapResults(TradeData memory data, uint256 amountOut) internal {
        // 获取交易后的余额
        uint256 traderToken0After = token0.balanceOf(trader);
        uint256 traderToken1After = token1.balanceOf(trader);
        uint256 poolToken0After = token0.balanceOf(address(pool));
        uint256 poolToken1After = token1.balanceOf(address(pool));
        
        // 验证交易者余额变化
        assertEq(data.trader0Before - traderToken0After, uint256(data.amount0Delta), "Trader should spend correct amount of token0");
        assertEq(traderToken1After - data.trader1Before, amountOut, "Trader should receive exact amount of token1");
        
        // 验证池余额变化
        assertEq(poolToken0After - data.pool0Before, uint256(data.amount0Delta), "Pool should receive correct amount of token0");
        assertEq(data.pool1Before - poolToken1After, amountOut, "Pool should send exact amount of token1");
        
        // 验证价格变化
        uint160 newPrice = pool.getCurrentSqrtPriceX96();
        assertEq(uint256(newPrice), uint256(data.expectedNewPrice), "Price should update as expected");
        
        // 验证恒定乘积不变量（考虑手续费）
        uint256 k1 = data.pool0Before * data.pool1Before;
        uint256 k2 = poolToken0After * poolToken1After;
        assertTrue(k2 >= k1, "Constant product invariant should hold or increase due to fees");
        
        emit log_named_uint("exactOutput - token0 spent:", uint256(data.amount0Delta));
        emit log_named_uint("exactOutput - token1 received:", amountOut);
    }
    
    // 交易数据结构 - 用于减少局部变量堆栈深度
    struct TradeData {
        uint256 trader0Before;
        uint256 trader1Before;
        uint256 pool0Before;
        uint256 pool1Before;
        int256 amount0Delta;
        int256 amount1Delta;
        uint160 expectedNewPrice;
    }
}

// 模拟UniswapV3池合约
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    
    uint160 private _currentSqrtPriceX96;
    int24 private _currentTick;
    
    // 模拟swap返回值
    int256 private _mockAmount0Delta;
    int256 private _mockAmount1Delta;
    
    // 模拟手续费
    uint256 private _mockCollectedFees;
    uint256 private _mockFeeToCollect;
    
    // 模拟错误
    bool private _shouldRevert;
    string private _revertReason;
    
    // 下一个价格
    uint160 private _nextSqrtPriceX96;
    
    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        _currentTick = 0;
    }
    
    // 设置当前价格
    function setCurrentSqrtPriceX96(uint160 sqrtPriceX96) external {
        _currentSqrtPriceX96 = sqrtPriceX96;
    }
    
    // 获取当前价格
    function getCurrentSqrtPriceX96() external view returns (uint160) {
        return _currentSqrtPriceX96;
    }
    
    // 设置下一个价格（交换后的价格）
    function setNextSqrtPriceX96(uint160 sqrtPriceX96) external {
        _nextSqrtPriceX96 = sqrtPriceX96;
    }
    
    // 设置模拟swap返回值
    function setMockSwapAmounts(int256 amount0Delta, int256 amount1Delta) external {
        _mockAmount0Delta = amount0Delta;
        _mockAmount1Delta = amount1Delta;
    }
    
    // 设置手续费收取
    function setMockFeeToCollect(uint256 feeAmount) external {
        _mockFeeToCollect = feeAmount;
    }
    
    // 获取模拟收取的手续费
    function getMockCollectedFees() external view returns (uint256) {
        return _mockCollectedFees;
    }
    
    // 设置是否应该回滚
    function setMockReverts(bool shouldRevert, string memory reason) external {
        _shouldRevert = shouldRevert;
        _revertReason = reason;
    }
    
    // 模拟slot0读取
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
    
    // 模拟全局手续费增长
    function feeGrowthGlobal0X128() external view returns (uint256) {
        return _mockCollectedFees * 5;
    }
    
    function feeGrowthGlobal1X128() external view returns (uint256) {
        return _mockCollectedFees * 10;
    }
    
    // 模拟swap函数
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        if (_shouldRevert) {
            revert(_revertReason);
        }
        
        // 实现交易逻辑
        if (amountSpecified > 0) {
            // exactInput: 转移Token到池中
            if (zeroForOne) {
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token1).transfer(recipient, uint256(-_mockAmount1Delta));
            } else {
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token0).transfer(recipient, uint256(-_mockAmount0Delta));
            }
        } else {
            // exactOutput: 转移指定输出量
            if (zeroForOne) {
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(_mockAmount0Delta));
                IERC20Minimal(token1).transfer(recipient, uint256(-amountSpecified));
            } else {
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(_mockAmount1Delta));
                IERC20Minimal(token0).transfer(recipient, uint256(-amountSpecified));
            }
        }
        
        // 更新价格
        _currentSqrtPriceX96 = _nextSqrtPriceX96;
        
        // 累计手续费
        _mockCollectedFees += _mockFeeToCollect;
        
        return (_mockAmount0Delta, _mockAmount1Delta);
    }
}

// 简化ERC20代币
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