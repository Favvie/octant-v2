# Ecosystem Governance System

Complete DAO council governance for contributor rewards using Octant's audited quadratic voting.

## Quick Start

### Architecture

```
Contributors (Recipients)     →    ContributorRegistry
                                         ↓
Ecosystem Leads (Voters)      →    EcosystemLeadNFT + EcosystemLeadVoting
                                         ↓
Approved Proposals            →    EcosystemGovernanceExecutor
                                         ↓
                              Fund Contributors / Mint NFTs / Execute Actions
```

### Key Principle

**Contributors DON'T vote** - they RECEIVE rewards voted on by the DAO council (Ecosystem Leads).

---

## Components

### 1. ContributorRegistry
**What**: Tracks contributors and their scores
**Who**: Contributors register with Merkle proofs
**Purpose**: Identify eligible reward recipients

### 2. EcosystemLeadNFT
**What**: Soulbound NFT for council membership
**Who**: DAO council members
**Purpose**: Gate access to governance voting

### 3. EcosystemLeadVoting
**What**: Quadratic voting mechanism
**Who**: NFT holders (council)
**Purpose**: Vote on funding and decisions

### 4. EcosystemGovernanceExecutor
**What**: Execution layer
**Who**: Authorized by governance
**Purpose**: Execute approved proposals

---

## Workflows

### Fund a Contributor

```solidity
// 1. Contributor registers
contributorRegistry.register("alice", 1000, proof);

// 2. Council member proposes funding
voting.proposeContributorFunding(alice, 10000e18, "Great work!");

// 3. Council votes (quadratic cost)
voting.signup(5000e18);           // Deposit tokens
voting.vote(pid, VoteType.For, 50); // Cast 50 votes (costs 2,500)

// 4. After approval + timelock
voting.queue(pid);
alice.redeem(shares);  // Alice gets 10,000 tokens
```

### Add Council Member

```solidity
// 1. Council proposes
voting.proposeNewLead(bob, "Active contributor");

// 2. Council votes...

// 3. After approval
executor.mintEcosystemLead(bob);  // Bob gets NFT
```

---

## Quadratic Voting

**Formula**: Cast W votes → Costs W² voting power

**Examples**:
- 10 votes = 100 power
- 50 votes = 2,500 power
- 100 votes = 10,000 power

**Why**: Prevents whale dominance, encourages consensus

---

## Security

✅ Audited (Octant/Least Authority)
✅ Soulbound NFTs (no vote selling)
✅ Quadratic cost (no whale attacks)
✅ Timelock (2-day security buffer)
✅ NFT gating (controlled membership)

---

## Deployment

```bash
forge script scripts/DeployEcosystemGovernance.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

---

## Documentation

- **Architecture**: See `ARCHITECTURE.md` for complete details
- **Deployment**: See `scripts/DeployEcosystemGovernance.s.sol`
- **Tests**: See `src/test/governance/`

---

## FAQ

**Q: Do contributors vote?**
A: No, only Ecosystem Leads (council) vote.

**Q: How do I become a council member?**
A: Existing council proposes you → council votes → you receive NFT.

**Q: Is this quadratic voting?**
A: Yes! Cost = weight² (from Octant's audited implementation).

**Q: Can I transfer my council NFT?**
A: No, it's soulbound (non-transferable).

---

## Support

Issues: https://github.com/golemfoundation/octant-v2/issues
Octant Docs: https://docs.octant.app/
