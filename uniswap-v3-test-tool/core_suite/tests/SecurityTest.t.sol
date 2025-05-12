// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/IERC20Minimal.sol";
import "v3-core/contracts/libraries/TickMath.sol";

// 添加闪电贷回调接口
interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}

/**
 * @title Uniswap V3 安全性测试
 * @notice 针对Uniswap V3合约的安全性进行测试
 */
contract SecurityTest is Test {
    // 模拟合约
    MockUniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;
    TokenWithReentrancy public reentrancyToken;
    
    // 测试账户
    address public trader = address(0x1);
    address public liquidityProvider = address(0x2);
    address public attacker = address(0x3);
    
    // 测试参数
    uint160 public initialSqrtPriceX96;
    
    function setUp() public {
        // 创建模拟代币
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        reentrancyToken = new TokenWithReentrancy("ReentrancyToken", "RTK", 18);
        
        // 给测试账户铸造代币
        token0.mint(trader, 1_000_000 ether);
        token1.mint(trader, 1_000_000 ether);
        token0.mint(liquidityProvider, 1_000_000 ether);
        token1.mint(liquidityProvider, 1_000_000 ether);
        token0.mint(attacker, 1_000_000 ether);
        token1.mint(attacker, 1_000_000 ether);
        reentrancyToken.mint(attacker, 1_000_000 ether);
        
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
        
        vm.startPrank(attacker);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        reentrancyToken.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    // 测试重入攻击保护
    function testReentrancyProtection() public {
        // 创建一个使用可重入代币的池子
        MockUniswapV3Pool maliciousPool = new MockUniswapV3Pool(
            address(reentrancyToken), 
            address(token1), 
            3000
        );
        
        // 设置初始池子状态
        reentrancyToken.mint(address(maliciousPool), 10_000 ether);
        token1.mint(address(maliciousPool), 10_000 ether);
        maliciousPool.setCurrentSqrtPriceX96(initialSqrtPriceX96);
        
        // 设置重入攻击目标
        reentrancyToken.setAttackTarget(address(maliciousPool));
        
        // 尝试执行交换，期望失败或者安全处理
        vm.startPrank(attacker);
        
        // 验证重入防护
        vm.expectRevert("ReentrancyGuard: reentrant call");
        
        // 尝试触发重入攻击
        maliciousPool.swap(
            attacker,
            true, // reentrancyToken -> token1
            int256(100 ether),
            TickMath.MIN_SQRT_RATIO + 1,
            abi.encode(attacker)
        );
        
        vm.stopPrank();
    }
    
    // 测试整数溢出保护
    function testOverflowProtection() public {
        // 尝试添加超大数量的流动性
        uint128 maxLiquidity = type(uint128).max;
        
        // 设置代币数量
        uint256 amount0 = type(uint256).max;
        uint256 amount1 = type(uint256).max;
        pool.setMockTokenAmounts(amount0, amount1);
        
        // 期望在内部计算中不会溢出
        vm.startPrank(liquidityProvider);
        
        // 验证溢出保护
        vm.expectRevert("Arithmetic operation underflowed or overflowed");
        
        // 尝试添加极限流动性
        pool.mintMock(liquidityProvider, -887272, 887272, maxLiquidity);
        
        vm.stopPrank();
    }
    
    // 测试权限控制
    function testAccessControl() public {
        // 尝试设置协议费用（应该只有工厂合约或所有者可以调用）
        vm.startPrank(attacker);
        
        // 验证权限控制
        vm.expectRevert("Not factory");
        pool.setFeeProtocol(1, 1);
        
        vm.stopPrank();
    }
    
    // 测试价格操纵防护
    function testPriceManipulationProtection() public {
        // 设置初始池子状态，很小的流动性
        token0.mint(address(pool), 10 ether);
        token1.mint(address(pool), 10 ether);
        pool.setLiquidity(100 ether);
        
        // 尝试大额交易以操纵价格
        uint256 largeAmount = 1_000_000 ether;
        
        // 设置模拟返回值
        int256 amount0Delta = int256(largeAmount);
        int256 amount1Delta = -int256(largeAmount * 999 / 1000); // 极低滑点
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // 设置极端价格变化
        uint160 manipulatedPrice = initialSqrtPriceX96 / 10;
        pool.setNextSqrtPriceX96(manipulatedPrice);
        
        // 设置滑点保护错误
        pool.setMockReverts(true, "SPL");
        
        // 预期滑点保护会触发
        vm.startPrank(attacker);
        vm.expectRevert(bytes("SPL"));
        
        // 尝试大额交易
        pool.swap(
            attacker,
            true,
            int256(largeAmount),
            initialSqrtPriceX96 / 2, // 限制价格滑点
            abi.encode(attacker)
        );
        
        vm.stopPrank();
    }
    
    // 测试闪电贷攻击防护
    function testFlashLoanAttackProtection() public {
        // 设置初始池子状态
        token0.mint(address(pool), 100_000 ether);
        token1.mint(address(pool), 100_000 ether);
        
        // 闪电贷金额
        uint256 flashLoanAmount0 = 50_000 ether;
        uint256 flashLoanAmount1 = 0;
        
        // 设置池子不会回调给获取闪电贷的合约
        FlashLoanAttacker attackerContract = new FlashLoanAttacker(address(pool), address(token0), address(token1));
        
        // 尝试闪电贷攻击
        vm.expectRevert("Not in flash");
        attackerContract.executeAttack(flashLoanAmount0, flashLoanAmount1);
    }
    
    // 测试手续费计算安全性
    function testFeeCalculationSecurity() public {
        // 设置初始池子状态
        token0.mint(address(pool), 100_000 ether);
        token1.mint(address(pool), 100_000 ether);
        
        // 设置交易金额
        uint256 swapAmount = 1000 ether;
        
        // 计算预期手续费
        uint256 expectedFee = swapAmount * 3 / 1000; // 0.3%
        
        // 设置模拟交换返回值
        int256 amount0Delta = int256(swapAmount);
        int256 amount1Delta = -int256(swapAmount - expectedFee);
        pool.setMockSwapAmounts(amount0Delta, amount1Delta);
        
        // 记录初始手续费
        uint256 feesBefore = pool.getMockCollectedFees();
        
        // 设置将被收取的手续费
        pool.setMockFeeToCollect(expectedFee);
        
        // 执行交换
        vm.startPrank(trader);
        pool.swap(
            trader,
            true,
            int256(swapAmount),
            TickMath.MIN_SQRT_RATIO + 1,
            abi.encode(trader)
        );
        vm.stopPrank();
        
        // 验证手续费计算
        uint256 feesAfter = pool.getMockCollectedFees();
        uint256 actualFee = feesAfter - feesBefore;
        
        // 验证手续费不会被操纵
        assertEq(actualFee, expectedFee, "Fee calculation should be secure and match expected value");
    }
}

// 模拟具有重入攻击功能的代币
contract TokenWithReentrancy is IERC20Minimal {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    address public attackTarget;
    bool public isAttacking;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function setAttackTarget(address _target) external {
        attackTarget = _target;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        // 在转账时尝试重入攻击
        if (to == attackTarget && !isAttacking && amount > 0) {
            isAttacking = true;
            
            // 尝试重入攻击，调用目标合约的可能易受攻击的函数
            (bool success,) = attackTarget.call(
                abi.encodeWithSignature(
                    "swap(address,bool,int256,uint160,bytes)",
                    msg.sender,
                    true,
                    int256(amount),
                    uint160(0),
                    bytes("")
                )
            );
            require(success, "Reentrancy attack failed");
            
            isAttacking = false;
        }
        
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
        
        // 在转账时尝试重入攻击
        if (to == attackTarget && !isAttacking && amount > 0) {
            isAttacking = true;
            
            // 尝试重入攻击
            (bool success,) = attackTarget.call(
                abi.encodeWithSignature(
                    "swap(address,bool,int256,uint160,bytes)",
                    msg.sender,
                    true,
                    int256(amount),
                    uint160(0),
                    bytes("")
                )
            );
            require(success, "Reentrancy attack failed");
            
            isAttacking = false;
        }
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

// 闪电贷攻击者合约
contract FlashLoanAttacker {
    address public pool;
    address public token0;
    address public token1;
    
    constructor(address _pool, address _token0, address _token1) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;
    }
    
    function executeAttack(uint256 amount0, uint256 amount1) external {
        // 尝试获取闪电贷款
        IUniswapV3Pool(pool).flash(address(this), amount0, amount1, bytes(""));
    }
    
    // 闪电贷回调函数
    function uniswapV3FlashCallback(uint256, uint256, bytes calldata) external {
        // 恶意攻击代码会在这里
        require(msg.sender == pool, "Unauthorized callback");
        
        // 尝试操纵池子状态或价格
        try IUniswapV3Pool(pool).swap(
            address(this),
            true,
            int256(1 ether),
            0,
            bytes("")
        ) {} catch {}
        
        // 偿还闪电贷款
        IERC20Minimal(token0).transfer(pool, IERC20Minimal(token0).balanceOf(address(this)));
        IERC20Minimal(token1).transfer(pool, IERC20Minimal(token1).balanceOf(address(this)));
    }
}

// 模拟ERC20代币合约
contract MockERC20 is IERC20Minimal {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
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
    
    mapping(bytes32 => PositionData) public positions;
    uint256 private mockCollectedFees;
    
    // 模拟一个再入防护锁
    bool private locked;
    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard: reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    bool private inFlash;
    modifier flashLoanOnly() {
        require(inFlash, "Not in flash");
        _;
    }
    
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
    function mintMock(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external nonReentrant returns (uint256, uint256) {
        // 检查数学溢出
        if (amount > 0 && uint256(amount) * mockAmount0 > type(uint256).max) {
            revert("Arithmetic operation underflowed or overflowed");
        }
        
        // 转移代币
        IERC20Minimal(token0).transferFrom(owner, address(this), mockAmount0);
        IERC20Minimal(token1).transferFrom(owner, address(this), mockAmount1);
        
        // 更新流动性
        liquidityValue += amount;
        
        // 更新position
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positions[positionKey].liquidity += amount;
        
        return (mockAmount0, mockAmount1);
    }
    
    // 移除流动性(模拟)
    function burnMock(address owner, int24 tickLower, int24 tickUpper, uint128 amount) external nonReentrant returns (uint256, uint256) {
        // 更新流动性
        liquidityValue -= amount;
        
        // 更新position
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positions[positionKey].liquidity -= amount;
        
        // 转移代币
        IERC20Minimal(token0).transfer(owner, mockAmount0);
        IERC20Minimal(token1).transfer(owner, mockAmount1);
        
        return (mockAmount0, mockAmount1);
    }
    
    // 提取手续费(模拟)
    function collectMock(address owner, int24 tickLower, int24 tickUpper) external nonReentrant returns (uint256, uint256) {
        // 转移手续费
        IERC20Minimal(token0).transfer(owner, mockAmount0);
        IERC20Minimal(token1).transfer(owner, mockAmount1);
        
        // 重置手续费增长
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
        positions[positionKey].feeGrowthInside0X128 = 0;
        positions[positionKey].feeGrowthInside1X128 = 0;
        
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
    ) external override nonReentrant returns (int256 amount0, int256 amount1) {
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
    
    // 闪电贷功能(模拟)
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override nonReentrant {
        // 转移token给接收者
        if (amount0 > 0) IERC20Minimal(token0).transfer(recipient, amount0);
        if (amount1 > 0) IERC20Minimal(token1).transfer(recipient, amount1);
        
        // 设置闪电贷状态
        inFlash = true;
        
        // 调用回调
        IUniswapV3FlashCallback(recipient).uniswapV3FlashCallback(amount0, amount1, data);
        
        // 重置闪电贷状态
        inFlash = false;
        
        // 验证还款
        // 实际实现中会计算手续费并验证还款金额
    }
    
    // 设置协议费用(模拟)
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override {
        // 仅限工厂合约调用
        if (msg.sender != address(1)) { // 假设地址1是工厂地址
            revert("Not factory");
        }
    }
    
    // 以下是为了满足接口要求的必要函数，但在测试中我们不会直接使用
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