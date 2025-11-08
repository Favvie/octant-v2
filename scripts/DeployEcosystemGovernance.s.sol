// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { EcosystemLeadNFT } from "../src/nft/EcosystemLeadNFT.sol";
import { EcosystemLeadVoting } from "../src/mechanisms/EcosystemLeadVoting.sol";
import { EcosystemGovernanceExecutor } from "../src/governance/EcosystemGovernanceExecutor.sol";
import { TokenizedAllocationMechanism } from "@octant-core/mechanisms/TokenizedAllocationMechanism.sol";
import { AllocationConfig } from "@octant-core/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Deploy Ecosystem Governance
 * @notice Deployment script for complete DAO council governance system
 * @dev Deploys and configures all governance contracts
 *
 * DEPLOYMENT ORDER:
 * 1. TokenizedAllocationMechanism implementation
 * 2. EcosystemGovernanceExecutor (temporary owner)
 * 3. EcosystemLeadNFT (owned by executor)
 * 4. EcosystemLeadVoting (proxied voting mechanism)
 * 5. Authorize voting contract in executor
 * 6. Mint initial NFTs to founding council
 * 7. Transfer executor ownership to multi-sig/timelock
 *
 * USAGE:
 * forge script scripts/DeployEcosystemGovernance.s.sol:DeployEcosystemGovernance \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify
 */
contract DeployEcosystemGovernance is Script {
    // ============================================
    // CONFIGURATION
    // ============================================

    // Governance token used for voting deposits
    address public constant GOVERNANCE_TOKEN = 0x0000000000000000000000000000000000000000; // TODO: Set actual token

    // Initial council members (replace with actual addresses)
    address[] public initialCouncil = [
        0x0000000000000000000000000000000000000001,
        0x0000000000000000000000000000000000000002,
        0x0000000000000000000000000000000000000003
    ];

    // Multi-sig or timelock for final governance control
    address public constant FINAL_OWNER = 0x0000000000000000000000000000000000000000; // TODO: Set actual owner

    // Voting parameters
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_SHARES = 1000 * 1e18;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant GRACE_PERIOD = 5 days;

    // Alpha parameters for ProperQF (1.0 = full quadratic)
    uint256 public constant ALPHA_NUMERATOR = 10000;
    uint256 public constant ALPHA_DENOMINATOR = 10000;

    // NFT metadata base URI
    string public constant NFT_BASE_URI = "https://ecosystem.example.com/metadata/";

    // ============================================
    // DEPLOYMENT
    // ============================================

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying ecosystem governance from:", deployer);
        console.log("Governance token:", GOVERNANCE_TOKEN);
        console.log("Final owner:", FINAL_OWNER);

        vm.startBroadcast(deployerPrivateKey);

        // ============================================
        // 1. Deploy TokenizedAllocationMechanism Implementation
        // ============================================

        console.log("\n1. Deploying TokenizedAllocationMechanism implementation...");
        TokenizedAllocationMechanism implementation = new TokenizedAllocationMechanism();
        console.log("   Implementation deployed at:", address(implementation));

        // ============================================
        // 2. Deploy Governance Executor (temporarily owned by deployer)
        // ============================================

        console.log("\n2. Deploying EcosystemGovernanceExecutor...");
        EcosystemGovernanceExecutor executor = new EcosystemGovernanceExecutor(
            address(0), // NFT address set later
            deployer // Temporary owner
        );
        console.log("   Executor deployed at:", address(executor));

        // ============================================
        // 3. Deploy Ecosystem Lead NFT (owned by executor)
        // ============================================

        console.log("\n3. Deploying EcosystemLeadNFT...");
        EcosystemLeadNFT nft = new EcosystemLeadNFT(address(executor), NFT_BASE_URI);
        console.log("   NFT deployed at:", address(nft));

        // Update executor with NFT address (requires redeployment or setter)
        // For now, we'll note this in documentation
        console.log("   Note: Redeploy executor with NFT address:", address(nft));

        // Redeploy executor with correct NFT address
        executor = new EcosystemGovernanceExecutor(address(nft), deployer);
        console.log("   Executor redeployed at:", address(executor));

        // Transfer NFT ownership to executor
        nft.transferOwnership(address(executor));
        console.log("   NFT ownership transferred to executor");

        // ============================================
        // 4. Deploy Ecosystem Lead Voting Mechanism
        // ============================================

        console.log("\n4. Deploying EcosystemLeadVoting...");

        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(GOVERNANCE_TOKEN),
            name: "Ecosystem Lead Voting Shares",
            symbol: "ELVS",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_SHARES,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: deployer // Temporary owner
        });

        EcosystemLeadVoting voting = new EcosystemLeadVoting(
            address(implementation), config, ALPHA_NUMERATOR, ALPHA_DENOMINATOR, address(nft)
        );
        console.log("   Voting mechanism deployed at:", address(voting));

        // ============================================
        // 5. Authorize Voting Contract in Executor
        // ============================================

        console.log("\n5. Authorizing voting contract in executor...");
        executor.authorizeVoter(address(voting));
        console.log("   Voting contract authorized");

        // ============================================
        // 6. Mint Initial NFTs to Founding Council
        // ============================================

        console.log("\n6. Minting initial NFTs to founding council...");
        console.log("   Council members:", initialCouncil.length);

        for (uint256 i = 0; i < initialCouncil.length; i++) {
            console.log("   Minting NFT to:", initialCouncil[i]);
            uint256 tokenId = executor.mintEcosystemLead(initialCouncil[i]);
            console.log("     Token ID:", tokenId);
        }

        // ============================================
        // 7. Transfer Ownership to Final Owner (Multi-sig/Timelock)
        // ============================================

        if (FINAL_OWNER != address(0) && FINAL_OWNER != deployer) {
            console.log("\n7. Transferring ownership to final owner...");

            // Transfer executor ownership
            executor.transferOwnership(FINAL_OWNER);
            console.log("   Executor ownership transferred to:", FINAL_OWNER);

            // Transfer voting ownership (via executor or direct)
            // Note: Voting mechanism owner should be executor or multi-sig
            console.log("   Note: Consider transferring voting ownership to executor or multi-sig");
        } else {
            console.log("\n7. Skipping ownership transfer (FINAL_OWNER not set)");
            console.log("   WARNING: Deployer retains ownership. Transfer manually!");
        }

        vm.stopBroadcast();

        // ============================================
        // DEPLOYMENT SUMMARY
        // ============================================

        console.log("\n===============================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("===============================================");
        console.log("Implementation:      ", address(implementation));
        console.log("Governance Executor: ", address(executor));
        console.log("Ecosystem Lead NFT:  ", address(nft));
        console.log("Lead Voting:         ", address(voting));
        console.log("Governance Token:    ", GOVERNANCE_TOKEN);
        console.log("Final Owner:         ", FINAL_OWNER);
        console.log("Initial Council:     ", initialCouncil.length, "members");
        console.log("===============================================");
        console.log("\nNEXT STEPS:");
        console.log("1. Verify FINAL_OWNER is correct");
        console.log("2. Ensure initial council members are correct");
        console.log("3. Test voting mechanism with small deposits");
        console.log("4. Create first proposal and test full lifecycle");
        console.log("5. Transfer ownership if not done automatically");
        console.log("===============================================\n");
    }
}
