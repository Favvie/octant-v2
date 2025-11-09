import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

const AAVE_POOL = '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2';
const aUSDC = '0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';

const MANAGEMENT = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';
const KEEPER = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';
const EMERGENCY_ADMIN = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';
const DONATION_ADDRESS = '0xFDb60A0e05539aA30acba38813cF6123B8780b04'; // Will be PaymentSplitter later

async function deployTokenizedStrategy(signer: ethers.Signer): Promise<string> {
  // YieldDonatingTokenizedStrategy is from octant-core but should be in build outputs
  const possiblePaths = [
    path.join(process.cwd(), '..', 'out', 'YieldDonatingTokenizedStrategy.sol', 'YieldDonatingTokenizedStrategy.json'),
    path.join(process.cwd(), '..', 'dependencies', 'octant-v2-core', 'out', 'YieldDonatingTokenizedStrategy.sol', 'YieldDonatingTokenizedStrategy.json')
  ];

  let artifact: any = null;
  let artifactPath = '';

  for (const p of possiblePaths) {
    try {
      artifact = JSON.parse(await fs.readFile(p, 'utf-8'));
      artifactPath = p;
      break;
    } catch (e) {
      // Try next path
    }
  }

  if (!artifact) {
    throw new Error(`Could not find YieldDonatingTokenizedStrategy artifact at any of: ${possiblePaths.join(', ')}`);
  }

  try {
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, signer);

    console.log('1️⃣ Deploying YieldDonatingTokenizedStrategy...');
    const tokenized = await factory.deploy();

    await tokenized.waitForDeployment();
    const address = await tokenized.getAddress();
    console.log(`✓ YieldDonatingTokenizedStrategy deployed at: ${address}\n`);

    return address;
  } catch (error) {
    console.error('Failed to deploy YieldDonatingTokenizedStrategy');
    console.error('Error:', error);
    throw error;
  }
}

async function deployAaveStrategy(signer: ethers.Signer, tokenizedStrategyAddress: string): Promise<string> {
  const artifactPath = path.join(process.cwd(), '..', 'out', 'AaveV3YieldDonatingStrategy.sol', 'AaveV3YieldDonatingStrategy.json');

  const artifact = JSON.parse(await fs.readFile(artifactPath, 'utf-8'));
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, signer);

  console.log('2️⃣ Deploying AaveV3YieldDonatingStrategy...');
  const strategy = await factory.deploy(
    AAVE_POOL,           // _aavePool
    aUSDC,               // _aToken
    USDC,                // _asset
    'Aave V3 Yield Donating Strategy',  // _name
    MANAGEMENT,          // _management
    KEEPER,              // _keeper
    EMERGENCY_ADMIN,     // _emergencyAdmin
    DONATION_ADDRESS,    // _donationAddress (will be PaymentSplitter)
    true,                // _enableBurning
    tokenizedStrategyAddress  // _tokenizedStrategyAddress
  );

  await strategy.waitForDeployment();
  const address = await strategy.getAddress();
  console.log(`✓ AaveV3YieldDonatingStrategy deployed at: ${address}\n`);

  return address;
}

async function deployPaymentSplitterManager(signer: ethers.Signer, strategyAddress: string, registryAddress: string): Promise<string> {
  const artifactPath = path.join(process.cwd(), '..', 'out', 'WeeklyPaymentSplitterManager.sol', 'WeeklyPaymentSplitterManager.json');

  const artifact = JSON.parse(await fs.readFile(artifactPath, 'utf-8'));
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, signer);

  console.log('3️⃣ Deploying WeeklyPaymentSplitterManager...');
  const manager = await factory.deploy(
    strategyAddress,     // _strategy
    registryAddress,     // _contributorRegistry
    MANAGEMENT           // _owner
  );

  await manager.waitForDeployment();
  const address = await manager.getAddress();
  console.log(`✓ WeeklyPaymentSplitterManager deployed at: ${address}\n`);

  return address;
}

async function main() {
  const rpcUrl = process.env.ETH_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;
  const registryAddress = process.env.CONTRIBUTOR_REGISTRY_ADDRESS;

  if (!rpcUrl || !privateKey) {
    throw new Error('Missing ETH_RPC_URL or PRIVATE_KEY in .env');
  }

  if (!registryAddress) {
    throw new Error('Missing CONTRIBUTOR_REGISTRY_ADDRESS in .env. Deploy ContributorRegistry first!');
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);

  console.log('Deploying from:', signer.address);
  console.log('Registry Address:', registryAddress);
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════\n');

  try {
    // Deploy TokenizedStrategy
    const tokenizedStrategyAddress = await deployTokenizedStrategy(signer);

    // Deploy Aave Strategy
    const strategyAddress = await deployAaveStrategy(signer, tokenizedStrategyAddress);

    // Deploy PaymentSplitter Manager
    const managerAddress = await deployPaymentSplitterManager(signer, strategyAddress, registryAddress);

    // Output summary
    console.log('═══════════════════════════════════════════════════════════════\n');
    console.log('✓ All strategy contracts deployed successfully!\n');
    console.log('Add to .env:\n');
    console.log(`TOKENIZED_STRATEGY_ADDRESS=${tokenizedStrategyAddress}`);
    console.log(`STRATEGY_ADDRESS=${strategyAddress}`);
    console.log(`WEEKLY_PAYMENT_SPLITTER_MANAGER_ADDRESS=${managerAddress}`);
    console.log('');
    console.log('Update strategy donation address:');
    console.log(`  setDonationAddress(${managerAddress})`);

  } catch (error) {
    console.error('\n❌ Deployment failed:', error);
    process.exit(1);
  }
}

main();
