// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRiskModel.sol";
import "./interfaces/IPolicyManager.sol";

/**
 * @title InsurancePool
 * @dev Manages the capital pool for the insurance protocol and handles policy creation
 */
contract InsurancePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Structs
    struct PoolInfo {
        IERC20 token; // Token used for this pool
        uint256 totalCapital; // Total capital in the pool
        uint256 allocatedCapital; // Capital allocated to active policies
        uint256 minCapitalRatio; // Minimum ratio of total:allocated capital (in bps, e.g. 12000 = 120%)
        bool active; // Whether the pool is active for new policies
    }

    // State variables
    mapping(address => PoolInfo) public pools;
    address[] public supportedTokens;

    IRiskModel public riskModel;
    IPolicyManager public policyManager;

    uint256 public protocolFee; // Fee taken from premiums (in bps, e.g. 1000 = 10%)
    address public feeCollector;

    // Events
    event PoolAdded(address indexed token);
    event PoolUpdated(
        address indexed token,
        bool active,
        uint256 minCapitalRatio
    );
    event CapitalAdded(
        address indexed token,
        address indexed provider,
        uint256 amount
    );
    event CapitalRemoved(
        address indexed token,
        address indexed provider,
        uint256 amount
    );
    event PolicyPurchased(
        address indexed buyer,
        address indexed token,
        uint256 amount,
        uint256 premium,
        uint256 duration,
        uint256 policyId
    );
    event ProtocolFeeUpdated(uint256 newFee);
    event FeeCollectorUpdated(address indexed newCollector);

    // Constructor
    constructor(
        address _riskModel,
        address _policyManager,
        uint256 _protocolFee
    ) {
        riskModel = IRiskModel(_riskModel);
        policyManager = IPolicyManager(_policyManager);
        protocolFee = _protocolFee;
        feeCollector = msg.sender;
    }

    // External functions

    /**
     * @dev Adds a new token pool
     * @param _token The token to be added
     * @param _minCapitalRatio Minimum capital ratio in bps
     */
    function addPool(
        address _token,
        uint256 _minCapitalRatio
    ) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(
            pools[_token].token == IERC20(address(0)),
            "Pool already exists"
        );

        pools[_token] = PoolInfo({
            token: IERC20(_token),
            totalCapital: 0,
            allocatedCapital: 0,
            minCapitalRatio: _minCapitalRatio,
            active: true
        });

        supportedTokens.push(_token);
        emit PoolAdded(_token);
    }

    /**
     * @dev Updates pool parameters
     * @param _token The token pool to update
     * @param _active Whether the pool should be active
     * @param _minCapitalRatio New minimum capital ratio
     */
    function updatePool(
        address _token,
        bool _active,
        uint256 _minCapitalRatio
    ) external onlyOwner {
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );

        pools[_token].active = _active;
        pools[_token].minCapitalRatio = _minCapitalRatio;

        emit PoolUpdated(_token, _active, _minCapitalRatio);
    }

    /**
     * @dev Adds capital to the specified pool
     * @param _token The token pool to add capital to
     * @param _amount Amount of tokens to add
     */
    function addCapital(address _token, uint256 _amount) external nonReentrant {
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );
        require(_amount > 0, "Amount must be greater than zero");

        PoolInfo storage pool = pools[_token];

        // Transfer tokens from user to the pool
        pool.token.safeTransferFrom(msg.sender, address(this), _amount);

        // Update pool capital
        pool.totalCapital += _amount;

        emit CapitalAdded(_token, msg.sender, _amount);
    }

    /**
     * @dev Removes capital from the specified pool
     * @param _token The token pool to remove capital from
     * @param _amount Amount of tokens to remove
     */
    function removeCapital(
        address _token,
        uint256 _amount
    ) external nonReentrant {
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );
        require(_amount > 0, "Amount must be greater than zero");

        PoolInfo storage pool = pools[_token];

        // Check if there's enough free capital
        uint256 freeCapital = pool.totalCapital - pool.allocatedCapital;
        require(_amount <= freeCapital, "Insufficient free capital");

        // Check if this would violate the minimum capital ratio
        require(
            pool.allocatedCapital == 0 ||
                ((pool.totalCapital - _amount) * 10000) /
                    pool.allocatedCapital >=
                pool.minCapitalRatio,
            "Would violate minimum capital ratio"
        );

        // Update pool capital
        pool.totalCapital -= _amount;

        // Transfer tokens to user
        pool.token.safeTransfer(msg.sender, _amount);

        emit CapitalRemoved(_token, msg.sender, _amount);
    }

    /**
     * @dev Purchases an insurance policy
     * @param _token The token to be insured
     * @param _amount Amount to insure
     * @param _duration Duration of the policy in seconds
     * @param _riskType Type of risk being insured
     * @param _insuredContract Address of the contract being insured (if applicable)
     * @return policyId The ID of the created policy
     */
    function purchasePolicy(
        address _token,
        uint256 _amount,
        uint256 _duration,
        uint8 _riskType,
        address _insuredContract
    ) external nonReentrant returns (uint256 policyId) {
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );
        require(pools[_token].active, "Pool is not active");
        require(_amount > 0, "Amount must be greater than zero");
        require(_duration > 0, "Duration must be greater than zero");

        PoolInfo storage pool = pools[_token];

        // Calculate premium using risk model
        uint256 premium = riskModel.calculatePremium(
            _token,
            _amount,
            _duration,
            _riskType,
            _insuredContract
        );
        require(premium > 0, "Premium calculation failed");

        // Check if the pool has enough free capital
        require(
            pool.totalCapital - pool.allocatedCapital >= _amount,
            "Insufficient free capital in pool"
        );

        // Take premium payment
        pool.token.safeTransferFrom(msg.sender, address(this), premium);

        // Calculate and transfer protocol fee
        uint256 fee = (premium * protocolFee) / 10000;
        if (fee > 0) {
            pool.token.safeTransfer(feeCollector, fee);
        }

        // Update allocated capital
        pool.allocatedCapital += _amount;

        // Create policy in policy manager
        policyId = policyManager.createPolicy(
            msg.sender,
            _token,
            _amount,
            premium - fee,
            block.timestamp,
            block.timestamp + _duration,
            _riskType,
            _insuredContract
        );

        emit PolicyPurchased(
            msg.sender,
            _token,
            _amount,
            premium,
            _duration,
            policyId
        );

        return policyId;
    }

    /**
     * @dev Releases allocated capital when a policy expires or is claimed
     * @param _token The token of the policy
     * @param _amount Amount to release
     */
    function releaseCapital(address _token, uint256 _amount) external {
        require(
            msg.sender == address(policyManager),
            "Only policy manager can release capital"
        );
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );
        require(_amount > 0, "Amount must be greater than zero");

        PoolInfo storage pool = pools[_token];
        require(
            pool.allocatedCapital >= _amount,
            "Amount exceeds allocated capital"
        );

        pool.allocatedCapital -= _amount;
    }

    /**
     * @dev Processes a claim payout
     * @param _token The token to pay out
     * @param _recipient The recipient of the payout
     * @param _amount Amount to pay out
     */
    function processClaim(
        address _token,
        address _recipient,
        uint256 _amount
    ) external {
        require(
            msg.sender == address(policyManager),
            "Only policy manager can process claims"
        );
        require(
            pools[_token].token != IERC20(address(0)),
            "Pool does not exist"
        );
        require(_amount > 0, "Amount must be greater than zero");

        PoolInfo storage pool = pools[_token];
        require(pool.totalCapital >= _amount, "Insufficient capital in pool");

        // Update pool capital
        pool.totalCapital -= _amount;
        pool.allocatedCapital -= _amount;

        // Transfer tokens to the recipient
        pool.token.safeTransfer(_recipient, _amount);
    }

    /**
     * @dev Updates the protocol fee
     * @param _newFee New protocol fee in bps
     */
    function updateProtocolFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 3000, "Fee too high"); // Max 30%
        protocolFee = _newFee;
        emit ProtocolFeeUpdated(_newFee);
    }

    /**
     * @dev Updates the fee collector address
     * @param _newCollector New fee collector address
     */
    function updateFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != address(0), "Invalid address");
        feeCollector = _newCollector;
        emit FeeCollectorUpdated(_newCollector);
    }

    /**
     * @dev Gets the number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    /**
     * @dev Checks if a token is supported
     * @param _token The token to check
     */
    function isTokenSupported(address _token) external view returns (bool) {
        return address(pools[_token].token) != address(0);
    }

    /**
     * @dev Gets the free capital available in a pool
     * @param _token The token pool to check
     */
    function getFreeCapital(address _token) external view returns (uint256) {
        return pools[_token].totalCapital - pools[_token].allocatedCapital;
    }
}
