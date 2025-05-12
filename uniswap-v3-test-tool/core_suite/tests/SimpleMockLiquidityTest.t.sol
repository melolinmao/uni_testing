// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";

/**
 * @title 简化版Uniswap V3流动性管理测试
 * @notice 使用模拟对象测试添加和移除流动性功能
 */
contract SimpleMockLiquidityTest is Test {
    // 模拟合约
    MockUniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    
    // 测试账户
    address public liquidityProvider = address(0x2);
    
    // 测试参数
    uint160 public initialSqrtPriceX96;
    int24 public tickLower = -100;
    int24 public tickUpper = 100;
    
    function setUp() public {
        // 创建模拟代币
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // 给流动性提供者铸造代币
        token0.mint(liquidityProvider, 1_000_000 ether);
        token1.mint(liquidityProvider, 1_000_000 ether);
        
        // 创建模拟池
        pool = new MockUniswapV3Pool(address(token0), address(token1), 3000);
        
        // 初始化价格
        initialSqrtPriceX96 = 79228162514264337593543950336; // 1:1
        pool.setCurrentSqrtPriceX96(initialSqrtPriceX96);
        
        // 授权
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    // 测试添加流动性
    function testMint() public {
        // 设置测试参数
        uint128 liquidityAmount = 1000000;
        
        // 记录初始状态
        uint256 lpToken0Before = token0.balanceOf(liquidityProvider);
        uint256 lpToken1Before = token1.balanceOf(liquidityProvider);
        uint128 poolLiquidityBefore = pool.getLiquidity();
        
        // 计算所需的token数量
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(liquidityAmount);
        
        // 设置模拟token转移
        pool.setMockTokenAmounts(amount0, amount1);
        
        // 模拟mint操作
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidityAmount);
        vm.stopPrank();
        
        // 验证流动性增加
        uint128 poolLiquidityAfter = pool.getLiquidity();
        assertEq(uint256(poolLiquidityAfter - poolLiquidityBefore), uint256(liquidityAmount), "Liquidity should increase by exact amount");
        
        // 验证token被转移
        uint256 lpToken0After = token0.balanceOf(liquidityProvider);
        uint256 lpToken1After = token1.balanceOf(liquidityProvider);
        assertEq(lpToken0Before - lpToken0After, amount0, "LP should spend correct amount of token0");
        assertEq(lpToken1Before - lpToken1After, amount1, "LP should spend correct amount of token1");
        
        // 验证池子接收到token
        assertEq(token0.balanceOf(address(pool)), amount0, "Pool should receive token0");
        assertEq(token1.balanceOf(address(pool)), amount1, "Pool should receive token1");
        
        // 验证流动性头寸被记录
        (uint128 positionLiquidity,,) = pool.positions(getPositionKey(liquidityProvider, tickLower, tickUpper));
        assertEq(uint256(positionLiquidity), uint256(liquidityAmount), "Position liquidity should be recorded");
        
        emit log_named_uint("Liquidity added:", liquidityAmount);
        emit log_named_uint("Token0 contributed:", amount0);
        emit log_named_uint("Token1 contributed:", amount1);
    }
    
    // 测试移除流动性
    function testBurn() public {
        // 先添加流动性
        uint128 liquidityAmount = 1000000;
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(liquidityAmount);
        pool.setMockTokenAmounts(amount0, amount1);
        
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidityAmount);
        
        // 记录状态
        uint256 lpToken0Before = token0.balanceOf(liquidityProvider);
        uint256 lpToken1Before = token1.balanceOf(liquidityProvider);
        uint128 poolLiquidityBefore = pool.getLiquidity();
        
        // 计算应该返还的token数量
        uint256 returnAmount0 = amount0 / 2;
        uint256 returnAmount1 = amount1 / 2;
        pool.setMockTokenAmounts(returnAmount0, returnAmount1);
        
        // 执行burn (移除一半流动性)
        uint128 burnAmount = liquidityAmount / 2;
        pool.burnMock(liquidityProvider, tickLower, tickUpper, burnAmount);
        vm.stopPrank();
        
        // 验证流动性减少
        uint128 poolLiquidityAfter = pool.getLiquidity();
        assertEq(uint256(poolLiquidityBefore - poolLiquidityAfter), uint256(burnAmount), "Liquidity should decrease by burn amount");
        
        // 验证token被返还
        uint256 lpToken0After = token0.balanceOf(liquidityProvider);
        uint256 lpToken1After = token1.balanceOf(liquidityProvider);
        assertEq(lpToken0After - lpToken0Before, returnAmount0, "LP should receive correct amount of token0");
        assertEq(lpToken1After - lpToken1Before, returnAmount1, "LP should receive correct amount of token1");
        
        // 验证流动性头寸被更新
        (uint128 positionLiquidity,,) = pool.positions(getPositionKey(liquidityProvider, tickLower, tickUpper));
        assertEq(uint256(positionLiquidity), uint256(liquidityAmount - burnAmount), "Position liquidity should be updated");
        
        emit log_named_uint("Liquidity burned:", burnAmount);
        emit log_named_uint("Token0 returned:", returnAmount0);
        emit log_named_uint("Token1 returned:", returnAmount1);
    }
    
    // 测试提取手续费
    function testCollect() public {
        // 先添加流动性
        uint128 liquidityAmount = 1000000;
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(liquidityAmount);
        pool.setMockTokenAmounts(amount0, amount1);
        
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidityAmount);
        
        // 模拟产生手续费
        uint256 fees0 = 10 ether;
        uint256 fees1 = 15 ether;
        pool.setMockFees(liquidityProvider, tickLower, tickUpper, fees0, fees1);
        
        // 记录状态
        uint256 lpToken0Before = token0.balanceOf(liquidityProvider);
        uint256 lpToken1Before = token1.balanceOf(liquidityProvider);
        
        // 执行collect
        pool.collectMock(liquidityProvider, tickLower, tickUpper);
        vm.stopPrank();
        
        // 验证手续费被提取
        uint256 lpToken0After = token0.balanceOf(liquidityProvider);
        uint256 lpToken1After = token1.balanceOf(liquidityProvider);
        assertEq(lpToken0After - lpToken0Before, fees0, "LP should receive correct fee amount of token0");
        assertEq(lpToken1After - lpToken1Before, fees1, "LP should receive correct fee amount of token1");
        
        // 验证手续费被清零
        (,uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = pool.positions(
            getPositionKey(liquidityProvider, tickLower, tickUpper)
        );
        assertEq(feeGrowthInside0X128, 0, "Fee growth for token0 should be reset");
        assertEq(feeGrowthInside1X128, 0, "Fee growth for token1 should be reset");
        
        emit log_named_uint("Fees collected for token0:", fees0);
        emit log_named_uint("Fees collected for token1:", fees1);
    }
    
    // 测试跨多次swap的手续费累积
    function testFeeGrowthAccumulation() public {
        // 先添加流动性
        uint128 liquidityAmount = 1000000;
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(liquidityAmount);
        pool.setMockTokenAmounts(amount0, amount1);
        
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidityAmount);
        vm.stopPrank();
        
        // 执行多次swap并产生手续费
        uint256 totalFees0 = 0;
        uint256 totalFees1 = 0;
        
        for (uint i = 0; i < 5; i++) {
            // 模拟swap产生的手续费
            uint256 swapFee0 = (i % 2 == 0) ? 1 ether : 0;
            uint256 swapFee1 = (i % 2 == 1) ? 2 ether : 0;
            
            pool.updateMockFeeGrowth(swapFee0, swapFee1);
            
            totalFees0 += swapFee0;
            totalFees1 += swapFee1;
            
            emit log_named_uint("Swap", i);
            emit log_named_uint("Fee0 generated:", swapFee0);
            emit log_named_uint("Fee1 generated:", swapFee1);
        }
        
        // 设置应该累积的手续费
        pool.setMockFees(liquidityProvider, tickLower, tickUpper, totalFees0, totalFees1);
        
        // 记录状态
        uint256 lpToken0Before = token0.balanceOf(liquidityProvider);
        uint256 lpToken1Before = token1.balanceOf(liquidityProvider);
        
        // 提取手续费
        vm.startPrank(liquidityProvider);
        pool.collectMock(liquidityProvider, tickLower, tickUpper);
        vm.stopPrank();
        
        // 验证累积的手续费被提取
        uint256 lpToken0After = token0.balanceOf(liquidityProvider);
        uint256 lpToken1After = token1.balanceOf(liquidityProvider);
        assertEq(lpToken0After - lpToken0Before, totalFees0, "LP should receive accumulated fee amount of token0");
        assertEq(lpToken1After - lpToken1Before, totalFees1, "LP should receive accumulated fee amount of token1");
        
        emit log_named_uint("Total fees collected for token0:", totalFees0);
        emit log_named_uint("Total fees collected for token1:", totalFees1);
    }
    
    // 简单的模糊测试：不同流动性量的添加和移除
    function testFuzzLiquidityOperations(uint128 liquidityAmount) public {
        // 限制输入范围，避免极端值
        vm.assume(liquidityAmount > 100);
        vm.assume(liquidityAmount < 1000000 ether);
        
        // 计算所需的token数量
        (uint256 amount0, uint256 amount1) = _calculateTokenAmounts(liquidityAmount);
        pool.setMockTokenAmounts(amount0, amount1);
        
        // 添加流动性
        vm.startPrank(liquidityProvider);
        pool.mintMock(liquidityProvider, tickLower, tickUpper, liquidityAmount);
        
        // 验证流动性添加
        uint128 poolLiquidity = pool.getLiquidity();
        assertEq(uint256(poolLiquidity), uint256(liquidityAmount), "Liquidity should match added amount");
        
        // 移除一半流动性
        uint128 burnAmount = liquidityAmount / 2;
        pool.setMockTokenAmounts(amount0 / 2, amount1 / 2);
        pool.burnMock(liquidityProvider, tickLower, tickUpper, burnAmount);
        vm.stopPrank();
        
        // 验证剩余流动性
        uint128 remainingLiquidity = pool.getLiquidity();
        assertEq(uint256(remainingLiquidity), uint256(liquidityAmount - burnAmount), "Remaining liquidity should be accurate");
    }
    
    // ======== 辅助方法 ========
    
    // 计算特定流动性量所需的token数量
    function _calculateTokenAmounts(uint128 liquidity) internal view returns (uint256 amount0, uint256 amount1) {
        // 这是一个简化的计算，在实际Uniswap V3中，计算会基于价格范围和流动性分布
        amount0 = uint256(liquidity) / 100;
        amount1 = uint256(liquidity) / 100;
    }
    
    // 计算头寸Key
    function getPositionKey(address _owner, int24 _tickLower, int24 _tickUpper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_owner, _tickLower, _tickUpper));
    }
}

// 扩展MockUniswapV3Pool以支持流动性测试
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    
    uint160 private _currentSqrtPriceX96;
    int24 private _currentTick;
    uint128 private _liquidity;
    
    // 流动性头寸
    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }
    
    // 头寸映射
    mapping(bytes32 => Position) public positions;
    
    // 全局手续费增长
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    
    // 模拟变量
    uint256 private _mockAmount0;
    uint256 private _mockAmount1;
    
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
    
    // 获取当前流动性
    function getLiquidity() external view returns (uint128) {
        return _liquidity;
    }
    
    // 设置模拟token数量
    function setMockTokenAmounts(uint256 amount0, uint256 amount1) external {
        _mockAmount0 = amount0;
        _mockAmount1 = amount1;
    }
    
    // 模拟mint操作
    function mintMock(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        // 更新总流动性
        _liquidity += amount;
        
        // 更新头寸
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positions[positionKey].liquidity += amount;
        
        // 转移token (模拟回调)
        IERC20Minimal(token0).transferFrom(msg.sender, address(this), _mockAmount0);
        IERC20Minimal(token1).transferFrom(msg.sender, address(this), _mockAmount1);
        
        return (_mockAmount0, _mockAmount1);
    }
    
    // 模拟burn操作
    function burnMock(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        // 检查流动性
        require(_liquidity >= amount, "Not enough liquidity");
        
        // 更新总流动性
        _liquidity -= amount;
        
        // 更新头寸
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        require(positions[positionKey].liquidity >= amount, "Not enough position liquidity");
        positions[positionKey].liquidity -= amount;
        
        // 返还token
        IERC20Minimal(token0).transfer(msg.sender, _mockAmount0);
        IERC20Minimal(token1).transfer(msg.sender, _mockAmount1);
        
        return (_mockAmount0, _mockAmount1);
    }
    
    // 设置模拟手续费
    function setMockFees(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint256 fees0,
        uint256 fees1
    ) external {
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positions[positionKey].feeGrowthInside0X128 = fees0;
        positions[positionKey].feeGrowthInside1X128 = fees1;
    }
    
    // 模拟collect操作
    function collectMock(
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 amount0, uint256 amount1) {
        // 获取头寸和应收手续费
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        Position storage position = positions[positionKey];
        
        amount0 = position.feeGrowthInside0X128;
        amount1 = position.feeGrowthInside1X128;
        
        // 重置手续费
        position.feeGrowthInside0X128 = 0;
        position.feeGrowthInside1X128 = 0;
        
        // 转移手续费
        if (amount0 > 0) {
            IERC20Minimal(token0).transfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20Minimal(token1).transfer(msg.sender, amount1);
        }
        
        return (amount0, amount1);
    }
    
    // 更新模拟全局手续费
    function updateMockFeeGrowth(uint256 fee0, uint256 fee1) external {
        feeGrowthGlobal0X128 += fee0;
        feeGrowthGlobal1X128 += fee1;
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
    
    // 模拟swap函数 (保留此接口以保持兼容性)
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        return (0, 0);
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