// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "v3-core/contracts/UniswapV3Pool.sol";

contract SpamSwaps is Script {
    function run() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        UniswapV3Pool pool = UniswapV3Pool(deployAddressHere); // 替换为实际部署地址

        uint256 rounds = vm.envUint("SWAP_ROUNDS"); // 例如 1000
        for (uint256 i = 0; i < rounds; i++) {
            pool.swap(address(this), true, 1 ether, 0, bytes(""));
        }
    }
}
