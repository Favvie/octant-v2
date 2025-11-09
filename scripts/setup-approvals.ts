import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

interface ContractAddresses {
  strategy: string | null;
  weeklyPaymentSplitterManager: string | null;
  contributorRegistry: string | null;
  ecosystemLeadNFT: string | null;
  ecosystemLeadVoting: string | null;
}

interface ApprovalConfig {
  asset: string;
  assetDecimals: number;
  addresses: ContractAddresses;
  roles: {
    keeper: string;
    management: string;
  };
}

// Minimal ABIs for approvals
const ERC20_ABI = [
  'function approve(address spender, uint256 amount) public returns (bool)',
  'function allowance(address owner, address spender) public view returns (uint256)',
  'function balanceOf(address account) public view returns (uint256)',
];

const IERC5192_ABI = [
  'function hasRole(bytes32 role, address account) public view returns (bool)',
];

class ApprovalsManager {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Signer;
  private config: ApprovalConfig | null = null;
  private configPath: string;

  constructor() {
    const rpcUrl = process.env.ETH_RPC_URL;
    if (!rpcUrl) {
      throw new Error('ETH_RPC_URL not set in .env');
    }

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.signer = new ethers.Wallet(
      process.env.PRIVATE_KEY || ethers.Wallet.createRandom().privateKey,
      this.provider
    );

    this.configPath = path.join(process.cwd(), 'deployment-config.json');
  }

  async loadConfig(): Promise<ApprovalConfig> {
    try {
      const deploymentConfig = JSON.parse(
        await fs.readFile(this.configPath, 'utf-8')
      );

      this.config = {
        asset: process.env.ASSET_ADDRESS || '',
        assetDecimals: parseInt(process.env.ASSET_DECIMALS || '18'),
        addresses: deploymentConfig.contracts,
        roles: {
          keeper: process.env.KEEPER_ADDRESS || (await this.signer.getAddress()),
          management: process.env.MANAGEMENT_ADDRESS || (await this.signer.getAddress()),
        },
      };

      return this.config;
    } catch (error) {
      throw new Error(
        `Failed to load config from ${this.configPath}. Run deploy-all.ts first.`
      );
    }
  }

  async checkApproval(
    tokenAddress: string,
    owner: string,
    spender: string,
    description: string
  ): Promise<{ approved: boolean; amount: bigint }> {
    const token = new ethers.Contract(
      tokenAddress,
      ERC20_ABI,
      this.provider
    );

    try {
      const allowance = await token.allowance(owner, spender);
      const isApproved =
        allowance >= ethers.parseUnits('1000000', this.config?.assetDecimals || 18);

      console.log(`\n📋 Checking: ${description}`);
      console.log(`   Owner: ${owner}`);
      console.log(`   Spender: ${spender}`);
      console.log(`   Current Allowance: ${ethers.formatUnits(allowance, this.config?.assetDecimals || 18)}`);
      console.log(`   Status: ${isApproved ? '✓ Sufficient' : '✗ Needs Approval'}`);

      return { approved: isApproved, amount: allowance };
    } catch (error) {
      console.error(`   Error checking allowance:`, error);
      return { approved: false, amount: 0n };
    }
  }

  async approveToken(
    tokenAddress: string,
    spender: string,
    description: string
  ): Promise<boolean> {
    if (!this.config) throw new Error('Config not loaded');

    const signerAddress = await this.signer.getAddress();
    const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.signer);

    try {
      console.log(`\n✏️  Setting Approval: ${description}`);
      console.log(`   Token: ${tokenAddress}`);
      console.log(`   Spender: ${spender}`);
      console.log(`   Amount: UNLIMITED (type(uint256).max)`);

      // Approve unlimited amount
      const maxUint256 =
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      const tx = await token.approve(spender, maxUint256);
      console.log(`   Transaction: ${tx.hash}`);

      const receipt = await tx.wait();
      console.log(`   ✓ Approved at block ${receipt?.blockNumber}`);

      return true;
    } catch (error) {
      console.error(`   ✗ Approval failed:`, error);
      return false;
    }
  }

  async verifyRoles(): Promise<void> {
    if (!this.config) throw new Error('Config not loaded');

    console.log('\n\n═══════════════════════════════════════════════════════════════');
    console.log('                    VERIFYING ROLES & PERMISSIONS          ');
    console.log('═══════════════════════════════════════════════════════════════\n');

    console.log('📍 Configuration Addresses:');
    console.log(`   Deployer: ${await this.signer.getAddress()}`);
    console.log(`   Keeper: ${this.config.roles.keeper}`);
    console.log(`   Management: ${this.config.roles.management}`);

    // Check strategy
    if (this.config.addresses.strategy) {
      console.log(`\n🏗️  Strategy Contract: ${this.config.addresses.strategy}`);
      console.log('   ℹ️  Verify in Explorer that:');
      console.log(
        '   - Deployer has admin/management role'
      );
      console.log(
        '   - Keeper is set as authorized caller for report()'
      );
    }

    // Check NFT
    if (this.config.addresses.ecosystemLeadNFT) {
      console.log(`\n🎭 NFT Contract: ${this.config.addresses.ecosystemLeadNFT}`);
      console.log('   ℹ️  Verify in Explorer that:');
      console.log('   - Can mint NFT to desired addresses');
      console.log('   - Is properly soulbound (non-transferable)');
    }

    // Check Voting
    if (this.config.addresses.ecosystemLeadVoting) {
      console.log(`\n🗳️  Voting Contract: ${this.config.addresses.ecosystemLeadVoting}`);
      console.log('   ℹ️  Verify in Explorer that:');
      console.log('   - Connected to correct NFT');
      console.log('   - Quadratic voting parameters are set');
    }

    // Check Registry
    if (this.config.addresses.contributorRegistry) {
      console.log(
        `\n📋 Contributor Registry: ${this.config.addresses.contributorRegistry}`
      );
      console.log('   ℹ️  Verify in Explorer that:');
      console.log('   - Merkle root is set correctly');
      console.log(
        '   - Can register contributors via merkle proofs'
      );
    }
  }

  async displayApprovalInstructions(): Promise<void> {
    if (!this.config) throw new Error('Config not loaded');

    console.log('\n\n═══════════════════════════════════════════════════════════════');
    console.log('                  SETUP & CONFIGURATION                      ');
    console.log('═══════════════════════════════════════════════════════════════\n');

    if (!this.config.addresses.strategy) {
      console.log(
        'ℹ️  Strategy not yet deployed. Deploy using deploy-all.ts first.'
      );
      return;
    }

    console.log('✅ No additional approvals needed!\n');
    console.log('The strategy is configured to directly interact with PaymentSplitter.');
    console.log('No intermediate approvals or roles are required.');

    console.log('\n📝 Keeper Configuration (Optional but Recommended)\n');

    console.log('If your strategy requires explicit keeper authorization:\n');

    console.log(`cast send ${this.config.addresses.strategy} \\`);
    console.log(`  "setKeeper(address)" \\`);
    console.log(`  "${this.config.roles.keeper}" \\`);
    console.log(`  --rpc-url $ETH_RPC_URL \\`);
    console.log(`  --private-key $PRIVATE_KEY\n`);

    console.log('Verify keeper is set:');
    console.log(`cast call ${this.config.addresses.strategy} \\`);
    console.log(`  "keeper()" \\`);
    console.log(`  --rpc-url $ETH_RPC_URL\n`);

    console.log('📌 Verify Strategy Configuration:\n');

    console.log('Check strategy asset:');
    console.log(`cast call ${this.config.addresses.strategy} \\`);
    console.log(`  "asset()" \\`);
    console.log(`  --rpc-url $ETH_RPC_URL\n`);

    console.log('Check total assets in strategy:');
    console.log(`cast call ${this.config.addresses.strategy} \\`);
    console.log(`  "totalAssets()" \\`);
    console.log(`  --rpc-url $ETH_RPC_URL\n`);
  }
}

async function main() {
  console.log(
    '🔐 Octant Contributor Rewards System - Approvals & Setup Script\n'
  );

  const manager = new ApprovalsManager();
  const config = await manager.loadConfig();

  console.log('═══════════════════════════════════════════════════════════════');
  console.log('                    CHECKING CURRENT STATE                    ');
  console.log('═══════════════════════════════════════════════════════════════\n');

  await manager.verifyRoles();

  await manager.displayApprovalInstructions();

  console.log('\n⏭️  NEXT STEPS:');
  console.log('───────────────────────────────────────\n');
  console.log('1. If needed, execute keeper configuration commands shown above');
  console.log('2. Run: npm run setup-keeper (to configure automated keeper)');
  console.log('3. Run: npm run health-check (to verify all systems ready)\n');
}

main().catch((error) => {
  console.error('❌ Setup failed:', error);
  process.exit(1);
});
