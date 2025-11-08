// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC5192 - Minimal Soulbound NFT Interface
 * @notice Interface for soulbound (non-transferable) tokens
 * @dev See https://eips.ethereum.org/EIPS/eip-5192
 */
interface IERC5192 {
    /// @notice Emitted when token is locked (made soulbound)
    event Locked(uint256 tokenId);

    /// @notice Emitted when token is unlocked (transferable again)
    event Unlocked(uint256 tokenId);

    /**
     * @notice Check if token is locked (non-transferable)
     * @param tokenId Token ID to check
     * @return locked True if token is locked
     */
    function locked(uint256 tokenId) external view returns (bool);
}
