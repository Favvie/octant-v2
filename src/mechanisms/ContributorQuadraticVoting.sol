// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import { QuadraticVotingMechanism } from "../../dependencies/octant-v2-core/src/mechanisms/mechanism/QuadraticVotingMechanism.sol";
import { AllocationConfig } from "../../dependencies/octant-v2-core/src/mechanisms/BaseAllocationMechanism.sol";
import { TokenizedAllocationMechanism } from "../../dependencies/octant-v2-core/src/mechanisms/TokenizedAllocationMechanism.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IGitcoinPassportScorer } from "../interfaces/IGitcoinPassportScorer.sol";

/**
 * @title Contributor Quadratic Voting
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Extends Octant's QuadraticVotingMechanism with contributor-specific logic
 * @dev Integrates Merkle proof verification, GitHub contributor registry, and Gitcoin Passport
 *
 *      CONTRIBUTOR REGISTRATION:
 *      ═══════════════════════════════════
 *      - Contributors must provide Merkle proof of eligibility
 *      - Each contributor has a GitHub username and contribution score
 *      - Voting power derived from contribution score (sqrt formula)
 *      - One-time registration per contributor (enforced by parent)
 *
 *      MERKLE PROOF SYSTEM:
 *      ═══════════════════════════════════
 *      - Gas-efficient verification of contributor eligibility
 *      - Leaf format: keccak256(abi.encodePacked(wallet, github, score))
 *      - Updatable Merkle root for new contributor batches
 *
 *      ANTI-SYBIL:
 *      ═══════════════════════════════════
 *      - Optional Gitcoin Passport integration
 *      - Minimum passport score requirement
 *      - Prevents low-quality participants
 *
 *      VOTING POWER CALCULATION:
 *      ═══════════════════════════════════
 *      - Based on contribution score (not token deposits)
 *      - Formula: votingPower = sqrt(contributionScore)
 *      - Normalized to 18 decimals for quadratic voting
 *      - Examples:
 *        - Score 100 → Voting Power 10
 *        - Score 400 → Voting Power 20 (4x score = 2x power)
 *        - Score 10,000 → Voting Power 100
 *
 * @custom:security Inherits all security features from QuadraticVotingMechanism
 * @custom:security Merkle proofs prevent unauthorized registrations
 */
contract ContributorQuadraticVoting is QuadraticVotingMechanism {
    using Math for uint256;

    // ============================================
    // STRUCTS
    // ============================================

    struct ContributorInfo {
        string github;
        uint256 score;
        uint256 votingPower;
        uint256 registeredAt;
        bool verified;
    }

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Current Merkle root for contributor verification
    bytes32 public merkleRoot;

    /// @notice Total number of registered contributors
    uint256 public totalContributors;

    /// @notice Mapping of wallet address to contributor info
    mapping(address => ContributorInfo) public contributors;

    /// @notice Mapping to prevent duplicate GitHub usernames
    mapping(string => address) public githubToAddress;

    /// @notice Minimum Gitcoin Passport score required (0 = disabled)
    uint256 public minPassportScore;

    /// @notice Address of Gitcoin Passport scorer (optional)
    address public passportScorer;

    // ============================================
    // EVENTS
    // ============================================

    event ContributorRegistered(address indexed wallet, string github, uint256 score, uint256 votingPower);
    event MerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event MinPassportScoreUpdated(uint256 oldScore, uint256 newScore);
    event PassportScorerUpdated(address indexed oldScorer, address indexed newScorer);

    // ============================================
    // ERRORS
    // ============================================

    error AlreadyRegisteredAsContributor();
    error InvalidMerkleProof();
    error GithubAlreadyClaimed();
    error PassportScoreTooLow();
    error InvalidGithub();
    error InvalidScore();
    error NotAVerifiedContributor();
    error DepositNotAllowed();

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize ContributorQuadraticVoting with configuration, alpha, and Merkle root
     * @dev Called by AllocationMechanismFactory during CREATE2 deployment
     * @param _implementation Address of shared TokenizedAllocationMechanism implementation
     * @param _config Configuration struct with mechanism parameters
     * @param _alphaNumerator Alpha numerator for ProperQF weighting
     * @param _alphaDenominator Alpha denominator for ProperQF weighting
     * @param _merkleRoot Initial Merkle root for contributor verification
     */
    constructor(
        address _implementation,
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        bytes32 _merkleRoot
    ) QuadraticVotingMechanism(_implementation, _config, _alphaNumerator, _alphaDenominator) {
        merkleRoot = _merkleRoot;
    }

    // ============================================
    // REGISTRATION FUNCTIONS
    // ============================================

    /**
     * @notice Register as a verified contributor with Merkle proof
     * @dev This replaces the standard signup flow - contributors must register before voting
     * @param github GitHub username
     * @param score Contribution score
     * @param proof Merkle proof demonstrating eligibility
     */
    function registerContributor(string calldata github, uint256 score, bytes32[] calldata proof) external {
        // Check not already registered
        if (contributors[msg.sender].verified) {
            revert AlreadyRegisteredAsContributor();
        }

        // Validate inputs
        if (bytes(github).length == 0) {
            revert InvalidGithub();
        }
        if (score == 0) {
            revert InvalidScore();
        }

        // Check GitHub not already claimed
        if (githubToAddress[github] != address(0)) {
            revert GithubAlreadyClaimed();
        }

        // Verify Merkle proof
        bytes32 leaf = _createLeaf(msg.sender, github, score);
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        // Optional: Check Gitcoin Passport score
        if (minPassportScore > 0 && passportScorer != address(0)) {
            uint256 passportScore = _getPassportScore(msg.sender);
            if (passportScore < minPassportScore) {
                revert PassportScoreTooLow();
            }
        }

        // Calculate voting power from contribution score
        // Uses sqrt for diminishing returns: votingPower = sqrt(score)
        uint256 votingPower = _calculateContributorVotingPower(score);

        // Store contributor info
        contributors[msg.sender] = ContributorInfo({
            github: github,
            score: score,
            votingPower: votingPower,
            registeredAt: block.timestamp,
            verified: true
        });

        githubToAddress[github] = msg.sender;
        totalContributors++;

        // Register in the base allocation mechanism (no deposit required)
        // This calls the parent's signup mechanism with 0 deposit
        // Voting power will be returned by our _getVotingPowerHook
        _tokenizedAllocation().signup(0);

        emit ContributorRegistered(msg.sender, github, score, votingPower);
    }

    // ============================================
    // HOOK OVERRIDES
    // ============================================

    /**
     * @notice Hook to authorize user registration
     * @dev Only allows verified contributors to signup
     *      Contributors must call registerContributor() first with valid Merkle proof
     * @param user Address attempting to signup
     * @return authorized True if user is a verified contributor
     */
    function _beforeSignupHook(address user) internal view virtual override returns (bool) {
        // Only verified contributors can participate
        return contributors[user].verified;
    }

    /**
     * @notice Hook to calculate voting power from deposit
     * @dev Overrides to use pre-calculated contributor voting power instead of deposit amount
     *      Ignores deposit parameter since voting power comes from contribution score
     * @param user User address
     * @param deposit Deposit amount (ignored in this implementation)
     * @return votingPower Pre-calculated voting power from contribution score (18 decimals)
     */
    function _getVotingPowerHook(address user, uint256 deposit) internal view virtual override returns (uint256) {
        // Return the voting power calculated during registration
        // Already normalized to 18 decimals
        return contributors[user].votingPower;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Verify a contributor's Merkle proof (view function)
     * @param wallet Contributor's wallet address
     * @param github GitHub username
     * @param score Contribution score
     * @param proof Merkle proof
     * @return bool True if proof is valid
     */
    function verifyContributor(
        address wallet,
        string memory github,
        uint256 score,
        bytes32[] memory proof
    ) public view returns (bool) {
        bytes32 leaf = _createLeaf(wallet, github, score);
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    /**
     * @notice Check if an address is a verified contributor
     * @param wallet Address to check
     * @return bool True if verified
     */
    function isVerifiedContributor(address wallet) external view returns (bool) {
        return contributors[wallet].verified;
    }

    /**
     * @notice Get contributor information
     * @param wallet Contributor's address
     * @return ContributorInfo struct
     */
    function getContributor(address wallet) external view returns (ContributorInfo memory) {
        if (!contributors[wallet].verified) {
            revert NotAVerifiedContributor();
        }
        return contributors[wallet];
    }

    /**
     * @notice Get wallet address for a GitHub username
     * @param github GitHub username
     * @return address Wallet address
     */
    function getAddressForGithub(string memory github) external view returns (address) {
        return githubToAddress[github];
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Update Merkle root (for new contributor batches)
     * @dev Only callable by mechanism owner
     * @param newRoot New Merkle root
     */
    function updateMerkleRoot(bytes32 newRoot) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;
        emit MerkleRootUpdated(oldRoot, newRoot);
    }

    /**
     * @notice Update minimum Gitcoin Passport score
     * @dev Only callable by mechanism owner
     * @param newScore New minimum score (0 to disable)
     */
    function updateMinPassportScore(uint256 newScore) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        uint256 oldScore = minPassportScore;
        minPassportScore = newScore;
        emit MinPassportScoreUpdated(oldScore, newScore);
    }

    /**
     * @notice Update Gitcoin Passport scorer address
     * @dev Only callable by mechanism owner
     * @param newScorer New scorer address (address(0) to disable)
     */
    function updatePassportScorer(address newScorer) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        address oldScorer = passportScorer;
        passportScorer = newScorer;
        emit PassportScorerUpdated(oldScorer, newScorer);
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Create a leaf hash for Merkle tree
     * @param wallet Contributor's wallet
     * @param github GitHub username
     * @param score Contribution score
     * @return bytes32 Leaf hash
     */
    function _createLeaf(address wallet, string memory github, uint256 score) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(wallet, github, score));
    }

    /**
     * @notice Calculate voting power from contribution score
     * @dev Uses square root for quadratic diminishing returns, normalized to 18 decimals
     * @param score Contribution score (raw integer)
     * @return uint256 Voting power (normalized to 18 decimals)
     */
    function _calculateContributorVotingPower(uint256 score) internal pure returns (uint256) {
        // Calculate sqrt(score)
        uint256 sqrtScore = score.sqrt();

        // Normalize to 18 decimals for compatibility with voting mechanism
        // Assuming score is a raw integer, scale up to 18 decimals
        return sqrtScore * 1e18;
    }

    /**
     * @notice Get Gitcoin Passport score for an address
     * @param wallet Address to check
     * @return uint256 Passport score
     */
    function _getPassportScore(address wallet) internal view returns (uint256) {
        if (passportScorer == address(0)) {
            return 0;
        }

        try IGitcoinPassportScorer(passportScorer).getScore(wallet) returns (uint256 score) {
            return score;
        } catch {
            return 0;
        }
    }
}
