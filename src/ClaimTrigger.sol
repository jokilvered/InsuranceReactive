// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "reactive-lib/abstract-base/AbstractCallback.sol";
import {IPolicyManager} from "./Interface.sol";

/**
 * @title ClaimTrigger
 * @dev Processes callbacks from the reactive network to trigger claims
 */
contract ClaimTrigger is AbstractCallback {
    // Events
    event ExploitClaimTriggered(
        address indexed contractAddress,
        uint256 indexed timestamp
    );
    event DepegClaimTriggered(
        address indexed stablecoin,
        uint256 price,
        uint256 indexed timestamp
    );
    event BridgeFailureClaimTriggered(
        address indexed bridge,
        uint256 indexed timestamp
    );
    event VolatilityClaimTriggered(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 indexed timestamp
    );
    event Received(address indexed sender, uint256 amount);

    // State variables
    address public owner;
    IPolicyManager public policyManager;
    mapping(address => bool) public authorizedListeners;

    // Cooldown tracking to prevent duplicate claims
    mapping(address => mapping(uint8 => uint256)) public lastClaimTime;
    uint256 public claimCooldown = 24 hours;

    /**
     * @dev Risk types
     */
    enum RiskType {
        SmartContractExploit,
        StablecoinDepeg,
        BridgeFailure,
        MarketVolatility
    }

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorizedListener(address sender) {
        require(authorizedListeners[sender], "Not authorized listener");
        _;
    }

    /**
     * @dev Constructor initializes the contract
     * @param _callbackSender Address of the callback sender
     * @param _policyManager Address of the policy manager
     */
    constructor(
        address _callbackSender,
        address _policyManager
    ) AbstractCallback(_callbackSender) {
        owner = msg.sender;
        policyManager = IPolicyManager(_policyManager);
    }

    /**
     * @dev Sets the policy manager address
     * @param _policyManager New policy manager address
     */
    function setPolicyManager(address _policyManager) external onlyOwner {
        require(_policyManager != address(0), "Invalid address");
        policyManager = IPolicyManager(_policyManager);
    }

    /**
     * @dev Sets the claim cooldown period
     * @param _cooldown New cooldown in seconds
     */
    function setClaimCooldown(uint256 _cooldown) external onlyOwner {
        claimCooldown = _cooldown;
    }

    /**
     * @dev Authorizes or deauthorizes a listener
     * @param _listener Listener address
     * @param _authorized Whether the listener is authorized
     */
    function setAuthorizedListener(
        address _listener,
        bool _authorized
    ) external onlyOwner {
        authorizedListeners[_listener] = _authorized;
    }

    /**
     * @dev Processes an exploit claim from the listener
     * @param sender The listener's address
     * @param contractAddress The address of the exploited contract
     * @param timestamp The timestamp of the exploit
     */
    function triggerExploitClaim(
        address sender,
        address contractAddress,
        uint256 timestamp
    )
        external
        authorizedSenderOnly
        rvmIdOnly(sender)
        onlyAuthorizedListener(sender)
    {
        // Check cooldown to prevent duplicate claims
        uint8 riskTypeId = uint8(RiskType.SmartContractExploit);
        if (
            block.timestamp - lastClaimTime[contractAddress][riskTypeId] <
            claimCooldown
        ) {
            return;
        }

        // Update last claim time
        lastClaimTime[contractAddress][riskTypeId] = block.timestamp;

        // Generate claim evidence
        bytes memory claimEvidence = abi.encode(
            "exploit",
            contractAddress,
            timestamp,
            block.timestamp
        );

        // Trigger claims processing in the policy manager
        policyManager.processContractClaims(
            contractAddress,
            address(0), // All tokens for this contract
            claimEvidence
        );

        emit ExploitClaimTriggered(contractAddress, timestamp);
    }

    /**
     * @dev Processes a stablecoin depeg claim from the listener
     * @param sender The listener's address
     * @param stablecoin The address of the depegged stablecoin
     * @param price The price at depeg
     * @param timestamp The timestamp of the depeg
     */
    function triggerDepegClaim(
        address sender,
        address stablecoin,
        uint256 price,
        uint256 timestamp
    )
        external
        authorizedSenderOnly
        rvmIdOnly(sender)
        onlyAuthorizedListener(sender)
    {
        // Check cooldown to prevent duplicate claims
        uint8 riskTypeId = uint8(RiskType.StablecoinDepeg);
        if (
            block.timestamp - lastClaimTime[stablecoin][riskTypeId] <
            claimCooldown
        ) {
            return;
        }

        // Update last claim time
        lastClaimTime[stablecoin][riskTypeId] = block.timestamp;

        // Generate claim evidence
        bytes memory claimEvidence = abi.encode(
            "depeg",
            stablecoin,
            price,
            timestamp,
            block.timestamp
        );

        // Trigger claims processing in the policy manager
        policyManager.processContractClaims(
            stablecoin,
            stablecoin, // The token is the stablecoin itself
            claimEvidence
        );

        emit DepegClaimTriggered(stablecoin, price, timestamp);
    }

    /**
     * @dev Processes a bridge failure claim from the listener
     * @param sender The listener's address
     * @param bridge The address of the failed bridge
     * @param timestamp The timestamp of the failure
     */
    function triggerBridgeFailureClaim(
        address sender,
        address bridge,
        uint256 timestamp
    )
        external
        authorizedSenderOnly
        rvmIdOnly(sender)
        onlyAuthorizedListener(sender)
    {
        // Check cooldown to prevent duplicate claims
        uint8 riskTypeId = uint8(RiskType.BridgeFailure);
        if (
            block.timestamp - lastClaimTime[bridge][riskTypeId] < claimCooldown
        ) {
            return;
        }

        // Update last claim time
        lastClaimTime[bridge][riskTypeId] = block.timestamp;

        // Generate claim evidence
        bytes memory claimEvidence = abi.encode(
            "bridge_failure",
            bridge,
            timestamp,
            block.timestamp
        );

        // Trigger claims processing in the policy manager
        policyManager.processContractClaims(
            bridge,
            address(0), // All tokens for this bridge
            claimEvidence
        );

        emit BridgeFailureClaimTriggered(bridge, timestamp);
    }

    /**
     * @dev Processes a market volatility claim from the listener
     * @param sender The listener's address
     * @param token The token with high volatility
     * @param oldPrice The previous price
     * @param newPrice The new price
     * @param timestamp The timestamp of the volatility
     */
    function triggerVolatilityClaim(
        address sender,
        address token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    )
        external
        authorizedSenderOnly
        rvmIdOnly(sender)
        onlyAuthorizedListener(sender)
    {
        // Check cooldown to prevent duplicate claims
        uint8 riskTypeId = uint8(RiskType.MarketVolatility);
        if (
            block.timestamp - lastClaimTime[token][riskTypeId] < claimCooldown
        ) {
            return;
        }

        // Update last claim time
        lastClaimTime[token][riskTypeId] = block.timestamp;

        // Generate claim evidence
        bytes memory claimEvidence = abi.encode(
            "volatility",
            token,
            oldPrice,
            newPrice,
            timestamp,
            block.timestamp
        );

        // Trigger claims processing in the policy manager
        policyManager.processContractClaims(
            address(0), // No specific contract
            token, // The volatile token
            claimEvidence
        );

        emit VolatilityClaimTriggered(token, oldPrice, newPrice, timestamp);
    }

    /**
     * @dev Allows the owner to manually trigger a claim for testing
     * @param riskType The type of risk
     * @param target The target contract or token
     */
    function manualTriggerClaim(
        RiskType riskType,
        address target
    ) external onlyOwner {
        bytes memory claimEvidence = abi.encode(
            "manual_trigger",
            uint8(riskType),
            target,
            block.timestamp
        );

        if (riskType == RiskType.SmartContractExploit) {
            policyManager.processContractClaims(
                target,
                address(0),
                claimEvidence
            );
        } else if (riskType == RiskType.StablecoinDepeg) {
            policyManager.processContractClaims(target, target, claimEvidence);
        } else if (riskType == RiskType.BridgeFailure) {
            policyManager.processContractClaims(
                target,
                address(0),
                claimEvidence
            );
        } else if (riskType == RiskType.MarketVolatility) {
            policyManager.processContractClaims(
                address(0),
                target,
                claimEvidence
            );
        }
    }

    /**
     * @dev Allows the owner to withdraw any trapped funds
     * @param token Token to withdraw (address(0) for ETH)
     * @param to Address to send funds to
     */
    function withdrawFunds(address token, address to) external onlyOwner {
        require(to != address(0), "Invalid address");

        if (token == address(0)) {
            // Withdraw ETH
            (bool success, ) = to.call{value: address(this).balance}("");
            require(success, "ETH transfer failed");
        } else {
            // Withdraw ERC20
            IERC20 tokenContract = IERC20(token);
            uint256 balance = tokenContract.balanceOf(address(this));
            tokenContract.transfer(to, balance);
        }
    }

    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable override {
        emit Received(msg.sender, msg.value);
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}
