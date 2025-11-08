// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EcosystemLeadNFT} from "../nft/EcosystemLeadNFT.sol";

/**
 * @title Ecosystem Governance Executor
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Executes governance decisions from voting mechanism
 * @dev Acts as bridge between voting contracts and controlled contracts
 *
 *      EXECUTION FLOW:
 *      ═══════════════════════════════════
 *      1. Voting mechanism passes proposal
 *      2. Shares minted to this executor
 *      3. Executor redeems shares and executes action
 *      4. Action: Mint NFT, transfer funds, update parameters
 *
 *      GOVERNANCE ACTIONS:
 *      ═══════════════════════════════════
 *      - Mint Ecosystem Lead NFTs
 *      - Revoke NFTs from members
 *      - Transfer governance tokens
 *      - Update protocol parameters
 *      - Execute arbitrary governance calls
 *
 *      SECURITY:
 *      ═══════════════════════════════════
 *      - Only authorized voting contracts can trigger
 *      - Timelock enforced by voting mechanism
 *      - Multi-step process prevents hasty decisions
 *
 * @custom:security Executor should own controlled contracts
 * @custom:security Only voting mechanisms should be able to execute
 */
contract EcosystemGovernanceExecutor is Ownable {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Ecosystem Lead NFT contract
    EcosystemLeadNFT public immutable ecosystemLeadNFT;

    /// @notice Mapping of authorized voting contracts
    mapping(address => bool) public authorizedVoters;

    // ============================================
    // EVENTS
    // ============================================

    event VoterAuthorized(address indexed voter);
    event VoterRevoked(address indexed voter);
    event NFTMinted(address indexed recipient, uint256 tokenId);
    event NFTRevoked(address indexed from, uint256 tokenId);
    event ActionExecuted(address indexed target, bytes data, uint256 value);

    // ============================================
    // ERRORS
    // ============================================

    error NotAuthorizedVoter(address caller);
    error ExecutionFailed(bytes returnData);

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyAuthorizedVoter() {
        if (!authorizedVoters[msg.sender]) {
            revert NotAuthorizedVoter(msg.sender);
        }
        _;
    }

    modifier onlyOwnerOrAuthorizedVoter() {
        if (msg.sender != owner() && !authorizedVoters[msg.sender]) {
            revert NotAuthorizedVoter(msg.sender);
        }
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize governance executor
     * @param _ecosystemLeadNFT Address of Ecosystem Lead NFT contract
     * @param _owner Initial owner (can authorize voters)
     */
    constructor(address _ecosystemLeadNFT, address _owner) Ownable(_owner) {
        ecosystemLeadNFT = EcosystemLeadNFT(_ecosystemLeadNFT);
    }

    // ============================================
    // VOTING AUTHORIZATION
    // ============================================

    /**
     * @notice Authorize voting contract to execute actions
     * @param voter Address of voting mechanism
     */
    function authorizeVoter(address voter) external onlyOwner {
        authorizedVoters[voter] = true;
        emit VoterAuthorized(voter);
    }

    /**
     * @notice Revoke authorization from voting contract
     * @param voter Address of voting mechanism
     */
    function revokeVoter(address voter) external onlyOwner {
        authorizedVoters[voter] = false;
        emit VoterRevoked(voter);
    }

    // ============================================
    // EXECUTION FUNCTIONS
    // ============================================

    /**
     * @notice Mint Ecosystem Lead NFT to address
     * @dev Called by owner or authorized voting contract
     * @param recipient Address to receive NFT
     * @return tokenId Minted token ID
     */
    function mintEcosystemLead(address recipient) external onlyOwnerOrAuthorizedVoter returns (uint256) {
        uint256 tokenId = ecosystemLeadNFT.mint(recipient);
        emit NFTMinted(recipient, tokenId);
        return tokenId;
    }

    /**
     * @notice Revoke Ecosystem Lead NFT from address
     * @dev Called by owner or authorized voting contract
     * @param from Address to revoke NFT from
     */
    function revokeEcosystemLead(address from) external onlyOwnerOrAuthorizedVoter {
        uint256 tokenId = ecosystemLeadNFT.addressToTokenId(from);
        ecosystemLeadNFT.revoke(from);
        emit NFTRevoked(from, tokenId);
    }

    /**
     * @notice Execute arbitrary governance action
     * @dev Called by owner or authorized voting contract
     * @param target Contract to call
     * @param data Calldata for the call
     * @param value ETH value to send
     * @return returnData Data returned from call
     */
    function executeAction(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyOwnerOrAuthorizedVoter returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call{value: value}(data);

        if (!success) {
            revert ExecutionFailed(returnData);
        }

        emit ActionExecuted(target, data, value);
        return returnData;
    }

    /**
     * @notice Batch execute multiple actions atomically
     * @dev All actions must succeed or entire batch reverts
     * @param targets Array of contracts to call
     * @param datas Array of calldata
     * @param values Array of ETH values
     */
    function batchExecuteActions(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    ) external onlyOwnerOrAuthorizedVoter {
        require(targets.length == datas.length && targets.length == values.length, "Array length mismatch");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returnData) = targets[i].call{value: values[i]}(datas[i]);

            if (!success) {
                revert ExecutionFailed(returnData);
            }

            emit ActionExecuted(targets[i], datas[i], values[i]);
        }
    }

    // ============================================
    // RECEIVE ETH
    // ============================================

    /**
     * @notice Allow contract to receive ETH for governance actions
     */
    receive() external payable {}
}
