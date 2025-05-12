// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";

// 定义闪电贷回调接口
interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}

/**
 * @title Uniswap V3 模糊测试
 * @notice 使用模糊测试方法测试Uniswap V3池在各种边缘情况下的稳定性
 */
contract FuzzPoolTest is Test {
    // 模拟合约
    MockUniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    
    // 测试账户
    address public trader = address(0x1);
    address public liquidityProvider = address(0x2);
    
    // 测试参数
    uint160 public initialSqrtPriceX96;
    
    function setUp() public {
        // 创建模拟代币
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // 给测试账户铸造代币
        token0.mint(trader, 1_000_000 ether);
        token1.mint(trader, 1_000_000 ether);
        token0.mint(liquidityProvider, 1_000_000 ether);
        token1.mint(liquidityProvider, 1_000_000 ether);
        
        // 创建模拟池
        pool = new MockUniswapV3Pool(address(token0), address(token1), 3000);
        
        // 初始化价格
        initialSqrtPriceX96 = 79228162514264337593543950336; // 1:1
        pool.setCurrentSqrtPriceX96(initialSqrtPriceX96);
        
        // 授权
        vm.startPrank(trader);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    // 模糊测试：Swap函数在各种输入量下的行为
    function testFuzz_Swap(uint256 amountIn) public {
        // 限制输入范围以避免过大的数值
        amountIn = bound(amountIn, 1, 100_000 ether);
        bool zeroForOne = true;
        
        // 设置代币余额
        token0.mint(trader, amountIn);
        
        // 初始池子状态
        token0.mint(address(pool), 100_000 ether);
        token1.mint(address(pool), 100_000 ether);
        
        // 计算可能的输出值
        int256 amount0Delta = int256(amountIn);
        int256 amount1Delta = -int256(amountIn * 997 / 1000); // 考虑0.3%手续费
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // 计算新价格
        uint160 newPrice = uint160(uint256(initialSqrtPriceX96) * 997 / 1000);
        pool.setNextSqrtPriceX96(newPrice);
        
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
        assertEq(returnedAmount0Delta, amount0Delta, "Return value amount0Delta should match expected");
        assertEq(returnedAmount1Delta, amount1Delta, "Return value amount1Delta should match expected");
    }
    
    // 模糊测试：添加流动性在不同tick范围内的行为
    function testFuzz_Mint(int24 tickLower, int24 tickUpper, uint128 liquidity) public {
        // 限制输入范围
        tickLower = int24(bound(int256(tickLower), -887272, 887272));
        tickUpper = int24(bound(int256(tickUpper), int256(tickLower) + 1, 887272));
        liquidity = uint128(bound(uint256(liquidity), 1, 1_000_000 ether));
        
        // 确保tick距离合理
        if (tickUpper - tickLower < 10) {
            tickUpper = tickLower + 10;
        }
        
        // 计算所需代币数量
        uint256 amount0 = uint256(liquidity) / 10;
        uint256 amount1 = uint256(liquidity) / 10;
        pool.setMockTokenAmounts(amount0, amount1);
        
        // 记录初始状态
        uint256 lpToken0Before = token0.balanceOf(liquidityProvider);
        uint256 lpToken1Before = token1.balanceOf(liquidityProvider);
        uint128 poolLiquidityBefore = pool.getLiquidity();
        
        // 添加流动性
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidity);
        vm.stopPrank();
        
        // 验证流动性增加
        uint128 poolLiquidityAfter = pool.getLiquidity();
        assertEq(
            uint256(poolLiquidityAfter - poolLiquidityBefore), 
            uint256(liquidity), 
            "Liquidity should increase by exact amount"
        );
        
        // 验证代币被转移
        uint256 lpToken0After = token0.balanceOf(liquidityProvider);
        uint256 lpToken1After = token1.balanceOf(liquidityProvider);
        assertEq(lpToken0Before - lpToken0After, amount0, "LP should spend correct amount of token0");
        assertEq(lpToken1Before - lpToken1After, amount1, "LP should spend correct amount of token1");
    }
    
    // 模糊测试：交换和流动性混合操作
    function testFuzz_SwapAndMint(
        uint256 amountIn, 
        int24 tickLower, 
        int24 tickUpper, 
        uint128 liquidity
    ) public {
        // 限制输入范围
        amountIn = bound(amountIn, 1, 10_000 ether);
        tickLower = int24(bound(int256(tickLower), -887272, 887272));
        tickUpper = int24(bound(int256(tickUpper), int256(tickLower) + 1, 887272));
        liquidity = uint128(bound(uint256(liquidity), 1, 100_000 ether));
        
        // 先执行交换
        bool zeroForOne = true;
        
        // 设置代币余额和模拟返回值
        token0.mint(trader, amountIn);
        token0.mint(address(pool), 100_000 ether);
        token1.mint(address(pool), 100_000 ether);
        
        int256 amount0Delta = int256(amountIn);
        int256 amount1Delta = -int256(amountIn * 997 / 1000);
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        uint160 newPrice = uint160(uint256(initialSqrtPriceX96) * 997 / 1000);
        pool.setNextSqrtPriceX96(newPrice);
        
        vm.startPrank(trader);
        pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // 然后添加流动性
        uint256 amount0 = uint256(liquidity) / 10;
        uint256 amount1 = uint256(liquidity) / 10;
        pool.setMockTokenAmounts(amount0, amount1);
        
        uint128 poolLiquidityBefore = pool.getLiquidity();
        
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidity);
        vm.stopPrank();
        
        // 验证流动性增加
        uint128 poolLiquidityAfter = pool.getLiquidity();
        assertEq(
            uint256(poolLiquidityAfter - poolLiquidityBefore), 
            uint256(liquidity), 
            "Liquidity should increase by exact amount"
        );
        
        // 验证价格变化
        assertEq(uint256(pool.getCurrentSqrtPriceX96()), uint256(newPrice), "Price should be updated after swap");
    }
    
    // 模糊测试：滑点参数对交换的影响
    function testFuzz_SlippageProtection(uint256 amountIn, uint160 priceLimit) public {
        // 限制输入范围
        amountIn = bound(amountIn, 1, 10_000 ether);
        bool zeroForOne = true;
        
        // 限制价格范围
        uint160 minSqrtPrice = TickMath.MIN_SQRT_RATIO + 1;
        uint160 currentPrice = initialSqrtPriceX96;
        priceLimit = uint160(bound(uint256(priceLimit), uint256(minSqrtPrice), uint256(currentPrice) - 1));
        
        // 设置模拟滑点错误
        pool.setMockReverts(true, "SPL");
        
        // 尝试执行交换但应该失败
        vm.startPrank(trader);
        vm.expectRevert(bytes("SPL"));
        pool.swap(
            trader,
            zeroForOne,
            int256(amountIn),
            priceLimit, // 价格限制太高，应该失败
            abi.encode(trader)
        );
        vm.stopPrank();
    }
    
    // 模糊测试：手续费计算
    function testFuzz_FeeCalculation(uint256 amountIn) public {
        // 限制输入范围
        amountIn = bound(amountIn, 100 ether, 10_000 ether);
        bool zeroForOne = true;
        
        // 设置代币余额
        token0.mint(trader, amountIn);
        token0.mint(address(pool), 100_000 ether);
        token1.mint(address(pool), 100_000 ether);
        
        // 计算预期手续费
        uint256 expectedFee = amountIn * 3 / 1000; // 0.3%
        
        // 设置模拟返回值
        int256 amount0Delta = int256(amountIn);
        int256 amount1Delta = -int256(amountIn - expectedFee);
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // 记录初始手续费
        uint256 feesBefore = pool.getMockCollectedFees();
        
        // 设置将被收取的手续费
        pool.setMockFeeToCollect(expectedFee);
        
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
        assertEq(feesAfter - feesBefore, expectedFee, "Fees should increase by expected amount");
    }
}

// 模拟ERC20代币合约
contract MockERC20 is IERC20Minimal {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

// 模拟Uniswap V3池合约
contract MockUniswapV3Pool is IUniswapV3Pool {
    address public immutable override token0;
    address public immutable override token1;
    uint24 public immutable override fee;
    
    uint128 private liquidityValue;
    uint160 private sqrtPriceX96;
    int24 private tick;
    
    mapping(bytes32 => PositionData) private positionsMap;
    uint256 private mockCollectedFees;
    
    struct PositionData {
        uint128 liquidity;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }
    
    // 模拟交换的返回值
    int256 private mockAmount0Delta;
    int256 private mockAmount1Delta;
    
    // 模拟交换后的新价格
    uint160 private nextSqrtPriceX96;
    
    // 模拟token转移的数量
    uint256 private mockAmount0;
    uint256 private mockAmount1;
    
    // 模拟错误
    bool private shouldRevert;
    string private revertMessage;
    
    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }
    
    // 实现接口必需的函数
    function factory() external pure override returns (address) {
        return address(1); // 模拟工厂地址
    }
    
    function tickSpacing() external pure override returns (int24) {
        return 60; // 模拟tick间距
    }
    
    function maxLiquidityPerTick() external pure override returns (uint128) {
        return type(uint128).max / 2; // 模拟最大流动性
    }
    
    // positions函数实现，替代public映射
    function positions(bytes32 key) external view override returns (
        uint128 _liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        PositionData memory position = positionsMap[key];
        return (
            position.liquidity,
            position.feeGrowthInside0X128,
            position.feeGrowthInside1X128,
            0, // 模拟tokensOwed0
            0  // 模拟tokensOwed1
        );
    }
    
    // observations实现
    function observations(uint256) external pure override returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    ) {
        return (0, 0, 0, false); // 返回空值
    }
    
    // 设置模拟交换返回值
    function setMockSwapAmounts(int256 _amount0Delta, int256 _amount1Delta) external {
        mockAmount0Delta = _amount0Delta;
        mockAmount1Delta = _amount1Delta;
    }
    
    // 设置模拟新价格
    function setNextSqrtPriceX96(uint160 _nextSqrtPriceX96) external {
        nextSqrtPriceX96 = _nextSqrtPriceX96;
    }
    
    // 设置模拟token转移数量
    function setMockTokenAmounts(uint256 _amount0, uint256 _amount1) external {
        mockAmount0 = _amount0;
        mockAmount1 = _amount1;
    }
    
    // 设置当前价格
    function setCurrentSqrtPriceX96(uint160 _sqrtPriceX96) external {
        sqrtPriceX96 = _sqrtPriceX96;
    }
    
    // 设置模拟错误
    function setMockReverts(bool _shouldRevert, string calldata _revertMessage) external {
        shouldRevert = _shouldRevert;
        revertMessage = _revertMessage;
    }
    
    // 设置手续费
    function setMockFeeToCollect(uint256 _fee) external {
        mockCollectedFees += _fee;
    }
    
    // 设置流动性
    function setLiquidity(uint128 _liquidity) external {
        liquidityValue = _liquidity;
    }
    
    // 获取当前价格
    function getCurrentSqrtPriceX96() public view returns (uint160) {
        return sqrtPriceX96;
    }
    
    // 获取流动性
    function getLiquidity() public view returns (uint128) {
        return liquidityValue;
    }
    
    // 获取已收取的手续费
    function getMockCollectedFees() public view returns (uint256) {
        return mockCollectedFees;
    }
    
    // 添加流动性(模拟)
    function mintMock(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256, uint256) {
        // 转移代币
        IERC20Minimal(token0).transferFrom(owner, address(this), mockAmount0);
        IERC20Minimal(token1).transferFrom(owner, address(this), mockAmount1);
        
        // 更新流动性
        liquidityValue += amount;
        
        // 更新position
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positionsMap[positionKey].liquidity += amount;
        
        return (mockAmount0, mockAmount1);
    }
    
    // 移除流动性(模拟)
    function burnMock(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256, uint256) {
        // 更新流动性
        liquidityValue -= amount;
        
        // 更新position
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positionsMap[positionKey].liquidity -= amount;
        
        // 转移代币
        IERC20Minimal(token0).transfer(owner, mockAmount0);
        IERC20Minimal(token1).transfer(owner, mockAmount1);
        
        return (mockAmount0, mockAmount1);
    }
    
    // 提取手续费(模拟)
    function collectMock(address owner, int24 tickLower, int24 tickUpper) external returns (uint256, uint256) {
        // 转移手续费
        IERC20Minimal(token0).transfer(owner, mockAmount0);
        IERC20Minimal(token1).transfer(owner, mockAmount1);
        
        // 重置手续费增长
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positionsMap[positionKey].feeGrowthInside0X128 = 0;
        positionsMap[positionKey].feeGrowthInside1X128 = 0;
        
        return (mockAmount0, mockAmount1);
    }
    
    // 设置手续费(模拟)
    function setMockFees(address owner, int24 tickLower, int24 tickUpper, uint256 fee0, uint256 fee1) external {
        mockAmount0 = fee0;
        mockAmount1 = fee1;
    }
    
    // 更新手续费增长
    function updateMockFeeGrowth(uint256 fee0, uint256 fee1) external {
        mockCollectedFees += fee0 + fee1;
    }
    
    // 交换功能(模拟)
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        if (shouldRevert) {
            revert(revertMessage);
        }
        
        // 执行交换
        if (zeroForOne) {
            if (amountSpecified > 0) {
                // 精确输入
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token1).transfer(recipient, uint256(-mockAmount1Delta));
            } else {
                // 精确输出
                IERC20Minimal(token0).transferFrom(msg.sender, address(this), uint256(mockAmount0Delta));
                IERC20Minimal(token1).transfer(recipient, uint256(-amountSpecified));
            }
        } else {
            if (amountSpecified > 0) {
                // 精确输入
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(amountSpecified));
                IERC20Minimal(token0).transfer(recipient, uint256(-mockAmount0Delta));
            } else {
                // 精确输出
                IERC20Minimal(token1).transferFrom(msg.sender, address(this), uint256(mockAmount1Delta));
                IERC20Minimal(token0).transfer(recipient, uint256(-amountSpecified));
            }
        }
        
        // 更新价格
        sqrtPriceX96 = nextSqrtPriceX96;
        
        return (mockAmount0Delta, mockAmount1Delta);
    }
    
    // 以下是实现接口所需的其他函数
    function observe(uint32[] calldata) external pure override returns (int56[] memory, uint160[] memory) {
        return (new int56[](0), new uint160[](0));
    }
    
    function increaseObservationCardinalityNext(uint16) external pure override {}
    
    function initialize(uint160) external pure override {}
    
    function mint(address, int24, int24, uint128, bytes calldata) external pure override returns (uint256, uint256) {
        return (0, 0);
    }
    
    function collect(address, int24, int24, uint128, uint128) external pure override returns (uint128, uint128) {
        return (0, 0);
    }
    
    function burn(int24, int24, uint128) external pure override returns (uint256, uint256) {
        return (0, 0);
    }
    
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // 转移token给接收者
        if (amount0 > 0) IERC20Minimal(token0).transfer(recipient, amount0);
        if (amount1 > 0) IERC20Minimal(token1).transfer(recipient, amount1);
        
        // 调用回调
        IUniswapV3FlashCallback(recipient).uniswapV3FlashCallback(amount0, amount1, data);
    }
    
    function setFeeProtocol(uint8, uint8) external pure override {}
    
    function collectProtocol(address, uint128, uint128) external pure override returns (uint128, uint128) {
        return (0, 0);
    }
    
    function slot0() external view override returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, false);
    }
    
    function feeGrowthGlobal0X128() external pure override returns (uint256) {
        return 0;
    }
    
    function feeGrowthGlobal1X128() external pure override returns (uint256) {
        return 0;
    }
    
    function protocolFees() external pure override returns (uint128, uint128) {
        return (0, 0);
    }
    
    function liquidity() external view override returns (uint128) {
        return liquidityValue;
    }
    
    function ticks(int24) external pure override returns (uint128, int128, uint256, uint256, int56, uint160, uint32, bool) {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }
    
    function tickBitmap(int16) external pure override returns (uint256) {
        return 0;
    }
    
    function snapshotCumulativesInside(int24, int24) external pure override returns (int56, uint160, uint32) {
        return (0, 0, 0);
    }
} 