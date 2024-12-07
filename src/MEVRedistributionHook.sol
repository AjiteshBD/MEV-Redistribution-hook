// pragma solidity ^0.8.0;

// import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
// import {PoolManager} from "v4-periphery/lib/v4-core/src/PoolManager.sol";

// import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
// import {PoolKey} from "v4-core/types/PoolKey.sol";
// import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
// import {ERC20} from "solmate/src/tokens/ERC20.sol";
// import {Hooks} from "v4-core/libraries/Hooks.sol";

// contract MEVRedistributionHook is BaseHook, ERC20 {
//     // Use CurrencyLibrary and BalanceDeltaLibrary
//     // to add some helper functions over the Currency and BalanceDelta
//     // data types
//     using CurrencyLibrary for Currency;
//     using BalanceDeltaLibrary for BalanceDelta;

//     ERC20 public token;
//     address[] public lpAddresses; // List of LP addresses
//     mapping(address => uint256) public lpShares; // Mapping of LP shares
//     uint256 public totalShares; // Total shares of all LPs
//     uint256 public totalMEVCaptured; // Total MEV captured

//     // Initialize BaseHook and ERC20
//     constructor(IPoolManager _manager, string memory _name, ERC20 _rewardToken, string memory _symbol)
//         BaseHook(_manager)
//         ERC20(_name, _symbol, 18)
//     {
//         token = _rewardToken;
//     }

//     // Set up hook permissions to return `true`
//     // for the two hook functions we are using
//     function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
//         return Hooks.Permissions({
//             beforeInitialize: false,
//             afterInitialize: false,
//             beforeAddLiquidity: false,
//             beforeRemoveLiquidity: false,
//             afterAddLiquidity: true,
//             afterRemoveLiquidity: false,
//             beforeSwap: false,
//             afterSwap: true,
//             beforeDonate: false,
//             afterDonate: false,
//             beforeSwapReturnDelta: false,
//             afterSwapReturnDelta: false,
//             afterAddLiquidityReturnDelta: false,
//             afterRemoveLiquidityReturnDelta: false
//         });
//     }

//     // Function to update LP shares
//     function _updateLPShares(address lp, uint256 amount) public {
//         if (lpShares[lp] == 0) {
//             lpAddresses.push(lp);
//         }
//         lpShares[lp] += amount;
//         totalShares += amount;
//     }

//     // Function to capture MEV from swap delta
//     function _captureMEV(BalanceDelta delta) public returns (uint256) {
//         uint256 mevAmount = _abs(delta.amount0()) + _abs(delta.amount1());
//         totalMEVCaptured += mevAmount;
//         return mevAmount;
//     }

//     function _abs(int128 x) internal pure returns (uint128) {
//         return uint128(x >= 0 ? x : -x);
//     }

//     // Function to distribute MEV profits proportionally to LPs
//     function _distributeMEVProfits(uint256 mevAmount) public {
//         require(totalShares > 0, "No liquidity providers to distribute MEV to");

//         for (uint256 i = 0; i < lpAddresses.length; i++) {
//             address lp = lpAddresses[i];
//             uint256 share = (lpShares[lp] * mevAmount) / totalShares;
//             if (share > 0) {
//                 require(token.transfer(lp, share), "MEV transfer failed");
//             }
//         }
//     }

//     function afterSwap(
//         address sender,
//         PoolKey calldata key,
//         IPoolManager.SwapParams calldata params,
//         BalanceDelta delta,
//         bytes calldata data
//     ) external override returns (bytes4, int128) {
//         uint256 mevCaptured = _captureMEV(delta);
//         _distributeMEVProfits(mevCaptured);
//         return (this.afterSwap.selector, 0);
//     }

//     function afterAddLiquidity(
//         address,
//         PoolKey calldata key,
//         IPoolManager.ModifyLiquidityParams calldata,
//         BalanceDelta delta,
//         BalanceDelta,
//         bytes calldata hookData
//     ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
//         // If this is not an ETH-TOKEN pool with this hook attached, ignore
//         if (!key.currency0.isAddressZero()) {
//             return (this.afterSwap.selector, delta);
//         }

//         // Mint points equivalent to how much ETH they're adding in liquidity
//         uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));

//         // Mint the points including any referral points
//         _updateLPShares(msg.sender, pointsForAddingLiquidity);

//         return (this.afterAddLiquidity.selector, delta);
//     }
// }

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {PoolManager} from "v4-periphery/lib/v4-core/src/PoolManager.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract MEVRedistributionHook is BaseHook, ERC20 {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    ERC20 public token;
    address[] public lpAddresses; // List of LP addresses
    mapping(address => uint256) public lpShares; // Mapping of LP shares
    uint256 public totalShares; // Total shares of all LPs
    uint256 public totalMEVCaptured; // Total MEV captured

    // Event declarations
    event MEVCaptured(uint256 amount);
    event MEVDistributed(address indexed lp, uint256 amount);
    event MEVOpportunityDetected(address indexed user, int128 amount);

    // Initialize BaseHook and ERC20
    constructor(IPoolManager _manager, string memory _name, ERC20 _rewardToken, string memory _symbol)
        BaseHook(_manager)
        ERC20(_name, _symbol, 18)
    {
        token = _rewardToken;
    }

    // Set up hook permissions to return `true`
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Function to update LP shares
    function _updateLPShares(address lp, uint256 amount) public {
        if (lpShares[lp] == 0) {
            lpAddresses.push(lp);
        }
        lpShares[lp] += amount;
        totalShares += amount;
    }

    // Function to capture MEV from swap delta
    function _captureMEV(BalanceDelta delta) internal returns (uint256) {
        uint256 mevAmount = _abs(delta.amount0()) + _abs(delta.amount1());
        totalMEVCaptured += mevAmount;
        emit MEVCaptured(mevAmount); // Emit event for captured MEV
        return mevAmount;
    }

    function _abs(int128 x) internal pure returns (uint128) {
        return uint128(x >= 0 ? x : -x);
    }

    // Function to distribute MEV profits proportionally to LPs
    function _distributeMEVProfits(uint256 mevAmount) internal {
        require(totalShares > 0, "No liquidity providers to distribute MEV to");

        for (uint256 i = 0; i < lpAddresses.length; i++) {
            address lp = lpAddresses[i];
            uint256 share = (lpShares[lp] * mevAmount) / totalShares;
            if (share > 0) {
                require(token.transfer(lp, share), "MEV transfer failed");
                emit MEVDistributed(lp, share); // Emit event for distributed MEV
            }
        }
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override returns (bytes4, int128) {
        // Detect potential MEV opportunity based on swap parameters
        if (isPotentialMEVOpportunity(delta)) {
            emit MEVOpportunityDetected(sender, delta.amount0() + delta.amount1());
        }
        uint256 mevCaptured = _captureMEV(delta);
        // uint256 poolBalance = token.balanceOf(address(poolManager));
        // require(poolBalance >= mevCaptured, "Insufficient pool funds for MEV");

        _distributeMEVProfits(mevCaptured);

        return (this.afterSwap.selector, 0);
    }

    function isPotentialMEVOpportunity(BalanceDelta delta) internal pure returns (bool) {
        // Basic heuristic for detecting potential MEV opportunities
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Example condition: Check if the absolute value of either amount is above a certain threshold
        return (_abs(amount0) > 10 ether || _abs(amount1) > 10 ether); // Adjust threshold as necessary
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (!key.currency0.isAddressZero()) {
            return (this.afterSwap.selector, delta);
        }

        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));

        _updateLPShares(msg.sender, pointsForAddingLiquidity);

        return (this.afterAddLiquidity.selector, delta);
    }
}
