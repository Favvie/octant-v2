import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

interface DeploymentConfig {
  network: {
    name: string;
    chainId: number;
    rpcUrl: string;
  };
  aave: {
    poolAddress: string;
    assetAddress: string;
    assetSymbol: string;
  };
  roles: {
    management: string;
    keeper: string;
    emergencyAdmin: string;
  };
  strategy: {
    name: string;
    symbol: string;
  };
  contracts: {
    strategyFactory: string | null;
    strategy: string | null;
    weeklyPaymentSplitterManager: string | null;
    ecosystemLeadNFT: string | null;
    ecosystemLeadVoting: string | null;
    ecosystemGovernanceExecutor: string | null;
    contributorRegistry: string | null;
  };
  deploymentTimestamp: number | null;
  deploymentBlockNumber: number | null;
  deploymentTransactionHashes: Record<string, string>;
}

const CONTRACTS = {
  YIELD_DONATING_STRATEGY: 'YieldDonatingTokenizedStrategy',
  AAVE_V3_STRATEGY: 'AaveV3YieldDonatingStrategy',
  STRATEGY_FACTORY: 'YieldDonatingStrategyFactory',
  WEEKLY_PAYMENT_SPLITTER: 'WeeklyPaymentSplitterManager',
  ECOSYSTEM_LEAD_NFT: 'EcosystemLeadNFT',
  ECOSYSTEM_LEAD_VOTING: 'EcosystemLeadVoting',
  ECOSYSTEM_GOVERNANCE_EXECUTOR: 'EcosystemGovernanceExecutor',
  CONTRIBUTOR_REGISTRY: 'ContributorRegistry',
};

class DeploymentManager {
  private provider: ethers.JsonRpcProvider;
  private signer: ethers.Signer;
  private config: DeploymentConfig | null = null;
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

  async loadConfig(): Promise<DeploymentConfig> {
    try {
      const data = await fs.readFile(this.configPath, 'utf-8');
      this.config = JSON.parse(data);
      console.log('✓ Loaded existing deployment config');
      return this.config;
    } catch (error) {
      console.log('ℹ No existing config found, creating new one');
      return this.createNewConfig();
    }
  }

  private async createNewConfig(): Promise<DeploymentConfig> {
    const network = await this.provider.getNetwork();
    const management = await this.signer.getAddress();

    const config: DeploymentConfig = {
      network: {
        name: network.name,
        chainId: Number(network.chainId),
        rpcUrl: process.env.ETH_RPC_URL || '',
      },
      aave: {
        poolAddress: process.env.AAVE_POOL_ADDRESS || '',
        assetAddress: process.env.ASSET_ADDRESS || '',
        assetSymbol: process.env.ASSET_SYMBOL || 'DAI',
      },
      roles: {
        management,
        keeper: process.env.KEEPER_ADDRESS || management,
        emergencyAdmin: process.env.EMERGENCY_ADMIN || management,
      },
      strategy: {
        name: 'Aave V3 Yield Donating Strategy',
        symbol: 'aYield',
      },
      contracts: {
        strategyFactory: null,
        strategy: null,
        weeklyPaymentSplitterManager: null,
        ecosystemLeadNFT: null,
        ecosystemLeadVoting: null,
        ecosystemGovernanceExecutor: null,
        contributorRegistry: null,
      },
      deploymentTimestamp: null,
      deploymentBlockNumber: null,
      deploymentTransactionHashes: {},
    };

    this.config = config;
    return config;
  }

  async saveConfig(): Promise<void> {
    if (!this.config) {
      throw new Error('No config to save');
    }

    this.config.deploymentTimestamp = Date.now();
    const blockNumber = await this.provider.getBlockNumber();
    this.config.deploymentBlockNumber = blockNumber;

    await fs.writeFile(
      this.configPath,
      JSON.stringify(this.config, null, 2)
    );
    console.log(`✓ Saved deployment config to ${this.configPath}`);
  }

  async deployYieldDonatingStrategy(): Promise<string> {
    console.log('\n📦 Deploying YieldDonatingTokenizedStrategy (Implementation)...');

    if (!this.config) throw new Error('Config not loaded');

    // In a real deployment, you would:
    // 1. Compile the contract
    // 2. Deploy it via forge or hardhat
    // For now, we'll create a placeholder showing the flow

    console.log(`
    To deploy YieldDonatingTokenizedStrategy:

    forge create src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol:YieldDonatingTokenizedStrategy \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const deploymentAddress = process.env.TOKENIZED_STRATEGY_ADDRESS || '';
    if (!deploymentAddress) {
      console.warn(
        '⚠️  TOKENIZED_STRATEGY_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return deploymentAddress;
  }

  async deployStrategyFactory(
    tokenizedStrategyAddress: string
  ): Promise<string> {
    console.log('\n📦 Deploying YieldDonatingStrategyFactory...');

    if (!this.config) throw new Error('Config not loaded');

    const { management, keeper, emergencyAdmin } =
      this.config.roles;

    console.log(`
    To deploy YieldDonatingStrategyFactory:

    forge create src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol:YieldDonatingStrategyFactory \\
      --constructor-args \\
        "${management}" \\
        "${keeper}" \\
        "${emergencyAdmin}" \\
        "${tokenizedStrategyAddress}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const factoryAddress = process.env.STRATEGY_FACTORY_ADDRESS || '';
    if (!factoryAddress) {
      console.warn(
        '⚠️  STRATEGY_FACTORY_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return factoryAddress;
  }

  async deployAaveV3Strategy(factoryAddress: string): Promise<string> {
    console.log('\n📦 Deploying AaveV3YieldDonatingStrategy via Factory...');

    if (!this.config) throw new Error('Config not loaded');

    const { assetAddress } = this.config.aave;
    const { name, symbol } = this.config.strategy;

    console.log(`
    To deploy AaveV3YieldDonatingStrategy via factory:

    cast send ${factoryAddress} \\
      "newAaveV3Strategy(address,address,string)" \\
      "${assetAddress}" \\
      "${assetAddress}" \\
      "${name}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY

    Then retrieve the deployed address from events.
    `);

    const strategyAddress = process.env.AAVE_STRATEGY_ADDRESS || '';
    if (!strategyAddress) {
      console.warn(
        '⚠️  AAVE_STRATEGY_ADDRESS not set. Deploy via factory and set in .env'
      );
    }

    return strategyAddress;
  }

  async deployContractorRegistry(merkleRoot: string): Promise<string> {
    console.log('\n📦 Deploying ContributorRegistry...');

    if (!this.config) throw new Error('Config not loaded');

    const { management } = this.config.roles;

    console.log(`
    To deploy ContributorRegistry:

    forge create src/registry/ContributorRegistry.sol:ContributorRegistry \\
      --constructor-args \\
        "${merkleRoot}" \\
        "${management}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const registryAddress = process.env.CONTRIBUTOR_REGISTRY_ADDRESS || '';
    if (!registryAddress) {
      console.warn(
        '⚠️  CONTRIBUTOR_REGISTRY_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return registryAddress;
  }

  async deployEcosystemLeadNFT(): Promise<string> {
    console.log('\n📦 Deploying EcosystemLeadNFT...');

    if (!this.config) throw new Error('Config not loaded');

    const { management } = this.config.roles;

    console.log(`
    To deploy EcosystemLeadNFT:

    forge create src/nft/EcosystemLeadNFT.sol:EcosystemLeadNFT \\
      --constructor-args \\
        "Ecosystem Lead" \\
        "ECOLEAD" \\
        "${management}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const nftAddress = process.env.ECOSYSTEM_LEAD_NFT_ADDRESS || '';
    if (!nftAddress) {
      console.warn(
        '⚠️  ECOSYSTEM_LEAD_NFT_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return nftAddress;
  }

  async deployEcosystemLeadVoting(nftAddress: string): Promise<string> {
    console.log('\n📦 Deploying EcosystemLeadVoting...');

    if (!this.config) throw new Error('Config not loaded');

    console.log(`
    To deploy EcosystemLeadVoting:

    forge create src/mechanisms/EcosystemLeadVoting.sol:EcosystemLeadVoting \\
      --constructor-args \\
        "${nftAddress}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const votingAddress = process.env.ECOSYSTEM_LEAD_VOTING_ADDRESS || '';
    if (!votingAddress) {
      console.warn(
        '⚠️  ECOSYSTEM_LEAD_VOTING_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return votingAddress;
  }

  async deployGovernanceExecutor(nftAddress: string): Promise<string> {
    console.log('\n📦 Deploying EcosystemGovernanceExecutor...');

    if (!this.config) throw new Error('Config not loaded');

    const { management } = this.config.roles;

    console.log(`
    To deploy EcosystemGovernanceExecutor:

    forge create src/governance/EcosystemGovernanceExecutor.sol:EcosystemGovernanceExecutor \\
      --constructor-args \\
        "${nftAddress}" \\
        "${management}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const executorAddress = process.env.ECOSYSTEM_GOVERNANCE_EXECUTOR_ADDRESS || '';
    if (!executorAddress) {
      console.warn(
        '⚠️  ECOSYSTEM_GOVERNANCE_EXECUTOR_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return executorAddress;
  }

  async deployWeeklyPaymentSplitterManager(
    strategyAddress: string,
    paymentSplitterFactoryAddress: string
  ): Promise<string> {
    console.log('\n📦 Deploying WeeklyPaymentSplitterManager...');

    if (!this.config) throw new Error('Config not loaded');

    const { management } = this.config.roles;

    console.log(`
    To deploy WeeklyPaymentSplitterManager:

    Note: The strategy should be configured to directly mint profit to PaymentSplitter.
    The manager orchestrates weekly distribution creation.

    forge create src/distribution/WeeklyPaymentSplitterManager.sol:WeeklyPaymentSplitterManager \\
      --constructor-args \\
        "${paymentSplitterFactoryAddress}" \\
        "${strategyAddress}" \\
        "${management}" \\
      --rpc-url ${this.config.network.rpcUrl} \\
      --private-key $PRIVATE_KEY \\
      --broadcast
    `);

    const managerAddress = process.env.WEEKLY_PAYMENT_SPLITTER_MANAGER_ADDRESS || '';
    if (!managerAddress) {
      console.warn(
        '⚠️  WEEKLY_PAYMENT_SPLITTER_MANAGER_ADDRESS not set. Please deploy and set in .env'
      );
    }

    return managerAddress;
  }

  async updateConfig(contractName: string, address: string): Promise<void> {
    if (!this.config) throw new Error('Config not loaded');

    const contractKey = Object.entries(CONTRACTS).find(
      ([, v]) => v === contractName
    )?.[0];

    if (contractKey) {
      const keyMap: Record<string, keyof DeploymentConfig['contracts']> = {
        YIELD_DONATING_STRATEGY: 'strategy',
        STRATEGY_FACTORY: 'strategyFactory',
        AAVE_V3_STRATEGY: 'strategy',
        WEEKLY_PAYMENT_SPLITTER: 'weeklyPaymentSplitterManager',
        ECOSYSTEM_LEAD_NFT: 'ecosystemLeadNFT',
        ECOSYSTEM_LEAD_VOTING: 'ecosystemLeadVoting',
        ECOSYSTEM_GOVERNANCE_EXECUTOR: 'ecosystemGovernanceExecutor',
        CONTRIBUTOR_REGISTRY: 'contributorRegistry',
      };

      const configKey = keyMap[contractKey];
      if (configKey) {
        (this.config.contracts[configKey] as string | null) = address;
      }
    }

    this.config.deploymentTransactionHashes[contractName] = address;
  }
}

async function main() {
  console.log('🚀 Octant Contributor Rewards System - Master Deployment Script\n');

  const manager = new DeploymentManager();
  const config = await manager.loadConfig();

  console.log(`\n📍 Network: ${config.network.name} (Chain ID: ${config.network.chainId})`);
  console.log(`🔑 Management Address: ${config.roles.management}`);
  console.log(`🤖 Keeper Address: ${config.roles.keeper}`);
  console.log(`🚨 Emergency Admin: ${config.roles.emergencyAdmin}`);
  console.log(`💰 Asset: ${config.aave.assetSymbol}`);

  console.log('\n\n═══════════════════════════════════════════════════════════════');
  console.log('           DEPLOYMENT SEQUENCE FOR MAINNET FORK              ');
  console.log('═══════════════════════════════════════════════════════════════\n');

  console.log('PHASE 1: CORE STRATEGY INFRASTRUCTURE');
  console.log('─────────────────────────────────────────\n');

  const tokenizedStrategyAddr = await manager.deployYieldDonatingStrategy();
  if (tokenizedStrategyAddr) {
    manager.updateConfig(
      CONTRACTS.YIELD_DONATING_STRATEGY,
      tokenizedStrategyAddr
    );
  }

  const factoryAddr = await manager.deployStrategyFactory(
    tokenizedStrategyAddr || process.env.TOKENIZED_STRATEGY_ADDRESS || ''
  );
  if (factoryAddr) {
    manager.updateConfig(CONTRACTS.STRATEGY_FACTORY, factoryAddr);
  }

  const strategyAddr = await manager.deployAaveV3Strategy(
    factoryAddr || process.env.STRATEGY_FACTORY_ADDRESS || ''
  );
  if (strategyAddr) {
    manager.updateConfig(CONTRACTS.AAVE_V3_STRATEGY, strategyAddr);
  }

  console.log('\nPHASE 2: GOVERNANCE & VOTING');
  console.log('─────────────────────────────────────────\n');

  const nftAddr = await manager.deployEcosystemLeadNFT();
  if (nftAddr) {
    manager.updateConfig(CONTRACTS.ECOSYSTEM_LEAD_NFT, nftAddr);
  }

  const votingAddr = await manager.deployEcosystemLeadVoting(
    nftAddr || process.env.ECOSYSTEM_LEAD_NFT_ADDRESS || ''
  );
  if (votingAddr) {
    manager.updateConfig(CONTRACTS.ECOSYSTEM_LEAD_VOTING, votingAddr);
  }

  const executorAddr = await manager.deployGovernanceExecutor(
    nftAddr || process.env.ECOSYSTEM_LEAD_NFT_ADDRESS || ''
  );
  if (executorAddr) {
    manager.updateConfig(CONTRACTS.ECOSYSTEM_GOVERNANCE_EXECUTOR, executorAddr);
  }

  console.log('\nPHASE 3: CONTRIBUTOR MANAGEMENT');
  console.log('─────────────────────────────────────────\n');

  // Load merkle root from generated file
  let merkleRoot = '0x0000000000000000000000000000000000000000000000000000000000000000';
  try {
    const merkleRootPath = path.join(
      process.cwd(),
      '../data/merkle-root.txt'
    );
    merkleRoot = (await fs.readFile(merkleRootPath, 'utf-8')).trim();
    console.log(`✓ Loaded Merkle root: ${merkleRoot}`);
  } catch (error) {
    console.warn(
      '⚠️  Could not load merkle-root.txt. Please run: npm run generate-merkle'
    );
  }

  const registryAddr = await manager.deployContractorRegistry(merkleRoot);
  if (registryAddr) {
    manager.updateConfig(CONTRACTS.CONTRIBUTOR_REGISTRY, registryAddr);
  }

  console.log('\nPHASE 4: YIELD DISTRIBUTION');
  console.log('─────────────────────────────────────────\n');

  const paymentSplitterFactory =
    process.env.PAYMENT_SPLITTER_FACTORY_ADDRESS || '';
  if (!paymentSplitterFactory) {
    console.warn(
      '⚠️  PAYMENT_SPLITTER_FACTORY_ADDRESS not set. Required for WeeklyPaymentSplitterManager'
    );
  }

  const managerAddr = await manager.deployWeeklyPaymentSplitterManager(
    strategyAddr || process.env.AAVE_STRATEGY_ADDRESS || '',
    paymentSplitterFactory
  );
  if (managerAddr) {
    manager.updateConfig(
      CONTRACTS.WEEKLY_PAYMENT_SPLITTER,
      managerAddr
    );
  }

  console.log('\n\n═══════════════════════════════════════════════════════════════');
  console.log('                    DEPLOYMENT SUMMARY                         ');
  console.log('═══════════════════════════════════════════════════════════════\n');

  console.log('📋 Deployment Configuration:');
  console.log(JSON.stringify(config.contracts, null, 2));

  await manager.saveConfig();

  console.log('\n\n⏭️  NEXT STEPS:');
  console.log('───────────────────────────────────────\n');
  console.log(
    '1. Deploy each contract using the provided forge commands above'
  );
  console.log('2. Update .env with deployed contract addresses');
  console.log('3. Run: npm run setup-approvals');
  console.log('4. Run: npm run setup-keeper');
  console.log('5. Run: npm run health-check');
  console.log('6. Run: npm run weekly:cycle (when ready for first distribution)\n');

  console.log('📚 For complete documentation, see docs/DEPLOYMENT.md\n');
}

main().catch((error) => {
  console.error('❌ Deployment failed:', error);
  process.exit(1);
});
