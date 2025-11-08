// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import { QuadraticVotingMechanism } from "@octant-core/mechanisms/mechanism/QuadraticVotingMechanism.sol";
import { AllocationConfig } from "@octant-core/mechanisms/BaseAllocationMechanism.sol";
import { TokenizedAllocationMechanism } from "@octant-core/mechanisms/TokenizedAllocationMechanism.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Ecosystem Lead Voting
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice NFT-gated quadratic voting for DAO council decisions
 * @dev Extends Octant's QuadraticVotingMechanism with NFT gating and token-based voting power
 *
 *      DAO COUNCIL STRUCTURE:
 *      ═══════════════════════════════════
 *      - Only Ecosystem Lead NFT holders can participate
 *      - Council votes on contributor funding and strategic decisions
 *      - Soulbound NFTs prevent vote selling
 *      - Token deposits determine voting power
 *
 *      VOTING POWER MECHANICS:
 *      ═══════════════════════════════════
 *      - Deposit governance tokens to get voting power
 *      - Linear: 1 token = 1 voting power (normalized to 18 decimals)
 *      - Quadratic cost: W² voting power to cast W votes
 *      - Prevents whale dominance while allowing stake-weighted influence
 *
 *      PROPOSAL TYPES:
 *      ═══════════════════════════════════
 *      1. Contributor Funding: Allocate rewards to verified contributors
 *      2. Strategic Decisions: General governance proposals
 *      3. NFT Minting: Vote to add new council members
 *
 *      VOTING COST EXAMPLES:
 *      ═══════════════════════════════════
 *      - Cast 10 votes → costs 100 voting power (100 tokens)
 *      - Cast 50 votes → costs 2,500 voting power (2,500 tokens)
 *      - Cast 100 votes → costs 10,000 voting power (10,000 tokens)
 *
 *      SECURITY FEATURES:
 *      ═══════════════════════════════════
 *      - NFT gating prevents unauthorized participation
 *      - Soulbound NFTs prevent vote market
 *      - Quadratic cost prevents whale attacks
 *      - Timelock & grace period for fund distribution
 *      - Inherits all Octant security audits
 *
 * @custom:security NFT gating ensures only council members vote
 * @custom:security Token deposits create stake alignment
 */
contract EcosystemLeadVoting is QuadraticVotingMechanism {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Ecosystem Lead NFT contract
    IERC721 public immutable ecosystemLeadNFT;

    /// @notice Optional: Reference to contributor registry for validation
    address public contributorRegistry;

    // ============================================
    // EVENTS
    // ============================================

    event ContributorRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ============================================
    // ERRORS
    // ============================================

    error NotAnEcosystemLead(address user);
    error InvalidContributor(address contributor);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize EcosystemLeadVoting with NFT gating
     * @param _implementation Address of shared TokenizedAllocationMechanism implementation
     * @param _config Configuration struct with mechanism parameters
     * @param _alphaNumerator Alpha numerator for ProperQF weighting
     * @param _alphaDenominator Alpha denominator for ProperQF weighting
     * @param _ecosystemLeadNFT Address of Ecosystem Lead NFT contract
     */
    constructor(
        address _implementation,
        AllocationConfig memory _config,
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        address _ecosystemLeadNFT
    ) QuadraticVotingMechanism(_implementation, _config, _alphaNumerator, _alphaDenominator) {
        if (_ecosystemLeadNFT == address(0)) revert TokenizedAllocationMechanism.InvalidRecipient(_ecosystemLeadNFT);
        ecosystemLeadNFT = IERC721(_ecosystemLeadNFT);
    }

    // ============================================
    // HOOK OVERRIDES
    // ============================================

    /**
     * @notice Hook to authorize user signup (NFT gating)
     * @dev Only Ecosystem Lead NFT holders can participate
     * @param user Address attempting to signup
     * @return authorized True if user holds Ecosystem Lead NFT
     */
    function _beforeSignupHook(address user) internal view virtual override returns (bool) {
        // Check if user holds Ecosystem Lead NFT
        if (ecosystemLeadNFT.balanceOf(user) == 0) {
            return false;
        }
        return true;
    }

    /**
     * @notice Hook to calculate voting power from token deposit
     * @dev Linear: 1 token = 1 voting power (normalized to 18 decimals)
     *      This creates stake alignment while quadratic cost prevents dominance
     *
     *      NORMALIZATION EXAMPLES:
     *      - Deposit 1000 USDC (6 decimals) → 1000e18 voting power
     *      - Deposit 10 governance tokens (18 decimals) → 10e18 voting power
     *
     * @param user User address (unused, kept for interface)
     * @param deposit Amount deposited in asset's native decimals
     * @return votingPower Normalized voting power in 18 decimals
     */
    function _getVotingPowerHook(address user, uint256 deposit) internal view virtual override returns (uint256) {
        // Get asset decimals for normalization
        uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();

        // Normalize to 18 decimals: 1 token = 1 voting power
        if (assetDecimals == 18) {
            return deposit;
        } else if (assetDecimals < 18) {
            // Scale up: multiply by 10^(18 - assetDecimals)
            uint256 scaleFactor = 10 ** (18 - assetDecimals);
            return deposit * scaleFactor;
        } else {
            // Scale down: divide by 10^(assetDecimals - 18)
            uint256 scaleFactor = 10 ** (assetDecimals - 18);
            return deposit / scaleFactor;
        }
    }

    // ============================================
    // PROPOSAL FUNCTIONS
    // ============================================

    /**
     * @notice Propose funding for a verified contributor
     * @dev Wraps standard propose with contributor validation
     * @param contributor Contributor address to fund
     * @param amount Amount to allocate (informational, in description)
     * @param reason Reasoning for funding proposal
     * @return pid Proposal ID
     */
    function proposeContributorFunding(
        address contributor,
        uint256 amount,
        string calldata reason
    ) external returns (uint256 pid) {
        // Optional: Validate contributor if registry is set
        if (contributorRegistry != address(0)) {
            // Call ContributorRegistry.isVerified(contributor)
            (bool success, bytes memory data) = contributorRegistry.staticcall(
                abi.encodeWithSignature("isVerified(address)", contributor)
            );

            if (!success || !abi.decode(data, (bool))) {
                revert InvalidContributor(contributor);
            }
        }

        // Create description with amount and reason
        string memory description = string(
            abi.encodePacked(
                "Contributor Funding: ", _addressToString(contributor), " - Amount: ", _uint256ToString(amount), " - ", reason
            )
        );

        // Propose using parent function
        return _tokenizedAllocation().propose(contributor, description);
    }

    /**
     * @notice Propose strategic decision
     * @dev General-purpose proposal for non-funding decisions
     * @param recipient Address to receive shares if passed (can be treasury/multisig)
     * @param description Description of strategic decision
     * @return pid Proposal ID
     */
    function proposeStrategicDecision(address recipient, string calldata description) external returns (uint256 pid) {
        return _tokenizedAllocation().propose(recipient, description);
    }

    /**
     * @notice Propose adding new ecosystem lead
     * @dev Creates proposal to mint NFT for address
     *      Execution requires additional integration with NFT contract
     * @param nominee Address to nominate as ecosystem lead
     * @param reason Reasoning for nomination
     * @return pid Proposal ID
     */
    function proposeNewLead(address nominee, string calldata reason) external returns (uint256 pid) {
        // Check nominee doesn't already have NFT
        if (ecosystemLeadNFT.balanceOf(nominee) > 0) {
            revert InvalidContributor(nominee);
        }

        string memory description = string(
            abi.encodePacked("New Ecosystem Lead: ", _addressToString(nominee), " - Reason: ", reason)
        );

        // Note: Recipient should be NFT contract or executor that will mint
        return _tokenizedAllocation().propose(nominee, description);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Set contributor registry address
     * @dev Only callable by mechanism owner
     * @param _contributorRegistry New contributor registry address
     */
    function setContributorRegistry(address _contributorRegistry) external {
        require(_tokenizedAllocation().owner() == msg.sender, "Only owner");
        address oldRegistry = contributorRegistry;
        contributorRegistry = _contributorRegistry;
        emit ContributorRegistryUpdated(oldRegistry, _contributorRegistry);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if address can participate (has NFT)
     * @param user Address to check
     * @return bool True if user holds Ecosystem Lead NFT
     */
    function canParticipate(address user) external view returns (bool) {
        return ecosystemLeadNFT.balanceOf(user) > 0;
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @notice Convert address to string
     * @param addr Address to convert
     * @return String representation of address
     */
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) & 0xf)];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i) - 4) & 0xf)];
        }
        return string(str);
    }

    /**
     * @notice Convert uint256 to string
     * @param value Number to convert
     * @return String representation of number
     */
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
