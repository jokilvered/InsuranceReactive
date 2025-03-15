// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRiskDataCollector.sol";

/**
 * @title RiskDataCollector
 * @dev Collects on-chain risk data for premium calculations
 */
contract RiskDataCollector is IRiskDataCollector, Ownable {
    // Risk types
    enum RiskType {
        SmartContractExploit,
        StablecoinDepeg,
        BridgeFailure,
        MarketVolatility
    }

    // State variables
    mapping(address => mapping(uint8 => uint256)) private contractRiskScores;
    mapping(address => uint256) private tokenVolatilityScores;

    // Authorized data providers
    mapping(address => bool) public authorizedProviders;

    // Events
    event RiskScoreUpdated(
        address indexed target,
        uint8 indexed riskType,
        uint256 score
    );
    event ProviderStatusUpdated(address indexed provider, bool authorized);

    /**
     * @dev Modifier to restrict access to authorized providers
     */
    modifier onlyAuthorizedProvider() {
        require(authorizedProviders[msg.sender], "Not authorized provider");
        _;
    }

    /**
     * @dev Sets the authorization status for a data provider
     * @param provider The address of the provider
     * @param authorized Whether the provider is authorized
     */
    function setProviderStatus(
        address provider,
        bool authorized
    ) external onlyOwner {
        authorizedProviders[provider] = authorized;
        emit ProviderStatusUpdated(provider, authorized);
    }

    /**
     * @dev Updates the risk score for a contract or token
     * @param target The target contract or token address
     * @param riskType The type of risk
     * @param score The new risk score (100 = baseline)
     */
    function updateRiskScore(
        address target,
        uint8 riskType,
        uint256 score
    ) external onlyAuthorizedProvider {
        require(score > 0, "Score must be positive");

        if (riskType == uint8(RiskType.MarketVolatility)) {
            tokenVolatilityScores[target] = score;
        } else {
            contractRiskScores[target][riskType] = score;
        }

        emit RiskScoreUpdated(target, riskType, score);
    }

    /**
     * @dev Gets the risk multiplier for premium calculation
     * @param token The token address
     * @param insuredContract The contract address (if applicable)
     * @param riskType The type of risk
     * @return multiplier The risk multiplier (100 = baseline)
     */
    function getRiskMultiplier(
        address token,
        address insuredContract,
        uint8 riskType
    ) external view override returns (uint256) {
        if (riskType == uint8(RiskType.SmartContractExploit)) {
            uint256 score = contractRiskScores[insuredContract][riskType];
            return score > 0 ? score : 100;
        } else if (riskType == uint8(RiskType.StablecoinDepeg)) {
            uint256 score = contractRiskScores[token][riskType];
            return score > 0 ? score : 100;
        } else if (riskType == uint8(RiskType.BridgeFailure)) {
            uint256 score = contractRiskScores[insuredContract][riskType];
            return score > 0 ? score : 100;
        } else if (riskType == uint8(RiskType.MarketVolatility)) {
            uint256 score = tokenVolatilityScores[token];
            return score > 0 ? score : 100;
        }

        return 100; // Default - no change to base premium
    }

    /**
     * @dev Batch updates multiple risk scores
     * @param targets Array of target addresses
     * @param riskTypes Array of risk types
     * @param scores Array of risk scores
     */
    function batchUpdateRiskScores(
        address[] calldata targets,
        uint8[] calldata riskTypes,
        uint256[] calldata scores
    ) external onlyAuthorizedProvider {
        require(
            targets.length == riskTypes.length &&
                targets.length == scores.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            require(scores[i] > 0, "Score must be positive");

            if (riskTypes[i] == uint8(RiskType.MarketVolatility)) {
                tokenVolatilityScores[targets[i]] = scores[i];
            } else {
                contractRiskScores[targets[i]][riskTypes[i]] = scores[i];
            }

            emit RiskScoreUpdated(targets[i], riskTypes[i], scores[i]);
        }
    }
}
