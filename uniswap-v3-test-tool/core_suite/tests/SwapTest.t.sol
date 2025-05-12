// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/UniswapV3Pool.sol";
import "v3-core/contracts/UniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";
import "v3-core/contracts/libraries/FullMath.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

/**
 * @title UniswapV3Pool 简化测试套件
 */
contract SwapTest is Test, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    // Mock 代币
    MockERC20 public usdc;
    MockERC20 public weth;
    address public mockUSDC;
    address public mockWETH;

    // 测试账户
    address public trader = address(0x1);
    address public liquidityProvider = address(0x2);

    // 合约实例
    UniswapV3Factory public factory;
    UniswapV3Pool public pool;
    IERC20Minimal public token0;
    IERC20Minimal public token1;

    // Tick 参数
    int24 public lowerTick;
    int24 public upperTick;
    int24 public currentTick;
    uint160 public initialSqrtPriceX96;
    uint160 public sqrtPriceX96;

    // 流动性量
    uint128 public liquidityAmount = 1_000_000;

    function setUp() public {
        // 使用本地Anvil节点
        vm.createSelectFork("http://localhost:8545");

        // 部署 Mock 代币并按地址排序
        MockERC20 mockToken0 = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 mockToken1 = new MockERC20("USD Coin", "USDC", 6);
        if (address(mockToken0) > address(mockToken1)) {
            (mockToken0, mockToken1) = (mockToken1, mockToken0);
        }
        token0 = IERC20Minimal(address(mockToken0));
        token1 = IERC20Minimal(address(mockToken1));
        mockWETH = address(mockToken0);
        mockUSDC = address(mockToken1);
        usdc = mockToken1;
        weth = mockToken0;

        // Mint 代币给各账户
        mockToken0.mint(trader, 10_000 ether);
        mockToken1.mint(trader, 10_000e6);
        mockToken0.mint(liquidityProvider, 100_000 ether);
        mockToken1.mint(liquidityProvider, 100_000e6);

        // 部署 factory 并创建 pool
        factory = new UniswapV3Factory();
        pool = UniswapV3Pool(factory.createPool(address(token0), address(token1), 3000));

        // 初始化 pool 价格为 price = 5/10 = 0.5
        initialSqrtPriceX96 = encodePriceSqrt(5, 10);
        pool.initialize(initialSqrtPriceX96);
        (sqrtPriceX96, , , , , , ) = pool.slot0();

        // 计算 tick 范围
        int24 tickSpacing = pool.tickSpacing();
        (uint160 sqrtPriceX96Current, int24 current, , , , , ) = pool.slot0();
        currentTick = current;

        // 选择一个包含当前tick的范围
        lowerTick = ((currentTick - tickSpacing * 100) / tickSpacing) * tickSpacing;
        upperTick = ((currentTick + tickSpacing * 100) / tickSpacing) * tickSpacing;

        // 准备交易者授权
        vm.startPrank(trader);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // Mint 回调：LP 支付代币给 pool
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        address payer = abi.decode(data, (address));
        if (amount0Owed > 0) token0.transferFrom(payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) token1.transferFrom(payer, msg.sender, amount1Owed);
    }

    // Swap 回调：trader 支付/接收代币
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));
        if (amount0Delta < 0) token0.transferFrom(sender, msg.sender, uint256(-amount0Delta));
        if (amount1Delta < 0) token1.transferFrom(sender, msg.sender, uint256(-amount1Delta));
    }

    /// @notice 验证 pool initialize
    function testPoolInitialization() public {
        (uint160 currentPriceX96, , , , , , ) = pool.slot0();
        assertEq(uint256(currentPriceX96), uint256(initialSqrtPriceX96), "Initial price mismatch");
        assertEq(uint256(pool.fee()), uint256(3000), "Fee should be 3000");
    }

    /// @notice 测试价格限制
    function testPriceLimits() public {
        (uint160 currentPrice, , , , , , ) = pool.slot0();
        
        vm.startPrank(trader);
        vm.expectRevert(bytes("SPL"));
        pool.swap(
            trader,
            true,
            int256(1000 * 10**6),
            currentPrice, // 使用当前价格作为限制，即不允许价格变化
            abi.encode(trader)
        );
        vm.stopPrank();
    }

    /// @notice 测试编码价格函数
    function testEncodePriceSqrt() public {
        // 简单验证encodePriceSqrt函数运行不会失败
        uint160 result = encodePriceSqrt(1, 1);
        assertTrue(result > 0, "Encoding 1:1 price should not be zero");
        
        // 验证编码结果单调性
        uint160 half = encodePriceSqrt(2, 1);
        uint160 quarter = encodePriceSqrt(4, 1);
        assertTrue(half > quarter, "Price 1/2 should be greater than 1/4");
    }

    /// @notice 测试编码价格单调性
    function testPriceEncoding() public {
        // 验证不同价格的单调性
        uint160 price1 = encodePriceSqrt(1, 1);  // 1.0
        uint160 price2 = encodePriceSqrt(1, 2);  // 2.0
        uint160 price3 = encodePriceSqrt(1, 5);  // 5.0
        
        assertTrue(price3 > price2, "Higher price ratio should encode to higher sqrt price");
        assertTrue(price2 > price1, "Higher price ratio should encode to higher sqrt price");
    }

    /// @notice 测试Mock代币的基本功能
    function testMockTokens() public {
        // 测试铸造功能
        weth.mint(address(this), 1 ether);
        assertEq(uint256(weth.balanceOf(address(this))), uint256(1 ether), "Mint should increase balance");
        
        // 测试转账功能
        vm.prank(address(this));
        weth.transfer(trader, 0.5 ether);
        assertEq(uint256(weth.balanceOf(address(this))), uint256(0.5 ether), "Transfer should decrease sender's balance");
        assertEq(uint256(weth.balanceOf(trader)), uint256(10_000 ether + 0.5 ether), "Transfer should increase receiver's balance");
    }

    /// @notice 测试工厂合约的功能
    function testFactoryFunctions() public {
        // 测试getPool函数
        address poolAddress = factory.getPool(address(token0), address(token1), 3000);
        assertEq(poolAddress, address(pool), "Factory should return correct pool address");
        
        // 测试不存在的池
        address nonExistentPool = factory.getPool(address(token0), address(token1), 10000);
        assertEq(nonExistentPool, address(0), "Non-existent pool should return zero address");
    }

    // price → sqrtPriceX96
    function encodePriceSqrt(uint256 base, uint256 quote) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(
            TickMath.getTickAtSqrtRatio(
                uint160(FullMath.mulDiv(quote, 1 << 96, base))
            )
        );
    }
}

/// @notice 简化的 ERC20 Mock
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
