// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title YieldDistributor
 * @notice Distributes yield to contributors using Merkle proofs
 * @dev Simple, gas-efficient distribution without pre-registration
 *
 * Key Features:
 * - Epoch-based distribution periods
 * - Direct claiming with Merkle proofs
 * - No pre-registration required
 * - Supports multiple assets (USDC, DAI, etc.)
 * - Prevents double-claiming per epoch
 */
contract YieldDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Epoch {
        bytes32 merkleRoot; // Merkle root for this epoch
        uint256 totalAmount; // Total amount to distribute
        address asset; // Asset address (USDC, DAI, etc.)
        uint256 startTime; // Epoch start timestamp
        uint256 endTime; // Epoch end timestamp (0 = no expiry)
        uint256 claimedAmount; // Amount claimed so far
        bool active; // Whether epoch is active
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current epoch ID (increments with each new epoch)
    uint256 public currentEpochId;

    /// @notice Mapping of epoch ID to Epoch data
    mapping(uint256 => Epoch) public epochs;

    /// @notice Mapping of epoch ID => contributor address => claimed status
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event EpochCreated(
        uint256 indexed epochId,
        bytes32 indexed merkleRoot,
        address indexed asset,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    );

    event YieldClaimed(
        uint256 indexed epochId, address indexed contributor, address indexed asset, uint256 amount
    );

    event EpochCancelled(uint256 indexed epochId);

    event EmergencyWithdraw(address indexed asset, uint256 amount, address indexed to);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error EpochNotActive();
    error EpochNotStarted();
    error EpochExpired();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidAmount();
    error InsufficientBalance();
    error InvalidEpochId();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the YieldDistributor
     * @param _owner Contract owner address
     */
    constructor(address _owner) Ownable(_owner) {
        currentEpochId = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        EPOCH MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new distribution epoch
     * @param merkleRoot Merkle root for contributor allocations
     * @param totalAmount Total amount to distribute
     * @param asset Asset address to distribute
     * @param startTime Epoch start timestamp
     * @param endTime Epoch end timestamp (0 for no expiry)
     * @return epochId The ID of the created epoch
     */
    function createEpoch(
        bytes32 merkleRoot,
        uint256 totalAmount,
        address asset,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner returns (uint256 epochId) {
        require(merkleRoot != bytes32(0), "Invalid merkle root");
        require(totalAmount > 0, "Invalid total amount");
        require(asset != address(0), "Invalid asset");
        require(startTime > 0, "Invalid start time");
        require(endTime == 0 || endTime > startTime, "Invalid end time");

        // Check that contract has sufficient balance
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < totalAmount) {
            revert InsufficientBalance();
        }

        epochId = ++currentEpochId;

        epochs[epochId] = Epoch({
            merkleRoot: merkleRoot,
            totalAmount: totalAmount,
            asset: asset,
            startTime: startTime,
            endTime: endTime,
            claimedAmount: 0,
            active: true
        });

        emit EpochCreated(epochId, merkleRoot, asset, totalAmount, startTime, endTime);
    }

    /**
     * @notice Cancel an active epoch (owner only)
     * @param epochId Epoch ID to cancel
     */
    function cancelEpoch(uint256 epochId) external onlyOwner {
        if (epochId == 0 || epochId > currentEpochId) {
            revert InvalidEpochId();
        }

        Epoch storage epoch = epochs[epochId];
        if (!epoch.active) {
            revert EpochNotActive();
        }

        epoch.active = false;
        emit EpochCancelled(epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim yield for a specific epoch
     * @param epochId Epoch ID to claim from
     * @param amount Amount allocated to the contributor
     * @param proof Merkle proof
     */
    function claim(uint256 epochId, uint256 amount, bytes32[] calldata proof) external nonReentrant {
        _claim(epochId, msg.sender, amount, proof);
    }

    /**
     * @notice Claim yield for multiple epochs in one transaction
     * @param epochIds Array of epoch IDs
     * @param amounts Array of amounts allocated
     * @param proofs Array of Merkle proofs
     */
    function claimMultiple(uint256[] calldata epochIds, uint256[] calldata amounts, bytes32[][] calldata proofs)
        external
        nonReentrant
    {
        require(epochIds.length == amounts.length && epochIds.length == proofs.length, "Array length mismatch");

        for (uint256 i = 0; i < epochIds.length; i++) {
            _claim(epochIds[i], msg.sender, amounts[i], proofs[i]);
        }
    }

    /**
     * @notice Internal claim function
     * @param epochId Epoch ID
     * @param contributor Contributor address
     * @param amount Amount to claim
     * @param proof Merkle proof
     */
    function _claim(uint256 epochId, address contributor, uint256 amount, bytes32[] calldata proof) internal {
        // Validate epoch ID
        if (epochId == 0 || epochId > currentEpochId) {
            revert InvalidEpochId();
        }

        Epoch storage epoch = epochs[epochId];

        // Check epoch is active
        if (!epoch.active) {
            revert EpochNotActive();
        }

        // Check epoch has started
        if (block.timestamp < epoch.startTime) {
            revert EpochNotStarted();
        }

        // Check epoch hasn't expired
        if (epoch.endTime > 0 && block.timestamp > epoch.endTime) {
            revert EpochExpired();
        }

        // Check not already claimed
        if (hasClaimed[epochId][contributor]) {
            revert AlreadyClaimed();
        }

        // Validate amount
        if (amount == 0) {
            revert InvalidAmount();
        }

        // Verify Merkle proof
        bytes32 leaf = _createLeaf(contributor, amount);
        if (!MerkleProof.verify(proof, epoch.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // Mark as claimed
        hasClaimed[epochId][contributor] = true;
        epoch.claimedAmount += amount;

        // Transfer tokens
        IERC20(epoch.asset).safeTransfer(contributor, amount);

        emit YieldClaimed(epochId, contributor, epoch.asset, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get epoch information
     * @param epochId Epoch ID
     * @return Epoch struct
     */
    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        if (epochId == 0 || epochId > currentEpochId) {
            revert InvalidEpochId();
        }
        return epochs[epochId];
    }

    /**
     * @notice Check if a contributor has claimed for an epoch
     * @param epochId Epoch ID
     * @param contributor Contributor address
     * @return bool True if claimed
     */
    function hasClaimedForEpoch(uint256 epochId, address contributor) external view returns (bool) {
        return hasClaimed[epochId][contributor];
    }

    /**
     * @notice Get remaining claimable amount for an epoch
     * @param epochId Epoch ID
     * @return uint256 Remaining amount
     */
    function getRemainingAmount(uint256 epochId) external view returns (uint256) {
        if (epochId == 0 || epochId > currentEpochId) {
            revert InvalidEpochId();
        }

        Epoch memory epoch = epochs[epochId];
        return epoch.totalAmount - epoch.claimedAmount;
    }

    /**
     * @notice Verify a claim proof without claiming (for frontend)
     * @param epochId Epoch ID
     * @param contributor Contributor address
     * @param amount Amount to verify
     * @param proof Merkle proof
     * @return bool True if proof is valid
     */
    function verifyClaim(uint256 epochId, address contributor, uint256 amount, bytes32[] calldata proof)
        external
        view
        returns (bool)
    {
        if (epochId == 0 || epochId > currentEpochId) {
            return false;
        }

        Epoch memory epoch = epochs[epochId];
        bytes32 leaf = _createLeaf(contributor, amount);
        return MerkleProof.verify(proof, epoch.merkleRoot, leaf);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency withdraw tokens (owner only)
     * @param asset Asset address
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function emergencyWithdraw(address asset, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        IERC20(asset).safeTransfer(to, amount);
        emit EmergencyWithdraw(asset, amount, to);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a leaf hash for Merkle tree
     * @param contributor Contributor's wallet
     * @param amount Amount allocated
     * @return bytes32 Leaf hash
     */
    function _createLeaf(address contributor, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contributor, amount));
    }
}
