import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

const OWNER = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';

async function deployNFT(signer: ethers.Signer): Promise<string> {
  const nftArtifactPath = path.join(process.cwd(), '..', 'out', 'EcosystemLeadNFT.sol', 'EcosystemLeadNFT.json');

  const nftArtifact = JSON.parse(await fs.readFile(nftArtifactPath, 'utf-8'));
  const nftFactory = new ethers.ContractFactory(nftArtifact.abi, nftArtifact.bytecode.object, signer);

  console.log('Deploying EcosystemLeadNFT...');
  const nft = await nftFactory.deploy(
    OWNER,
    'ipfs://QmBaseURI/'  // Base URI for token metadata
  );

  await nft.waitForDeployment();
  const nftAddress = await nft.getAddress();
  console.log(`✓ EcosystemLeadNFT deployed at: ${nftAddress}`);

  return nftAddress;
}

async function deployVoting(signer: ethers.Signer, nftAddress: string): Promise<string> {
  const votingArtifactPath = path.join(process.cwd(), '..', 'out', 'EcosystemLeadVoting.sol', 'EcosystemLeadVoting.json');

  const votingArtifact = JSON.parse(await fs.readFile(votingArtifactPath, 'utf-8'));
  const votingFactory = new ethers.ContractFactory(votingArtifact.abi, votingArtifact.bytecode.object, signer);

  console.log('Deploying EcosystemLeadVoting...');
  const voting = await votingFactory.deploy(nftAddress);

  await voting.waitForDeployment();
  const votingAddress = await voting.getAddress();
  console.log(`✓ EcosystemLeadVoting deployed at: ${votingAddress}`);

  return votingAddress;
}

async function deployGovernanceExecutor(signer: ethers.Signer, votingAddress: string): Promise<string> {
  const executorArtifactPath = path.join(process.cwd(), '..', 'out', 'EcosystemGovernanceExecutor.sol', 'EcosystemGovernanceExecutor.json');

  const executorArtifact = JSON.parse(await fs.readFile(executorArtifactPath, 'utf-8'));
  const executorFactory = new ethers.ContractFactory(executorArtifact.abi, executorArtifact.bytecode.object, signer);

  console.log('Deploying EcosystemGovernanceExecutor...');
  const executor = await executorFactory.deploy(votingAddress, OWNER);

  await executor.waitForDeployment();
  const executorAddress = await executor.getAddress();
  console.log(`✓ EcosystemGovernanceExecutor deployed at: ${executorAddress}`);

  return executorAddress;
}

async function main() {
  const rpcUrl = process.env.ETH_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;

  if (!rpcUrl || !privateKey) {
    throw new Error('Missing ETH_RPC_URL or PRIVATE_KEY in .env');
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);

  console.log('Deploying from:', signer.address);
  console.log('');

  try {
    const nftAddress = await deployNFT(signer);
    console.log('');

    const votingAddress = await deployVoting(signer, nftAddress);
    console.log('');

    const executorAddress = await deployGovernanceExecutor(signer, votingAddress);
    console.log('');

    console.log('\n✓ All governance contracts deployed!');
    console.log('\nAdd to .env:');
    console.log(`ECOSYSTEM_LEAD_NFT_ADDRESS=${nftAddress}`);
    console.log(`ECOSYSTEM_LEAD_VOTING_ADDRESS=${votingAddress}`);
    console.log(`ECOSYSTEM_GOVERNANCE_EXECUTOR_ADDRESS=${executorAddress}`);

  } catch (error) {
    console.error('Deployment failed:', error);
    process.exit(1);
  }
}

main();
