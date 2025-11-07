// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {
    AaveV3YieldDonatingStrategy as AaveStrategy,
    ERC20
} from "../../strategies/yieldDonating/AaveV3YieldDonatingStrategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {IAToken} from "../../interfaces/Aave/IAToken.sol";
import {IPool} from "../../interfaces/Aave/IPool.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract AaveV3YieldDonatingSetup is Test, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    AaveStrategy public aaveStrategy;

    // Aave-specific contracts
    IPool public aavePool;
    IAToken public aToken;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter = address(3); // This is the donation address
    address public emergencyAdmin = address(5);

    // YieldDonating specific variables
    bool public enableBurning = true;
    address public tokenizedStrategyAddress;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1,000,000 of the asset
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // Mainnet Aave v3 addresses (can be overridden per network)
    address public constant AAVE_V3_POOL_MAINNET = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    // USDC addresses on mainnet
    address public constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AUSDC_MAINNET = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    function setUp() public virtual {
        // Fork mainnet for testing with real Aave contracts
        // You can override this in specific tests for other networksc
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string("https://rpc.ankr.com/eth"));
        // vm.createSelectFork(rpcUrl);
        // Pinning to a specific block ensures consistent test results

        // Block 21100000 is from November 2024, known to have working Aave v3 state

        // string memory rpcUrl = vm.envOr("ETH_RPC_URL", string("https://rpc.ankr.com/eth"));

        vm.createSelectFork(rpcUrl, 21100000);

        // Use USDC and Aave v3 on mainnet by default
        asset = ERC20(USDC_MAINNET);
        aavePool = IPool(AAVE_V3_POOL_MAINNET);
        aToken = IAToken(AUSDC_MAINNET);

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Deploy YieldDonatingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());
        aaveStrategy = AaveStrategy(address(strategy));

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(address(aavePool), "aavePool");
        vm.label(address(aToken), "aToken");
        vm.label(user, "user");
    }

    function setUpStrategy() public returns (address) {
        // Deploy the Aave v3 YieldDonating strategy
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new AaveStrategy(
                    address(aavePool),
                    address(aToken),
                    address(asset),
                    "Aave v3 USDC YieldDonating Strategy",
                    management,
                    keeper,
                    emergencyAdmin,
                    dragonRouter,
                    enableBurning,
                    tokenizedStrategyAddress
                )
            )
        );

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount, true);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        // Call using low-level call since setEnableBurning may not be in all interfaces
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", _enableBurning));
        require(success, "setEnableBurning failed");
    }

    /**
     * @notice Helper function to simulate yield generation in Aave
     * @dev This simulates time passing and interest accruing
     */
    function simulateYield() public {
        // Skip forward in time to allow interest to accrue
        skip(30 days);

        // Roll forward blocks as well
        vm.roll(block.number + 216000); // ~30 days of blocks at 12s per block
    }

    /**
     * @notice Helper to get the current aToken balance of the strategy
     */
    function strategyATokenBalance() public view returns (uint256) {
        return aToken.balanceOf(address(strategy));
    }
}
