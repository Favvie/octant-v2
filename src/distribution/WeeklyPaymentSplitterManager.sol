// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Octant imports
import {PaymentSplitterFactory} from "@octant-core/factories/PaymentSplitterFactory.sol";
import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

/**
 * @title WeeklyPaymentSplitterManager
 * @notice Manages weekly yield distribution using Octant's PaymentSplitter infrastructure
 * @dev Integrates with Octant's YieldDonatingStrategy and PaymentSplitterFactory
 *
 * Key Features:
 * - Deploys a new PaymentSplitter each week via Octant's factory
 * - Redeems dragonRouter's strategy shares automatically
 * - Distributes yield to active GitHub contributors
 * - Tracks historical distributions per week
 *
 * Octant Integration:
 * - Uses PaymentSplitterFactory for gas-efficient deployments
 * - Integrates with YieldDonatingStrategy's dragonRouter
 * - Leverages Octant's battle-tested PaymentSplitter contract
 */
contract WeeklyPaymentSplitterManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct WeeklyDistribution {
        uint256 weekNumber; // ISO week number
        address paymentSplitter; // Address of deployed PaymentSplitter
        uint256 totalAmount; // Total yield distributed this week
        uint256 contributorCount; // Number of contributors
        uint256 timestamp; // When distribution was created
        bool active; // Whether distribution is active
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Octant's PaymentSplitterFactory
    PaymentSplitterFactory public immutable factory;

    /// @notice Octant's YieldDonatingStrategy
    IStrategyInterface public strategy;

    /// @notice DragonRouter address (receives profit shares from strategy)
    address public dragonRouter;

    /// @notice Underlying asset (USDC, DAI, etc.)
    IERC20 public asset;

    /// @notice Current week number
    uint256 public currentWeek;

    /// @notice Mapping of week number to distribution info
    mapping(uint256 => WeeklyDistribution) public distributions;

    /// @notice Array of all week numbers for enumeration
    uint256[] public weekNumbers;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event WeeklyDistributionCreated(
        uint256 indexed weekNumber,
        address indexed paymentSplitter,
        uint256 totalAmount,
        uint256 contributorCount,
        address[] contributors,
        string[] githubNames
    );

    event StrategySharesRedeemed(uint256 shares, uint256 assets);

    event DistributionCancelled(uint256 indexed weekNumber);

    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error WeekAlreadyExists();
    error WeekNotFound();
    error InvalidWeekNumber();
    error NoSharesToRedeem();
    error ArrayLengthMismatch();
    error DistributionNotActive();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the weekly distribution manager
     * @param _factory Octant's PaymentSplitterFactory address
     * @param _strategy Octant's YieldDonatingStrategy address
     * @param _dragonRouter DragonRouter address from strategy
     * @param _owner Contract owner
     */
    constructor(address _factory, address _strategy, address _dragonRouter, address _owner) Ownable(_owner) {
        require(_factory != address(0), "Invalid factory");
        require(_strategy != address(0), "Invalid strategy");
        require(_dragonRouter != address(0), "Invalid dragonRouter");

        factory = PaymentSplitterFactory(_factory);
        strategy = IStrategyInterface(_strategy);
        dragonRouter = _dragonRouter;
        asset = IERC20(strategy.asset());
    }

    /*//////////////////////////////////////////////////////////////
                        DISTRIBUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new weekly distribution
     * @dev Deploys a new PaymentSplitter via Octant's factory, redeems shares, and funds it
     *
     * @param weekNumber ISO week number (e.g., 45 for week 45 of 2024)
     * @param contributors Array of contributor addresses
     * @param githubNames Array of GitHub usernames (for tracking)
     * @param shares Array of share allocations
     * @return paymentSplitter Address of the deployed PaymentSplitter
     */
    function createWeeklyDistribution(
        uint256 weekNumber,
        address[] memory contributors,
        string[] memory githubNames,
        uint256[] memory shares
    ) external onlyOwner nonReentrant returns (address paymentSplitter) {
        // Validate inputs
        if (weekNumber == 0) revert InvalidWeekNumber();
        if (distributions[weekNumber].paymentSplitter != address(0)) revert WeekAlreadyExists();
        if (contributors.length != githubNames.length || contributors.length != shares.length) {
            revert ArrayLengthMismatch();
        }

        // Step 1: Redeem dragonRouter's strategy shares
        uint256 totalAmount = _redeemStrategyShares();

        // Step 2: Deploy new PaymentSplitter using Octant's factory
        paymentSplitter = factory.createPaymentSplitter(contributors, githubNames, shares);

        // Step 3: Transfer assets to the new PaymentSplitter
        asset.safeTransfer(paymentSplitter, totalAmount);

        // Step 4: Record distribution
        distributions[weekNumber] = WeeklyDistribution({
            weekNumber: weekNumber,
            paymentSplitter: paymentSplitter,
            totalAmount: totalAmount,
            contributorCount: contributors.length,
            timestamp: block.timestamp,
            active: true
        });

        weekNumbers.push(weekNumber);
        currentWeek = weekNumber;

        emit WeeklyDistributionCreated(weekNumber, paymentSplitter, totalAmount, contributors.length, contributors, githubNames);

        return paymentSplitter;
    }

    /**
     * @notice Cancel a weekly distribution (emergency only)
     * @param weekNumber Week to cancel
     */
    function cancelDistribution(uint256 weekNumber) external onlyOwner {
        WeeklyDistribution storage dist = distributions[weekNumber];
        if (dist.paymentSplitter == address(0)) revert WeekNotFound();
        if (!dist.active) revert DistributionNotActive();

        dist.active = false;
        emit DistributionCancelled(weekNumber);
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem dragonRouter's strategy shares for underlying assets
     * @dev Called internally before each distribution
     * @return assets Amount of assets received
     */
    function _redeemStrategyShares() internal returns (uint256 assets) {
        // Get dragonRouter's share balance
        uint256 shares = strategy.balanceOf(dragonRouter);
        if (shares == 0) revert NoSharesToRedeem();

        // Redeem shares for assets (requires dragonRouter approval)
        // The redeemed assets go to this contract
        assets = strategy.redeem(shares, address(this), dragonRouter);

        emit StrategySharesRedeemed(shares, assets);
        return assets;
    }

    /**
     * @notice Manually trigger share redemption (for testing or emergency)
     * @return assets Amount of assets received
     */
    function redeemShares() external onlyOwner returns (uint256 assets) {
        return _redeemStrategyShares();
    }

    /**
     * @notice Preview how many assets would be received from redeeming current shares
     * @return assets Estimated asset amount
     */
    function previewRedemption() external view returns (uint256 assets) {
        uint256 shares = strategy.balanceOf(dragonRouter);
        return strategy.convertToAssets(shares);
    }

    /**
     * @notice Update strategy address (if strategy is redeployed)
     * @param newStrategy New strategy address
     */
    function updateStrategy(address newStrategy) external onlyOwner {
        require(newStrategy != address(0), "Invalid strategy");

        address oldStrategy = address(strategy);
        strategy = IStrategyInterface(newStrategy);
        asset = IERC20(strategy.asset());

        emit StrategyUpdated(oldStrategy, newStrategy);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get distribution info for a specific week
     * @param weekNumber Week to query
     * @return distribution WeeklyDistribution struct
     */
    function getDistribution(uint256 weekNumber) external view returns (WeeklyDistribution memory) {
        return distributions[weekNumber];
    }

    /**
     * @notice Get PaymentSplitter address for a specific week
     * @param weekNumber Week to query
     * @return splitter PaymentSplitter address
     */
    function getPaymentSplitter(uint256 weekNumber) external view returns (address splitter) {
        return distributions[weekNumber].paymentSplitter;
    }

    /**
     * @notice Get total number of distributions created
     * @return count Number of weeks with distributions
     */
    function getDistributionCount() external view returns (uint256 count) {
        return weekNumbers.length;
    }

    /**
     * @notice Get all week numbers
     * @return Array of week numbers
     */
    function getAllWeeks() external view returns (uint256[] memory) {
        return weekNumbers;
    }

    /**
     * @notice Get current dragonRouter share balance in strategy
     * @return shares Share balance
     */
    function getDragonRouterShares() external view returns (uint256 shares) {
        return strategy.balanceOf(dragonRouter);
    }

    /**
     * @notice Get asset value of dragonRouter's shares
     * @return assets Asset value
     */
    function getDragonRouterAssetValue() external view returns (uint256 assets) {
        uint256 shares = strategy.balanceOf(dragonRouter);
        return strategy.convertToAssets(shares);
    }

    /**
     * @notice Check how much a contributor can claim from a specific week
     * @param weekNumber Week to query
     * @param contributor Contributor address
     * @return releasable Amount claimable
     */
    function getReleasable(uint256 weekNumber, address contributor) external view returns (uint256 releasable) {
        address splitter = distributions[weekNumber].paymentSplitter;
        if (splitter == address(0)) return 0;

        return PaymentSplitter(payable(splitter)).releasable(asset, contributor);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency withdraw accidentally sent tokens
     * @param token Token address
     * @param amount Amount to withdraw
     * @param to Recipient
     */
    function emergencyWithdraw(address token, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }
}