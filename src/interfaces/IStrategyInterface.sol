// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    /**
     * @notice Returns the dragon router address that receives donated yields
     * @return The address of the dragon router
     */
    function dragonRouter() external view returns (address);

    /**
     * @notice Returns the current balance of aTokens held by the strategy (Aave-specific)
     * @return The aToken balance
     */
    function balanceOfAToken() external view returns (uint256);

    /**
     * @notice Returns the estimated APR from the yield source
     * @return The estimated APR
     */
    function estimatedAPR() external view returns (uint256);
}
