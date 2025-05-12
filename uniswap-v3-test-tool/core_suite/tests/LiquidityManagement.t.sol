// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/UniswapV3Factory.sol";
import "v3-core/contracts/UniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/SqrtPriceMath.sol";
import "v3-core/contracts/libraries/FullMath.sol";

/**
 * @title UniswapV3Pool 简化流动性管理测试
 */
contract LiquidityManagementTest is Test {
    // 测试Token合约
    MockERC20 public usdc;
    MockERC20 public weth;
    address public mockUSDC;
    address public mockWETH;
    
    // 测试账户
    address public liquidityProvider = address(0x1);
    address public trader = address(0x2);
    
    // 合约实例
    UniswapV3Factory public factory;
    UniswapV3Pool public pool;
    IERC20Minimal public token0;
    IERC20Minimal public token1;
    
    // 测试参数
    int24 public lowerTick;
    int24 public upperTick;
    uint160 public initialSqrtPriceX96;
    
    function setUp() public {
        // 使用本地Anvil节点
        vm.createSelectFork("http://localhost:8545");
        
        // 创建模拟代币
        MockERC20 mockToken0 = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 mockToken1 = new MockERC20("USD Coin", "USDC", 6);
        if (address(mockToken0) > address(mockToken1)) {
            (mockToken0, mockToken1) = (mockToken1, mockToken0);
        }
        token0 = IERC20Minimal(address(mockToken0));
        token1 = IERC20Minimal(address(mockToken1));
        mockUSDC = address(mockToken1);
        mockWETH = address(mockToken0);
        usdc = mockToken1;
        weth = mockToken0;
        
        // 给测试账户铸造代币
        mockToken0.mint(liquidityProvider, 1_000_000 ether);
        mockToken1.mint(liquidityProvider, 1_000_000 * 10**6);
        mockToken0.mint(trader, 10_000 ether);
        mockToken1.mint(trader, 10_000 * 10**6);
        
        // 部署工厂合约并创建池
        factory = new UniswapV3Factory();
        pool = UniswapV3Pool(factory.createPool(address(token0), address(token1), 3000));
        
        // 初始化价格 (1 = 1)
        initialSqrtPriceX96 = encodePriceSqrt(1, 1);
        pool.initialize(initialSqrtPriceX96);
        
        // 计算tick范围
        int24 tickSpacing = pool.tickSpacing();
        (uint160 sqrtPriceX96Current, int24 currentTick, , , , , ) = pool.slot0();
        
        // 选择一个包含当前tick的范围
        lowerTick = ((currentTick - tickSpacing * 100) / tickSpacing) * tickSpacing;
        upperTick = ((currentTick + tickSpacing * 100) / tickSpacing) * tickSpacing;
        
        // 授权
        vm.startPrank(liquidityProvider);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(trader);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    // 测试初始化池
    function testPoolInitialization() public {
        (uint160 currentPriceX96, , , , , , ) = pool.slot0();
        assertEq(uint256(currentPriceX96), uint256(initialSqrtPriceX96), "Initial price mismatch");
        assertEq(uint256(pool.fee()), uint256(3000), "Fee should be 3000");
    }
    
    // 测试授权
    function testApprovals() public {
        uint256 token0Allowance = token0.allowance(liquidityProvider, address(pool));
        uint256 token1Allowance = token1.allowance(liquidityProvider, address(pool));
        
        assertTrue(token0Allowance > 0, "Token0 allowance should be positive");
        assertTrue(token1Allowance > 0, "Token1 allowance should be positive");
    }
    
    // 测试token铸造功能
    function testTokenMint() public {
        uint256 initialBalance = token0.balanceOf(address(this));
        uint256 mintAmount = 10 ether;
        
        weth.mint(address(this), mintAmount);
        
        uint256 finalBalance = token0.balanceOf(address(this));
        assertEq(finalBalance - initialBalance, mintAmount, "Mint should increase balance by correct amount");
    }
    
    // 测试factory功能
    function testFactoryFunctions() public {
        address poolAddress = factory.getPool(address(token0), address(token1), 3000);
        assertEq(poolAddress, address(pool), "Factory should return correct pool address");
        
        // 测试不存在的池
        address nonExistentPool = factory.getPool(address(token0), address(token1), 10000);
        assertEq(nonExistentPool, address(0), "Non-existent pool should return zero address");
    }
    
    // 编码价格
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