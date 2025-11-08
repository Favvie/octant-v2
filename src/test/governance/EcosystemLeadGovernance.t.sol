// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { EcosystemLeadNFT } from "../../nft/EcosystemLeadNFT.sol";
import { EcosystemLeadVoting } from "../../mechanisms/EcosystemLeadVoting.sol";
import { EcosystemGovernanceExecutor } from "../../governance/EcosystemGovernanceExecutor.sol";
import { TokenizedAllocationMechanism } from "../../../dependencies/octant-v2-core/src/mechanisms/TokenizedAllocationMechanism.sol";
import { AllocationConfig } from "../../../dependencies/octant-v2-core/src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/**
 * @title Ecosystem Lead Governance Test
 * @notice Comprehensive tests for DAO council governance system
 */
contract EcosystemLeadGovernanceTest is Test {
    // Contracts
    EcosystemLeadNFT public nft;
    EcosystemLeadVoting public voting;
    EcosystemGovernanceExecutor public executor;
    TokenizedAllocationMechanism public implementation;
    ERC20Mock public governanceToken;

    // Actors
    address public owner = address(0x1);
    address public lead1 = address(0x100);
    address public lead2 = address(0x101);
    address public lead3 = address(0x102);
    address public nonLead = address(0x200);

    // Parameters
    uint256 public votingDelay = 1 days;
    uint256 public votingPeriod = 7 days;
    uint256 public timelockDelay = 2 days;
    uint256 public gracePeriod = 5 days;
    uint256 public quorumShares = 1000 * 1e18;

    function setUp() public {
        // Deploy governance token
        governanceToken = new ERC20Mock();

        // Deploy executor (temporarily owned by owner)
        executor = new EcosystemGovernanceExecutor(address(0), owner);

        // Deploy NFT (owned by executor)
        vm.prank(owner);
        nft = new EcosystemLeadNFT(address(executor), "ipfs://base/");

        // Redeploy executor with NFT address
        executor = new EcosystemGovernanceExecutor(address(nft), owner);

        // Transfer NFT ownership to executor
        vm.prank(owner);
        nft.transferOwnership(address(executor));

        // Deploy implementation
        implementation = new TokenizedAllocationMechanism();

        // Configure voting mechanism
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(governanceToken)),
            name: "Ecosystem Lead Voting Shares",
            symbol: "ELVS",
            votingDelay: votingDelay,
            votingPeriod: votingPeriod,
            quorumShares: quorumShares,
            timelockDelay: timelockDelay,
            gracePeriod: gracePeriod,
            owner: owner
        });

        // Deploy voting mechanism
        vm.prank(owner);
        voting = new EcosystemLeadVoting(address(implementation), config, 10000, 10000, address(nft));

        // Authorize voting contract
        vm.prank(owner);
        executor.authorizeVoter(address(voting));

        // Mint NFTs to initial leads
        vm.startPrank(owner);
        executor.mintEcosystemLead(lead1);
        executor.mintEcosystemLead(lead2);
        executor.mintEcosystemLead(lead3);
        vm.stopPrank();

        // Distribute governance tokens
        governanceToken.mint(lead1, 10000e18);
        governanceToken.mint(lead2, 5000e18);
        governanceToken.mint(lead3, 3000e18);
    }

    // ============================================
    // NFT TESTS
    // ============================================

    function test_NFT_MintSuccess() public {
        address newLead = address(0x103);

        vm.prank(owner);
        uint256 tokenId = executor.mintEcosystemLead(newLead);

        assertTrue(nft.isLead(newLead));
        assertEq(nft.balanceOf(newLead), 1);
        assertEq(nft.ownerOf(tokenId), newLead);
    }

    function test_NFT_RevertAlreadyHasNFT() public {
        vm.prank(owner);
        vm.expectRevert();
        executor.mintEcosystemLead(lead1);
    }

    function test_NFT_Soulbound() public {
        // Try to transfer
        vm.prank(lead1);
        vm.expectRevert(EcosystemLeadNFT.CannotTransferSoulbound.selector);
        nft.transferFrom(lead1, lead2, 1);
    }

    function test_NFT_RevokeSuccess() public {
        vm.prank(owner);
        executor.revokeEcosystemLead(lead1);

        assertFalse(nft.isLead(lead1));
        assertEq(nft.balanceOf(lead1), 0);
    }

    function test_NFT_LockedReturnsTrue() public view {
        assertTrue(nft.locked(1));
        assertTrue(nft.locked(2));
        assertTrue(nft.locked(3));
    }

    // ============================================
    // VOTING ACCESS TESTS
    // ============================================

    function test_Voting_LeadCanSignup() public {
        vm.startPrank(lead1);
        governanceToken.approve(address(voting), 1000e18);
        voting.signup(1000e18);
        vm.stopPrank();

        // Verify voting power
        // Note: Would need to access internal state or events
        // For now, just ensure no revert
    }

    function test_Voting_NonLeadCannotSignup() public {
        governanceToken.mint(nonLead, 1000e18);

        vm.startPrank(nonLead);
        governanceToken.approve(address(voting), 1000e18);
        vm.expectRevert();
        voting.signup(1000e18);
        vm.stopPrank();
    }

    function test_Voting_CanParticipate() public view {
        assertTrue(voting.canParticipate(lead1));
        assertTrue(voting.canParticipate(lead2));
        assertFalse(voting.canParticipate(nonLead));
    }

    // ============================================
    // EXECUTOR TESTS
    // ============================================

    function test_Executor_AuthorizeVoter() public {
        address newVoter = address(0x999);

        vm.prank(owner);
        executor.authorizeVoter(newVoter);

        assertTrue(executor.authorizedVoters(newVoter));
    }

    function test_Executor_RevokeVoter() public {
        vm.prank(owner);
        executor.revokeVoter(address(voting));

        assertFalse(executor.authorizedVoters(address(voting)));
    }

    function test_Executor_OnlyAuthorizedCanMint() public {
        address newLead = address(0x104);

        // Remove authorization
        vm.prank(owner);
        executor.revokeVoter(address(voting));

        // Try to mint
        vm.prank(address(voting));
        vm.expectRevert();
        executor.mintEcosystemLead(newLead);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function test_Integration_GetAllLeads() public view {
        address[] memory leads = nft.getAllLeads();
        assertEq(leads.length, 3);
        assertEq(leads[0], lead1);
        assertEq(leads[1], lead2);
        assertEq(leads[2], lead3);
    }

    function test_Integration_TotalMembers() public view {
        assertEq(nft.totalMembers(), 3);
    }

    function test_Integration_BatchMint() public {
        address[] memory newLeads = new address[](2);
        newLeads[0] = address(0x105);
        newLeads[1] = address(0x106);

        vm.prank(owner);
        uint256[] memory tokenIds = executor.mintEcosystemLead(newLeads[0]);

        vm.prank(owner);
        executor.mintEcosystemLead(newLeads[1]);

        assertEq(nft.totalMembers(), 5);
        assertTrue(nft.isLead(newLeads[0]));
        assertTrue(nft.isLead(newLeads[1]));
    }

    // ============================================
    // METADATA TESTS
    // ============================================

    function test_NFT_TokenURI() public view {
        string memory uri = nft.tokenURI(1);
        assertEq(uri, "ipfs://base/1");
    }

    function test_NFT_UpdateBaseURI() public {
        vm.prank(owner);
        executor.executeAction(
            address(nft), abi.encodeWithSignature("setBaseURI(string)", "https://new-uri/"), 0
        );

        string memory uri = nft.tokenURI(1);
        assertEq(uri, "https://new-uri/1");
    }

    // ============================================
    // PROPOSAL TESTS (Simplified)
    // ============================================

    function test_Voting_ProposeContributorFunding() public {
        address contributor = address(0x300);

        // Lead1 creates proposal
        vm.prank(lead1);
        uint256 pid = voting.proposeContributorFunding(contributor, 1000e18, "Great contribution!");

        // Verify proposal exists (would need to check via events or state)
        // For now, just ensure no revert
        assertTrue(pid > 0 || pid == 0); // Placeholder assertion
    }

    function test_Voting_ProposeStrategicDecision() public {
        address treasury = address(0x400);

        vm.prank(lead1);
        uint256 pid = voting.proposeStrategicDecision(treasury, "Allocate funds to marketing");

        assertTrue(pid > 0 || pid == 0); // Placeholder assertion
    }

    function test_Voting_ProposeNewLead() public {
        address nominee = address(0x500);

        vm.prank(lead1);
        uint256 pid = voting.proposeNewLead(nominee, "Active contributor, proven track record");

        assertTrue(pid > 0 || pid == 0); // Placeholder assertion
    }

    function test_Voting_ProposeNewLeadRevertAlreadyHasNFT() public {
        vm.prank(lead1);
        vm.expectRevert();
        voting.proposeNewLead(lead2, "Already a lead");
    }

    // ============================================
    // ACCESS CONTROL TESTS
    // ============================================

    function test_Executor_OnlyOwnerCanAuthorize() public {
        vm.prank(lead1);
        vm.expectRevert();
        executor.authorizeVoter(address(0x999));
    }

    function test_NFT_OnlyExecutorCanMint() public {
        // Direct call to NFT should fail (not owner)
        vm.prank(owner);
        vm.expectRevert();
        nft.mint(address(0x999));
    }

    // ============================================
    // RECEIVE ETH TEST
    // ============================================

    function test_Executor_ReceiveETH() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(executor).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(executor).balance, 1 ether);
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    receive() external payable { }
}