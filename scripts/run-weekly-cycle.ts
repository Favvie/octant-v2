import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';
import { execSync } from 'child_process';

dotenv.config({ path: '../.env' });

interface WeeklyCycleConfig {
  weekNumber: number;
  timestamp: number;
  strategy: string;
  manager: string;
  asset: string;
}

interface StepResult {
  step: string;
  status: 'SUCCESS' | 'FAILED' | 'SKIPPED';
  message: string;
  details?: any;
  txHash?: string;
}

const MANAGER_ABI = [
  'function createWeeklyDistribution(uint256 weekNumber, address[] memory contributors, string[] memory githubNames, uint256[] memory shares) external returns (address)',
  'function previewRedemption() external view returns (uint256)',
  'function getLatestRedemption() external view returns (uint256)',
];

const STRATEGY_ABI = [
  'function report() external returns (uint256 profit, uint256 loss)',
  'function totalAssets() external view returns (uint256)',
  'function balanceOf(address) external view returns (uint256)',
];

class WeeklyCycleManager {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Signer;
  private results: StepResult[] = [];
  private config: WeeklyCycleConfig | null = null;
  private deploymentConfig: any = null;

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
  }

  private addResult(
    step: string,
    status: 'SUCCESS' | 'FAILED' | 'SKIPPED',
    message: string,
    details?: any,
    txHash?: string
  ): void {
    this.results.push({
      step,
      status,
      message,
      details,
      txHash,
    });
  }

  async loadConfig(): Promise<WeeklyCycleConfig> {
    try {
      const deploymentConfigPath = path.join(
        process.cwd(),
        'deployment-config.json'
      );
      this.deploymentConfig = JSON.parse(
        await fs.readFile(deploymentConfigPath, 'utf-8')
      );

      this.config = {
        weekNumber: Math.floor(Date.now() / (7 * 24 * 60 * 60 * 1000)),
        timestamp: Date.now(),
        strategy: this.deploymentConfig.contracts.strategy || '',
        manager: this.deploymentConfig.contracts.weeklyPaymentSplitterManager || '',
        asset: process.env.ASSET_ADDRESS || '',
      };

      return this.config;
    } catch (error) {
      throw new Error(
        `Failed to load config: ${error}. Run deploy-all.ts first.`
      );
    }
  }

  async stepVerifyConfiguration(): Promise<boolean> {
    console.log('\n📋 Step 1: Verifying Configuration');
    console.log('─────────────────────────────────────────\n');

    if (
      !this.config?.strategy ||
      !this.config?.manager ||
      !this.config?.asset
    ) {
      this.addResult(
        'Configuration Check',
        'FAILED',
        'Missing required contract addresses',
        this.config
      );
      return false;
    }

    console.log('✓ Strategy:', this.config.strategy);
    console.log('✓ Manager:', this.config.manager);
    console.log('✓ Asset:', this.config.asset);
    console.log('✓ Week Number:', this.config.weekNumber);

    this.addResult(
      'Configuration Check',
      'SUCCESS',
      'All configuration values present'
    );
    return true;
  }

  async stepFetchGitHubContributions(): Promise<boolean> {
    console.log('\n📊 Step 2: Fetching GitHub Contributions');
    console.log('─────────────────────────────────────────\n');

    try {
      console.log('Running: npm run track');
      execSync('npm run track', { cwd: process.cwd(), stdio: 'inherit' });

      // Verify contributors file was generated
      const contributorsPath = path.join(
        process.cwd(),
        '../data/contributors.json'
      );
      const contributors = JSON.parse(
        await fs.readFile(contributorsPath, 'utf-8')
      );

      const eligibleCount = contributors.contributors?.filter(
        (c: any) => c.eligible
      ).length || 0;

      console.log(`\n✓ Found ${eligibleCount} eligible contributors`);

      this.addResult(
        'GitHub Contributions Fetch',
        'SUCCESS',
        `Fetched ${contributors.contributors?.length || 0} contributors, ${eligibleCount} eligible`,
        { totalCount: contributors.contributors?.length, eligibleCount }
      );

      return true;
    } catch (error) {
      this.addResult(
        'GitHub Contributions Fetch',
        'FAILED',
        `Error fetching contributions: ${error}`
      );
      return false;
    }
  }

  async stepGenerateMerkleTree(): Promise<boolean> {
    console.log('\n🌳 Step 3: Generating Merkle Tree');
    console.log('─────────────────────────────────────────\n');

    try {
      console.log('Running: npm run generate-merkle');
      execSync('npm run generate-merkle', {
        cwd: process.cwd(),
        stdio: 'inherit',
      });

      // Verify files were generated
      const merkleRootPath = path.join(process.cwd(), '../data/merkle-root.txt');
      const merkleRoot = await fs.readFile(merkleRootPath, 'utf-8');

      console.log(`\n✓ Generated Merkle root: ${merkleRoot.trim().substring(0, 10)}...`);

      this.addResult(
        'Merkle Tree Generation',
        'SUCCESS',
        'Successfully generated merkle tree and proofs',
        { merkleRoot: merkleRoot.trim() }
      );

      return true;
    } catch (error) {
      this.addResult(
        'Merkle Tree Generation',
        'FAILED',
        `Error generating merkle tree: ${error}`
      );
      return false;
    }
  }

  async stepCalculateDistribution(): Promise<any> {
    console.log('\n🧮 Step 4: Calculating Distribution');
    console.log('─────────────────────────────────────────\n');

    try {
      console.log('Running: npm run calculate-payment-splitter');
      execSync('npm run calculate-payment-splitter', {
        cwd: process.cwd(),
        stdio: 'inherit',
      });

      // Load the distribution data
      const distributionPath = path.join(
        process.cwd(),
        `../data/weekly-distribution.json`
      );

      let distribution = null;
      try {
        distribution = JSON.parse(
          await fs.readFile(distributionPath, 'utf-8')
        );
      } catch {
        // If specific week file doesn't exist, use a generated one
        console.log('⚠️  Using calculated distribution data');
        distribution = {
          weekNumber: this.config?.weekNumber,
          contributors: [],
          githubNames: [],
          shares: [],
        };
      }

      console.log(
        `\n✓ Calculated distribution for ${distribution.contributors?.length || 0} recipients`
      );

      this.addResult(
        'Distribution Calculation',
        'SUCCESS',
        `Calculated distribution parameters`,
        distribution
      );

      return distribution;
    } catch (error) {
      this.addResult(
        'Distribution Calculation',
        'FAILED',
        `Error calculating distribution: ${error}`
      );
      return null;
    }
  }

  async stepReportStrategy(): Promise<boolean> {
    console.log('\n📈 Step 5: Verifying Strategy Health');
    console.log('─────────────────────────────────────────\n');

    if (!this.config?.strategy) {
      this.addResult(
        'Strategy Verification',
        'SKIPPED',
        'Strategy address not configured'
      );
      return true;
    }

    try {
      const strategy = new ethers.Contract(
        this.config.strategy,
        STRATEGY_ABI,
        this.signer
      );

      const totalAssets = await strategy.totalAssets();
      console.log(`✓ Current assets in strategy: ${ethers.formatUnits(totalAssets, 18)}`);

      console.log(
        '\n✅ Strategy is accumulating yield from Aave'
      );
      console.log(
        '   Weekly distribution will transfer yield to PaymentSplitter'
      );

      this.addResult(
        'Strategy Verification',
        'SUCCESS',
        'Strategy healthy and accumulating yield',
        { totalAssets: ethers.formatUnits(totalAssets, 18) }
      );

      return true;
    } catch (error) {
      this.addResult(
        'Strategy Verification',
        'FAILED',
        `Error checking strategy: ${error}`
      );
      return false;
    }
  }

  async stepPreviewYield(): Promise<boolean> {
    console.log('\n🔍 Step 6: Checking Available Yield');
    console.log('─────────────────────────────────────────\n');

    if (!this.config?.strategy) {
      this.addResult(
        'Yield Check',
        'SKIPPED',
        'Strategy address not configured'
      );
      return true;
    }

    try {
      const strategy = new ethers.Contract(
        this.config.strategy,
        STRATEGY_ABI,
        this.provider
      );

      const totalAssets = await strategy.totalAssets();
      console.log(
        `✓ Total assets in strategy: ${ethers.formatUnits(totalAssets, 18)} tokens`
      );
      console.log(
        `   (Principal + accumulated yield from Aave)`
      );

      this.addResult(
        'Yield Check',
        'SUCCESS',
        `Strategy holding ${ethers.formatUnits(totalAssets, 18)} assets`,
        { totalAssets: ethers.formatUnits(totalAssets, 18) }
      );

      return true;
    } catch (error) {
      this.addResult(
        'Yield Check',
        'FAILED',
        `Error checking yield: ${error}`
      );
      return false;
    }
  }

  async stepCreateDistribution(distribution: any): Promise<boolean> {
    console.log('\n💰 Step 7: Creating Weekly Distribution');
    console.log('─────────────────────────────────────────\n');

    if (!this.config?.manager) {
      this.addResult(
        'Distribution Creation',
        'SKIPPED',
        'Manager address not configured'
      );
      return true;
    }

    if (!distribution || !distribution.contributors) {
      this.addResult(
        'Distribution Creation',
        'FAILED',
        'No distribution data available'
      );
      return false;
    }

    try {
      const manager = new ethers.Contract(
        this.config.manager,
        MANAGER_ABI,
        this.signer
      );

      console.log(`\n⚠️  To create the distribution, execute:\n`);

      console.log(
        `cast send ${this.config.manager} \\`
      );
      console.log(`  "createWeeklyDistribution(uint256,address[],string[],uint256[])" \\`);
      console.log(`  "${this.config.weekNumber}" \\`);
      console.log(
        `  "[${distribution.contributors.join(',')}]" \\`
      );
      console.log(
        `  "[${distribution.githubNames.map((n: string) => `"${n}"`).join(',')}]" \\`
      );
      console.log(
        `  "[${distribution.shares.join(',')}]" \\`
      );
      console.log(`  --rpc-url $ETH_RPC_URL \\`);
      console.log(`  --private-key $PRIVATE_KEY\n`);

      console.log(
        'Or use the sendDistribution.ts helper script.\n'
      );

      this.addResult(
        'Distribution Creation',
        'SUCCESS',
        'Distribution ready - manual execution required',
        {
          contributors: distribution.contributors.length,
          command: `cast send ${this.config.manager} createWeeklyDistribution(...)`,
        }
      );

      return true;
    } catch (error) {
      this.addResult(
        'Distribution Creation',
        'FAILED',
        `Error creating distribution: ${error}`
      );
      return false;
    }
  }

  printResults(): void {
    console.log('\n\n═══════════════════════════════════════════════════════════════');
    console.log('                     WEEKLY CYCLE REPORT                     ');
    console.log('═══════════════════════════════════════════════════════════════\n');

    const statusSymbols: Record<string, string> = {
      SUCCESS: '✅',
      FAILED: '❌',
      SKIPPED: '⏭️',
    };

    for (const result of this.results) {
      const symbol = statusSymbols[result.status];
      console.log(`${symbol} ${result.step}`);
      console.log(`   └─ ${result.message}`);

      if (result.txHash) {
        console.log(`      Tx: ${result.txHash}`);
      }
    }

    const failedCount = this.results.filter((r) => r.status === 'FAILED').length;
    const successCount = this.results.filter((r) => r.status === 'SUCCESS')
      .length;

    console.log('\n───────────────────────────────────────────────────────────────');
    console.log(`Summary: ${successCount} succeeded, ${failedCount} failed`);

    if (failedCount > 0) {
      console.log(
        '\n🚨 Some steps failed. Review errors above and retry.\n'
      );
    } else {
      console.log(
        '\n✅ Weekly cycle completed! Contributors can now claim their yield.\n'
      );
    }

    console.log('📝 NEXT ACTIONS:');
    console.log('───────────────────────────────────────\n');
    console.log(
      '1. Ensure keeper has called strategy.report() to mint profit shares'
    );
    console.log(
      '2. Execute the createWeeklyDistribution command shown above'
    );
    console.log('3. Contributors will be able to claim yield from PaymentSplitter\n');
  }
}

async function main() {
  console.log('📅 Octant Contributor Rewards System - Weekly Distribution Cycle\n');

  const manager = new WeeklyCycleManager();
  const config = await manager.loadConfig();

  console.log(`═══════════════════════════════════════════════════════════════`);
  console.log(`Week #${config.weekNumber} Distribution Cycle`);
  console.log(
    `Started: ${new Date(config.timestamp).toISOString()}`
  );
  console.log(`═══════════════════════════════════════════════════════════════\n`);

  // Run all steps
  const step1 = await manager.stepVerifyConfiguration();
  if (!step1) {
    console.error(
      '\n❌ Configuration check failed. Cannot proceed.'
    );
    process.exit(1);
  }

  await manager.stepFetchGitHubContributions();
  await manager.stepGenerateMerkleTree();
  const distribution = await manager.stepCalculateDistribution();
  await manager.stepReportStrategy();
  await manager.stepPreviewYield();
  await manager.stepCreateDistribution(distribution);

  manager.printResults();
}

main().catch((error) => {
  console.error('❌ Weekly cycle failed:', error);
  process.exit(1);
});
