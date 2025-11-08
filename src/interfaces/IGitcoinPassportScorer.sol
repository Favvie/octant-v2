// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGitcoinPassportScorer
 * @notice Interface for Gitcoin Passport Scorer contract
 * @dev Used for Sybil resistance in contributor voting mechanisms
 */
interface IGitcoinPassportScorer {
    /**
     * @notice Get the Gitcoin Passport score for an address
     * @param wallet Address to check
     * @return score Passport score (higher = more trustworthy)
     */
    function getScore(address wallet) external view returns (uint256 score);
}
