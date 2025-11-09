import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

interface HealthCheckResult {
  component: string;
  status: 'OK' | 'WARNING' | 'ERROR' | 'UNCONFIGURED';
  message: string;
  details?: Record<string, any>;
}

// Minimal ABIs
const STRATEGY_ABI = [
  'function balanceOf(address account) public view returns (uint256)',
  'function totalAssets() public view returns (uint256)',
  'function asset() public view returns (address)',
];

const REGISTRY_ABI = [
  'function merkleRoot() public view returns (bytes32)',
  'function getContributor(address) public view returns (tuple(address, string, uint256, uint256))',
];

class HealthChecker {
  private provider: ethers.JsonRpcProvider;
  private results: HealthCheckResult[] = [];
  private configPath: string;

  constructor() {
    const rpcUrl = process.env.ETH_RPC_URL;
    if (!rpcUrl) {
      throw new Error('ETH_RPC_URL not set in .env');
    }

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.configPath = path.join(process.cwd(), 'deployment-config.json');
  }

  async loadDeploymentConfig(): Promise<any> {
    try {
      const data = await fs.readFile(this.configPath, 'utf-8');
      return JSON.parse(data);
    } catch (error) {
      this.addResult('Configuration', 'ERROR', 'Could not load deployment-config.json');
      return null;
    }
  }

  addResult(
    component: string,
    status: 'OK' | 'WARNING' | 'ERROR' | 'UNCONFIGURED',
    message: string,
    details?: Record<string, any>
  ): void {
    this.results.push({ component, status, message, details });
  }

  async checkNetwork(): Promise<void> {
    try {
      const network = await this.provider.getNetwork();
      const blockNumber = await this.provider.getBlockNumber();

      this.addResult(
        'Network',
        'OK',
        `Connected to ${network.name}`,
        {
          chainId: network.chainId,
          blockNumber,
        }
      );
    } catch (error) {
      this.addResult('Network', 'ERROR', 'Failed to connect to RPC', {
        error: String(error),
      });
    }
  }

  async checkStrategy(strategyAddress: string): Promise<void> {
    if (!strategyAddress || strategyAddress === '') {
      this.addResult('Strategy', 'UNCONFIGURED', 'No strategy address configured');
      return;
    }

    try {
      const strategy = new ethers.Contract(
        strategyAddress,
        STRATEGY_ABI,
        this.provider
      );

      const totalAssets = await strategy.totalAssets();
      const asset = await strategy.asset();

      if (totalAssets === 0n) {
        this.addResult(
          'Strategy',
          'WARNING',
          'Strategy deployed but no assets deposited',
          { address: strategyAddress, asset }
        );
      } else {
        this.addResult(
          'Strategy',
          'OK',
          `Strategy active with ${ethers.formatUnits(totalAssets, 18)} assets`,
          { address: strategyAddress, totalAssets, asset }
        );
      }
    } catch (error) {
      this.addResult(
        'Strategy',
        'ERROR',
        'Could not read strategy data',
        { address: strategyAddress, error: String(error) }
      );
    }
  }

  async checkStrategyConfiguration(strategyAddress: string): Promise<void> {
    if (!strategyAddress) {
      this.addResult(
        'Strategy Configuration',
        'UNCONFIGURED',
        'Strategy address not configured'
      );
      return;
    }

    try {
      const strategy = new ethers.Contract(
        strategyAddress,
        STRATEGY_ABI,
        this.provider
      );

      const asset = await strategy.asset();
      const totalAssets = await strategy.totalAssets();

      this.addResult(
        'Strategy Configuration',
        'OK',
        'Strategy properly configured',
        {
          strategy: strategyAddress,
          asset,
          totalAssets: ethers.formatUnits(totalAssets, 18),
        }
      );
    } catch (error) {
      this.addResult(
        'Strategy Configuration',
        'ERROR',
        'Could not verify strategy configuration',
        { error: String(error) }
      );
    }
  }

  async checkContributorRegistry(registryAddress: string): Promise<void> {
    if (!registryAddress || registryAddress === '') {
      this.addResult(
        'Contributor Registry',
        'UNCONFIGURED',
        'No registry address configured'
      );
      return;
    }

    try {
      const registry = new ethers.Contract(
        registryAddress,
        REGISTRY_ABI,
        this.provider
      );

      const merkleRoot = await registry.merkleRoot();

      if (merkleRoot === '0x' + '0'.repeat(64)) {
        this.addResult(
          'Contributor Registry',
          'WARNING',
          'Merkle root not set',
          { address: registryAddress }
        );
      } else {
        this.addResult(
          'Contributor Registry',
          'OK',
          'Registry configured with merkle root',
          { address: registryAddress, merkleRoot }
        );
      }
    } catch (error) {
      this.addResult(
        'Contributor Registry',
        'ERROR',
        'Could not read registry data',
        { address: registryAddress, error: String(error) }
      );
    }
  }

  async checkMerkleTreeData(): Promise<void> {
    try {
      // Check if merkle root file exists
      const merkleRootPath = path.join(process.cwd(), '../data/merkle-root.txt');
      const merkleTreePath = path.join(process.cwd(), '../data/merkle-tree.json');
      const contributorsPath = path.join(
        process.cwd(),
        '../data/contributors.json'
      );

      const hasRoot = await fs.access(merkleRootPath).then(() => true).catch(() => false);
      const hasTree = await fs.access(merkleTreePath).then(() => true).catch(() => false);
      const hasContributors = await fs.access(contributorsPath).then(() => true).catch(() => false);

      if (!hasRoot || !hasTree || !hasContributors) {
        this.addResult(
          'Merkle Tree Data',
          'WARNING',
          'Missing merkle tree files',
          {
            merkleRoot: hasRoot,
            merkleTree: hasTree,
            contributors: hasContributors,
          }
        );
      } else {
        const treeData = JSON.parse(await fs.readFile(merkleTreePath, 'utf-8'));
        const contributorCount = treeData.leaves?.length || 0;

        this.addResult(
          'Merkle Tree Data',
          'OK',
          `Merkle tree data available with ${contributorCount} contributors`,
          { hasRoot, hasTree, hasContributors, contributorCount }
        );
      }
    } catch (error) {
      this.addResult(
        'Merkle Tree Data',
        'ERROR',
        'Error checking merkle data',
        { error: String(error) }
      );
    }
  }

  async checkGitHubData(): Promise<void> {
    try {
      const contributorsPath = path.join(
        process.cwd(),
        '../data/contributors.json'
      );
      const data = JSON.parse(await fs.readFile(contributorsPath, 'utf-8'));

      const eligibleCount = data.contributors?.filter(
        (c: any) => c.eligible
      ).length || 0;
      const totalCount = data.contributors?.length || 0;

      if (totalCount === 0) {
        this.addResult(
          'GitHub Data',
          'WARNING',
          'No contributor data found',
          { totalCount: 0 }
        );
      } else {
        this.addResult(
          'GitHub Data',
          'OK',
          `GitHub data available: ${eligibleCount} eligible / ${totalCount} total contributors`,
          { totalCount, eligibleCount }
        );
      }
    } catch (error) {
      this.addResult(
        'GitHub Data',
        'WARNING',
        'Could not load GitHub data',
        { error: String(error) }
      );
    }
  }

  async checkEnvironmentVariables(): Promise<void> {
    const required = [
      'ETH_RPC_URL',
      'PRIVATE_KEY',
      'ASSET_ADDRESS',
      'AAVE_POOL_ADDRESS',
    ];

    const optional = [
      'KEEPER_ADDRESS',
      'DRAGON_ROUTER',
      'STRATEGY_FACTORY_ADDRESS',
      'AAVE_STRATEGY_ADDRESS',
      'WEEKLY_PAYMENT_SPLITTER_MANAGER_ADDRESS',
    ];

    const missing = required.filter((v) => !process.env[v]);
    const missingOptional = optional.filter((v) => !process.env[v]);

    if (missing.length > 0) {
      this.addResult(
        'Environment Variables',
        'ERROR',
        `Missing required environment variables: ${missing.join(', ')}`,
        { missing }
      );
    } else if (missingOptional.length > 0) {
      this.addResult(
        'Environment Variables',
        'WARNING',
        `Missing optional environment variables: ${missingOptional.join(', ')}`,
        { missing: missingOptional }
      );
    } else {
      this.addResult(
        'Environment Variables',
        'OK',
        'All required environment variables configured'
      );
    }
  }

  async runAllChecks(): Promise<void> {
    console.log('🔍 Running health checks...\n');

    await this.checkEnvironmentVariables();
    await this.checkNetwork();
    await this.checkMerkleTreeData();
    await this.checkGitHubData();

    const config = await this.loadDeploymentConfig();

    if (config && config.contracts) {
      await this.checkStrategy(config.contracts.strategy);
      await this.checkStrategyConfiguration(config.contracts.strategy);
      await this.checkContributorRegistry(config.contracts.contributorRegistry);
    }
  }

  printResults(): void {
    console.log('\n═══════════════════════════════════════════════════════════════');
    console.log('                         HEALTH CHECK REPORT                  ');
    console.log('═══════════════════════════════════════════════════════════════\n');

    const statusSymbols: Record<string, string> = {
      OK: '✅',
      WARNING: '⚠️',
      ERROR: '❌',
      UNCONFIGURED: '⏸️',
    };

    let hasErrors = false;
    let hasWarnings = false;

    for (const result of this.results) {
      const symbol = statusSymbols[result.status];
      console.log(`${symbol} ${result.component}: ${result.message}`);

      if (result.details) {
        for (const [key, value] of Object.entries(result.details)) {
          if (typeof value === 'object') {
            console.log(`     ${key}: ${JSON.stringify(value)}`);
          } else {
            console.log(`     ${key}: ${value}`);
          }
        }
      }

      if (result.status === 'ERROR') hasErrors = true;
      if (result.status === 'WARNING') hasWarnings = true;
    }

    // Summary
    const errorCount = this.results.filter((r) => r.status === 'ERROR').length;
    const warningCount = this.results.filter(
      (r) => r.status === 'WARNING'
    ).length;
    const okCount = this.results.filter((r) => r.status === 'OK').length;

    console.log('\n───────────────────────────────────────────────────────────────');
    console.log(
      `Summary: ${okCount} OK, ${warningCount} Warnings, ${errorCount} Errors`
    );

    if (hasErrors) {
      console.log('\n🚨 CRITICAL ISSUES FOUND - System not ready for production');
      console.log('   Please resolve all errors before proceeding.\n');
    } else if (hasWarnings) {
      console.log('\n⚠️  Warnings detected - Review before production deployment');
      console.log('   Consider resolving warnings for optimal performance.\n');
    } else {
      console.log('\n✅ All checks passed! System ready for operation.\n');
    }

    console.log('📋 NEXT STEPS:');
    console.log('───────────────────────────────────────\n');
    if (hasErrors) {
      console.log('1. Fix all errors listed above');
      console.log('2. Run health check again: npm run health-check');
      console.log('3. Once green, proceed with: npm run weekly:cycle\n');
    } else if (hasWarnings) {
      console.log('1. Review warnings above');
      console.log('2. Run: npm run setup-approvals (if approvals needed)');
      console.log('3. Run: npm run setup-keeper (if keeper needed)');
      console.log('4. Run: npm run weekly:cycle (when ready)\n');
    } else {
      console.log('1. System is ready for weekly distributions');
      console.log('2. Run: npm run weekly:cycle\n');
    }
  }
}

async function main() {
  console.log('🏥 Octant Contributor Rewards System - Health Check\n');

  const checker = new HealthChecker();
  await checker.runAllChecks();
  checker.printResults();
}

main().catch((error) => {
  console.error('❌ Health check failed:', error);
  process.exit(1);
});
