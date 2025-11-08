// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ContributorRegistry
 * @notice Registry of verified GitHub contributors using Merkle proofs
 * @dev Uses Merkle tree for gas-efficient verification of contributor eligibility
 *
 * Key Features:
 * - Merkle proof verification for contributor eligibility
 * - One-time registration per contributor
 * - Stores contributor info (GitHub, score, voting power)
 * - Updatable Merkle root for new contributor batches
 * - Integration with Gitcoin Passport for Sybil resistance
 */
contract ContributorRegistry is Ownable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ContributorInfo {
        string github;
        uint256 score;
        uint256 votingPower;
        uint256 registeredAt;
        bool verified;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current Merkle root for contributor verification
    bytes32 public merkleRoot;

    /// @notice Total number of registered contributors
    uint256 public totalRegistered;

    /// @notice Mapping of wallet address to contributor info
    mapping(address => ContributorInfo) public contributors;

    /// @notice Mapping to prevent duplicate GitHub usernames
    mapping(string => address) public githubToAddress;

    /// @notice Minimum Gitcoin Passport score required (optional, 0 = disabled)
    uint256 public minPassportScore;

    /// @notice Address of Gitcoin Passport scorer (optional)
    address public passportScorer;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ContributorRegistered(address indexed wallet, string github, uint256 score, uint256 votingPower);

    event MerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    event MinPassportScoreUpdated(uint256 oldScore, uint256 newScore);

    event PassportScorerUpdated(address indexed oldScorer, address indexed newScorer);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyRegistered();
    error InvalidProof();
    error NotRegistered();
    error GithubAlreadyClaimed();
    error PassportScoreTooLow();
    error InvalidGithub();
    error InvalidScore();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the ContributorRegistry
     * @param _merkleRoot Initial Merkle root
     * @param _owner Contract owner address
     */
    constructor(bytes32 _merkleRoot, address _owner) Ownable(_owner) {
        merkleRoot = _merkleRoot;
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register as a verified contributor
     * @param github GitHub username
     * @param score Contribution score
     * @param proof Merkle proof
     */
    function register(string calldata github, uint256 score, bytes32[] calldata proof) external nonReentrant {
        // Check not already registered
        if (contributors[msg.sender].verified) {
            revert AlreadyRegistered();
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
            revert InvalidProof();
        }

        // Optional: Check Gitcoin Passport score
        if (minPassportScore > 0 && passportScorer != address(0)) {
            uint256 passportScore = _getPassportScore(msg.sender);
            if (passportScore < minPassportScore) {
                revert PassportScoreTooLow();
            }
        }

        // Calculate voting power (using square root for diminishing returns)
        uint256 votingPower = _calculateVotingPower(score);

        // Store contributor info
        contributors[msg.sender] = ContributorInfo({
            github: github,
            score: score,
            votingPower: votingPower,
            registeredAt: block.timestamp,
            verified: true
        });

        githubToAddress[github] = msg.sender;
        totalRegistered++;

        emit ContributorRegistered(msg.sender, github, score, votingPower);
    }

    /**
     * @notice Batch register multiple contributors (owner only, for migration)
     * @param wallets Array of wallet addresses
     * @param githubs Array of GitHub usernames
     * @param scores Array of contribution scores
     * @param proofs Array of Merkle proofs
     */
    function batchRegister(
        address[] calldata wallets,
        string[] calldata githubs,
        uint256[] calldata scores,
        bytes32[][] calldata proofs
    ) external onlyOwner {
        require(
            wallets.length == githubs.length && wallets.length == scores.length && wallets.length == proofs.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < wallets.length; i++) {
            address wallet = wallets[i];

            // Skip if already registered
            if (contributors[wallet].verified) {
                continue;
            }

            string memory github = githubs[i];
            uint256 score = scores[i];

            // Verify proof
            bytes32 leaf = _createLeaf(wallet, github, score);
            if (!MerkleProof.verify(proofs[i], merkleRoot, leaf)) {
                continue; // Skip invalid proofs
            }

            // Store contributor
            uint256 votingPower = _calculateVotingPower(score);
            contributors[wallet] = ContributorInfo({
                github: github,
                score: score,
                votingPower: votingPower,
                registeredAt: block.timestamp,
                verified: true
            });

            githubToAddress[github] = wallet;
            totalRegistered++;

            emit ContributorRegistered(wallet, github, score, votingPower);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
    function isVerified(address wallet) external view returns (bool) {
        return contributors[wallet].verified;
    }

    /**
     * @notice Get contributor information
     * @param wallet Contributor's address
     * @return ContributorInfo struct
     */
    function getContributor(address wallet) external view returns (ContributorInfo memory) {
        if (!contributors[wallet].verified) {
            revert NotRegistered();
        }
        return contributors[wallet];
    }

    /**
     * @notice Get voting power for a contributor
     * @param wallet Contributor's address
     * @return uint256 Voting power
     */
    function getVotingPower(address wallet) external view returns (uint256) {
        if (!contributors[wallet].verified) {
            revert NotRegistered();
        }
        return contributors[wallet].votingPower;
    }

    /**
     * @notice Get wallet address for a GitHub username
     * @param github GitHub username
     * @return address Wallet address
     */
    function getAddressForGithub(string memory github) external view returns (address) {
        return githubToAddress[github];
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update Merkle root (for new contributor batches)
     * @param newRoot New Merkle root
     */
    function updateMerkleRoot(bytes32 newRoot) external onlyOwner {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;
        emit MerkleRootUpdated(oldRoot, newRoot);
    }

    /**
     * @notice Update minimum Gitcoin Passport score
     * @param newScore New minimum score (0 to disable)
     */
    function updateMinPassportScore(uint256 newScore) external onlyOwner {
        uint256 oldScore = minPassportScore;
        minPassportScore = newScore;
        emit MinPassportScoreUpdated(oldScore, newScore);
    }

    /**
     * @notice Update Gitcoin Passport scorer address
     * @param newScorer New scorer address (address(0) to disable)
     */
    function updatePassportScorer(address newScorer) external onlyOwner {
        address oldScorer = passportScorer;
        passportScorer = newScorer;
        emit PassportScorerUpdated(oldScorer, newScorer);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * @dev Uses square root for quadratic diminishing returns
     * @param score Contribution score
     * @return uint256 Voting power
     */
    function _calculateVotingPower(uint256 score) internal pure returns (uint256) {
        // Simple square root for quadratic voting
        // votingPower = sqrt(score)
        return sqrt(score);
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

        // Call Gitcoin Passport Scorer contract
        // Interface: function getScore(address) external view returns (uint256)
        (bool success, bytes memory data) = passportScorer.staticcall(
            abi.encodeWithSignature("getScore(address)", wallet)
        );

        if (!success || data.length == 0) {
            return 0;
        }

        return abi.decode(data, (uint256));
    }

    /**
     * @notice Calculate square root (Babylonian method)
     * @param x Input value
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
