// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interface.sol";

/**
 * @title RiskModel
 * @dev Calculates premiums based on risk parameters
 */
contract RiskModel is IRiskModel, Ownable {
    // Risk types
    enum RiskType {
        SmartContractExploit,
        StablecoinDepeg,
        BridgeFailure,
        MarketVolatility
    }

    // Risk parameters for smart contract exploits
    struct ContractRiskParams {
        uint256 baseRate; // Base annual rate in bps (e.g. 500 = 5%)
        uint256 codeAgeMultiplier; // Multiplier based on code age (100 = no change)
        uint256 valueLockedMultiplier; // Multiplier based on TVL (100 = no change)
        uint256 auditBonus; // Discount for audited contracts in bps
        bool active; // Whether this contract can be insured
    }

    // Risk parameters for stablecoins
    struct StablecoinRiskParams {
        uint256 baseRate; // Base annual rate in bps
        uint256 collateralMultiplier; // Multiplier based on collateralization (100 = no change)
        uint256 marketCapMultiplier; // Multiplier based on market cap (100 = no change)
        uint256 volatilityMultiplier; // Multiplier based on historical volatility
        bool active; // Whether this stablecoin can be insured
    }

    // Risk parameters for bridges
    struct BridgeRiskParams {
        uint256 baseRate; // Base annual rate in bps
        uint256 securityMultiplier; // Multiplier based on security features
        uint256 ageMultiplier; // Multiplier based on bridge age
        uint256 tvlMultiplier; // Multiplier based on TVL
        bool active; // Whether this bridge can be insured
    }

    // Risk parameters for market volatility
    struct VolatilityRiskParams {
        uint256 baseRate; // Base annual rate in bps
        uint256 historicalVolatilityMultiplier; // Multiplier based on historical volatility
        uint256 marketCapMultiplier; // Multiplier based on market cap
        uint256 liquidityMultiplier; // Multiplier based on liquidity
        bool active; // Whether this token can be insured for volatility
    }

    // State variables
    mapping(address => ContractRiskParams) public contractRiskParams;
    mapping(address => StablecoinRiskParams) public stablecoinRiskParams;
    mapping(address => BridgeRiskParams) public bridgeRiskParams;
    mapping(address => VolatilityRiskParams) public volatilityRiskParams;

    // Global risk parameters
    uint256 public globalRiskMultiplier = 100; // 100 = 1x (no change)
    uint256 public durationMultiplier = 100; // 100 = 1x (no change)
    uint256 public coverageMultiplier = 100; // 100 = 1x (no change)

    IRiskDataCollector public riskDataCollector;

    // Events
    event ContractRiskParamsUpdated(address indexed contractAddress);
    event StablecoinRiskParamsUpdated(address indexed stablecoin);
    event BridgeRiskParamsUpdated(address indexed bridge);
    event VolatilityRiskParamsUpdated(address indexed token);
    event GlobalRiskParametersUpdated();
    event RiskDataCollectorUpdated(address indexed collector);

    /**
     * @dev Constructor
     * @param _riskDataCollector Address of the risk data collector
     */
    constructor(address _riskDataCollector) Ownable(msg.sender) {
        if (_riskDataCollector != address(0)) {
            riskDataCollector = IRiskDataCollector(_riskDataCollector);
        }
    }

    /**
     * @dev Sets the risk data collector
     * @param _riskDataCollector New risk data collector address
     */
    function setRiskDataCollector(
        address _riskDataCollector
    ) external onlyOwner {
        require(_riskDataCollector != address(0), "Invalid address");
        riskDataCollector = IRiskDataCollector(_riskDataCollector);
        emit RiskDataCollectorUpdated(_riskDataCollector);
    }

    /**
     * @dev Updates global risk parameters
     * @param _globalRiskMultiplier New global risk multiplier
     * @param _durationMultiplier New duration multiplier
     * @param _coverageMultiplier New coverage multiplier
     */
    function updateGlobalRiskParameters(
        uint256 _globalRiskMultiplier,
        uint256 _durationMultiplier,
        uint256 _coverageMultiplier
    ) external onlyOwner {
        globalRiskMultiplier = _globalRiskMultiplier;
        durationMultiplier = _durationMultiplier;
        coverageMultiplier = _coverageMultiplier;
        emit GlobalRiskParametersUpdated();
    }

    /**
     * @dev Updates smart contract risk parameters
     * @param _contract The contract address
     * @param _baseRate Base annual rate in bps
     * @param _codeAgeMultiplier Multiplier based on code age
     * @param _valueLockedMultiplier Multiplier based on TVL
     * @param _auditBonus Discount for audited contracts
     * @param _active Whether this contract can be insured
     */
    function updateContractRiskParams(
        address _contract,
        uint256 _baseRate,
        uint256 _codeAgeMultiplier,
        uint256 _valueLockedMultiplier,
        uint256 _auditBonus,
        bool _active
    ) external onlyOwner {
        contractRiskParams[_contract] = ContractRiskParams({
            baseRate: _baseRate,
            codeAgeMultiplier: _codeAgeMultiplier,
            valueLockedMultiplier: _valueLockedMultiplier,
            auditBonus: _auditBonus,
            active: _active
        });
        emit ContractRiskParamsUpdated(_contract);
    }

    /**
     * @dev Updates stablecoin risk parameters
     * @param _stablecoin The stablecoin address
     * @param _baseRate Base annual rate in bps
     * @param _collateralMultiplier Multiplier based on collateralization
     * @param _marketCapMultiplier Multiplier based on market cap
     * @param _volatilityMultiplier Multiplier based on historical volatility
     * @param _active Whether this stablecoin can be insured
     */
    function updateStablecoinRiskParams(
        address _stablecoin,
        uint256 _baseRate,
        uint256 _collateralMultiplier,
        uint256 _marketCapMultiplier,
        uint256 _volatilityMultiplier,
        bool _active
    ) external onlyOwner {
        stablecoinRiskParams[_stablecoin] = StablecoinRiskParams({
            baseRate: _baseRate,
            collateralMultiplier: _collateralMultiplier,
            marketCapMultiplier: _marketCapMultiplier,
            volatilityMultiplier: _volatilityMultiplier,
            active: _active
        });
        emit StablecoinRiskParamsUpdated(_stablecoin);
    }

    /**
     * @dev Updates bridge risk parameters
     * @param _bridge The bridge address
     * @param _baseRate Base annual rate in bps
     * @param _securityMultiplier Multiplier based on security features
     * @param _ageMultiplier Multiplier based on bridge age
     * @param _tvlMultiplier Multiplier based on TVL
     * @param _active Whether this bridge can be insured
     */
    function updateBridgeRiskParams(
        address _bridge,
        uint256 _baseRate,
        uint256 _securityMultiplier,
        uint256 _ageMultiplier,
        uint256 _tvlMultiplier,
        bool _active
    ) external onlyOwner {
        bridgeRiskParams[_bridge] = BridgeRiskParams({
            baseRate: _baseRate,
            securityMultiplier: _securityMultiplier,
            ageMultiplier: _ageMultiplier,
            tvlMultiplier: _tvlMultiplier,
            active: _active
        });
        emit BridgeRiskParamsUpdated(_bridge);
    }

    /**
     * @dev Updates volatility risk parameters
     * @param _token The token address
     * @param _baseRate Base annual rate in bps
     * @param _historicalVolatilityMultiplier Multiplier based on historical volatility
     * @param _marketCapMultiplier Multiplier based on market cap
     * @param _liquidityMultiplier Multiplier based on liquidity
     * @param _active Whether this token can be insured for volatility
     */
    function updateVolatilityRiskParams(
        address _token,
        uint256 _baseRate,
        uint256 _historicalVolatilityMultiplier,
        uint256 _marketCapMultiplier,
        uint256 _liquidityMultiplier,
        bool _active
    ) external onlyOwner {
        volatilityRiskParams[_token] = VolatilityRiskParams({
            baseRate: _baseRate,
            historicalVolatilityMultiplier: _historicalVolatilityMultiplier,
            marketCapMultiplier: _marketCapMultiplier,
            liquidityMultiplier: _liquidityMultiplier,
            active: _active
        });
        emit VolatilityRiskParamsUpdated(_token);
    }

    /**
     * @dev Calculates the premium for an insurance policy
     * @param _token The token to be insured
     * @param _amount Amount to insure
     * @param _duration Duration of the policy in seconds
     * @param _riskType Type of risk being insured
     * @param _insuredContract Address of the contract being insured (if applicable)
     * @return premium The calculated premium
     */
    function calculatePremium(
        address _token,
        uint256 _amount,
        uint256 _duration,
        uint8 _riskType,
        address _insuredContract
    ) external view override returns (uint256) {
        // Convert duration from seconds to years (for annual rate calculation)
        uint256 durationInYears = (_duration * 1e18) / 365 days;

        uint256 baseRateAnnual;
        uint256 finalRateMultiplier = 100; // Start with 1x multiplier

        if (_riskType == uint8(RiskType.SmartContractExploit)) {
            // Verify the contract is active for insurance
            require(
                contractRiskParams[_insuredContract].active,
                "Contract not insurable"
            );

            baseRateAnnual = contractRiskParams[_insuredContract].baseRate;

            // Apply specific multipliers for smart contract risk
            finalRateMultiplier =
                (finalRateMultiplier *
                    contractRiskParams[_insuredContract].codeAgeMultiplier *
                    contractRiskParams[_insuredContract]
                        .valueLockedMultiplier) /
                10000; // Divide by 100^2 since we're multiplying two percentages

            // Apply audit bonus (discount)
            if (contractRiskParams[_insuredContract].auditBonus > 0) {
                finalRateMultiplier =
                    (finalRateMultiplier *
                        (10000 -
                            contractRiskParams[_insuredContract].auditBonus)) /
                    10000;
            }
        } else if (_riskType == uint8(RiskType.StablecoinDepeg)) {
            // Verify the stablecoin is active for insurance
            require(
                stablecoinRiskParams[_token].active,
                "Stablecoin not insurable"
            );

            baseRateAnnual = stablecoinRiskParams[_token].baseRate;

            // Apply specific multipliers for stablecoin risk
            finalRateMultiplier =
                (finalRateMultiplier *
                    stablecoinRiskParams[_token].collateralMultiplier *
                    stablecoinRiskParams[_token].marketCapMultiplier *
                    stablecoinRiskParams[_token].volatilityMultiplier) /
                1000000; // Divide by 100^3 since we're multiplying three percentages
        } else if (_riskType == uint8(RiskType.BridgeFailure)) {
            // Verify the bridge is active for insurance
            require(
                bridgeRiskParams[_insuredContract].active,
                "Bridge not insurable"
            );

            baseRateAnnual = bridgeRiskParams[_insuredContract].baseRate;

            // Apply specific multipliers for bridge risk
            finalRateMultiplier =
                (finalRateMultiplier *
                    bridgeRiskParams[_insuredContract].securityMultiplier *
                    bridgeRiskParams[_insuredContract].ageMultiplier *
                    bridgeRiskParams[_insuredContract].tvlMultiplier) /
                1000000; // Divide by 100^3 since we're multiplying three percentages
        } else if (_riskType == uint8(RiskType.MarketVolatility)) {
            // Verify the token is active for volatility insurance
            require(
                volatilityRiskParams[_token].active,
                "Token not insurable for volatility"
            );

            baseRateAnnual = volatilityRiskParams[_token].baseRate;

            // Apply specific multipliers for volatility risk
            finalRateMultiplier =
                (finalRateMultiplier *
                    volatilityRiskParams[_token]
                        .historicalVolatilityMultiplier *
                    volatilityRiskParams[_token].marketCapMultiplier *
                    volatilityRiskParams[_token].liquidityMultiplier) /
                1000000; // Divide by 100^3 since we're multiplying three percentages
        } else {
            revert("Invalid risk type");
        }

        // Apply global risk multipliers
        finalRateMultiplier =
            (finalRateMultiplier * globalRiskMultiplier) /
            100;

        // Apply coverage amount multiplier (higher coverage = higher rate)
        uint256 coverageMultiplierApplied = 100;
        if (_amount >= 1000000 * 1e18) {
            // 1M tokens
            coverageMultiplierApplied = coverageMultiplier;
        } else if (_amount >= 100000 * 1e18) {
            // 100K tokens
            coverageMultiplierApplied = (coverageMultiplier + 100) / 2; // Average of multiplier and no change
        }

        finalRateMultiplier =
            (finalRateMultiplier * coverageMultiplierApplied) /
            100;

        // Apply duration multiplier (longer duration = slightly lower rate)
        uint256 durationMultiplierApplied = 100;
        if (_duration >= 180 days) {
            durationMultiplierApplied = durationMultiplier;
        } else if (_duration >= 30 days) {
            durationMultiplierApplied = (durationMultiplier + 100) / 2; // Average of multiplier and no change
        }

        finalRateMultiplier =
            (finalRateMultiplier * durationMultiplierApplied) /
            100;

        // Get additional risk data from the collector if available
        if (address(riskDataCollector) != address(0)) {
            uint256 dynamicRiskMultiplier = riskDataCollector.getRiskMultiplier(
                _token,
                _insuredContract,
                _riskType
            );

            if (dynamicRiskMultiplier > 0) {
                finalRateMultiplier =
                    (finalRateMultiplier * dynamicRiskMultiplier) /
                    100;
            }
        }

        // Calculate the final premium
        // Premium = Amount * Annual Rate * Duration (in years) * Final Rate Multiplier
        uint256 premium = (_amount *
            baseRateAnnual *
            durationInYears *
            finalRateMultiplier) / (10000 * 1e18);

        // Ensure minimum premium
        uint256 minimumPremium = _amount / 1000; // 0.1% of coverage amount as minimum
        return premium > minimumPremium ? premium : minimumPremium;
    }

    /**
     * @dev Checks if a specific insurance is available
     * @param _token The token to be insured
     * @param _riskType Type of risk
     * @param _insuredContract Address of contract (if applicable)
     * @return available Whether insurance is available
     */
    function isInsuranceAvailable(
        address _token,
        uint8 _riskType,
        address _insuredContract
    ) external view returns (bool) {
        if (_riskType == uint8(RiskType.SmartContractExploit)) {
            return contractRiskParams[_insuredContract].active;
        } else if (_riskType == uint8(RiskType.StablecoinDepeg)) {
            return stablecoinRiskParams[_token].active;
        } else if (_riskType == uint8(RiskType.BridgeFailure)) {
            return bridgeRiskParams[_insuredContract].active;
        } else if (_riskType == uint8(RiskType.MarketVolatility)) {
            return volatilityRiskParams[_token].active;
        }

        return false;
    }

    /**
     * @dev Gets default risk parameters for a new contract if no custom params exist
     * @param _riskType The type of risk
     * @return baseRate The default base rate
     */
    function getDefaultRiskParams(
        uint8 _riskType
    ) external pure returns (uint256) {
        if (_riskType == uint8(RiskType.SmartContractExploit)) {
            return 1000; // 10% annual base rate
        } else if (_riskType == uint8(RiskType.StablecoinDepeg)) {
            return 500; // 5% annual base rate
        } else if (_riskType == uint8(RiskType.BridgeFailure)) {
            return 1500; // 15% annual base rate
        } else if (_riskType == uint8(RiskType.MarketVolatility)) {
            return 2000; // 20% annual base rate
        }

        return 1000; // Default 10%
    }
}
