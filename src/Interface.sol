// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

// src/interfaces/IInsurancePool.sol
interface IInsurancePool {
    function releaseCapital(address _token, uint256 _amount) external;
    function processClaim(address _token, address _recipient, uint256 _amount) external;
}

// src/interfaces/IPolicyManager.sol
interface IPolicyManager {
    function createPolicy(
        address _policyholder,
        address _insuredToken,
        uint256 _coverAmount,
        uint256 _premium,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _riskType,
        address _insuredContract
    ) external returns (uint256);
    
    function processContractClaims(
        address _insuredContract,
        address _insuredToken,
        bytes calldata _claimEvidence
    ) external;
}

// src/interfaces/IRiskModel.sol
interface IRiskModel {
    function calculatePremium(
        address _token,
        uint256 _amount,
        uint256 _duration,
        uint8 _riskType,
        address _insuredContract
    ) external view returns (uint256);
}

// src/interfaces/IRiskDataCollector.sol
interface IRiskDataCollector {
    function getRiskMultiplier(
        address _token,
        address _insuredContract,
        uint8 _riskType
    ) external view returns (uint256);
}