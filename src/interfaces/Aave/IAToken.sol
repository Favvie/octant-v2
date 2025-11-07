// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAToken
 * @notice Defines the basic interface for an AToken.
 * @dev Based on Aave v3 IAToken interface
 */
interface IAToken is IERC20 {
    /**
     * @notice Returns the address of the underlying asset of this aToken
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the Aave pool
     * @return The address of the pool
     */
    function POOL() external view returns (address);
}
