import { Octokit } from '@octokit/rest';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

// Types
interface TrackedRepo {
  owner: string;
  repo: string;
  description: string;
}

interface ContributorScore {
  github: string;
  wallet: string | null;
  commits: number;
  prs: number;
  issues: number;
  reviews: number;
  totalScore: number;
  lastUpdated: string;
  eligible: boolean;
  repos: string[];
}

interface Config {
  trackedRepos: TrackedRepo[];
  scoring: {
    commitWeight: number;
    prWeight: number;
    issueWeight: number;
    reviewWeight: number;
  };
  timeFrame: {
    months: number;
    description: string;
  };
  minScore: number;
}

// Initialize Octokit with GitHub token
const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN,
});

// Load configuration
async function loadConfig(): Promise<Config> {
  const configPath = path.join(process.cwd(), 'config.json');
  const configData = await fs.readFile(configPath, 'utf-8');
  return JSON.parse(configData);
}

// Calculate date for time frame
function getStartDate(months: number): Date {
  const date = new Date();
  date.setMonth(date.getMonth() - months);
  return date;
}

// Fetch commits for a repository
async function fetchCommits(
  owner: string,
  repo: string,
  since: Date
): Promise<Map<string, number>> {
  console.log(`  📦 Fetching commits from ${owner}/${repo}...`);
  
  const commitCounts = new Map<string, number>();
  let page = 1;
  const perPage = 100;

  try {
    while (true) {
      const { data: commits } = await octokit.repos.listCommits({
        owner,
        repo,
        since: since.toISOString(),
        per_page: perPage,
        page,
      });

      if (commits.length === 0) break;

      for (const commit of commits) {
        const author = commit.author?.login;
        if (author) {
          commitCounts.set(author, (commitCounts.get(author) || 0) + 1);
        }
      }

      // Check if we have more pages
      if (commits.length < perPage) break;
      page++;
      
      // Rate limiting delay
      await sleep(100);
    }
  } catch (error: any) {
    console.error(`  ❌ Error fetching commits: ${error.message}`);
  }

  return commitCounts;
}

// Fetch pull requests for a repository
async function fetchPullRequests(
  owner: string,
  repo: string,
  since: Date
): Promise<Map<string, number>> {
  console.log(`  🔀 Fetching pull requests from ${owner}/${repo}...`);
  
  const prCounts = new Map<string, number>();
  let page = 1;
  const perPage = 100;

  try {
    while (true) {
      const { data: prs } = await octokit.pulls.list({
        owner,
        repo,
        state: 'all',
        sort: 'updated',
        direction: 'desc',
        per_page: perPage,
        page,
      });

      if (prs.length === 0) break;

      let foundOldPR = false;
      for (const pr of prs) {
        const updatedAt = new Date(pr.updated_at);
        if (updatedAt < since) {
          foundOldPR = true;
          break;
        }

        const author = pr.user?.login;
        if (author) {
          prCounts.set(author, (prCounts.get(author) || 0) + 1);
        }
      }

      if (foundOldPR || prs.length < perPage) break;
      page++;
      
      await sleep(100);
    }
  } catch (error: any) {
    console.error(`  ❌ Error fetching PRs: ${error.message}`);
  }

  return prCounts;
}

// Fetch issues for a repository
async function fetchIssues(
  owner: string,
  repo: string,
  since: Date
): Promise<Map<string, number>> {
  console.log(`  🐛 Fetching issues from ${owner}/${repo}...`);
  
  const issueCounts = new Map<string, number>();
  let page = 1;
  const perPage = 100;

  try {
    while (true) {
      const { data: issues } = await octokit.issues.listForRepo({
        owner,
        repo,
        state: 'all',
        sort: 'updated',
        direction: 'desc',
        since: since.toISOString(),
        per_page: perPage,
        page,
      });

      if (issues.length === 0) break;

      for (const issue of issues) {
        // Skip pull requests (they also appear in issues)
        if (issue.pull_request) continue;

        const author = issue.user?.login;
        if (author) {
          issueCounts.set(author, (issueCounts.get(author) || 0) + 1);
        }
      }

      if (issues.length < perPage) break;
      page++;
      
      await sleep(100);
    }
  } catch (error: any) {
    console.error(`  ❌ Error fetching issues: ${error.message}`);
  }

  return issueCounts;
}

// Fetch PR reviews for a repository
async function fetchReviews(
  owner: string,
  repo: string,
  since: Date
): Promise<Map<string, number>> {
  console.log(`  👀 Fetching reviews from ${owner}/${repo}...`);
  
  const reviewCounts = new Map<string, number>();
  let page = 1;
  const perPage = 100;

  try {
    // First get PRs
    const { data: prs } = await octokit.pulls.list({
      owner,
      repo,
      state: 'all',
      sort: 'updated',
      direction: 'desc',
      per_page: 30, // Limit to recent PRs for reviews
      page: 1,
    });

    for (const pr of prs) {
      const updatedAt = new Date(pr.updated_at);
      if (updatedAt < since) continue;

      try {
        const { data: reviews } = await octokit.pulls.listReviews({
          owner,
          repo,
          pull_number: pr.number,
        });

        for (const review of reviews) {
          const reviewer = review.user?.login;
          if (reviewer && new Date(review.submitted_at || '') >= since) {
            reviewCounts.set(reviewer, (reviewCounts.get(reviewer) || 0) + 1);
          }
        }
        
        await sleep(100);
      } catch (error: any) {
        // Skip if we can't fetch reviews for this PR
        continue;
      }
    }
  } catch (error: any) {
    console.error(`  ❌ Error fetching reviews: ${error.message}`);
  }

  return reviewCounts;
}

// Process a single repository
async function processRepository(
  repo: TrackedRepo,
  since: Date,
  scoring: Config['scoring']
): Promise<Map<string, Partial<ContributorScore>>> {
  console.log(`\n📊 Processing ${repo.owner}/${repo.repo}...`);
  
  const contributors = new Map<string, Partial<ContributorScore>>();

  // Fetch all contribution types
  const [commits, prs, issues, reviews] = await Promise.all([
    fetchCommits(repo.owner, repo.repo, since),
    fetchPullRequests(repo.owner, repo.repo, since),
    fetchIssues(repo.owner, repo.repo, since),
    fetchReviews(repo.owner, repo.repo, since),
  ]);

  // Combine all contributors
  const allContributors = new Set([
    ...commits.keys(),
    ...prs.keys(),
    ...issues.keys(),
    ...reviews.keys(),
  ]);

  for (const github of allContributors) {
    const commitCount = commits.get(github) || 0;
    const prCount = prs.get(github) || 0;
    const issueCount = issues.get(github) || 0;
    const reviewCount = reviews.get(github) || 0;

    const score =
      commitCount * scoring.commitWeight +
      prCount * scoring.prWeight +
      issueCount * scoring.issueWeight +
      reviewCount * scoring.reviewWeight;

    contributors.set(github, {
      github,
      commits: commitCount,
      prs: prCount,
      issues: issueCount,
      reviews: reviewCount,
      totalScore: score,
      repos: [`${repo.owner}/${repo.repo}`],
    });
  }

  console.log(`  ✅ Found ${contributors.size} contributors`);
  return contributors;
}

// Merge contributors from multiple repositories
function mergeContributors(
  allContributors: Map<string, Partial<ContributorScore>>[]
): Map<string, ContributorScore> {
  const merged = new Map<string, ContributorScore>();

  for (const repoContributors of allContributors) {
    for (const [github, data] of repoContributors) {
      const existing = merged.get(github);

      if (existing) {
        // Merge data
        existing.commits += data.commits || 0;
        existing.prs += data.prs || 0;
        existing.issues += data.issues || 0;
        existing.reviews += data.reviews || 0;
        existing.totalScore += data.totalScore || 0;
        existing.repos.push(...(data.repos || []));
      } else {
        // New contributor
        merged.set(github, {
          github,
          wallet: null,
          commits: data.commits || 0,
          prs: data.prs || 0,
          issues: data.issues || 0,
          reviews: data.reviews || 0,
          totalScore: data.totalScore || 0,
          lastUpdated: new Date().toISOString(),
          eligible: false,
          repos: data.repos || [],
        });
      }
    }
  }

  return merged;
}

// Load existing wallet mappings (if any)
async function loadWalletMappings(): Promise<Map<string, string>> {
  try {
    const mappingPath = path.join(process.cwd(), '../data/wallet-mappings.json');
    const data = await fs.readFile(mappingPath, 'utf-8');
    const mappings = JSON.parse(data);
    return new Map(Object.entries(mappings));
  } catch {
    return new Map();
  }
}

// Sleep utility
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Main function
async function main() {
  console.log('🚀 Starting GitHub Contributor Tracker\n');

  // Load configuration
  const config = await loadConfig();
  const since = getStartDate(config.timeFrame.months);
  
  console.log(`📅 Tracking contributions since: ${since.toISOString()}`);
  console.log(`📚 Tracking ${config.trackedRepos.length} repositories\n`);

  // Check for GitHub token
  if (!process.env.GITHUB_TOKEN) {
    console.error('❌ GITHUB_TOKEN not found in environment variables');
    console.log('\n💡 To create a GitHub token:');
    console.log('   1. Go to https://github.com/settings/tokens');
    console.log('   2. Generate a new token (classic)');
    console.log('   3. Select scopes: public_repo');
    console.log('   4. Add to .env file: GITHUB_TOKEN=your_token_here\n');
    process.exit(1);
  }

  // Load existing wallet mappings
  const walletMappings = await loadWalletMappings();
  console.log(`💰 Loaded ${walletMappings.size} existing wallet mappings\n`);

  // Process all repositories
  const allContributors: Map<string, Partial<ContributorScore>>[] = [];

  for (const repo of config.trackedRepos) {
    try {
      const contributors = await processRepository(repo, since, config.scoring);
      allContributors.push(contributors);
      await sleep(500); // Rate limiting between repos
    } catch (error: any) {
      console.error(`❌ Failed to process ${repo.owner}/${repo.repo}: ${error.message}`);
    }
  }

  // Merge all contributors
  console.log('\n🔄 Merging contributor data...');
  const mergedContributors = mergeContributors(allContributors);

  // Apply wallet mappings and eligibility
  for (const [github, data] of mergedContributors) {
    data.wallet = walletMappings.get(github) || null;
    data.eligible = data.totalScore >= config.minScore && data.wallet !== null;
  }

  // Sort by score
  const sortedContributors = Array.from(mergedContributors.values())
    .sort((a, b) => b.totalScore - a.totalScore);

  // Generate statistics
  const stats = {
    totalContributors: sortedContributors.length,
    eligibleContributors: sortedContributors.filter(c => c.eligible).length,
    contributorsWithWallet: sortedContributors.filter(c => c.wallet !== null).length,
    contributorsMeetingMinScore: sortedContributors.filter(c => c.totalScore >= config.minScore).length,
    totalCommits: sortedContributors.reduce((sum, c) => sum + c.commits, 0),
    totalPRs: sortedContributors.reduce((sum, c) => sum + c.prs, 0),
    totalIssues: sortedContributors.reduce((sum, c) => sum + c.issues, 0),
    totalReviews: sortedContributors.reduce((sum, c) => sum + c.reviews, 0),
    topContributors: sortedContributors.slice(0, 10).map(c => ({
      github: c.github,
      score: c.totalScore,
      eligible: c.eligible,
    })),
  };

  // Save results
  const outputPath = path.join(process.cwd(), '../data/contributors.json');
  const output = {
    lastUpdated: new Date().toISOString(),
    config: {
      timeFrame: config.timeFrame,
      minScore: config.minScore,
      trackedRepos: config.trackedRepos.length,
    },
    stats,
    contributors: sortedContributors,
  };

  await fs.writeFile(outputPath, JSON.stringify(output, null, 2));

  // Print summary
  console.log('\n✅ Tracking complete!');
  console.log('\n📊 STATISTICS:');
  console.log(`   Total Contributors: ${stats.totalContributors}`);
  console.log(`   Eligible Contributors: ${stats.eligibleContributors}`);
  console.log(`   Contributors with Wallet: ${stats.contributorsWithWallet}`);
  console.log(`   Meeting Min Score (${config.minScore}): ${stats.contributorsMeetingMinScore}`);
  console.log(`\n   Total Commits: ${stats.totalCommits}`);
  console.log(`   Total PRs: ${stats.totalPRs}`);
  console.log(`   Total Issues: ${stats.totalIssues}`);
  console.log(`   Total Reviews: ${stats.totalReviews}`);

  console.log('\n🏆 TOP 10 CONTRIBUTORS:');
  stats.topContributors.forEach((c, i) => {
    const badge = c.eligible ? '✅' : '❌';
    console.log(`   ${i + 1}. ${badge} ${c.github} - Score: ${c.score}`);
  });

  console.log(`\n💾 Results saved to: ${outputPath}`);
  console.log('\n💡 NEXT STEPS:');
  console.log('   1. Review the contributors list');
  console.log('   2. Add wallet mappings to data/wallet-mappings.json');
  console.log('   3. Run: npm run generate-merkle');
}

// Run the script
main().catch(console.error);