import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

const AAVE_POOL = '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2';
const aUSDC = '0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';

// ABI for AaveV3YieldDonatingStrategy constructor
const STRATEGY_ABI = [
  'constructor(address,address,address,string,address,address,address,address,bool,address)'
];

async function main() {
  const rpcUrl = process.env.ETH_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;

  if (!rpcUrl || !privateKey) {
    throw new Error('Missing ETH_RPC_URL or PRIVATE_KEY in .env');
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);

  console.log('Deploying from:', signer.address);

  // Read the contract bytecode
  const fs = await import('fs/promises');
  const path = await import('path');

  // Get contract bytecode from artifacts
  const artifactPath = path.join(process.cwd(), '..', 'out', 'AaveV3YieldDonatingStrategy.sol', 'AaveV3YieldDonatingStrategy.json');
  
  try {
    const artifact = JSON.parse(await fs.readFile(artifactPath, 'utf-8'));
    const bytecode = artifact.bytecode.object;

    const factory = new ethers.ContractFactory(artifact.abi, bytecode, signer);

    console.log('\nDeploying AaveV3YieldDonatingStrategy...');
    const strategy = await factory.deploy(
      AAVE_POOL,
      aUSDC,
      USDC,
      'Aave V3 Yield Donating Strategy',
      '0xFDb60A0e05539aA30acba38813cF6123B8780b04', // management
      '0xFDb60A0e05539aA30acba38813cF6123B8780b04', // keeper
      '0xFDb60A0e05539aA30acba38813cF6123B8780b04', // emergencyAdmin
      '0xFDb60A0e05539aA30acba38813cF6123B8780b04', // donationAddress
      true, // enableBurning
      '0x0000000000000000000000000000000000000000' // tokenizedStrategyAddress (placeholder)
    );

    await strategy.waitForDeployment();
    const strategyAddress = await strategy.getAddress();

    console.log(`\n✓ Strategy deployed at: ${strategyAddress}`);
    console.log(`\nAdd to .env:\nSTRATEGY_ADDRESS=${strategyAddress}`);

  } catch (error) {
    console.error('Deployment failed:', error);
    process.exit(1);
  }
}

main();
