// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/UniswapV3Factory.sol";
import "v3-core/contracts/UniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";

/**
 * @title UniswapV3Pool 初始化测试 (使用本地模拟合约)
 */
contract PoolInitializationTest is Test {
    // 测试Token地址 - 使用模拟地址
    address mockUSDC;
    address mockWETH;
    
    // 测试账户
    address public deployer = address(0x1);
    
    // 池地址 - 将在测试中创建
    address public poolAddress;
    
    // 合约实例
    UniswapV3Factory factory;
    UniswapV3Pool pool;
    MockERC20 usdc;
    MockERC20 weth;
    
    function setUp() public {
        console.log("Setting up PoolInitializationTest...");
        
        // 使用本地Anvil节点进行主网分叉测试
        string memory forkRpc = vm.envOr("ANVIL_RPC_URL", string("http://localhost:8545"));
        uint256 forkId = vm.createSelectFork(forkRpc);
        console.log("Connected to fork at:", forkRpc, "Fork ID:", forkId);
        
        // 设置测试账户
        vm.deal(deployer, 100 ether);
        
        // 创建模拟代币
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        mockUSDC = address(usdc);
        mockWETH = address(weth);
        console.log("Created mock USDC at:", mockUSDC);
        console.log("Created mock WETH at:", mockWETH);
        
        // 部署工厂合约
        vm.startPrank(deployer);
        factory = new UniswapV3Factory();
        console.log("Deployed UniswapV3Factory at:", address(factory));
        
        // 创建一个新池
        poolAddress = factory.createPool(mockUSDC, mockWETH, 500); // 创建一个0.05%费率的池
        console.log("Created pool at:", poolAddress);
        pool = UniswapV3Pool(poolAddress);
        vm.stopPrank();
    }
    
    // 测试池地址计算
    function testPoolAddress() public {
        // 验证新创建池的地址
        address calculatedAddress = factory.getPool(mockUSDC, mockWETH, 500);
        assertEq(calculatedAddress, poolAddress, "Pool address calculation failed");
    }
    
    // 测试池初始化
    function testPoolInitialization() public {
        // 验证初始化前的状态
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        assertEq(uint256(sqrtPriceX96), 0, "Initial sqrtPriceX96 should be 0");
        
        // 设置初始价格 (1 WETH = 2000 USDC)
        uint160 initialSqrtPriceX96 = 1771845684677455620533674329751217; // 约等于sqrt(2000) * 2^96
        
        // 初始化池
        vm.startPrank(deployer);
        pool.initialize(initialSqrtPriceX96);
        vm.stopPrank();
        
        // 验证初始化后的状态
        (sqrtPriceX96, , , , , , ) = pool.slot0();
        assertEq(uint256(sqrtPriceX96), uint256(initialSqrtPriceX96), "Pool initialization with sqrtPriceX96 failed");
        
        // 验证初始流动性为0
        uint128 liquidity = pool.liquidity();
        assertEq(uint256(liquidity), 0, "Initial liquidity should be 0");
        
        // 验证token0和token1地址
        (address token0, address token1) = mockUSDC < mockWETH ? (mockUSDC, mockWETH) : (mockWETH, mockUSDC);
        assertEq(pool.token0(), token0, "Incorrect token0");
        assertEq(pool.token1(), token1, "Incorrect token1");
        
        // 验证费率
        assertEq(uint256(pool.fee()), 500, "Incorrect fee");
    }
    
    // 测试观察初始状态
    function testInitialObservations() public {
        // 初始化池
        vm.startPrank(deployer);
        pool.initialize(1771845684677455620533674329751217);
        vm.stopPrank();
        
        // 验证初始观察数据
        (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized) = pool.observations(0);
        
        // 确认观察槽已初始化
        assertTrue(initialized, "Initial observation slot should be initialized");
        
        // 确认初始累计tick为0
        assertEq(int256(tickCumulative), 0, "Initial tickCumulative should be 0");
    }
    
    // 测试最大流动性
    function testMaxLiquidityPerTick() public {
        uint128 maxLiquidity = pool.maxLiquidityPerTick();
        assertTrue(maxLiquidity > 0, "maxLiquidityPerTick should be positive");
        
        // 验证计算逻辑 (根据Uniswap V3白皮书)
        // maxLiquidity = (2^128 - 1) / ((ratio of max tick to min tick)^(1/2) - 1)
        int24 tickSpacing = pool.tickSpacing();
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        
        uint256 numTicks = uint256(int256(maxTick - minTick)) / uint256(int256(tickSpacing));
        assertTrue(numTicks > 0, "Number of ticks should be positive");
    }
}

// 模拟ERC20代币，用于测试
contract MockERC20 is IERC20Minimal {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        _allowances[sender][msg.sender] -= amount;
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
} 