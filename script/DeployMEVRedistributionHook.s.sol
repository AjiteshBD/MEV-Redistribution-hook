// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MEVRedistributionHook} from "../src/MEVRedistributionHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {console} from "forge-std/console.sol";

contract DeployMEVRedistributionHook is Script {
    function run() external {
        // Load deployer's private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Define the PoolManager and reward token addresses
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address rewardTokenAddress = vm.envAddress("REWARD_TOKEN_ADDRESS");

        // Initialize interfaces
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        ERC20 rewardToken = ERC20(rewardTokenAddress);

        // Deploy the MEVRedistributionHook contract
        MEVRedistributionHook hook =
            new MEVRedistributionHook(poolManager, "MEV Redistribution Token", rewardToken, "MEVRT");

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("MEVRedistributionHook deployed at:", address(hook));
    }
}
