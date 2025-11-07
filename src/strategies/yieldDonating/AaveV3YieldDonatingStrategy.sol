// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {YieldDonatingStrategy} from "./YieldDonatingStrategy.sol";
import {IPool} from "../../interfaces/Aave/IPool.sol";
import {IAToken} from "../../interfaces/Aave/IAToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AaveV3 YieldDonating Strategy
 * @author Octant
 * @notice Strategy that supplies assets to Aave v3 and donates all yield to the dragonRouter
 * @dev This strategy deposits assets into Aave v3's lending pool to earn yield,
 *      and automatically mints all profits as shares to the donation address.
 */
contract AaveV3YieldDonatingStrategy is YieldDonatingStrategy {
    using SafeERC20 for ERC20;

    /// @notice The aToken received when supplying to Aave
    IAToken public immutable aToken;

    /**
     * @param _aavePool Address of the Aave v3 Pool contract
     * @param _aToken Address of the aToken for the underlying asset
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _aavePool,
        address _aToken,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        YieldDonatingStrategy(
            _aavePool, // yieldSource
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        require(_aToken != address(0), "Invalid aToken address");
        aToken = IAToken(_aToken);

        // Verify that the aToken matches the pool and asset
        require(aToken.UNDERLYING_ASSET_ADDRESS() == _asset, "aToken asset mismatch");
        require(aToken.POOL() == _aavePool, "aToken pool mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                         STRATEGY IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deploys funds to Aave v3 by supplying the underlying asset
     * @param _amount The amount of 'asset' to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        // Supply assets to Aave pool
        // The pool will mint aTokens 1:1 to this contract
        // Ensure sufficient allowance (safeguard in case of any approval issues)

        uint256 currentAllowance = ERC20(asset).allowance(address(this), address(yieldSource));

        if (currentAllowance < _amount) {
            ERC20(asset).forceApprove(address(yieldSource), type(uint256).max);
        }
        IPool(address(yieldSource)).supply(address(asset), _amount, address(this), 0);
    }

    /**
     * @dev Withdraws funds from Aave v3
     * @param _amount The amount of 'asset' to free
     */
    function _freeFunds(uint256 _amount) internal override {
        // Withdraw assets from Aave pool
        // This will burn aTokens and return the underlying asset
        IPool(address(yieldSource)).withdraw(address(asset), _amount, address(this));
    }

    /**
     * @dev Returns the total assets managed by the strategy
     * @return _totalAssets The total amount of underlying asset controlled by the strategy
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // aTokens are rebasing - their balance increases as interest accrues
        // The aToken balance represents our claim on the underlying asset
        uint256 aTokenBalance = aToken.balanceOf(address(this));

        // Add any loose assets held by the strategy (not deployed)
        uint256 looseAssets = ERC20(asset).balanceOf(address(this));

        // Total assets = aToken balance + loose assets
        _totalAssets = aTokenBalance + looseAssets;
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emergency withdraw function to pull funds from Aave in case of shutdown
     * @param _amount The amount of asset to attempt to free
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        // Get current aToken balance
        uint256 aTokenBalance = aToken.balanceOf(address(this));

        // Only withdraw what we have
        uint256 amountToWithdraw = _amount > aTokenBalance ? aTokenBalance : _amount;

        if (amountToWithdraw > 0) {
            IPool(address(yieldSource)).withdraw(address(asset), amountToWithdraw, address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current balance of aTokens held by the strategy
     * @return The aToken balance
     */
    function balanceOfAToken() external view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the estimated APR from the Aave pool
     * @dev This would need to be implemented by querying Aave's data provider
     * @return The estimated APR (could be implemented in a separate oracle)
     */
    function estimatedAPR() external view virtual returns (uint256) {
        // This is a placeholder - actual implementation would query
        // Aave's PoolDataProvider for the current supply APR
        return 0;
    }
}
