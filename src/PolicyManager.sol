// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IInsurancePool.sol";

/**
 * @title PolicyManager
 * @dev Manages insurance policies and claims for the protocol
 */
contract PolicyManager is Ownable, ReentrancyGuard {
    // Policy status enum
    enum PolicyStatus {
        Active,
        Expired,
        Claimed,
        Cancelled
    }

    // Risk types enum
    enum RiskType {
        SmartContractExploit,
        StablecoinDepeg,
        BridgeFailure,
        MarketVolatility
    }

    // Policy struct
    struct Policy {
        address policyholder;
        address insuredToken;
        uint256 coverAmount;
        uint256 premium;
        uint256 startTime;
        uint256 endTime;
        RiskType riskType;
        address insuredContract;
        PolicyStatus status;
        uint256 claimAmount;
        uint256 claimTime;
    }

    // State variables
    IInsurancePool public insurancePool;
    mapping(uint256 => Policy) public policies;
    uint256 public nextPolicyId;
    mapping(address => uint256[]) public policyholderPolicies;
    mapping(address => mapping(address => uint256[])) public contractPolicies; // insuredContract => insuredToken => policyIds

    // Claim processor addresses allowed to process claims
    mapping(address => bool) public authorizedClaimProcessors;

    // Events
    event PolicyCreated(
        uint256 indexed policyId,
        address indexed policyholder,
        address indexed insuredToken,
        uint256 coverAmount
    );
    event PolicyExpired(uint256 indexed policyId);
    event PolicyClaimed(uint256 indexed policyId, uint256 claimAmount);
    event PolicyCancelled(uint256 indexed policyId);
    event ClaimProcessorAuthorized(address indexed processor, bool authorized);

    // Modifiers
    modifier onlyInsurancePool() {
        require(
            msg.sender == address(insurancePool),
            "Only insurance pool can call"
        );
        _;
    }

    modifier onlyAuthorizedClaimProcessor() {
        require(
            authorizedClaimProcessors[msg.sender],
            "Not authorized claim processor"
        );
        _;
    }

    // Constructor
    constructor() {
        nextPolicyId = 1;
    }

    /**
     * @dev Sets the insurance pool address
     * @param _insurancePool Address of the insurance pool
     */
    function setInsurancePool(address _insurancePool) external onlyOwner {
        require(_insurancePool != address(0), "Invalid address");
        insurancePool = IInsurancePool(_insurancePool);
    }

    /**
     * @dev Authorizes or revokes a claim processor
     * @param _processor Address of the processor
     * @param _authorized Whether the processor is authorized
     */
    function setClaimProcessor(
        address _processor,
        bool _authorized
    ) external onlyOwner {
        require(_processor != address(0), "Invalid address");
        authorizedClaimProcessors[_processor] = _authorized;
        emit ClaimProcessorAuthorized(_processor, _authorized);
    }

    /**
     * @dev Creates a new insurance policy
     * @param _policyholder Address of the policyholder
     * @param _insuredToken Token being insured
     * @param _coverAmount Amount of coverage
     * @param _premium Premium paid for the policy
     * @param _startTime Start time of the policy
     * @param _endTime End time of the policy
     * @param _riskType Type of risk covered
     * @param _insuredContract Address of contract being insured (if applicable)
     * @return policyId ID of the created policy
     */
    function createPolicy(
        address _policyholder,
        address _insuredToken,
        uint256 _coverAmount,
        uint256 _premium,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _riskType,
        address _insuredContract
    ) external onlyInsurancePool returns (uint256 policyId) {
        require(_startTime < _endTime, "Invalid time range");
        require(
            _riskType <= uint8(RiskType.MarketVolatility),
            "Invalid risk type"
        );

        policyId = nextPolicyId++;

        policies[policyId] = Policy({
            policyholder: _policyholder,
            insuredToken: _insuredToken,
            coverAmount: _coverAmount,
            premium: _premium,
            startTime: _startTime,
            endTime: _endTime,
            riskType: RiskType(_riskType),
            insuredContract: _insuredContract,
            status: PolicyStatus.Active,
            claimAmount: 0,
            claimTime: 0
        });

        // Add to policyholder's policies
        policyholderPolicies[_policyholder].push(policyId);

        // Add to contract policies if applicable
        if (_insuredContract != address(0)) {
            contractPolicies[_insuredContract][_insuredToken].push(policyId);
        }

        emit PolicyCreated(
            policyId,
            _policyholder,
            _insuredToken,
            _coverAmount
        );

        return policyId;
    }

    /**
     * @dev Processes an insurance claim
     * @param _policyId ID of the policy
     * @param _claimAmount Amount to claim
     * @param _claimEvidence Extra data proving claim validity
     */
    function processClaim(
        uint256 _policyId,
        uint256 _claimAmount,
        bytes calldata _claimEvidence
    ) external onlyAuthorizedClaimProcessor nonReentrant {
        Policy storage policy = policies[_policyId];

        // Validate the policy is active
        require(policy.status == PolicyStatus.Active, "Policy not active");
        require(
            block.timestamp >= policy.startTime &&
                block.timestamp <= policy.endTime,
            "Policy not in valid timeframe"
        );
        require(
            _claimAmount > 0 && _claimAmount <= policy.coverAmount,
            "Invalid claim amount"
        );

        // Validate claim evidence - in production, this would perform specific validation based on risk type
        // For demo purposes, we're just checking that something was provided
        require(_claimEvidence.length > 0, "No claim evidence provided");

        // Update policy status
        policy.status = PolicyStatus.Claimed;
        policy.claimAmount = _claimAmount;
        policy.claimTime = block.timestamp;

        // Process the claim payout
        insurancePool.processClaim(
            policy.insuredToken,
            policy.policyholder,
            _claimAmount
        );

        // Release remaining capital if partial claim
        if (_claimAmount < policy.coverAmount) {
            insurancePool.releaseCapital(
                policy.insuredToken,
                policy.coverAmount - _claimAmount
            );
        }

        emit PolicyClaimed(_policyId, _claimAmount);
    }

    /**
     * @dev Processes claims for policies covering a specific contract
     * @param _insuredContract The contract that experienced an insured event
     * @param _insuredToken The token involved in the insured event
     * @param _claimEvidence Evidence proving the claim
     */
    function processContractClaims(
        address _insuredContract,
        address _insuredToken,
        bytes calldata _claimEvidence
    ) external onlyAuthorizedClaimProcessor nonReentrant {
        uint256[] storage policyIds = contractPolicies[_insuredContract][
            _insuredToken
        ];
        require(policyIds.length > 0, "No policies for this contract/token");

        // Process claims for all eligible policies
        for (uint256 i = 0; i < policyIds.length; i++) {
            uint256 policyId = policyIds[i];
            Policy storage policy = policies[policyId];

            // Skip if already claimed or not active
            if (policy.status != PolicyStatus.Active) {
                continue;
            }

            // Check if policy is in valid timeframe
            if (
                block.timestamp < policy.startTime ||
                block.timestamp > policy.endTime
            ) {
                continue;
            }

            // Update policy status
            policy.status = PolicyStatus.Claimed;
            policy.claimAmount = policy.coverAmount;
            policy.claimTime = block.timestamp;

            // Process the claim payout
            insurancePool.processClaim(
                policy.insuredToken,
                policy.policyholder,
                policy.coverAmount
            );

            emit PolicyClaimed(policyId, policy.coverAmount);
        }
    }

    /**
     * @dev Expires policies that have reached their end time
     * @param _policyIds Array of policy IDs to check for expiration
     */
    function expirePolicies(uint256[] calldata _policyIds) external {
        for (uint256 i = 0; i < _policyIds.length; i++) {
            uint256 policyId = _policyIds[i];
            Policy storage policy = policies[policyId];

            // Skip if not active
            if (policy.status != PolicyStatus.Active) {
                continue;
            }

            // Check if expired
            if (block.timestamp > policy.endTime) {
                policy.status = PolicyStatus.Expired;

                // Release allocated capital
                insurancePool.releaseCapital(
                    policy.insuredToken,
                    policy.coverAmount
                );

                emit PolicyExpired(policyId);
            }
        }
    }

    /**
     * @dev Cancels a policy (only callable by policy holder)
     * @param _policyId ID of the policy to cancel
     */
    function cancelPolicy(uint256 _policyId) external nonReentrant {
        Policy storage policy = policies[_policyId];

        require(policy.policyholder == msg.sender, "Not policy holder");
        require(policy.status == PolicyStatus.Active, "Policy not active");

        policy.status = PolicyStatus.Cancelled;

        // Calculate refund amount based on time elapsed
        uint256 totalDuration = policy.endTime - policy.startTime;
        uint256 elapsed = block.timestamp - policy.startTime;
        uint256 refundRatio = 0;

        if (elapsed < totalDuration) {
            refundRatio = ((totalDuration - elapsed) * 7000) / totalDuration; // 70% of remaining time
        }

        uint256 refundAmount = (policy.premium * refundRatio) / 10000;

        // Release allocated capital
        insurancePool.releaseCapital(policy.insuredToken, policy.coverAmount);

        // Process refund if applicable
        if (refundAmount > 0) {
            // In a real implementation, we would transfer the refund here
            // For this demo, we'll just emit the event
        }

        emit PolicyCancelled(_policyId);
    }

    /**
     * @dev Gets policies for a specific policyholder
     * @param _policyholder Address of the policyholder
     * @return policyIds Array of policy IDs
     */
    function getPoliciesForPolicyholder(
        address _policyholder
    ) external view returns (uint256[] memory) {
        return policyholderPolicies[_policyholder];
    }

    /**
     * @dev Gets policies for a specific insured contract
     * @param _insuredContract Address of the insured contract
     * @param _insuredToken Token being insured
     * @return policyIds Array of policy IDs
     */
    function getPoliciesForContract(
        address _insuredContract,
        address _insuredToken
    ) external view returns (uint256[] memory) {
        return contractPolicies[_insuredContract][_insuredToken];
    }

    /**
     * @dev Checks if a policy is active
     * @param _policyId ID of the policy
     * @return isActive Whether the policy is active
     */
    function isPolicyActive(uint256 _policyId) external view returns (bool) {
        Policy storage policy = policies[_policyId];
        return
            policy.status == PolicyStatus.Active &&
            block.timestamp >= policy.startTime &&
            block.timestamp <= policy.endTime;
    }
}
