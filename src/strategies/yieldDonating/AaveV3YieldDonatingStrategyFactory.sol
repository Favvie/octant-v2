// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AaveV3YieldDonatingStrategy} from "./AaveV3YieldDonatingStrategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import {IAToken} from "../../interfaces/Aave/IAToken.sol";

/**
 * @title AaveV3 YieldDonating Strategy Factory
 * @author Octant
 * @notice Factory for deploying AaveV3YieldDonatingStrategy instances
 * @dev Specialized factory that handles the additional aToken parameter required for Aave v3 strategies
 */
contract AaveV3YieldDonatingStrategyFactory {
    event NewAaveV3Strategy(address indexed strategy, address indexed asset, address indexed aToken, address aavePool);

    address public immutable emergencyAdmin;
    address public immutable tokenizedStrategyAddress;

    address public management;
    address public donationAddress;
    address public keeper;
    bool public enableBurning = true;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    /**
     * @param _management Address with management role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _tokenizedStrategyAddress Address of the deployed YieldDonatingTokenizedStrategy
     */
    constructor(
        address _management,
        address _donationAddress,
        address _keeper,
        address _emergencyAdmin,
        address _tokenizedStrategyAddress
    ) {
        require(_tokenizedStrategyAddress != address(0), "Invalid tokenized strategy address");
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        tokenizedStrategyAddress = _tokenizedStrategyAddress;
    }

    /**
     * @notice Deploy a new AaveV3 YieldDonating Strategy.
     * @param _aavePool The address of the Aave v3 Pool contract
     * @param _aToken The address of the aToken for the underlying asset
     * @param _asset The underlying asset for the strategy to use
     * @param _name The name for the strategy
     * @return The address of the new strategy
     */
    function newAaveV3Strategy(
        address _aavePool,
        address _aToken,
        address _asset,
        string calldata _name
    ) external returns (address) {
        require(_aToken != address(0), "Invalid aToken address");
        require(_aavePool != address(0), "Invalid Aave pool address");
        require(_asset != address(0), "Invalid asset address");

        // Validate aToken configuration
        IAToken aToken = IAToken(_aToken);
        require(aToken.UNDERLYING_ASSET_ADDRESS() == _asset, "aToken asset mismatch");
        require(aToken.POOL() == _aavePool, "aToken pool mismatch");

        // Deploy new AaveV3YieldDonating strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new AaveV3YieldDonatingStrategy(
                    _aavePool,
                    _aToken,
                    _asset,
                    _name,
                    management,
                    keeper,
                    emergencyAdmin,
                    donationAddress,
                    enableBurning,
                    tokenizedStrategyAddress
                )
            )
        );

        emit NewAaveV3Strategy(address(_newStrategy), _asset, _aToken, _aavePool);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    /**
     * @notice Update management addresses
     * @param _management New management address
     * @param _donationAddress New donation address
     * @param _keeper New keeper address
     */
    function setAddresses(address _management, address _donationAddress, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
    }

    /**
     * @notice Toggle burning of losses from donation address
     * @param _enableBurning Whether to enable loss-protection burning
     */
    function setEnableBurning(bool _enableBurning) external {
        require(msg.sender == management, "!management");
        enableBurning = _enableBurning;
    }

    /**
     * @notice Check if a strategy was deployed by this factory
     * @param _strategy The strategy address to check
     * @return True if the strategy was deployed by this factory
     */
    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
