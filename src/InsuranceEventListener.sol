pragma solidity >=0.8.0;

import "reactive-lib/interfaces/IReactive.sol";
import "reactive-lib/abstract-base/AbstractPausableReactive.sol";

/**
 * @title InsuranceEventListener
 * @dev Reactive contract that monitors events across chains for insurable events
 */
contract InsuranceEventListener is IReactive, AbstractPausableReactive {
    // Event signatures
    // Standard ERC20 Transfer event topic
    uint256 private constant ERC20_TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // Topics for specific protocols (examples)
    uint256 private constant BRIDGE_TRANSFER_TOPIC_0 =
        0x6b616089d04950dc06c45c6dd787d657980543f89651aec47924752c7d16c888; // Example
    uint256 private constant POOL_SWAP_TOPIC_0 =
        0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822; // Uniswap Swap
    uint256 private constant ORACLE_PRICE_UPDATE_TOPIC_0 =
        0x91cb3bb75cfbd718bbfccc56b7f53d92d7048ef4ca39a3b5b3d12dbffa3aaedb; // Example

    // Callback constants
    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

    uint256 private constant ETHEREUM_CHAIN_ID = 1;
    uint256 private constant BINANCE_SMART_CHAIN_ID = 56;
    uint256 private constant POLYGON_POS_CHAIN_ID = 137;
    uint256 private constant AVALANCHE_C_CHAIN_ID = 43114;
    uint256 private constant BASE_CHAIN_ID = 8453;
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    // Smart contract exploit detection parameters
    struct ExploitDetectionParams {
        uint256 largeTransferThreshold; // Threshold for detecting large transfers
        uint256 rapidTransferCount; // Number of transfers in short time to flag
        uint256 rapidTransferWindow; // Time window for rapid transfers (seconds)
        mapping(address => uint256[]) tokenTransferTimestamps; // Timestamps of recent token transfers
    }

    // Stablecoin depeg detection parameters
    struct DepegDetectionParams {
        uint256 priceThreshold; // Price threshold for depeg (scaled by 1e18)
        uint256 depegDuration; // Duration threshold for depeg (seconds)
        mapping(address => uint256) tokenDepegStartTime; // Start time of depeg event
    }

    // Bridge failure detection parameters
    struct BridgeDetectionParams {
        mapping(address => bool) monitoredBridges; // Bridges being monitored
        mapping(address => uint256) failureTimestamp; // Timestamp of detected failure
    }

    // Price volatility detection parameters
    struct VolatilityDetectionParams {
        uint256 volatilityThreshold; // Volatility threshold percentage (scaled by 1e18)
        uint256 timeWindow; // Time window for volatility calculation
        mapping(address => uint256) lastPriceTimestamp; // Timestamp of last price update
        mapping(address => uint256) lastPrice; // Last recorded price
    }

    // State variables
    ExploitDetectionParams private exploitParams;
    DepegDetectionParams private depegParams;
    BridgeDetectionParams private bridgeParams;
    VolatilityDetectionParams private volatilityParams;

    address private claimTrigger;
    mapping(address => bool) private monitoredContracts;
    mapping(address => bool) private monitoredStablecoins;
    mapping(address => bool) private monitoredTokens;

    // Events
    event ExploitDetected(address indexed contract_address, uint256 timestamp);
    event DepegDetected(
        address indexed stablecoin,
        uint256 price,
        uint256 timestamp
    );
    event BridgeFailureDetected(address indexed bridge, uint256 timestamp);
    event HighVolatilityDetected(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );

    /**
     * @dev Constructor initializes the contract with default parameters
     * @param _claimTrigger Address of the claim trigger contract
     */
    constructor(address _claimTrigger) payable {
        require(_claimTrigger != address(0), "Invalid claim trigger address");
        claimTrigger = _claimTrigger;
        owner = msg.sender;
        paused = false;

        // Set default parameters
        exploitParams.largeTransferThreshold = 1000000 * 1e18; // 1M tokens
        exploitParams.rapidTransferCount = 5;
        exploitParams.rapidTransferWindow = 10 minutes;

        depegParams.priceThreshold = 95 * 1e16; // 0.95 USD
        depegParams.depegDuration = 30 minutes;

        volatilityParams.volatilityThreshold = 20 * 1e16; // 20%
        volatilityParams.timeWindow = 1 hours;

        if (!vm) {
            // Subscribe to events on supported chains
            subscribeToEvents();
        }
    }

    /**
     * @dev Configures the contract subscriptions
     */
    function subscribeToEvents() private {
        // Subscribe to ERC20 transfers on multiple chains
        service.subscribe(
            ETHEREUM_CHAIN_ID,
            address(0), // Any contract
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        service.subscribe(
            BINANCE_SMART_CHAIN_ID,
            address(0),
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to bridge events
        service.subscribe(
            ETHEREUM_CHAIN_ID,
            address(0),
            BRIDGE_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to price oracle updates
        service.subscribe(
            ETHEREUM_CHAIN_ID,
            address(0),
            ORACLE_PRICE_UPDATE_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to pool swaps
        service.subscribe(
            ETHEREUM_CHAIN_ID,
            address(0),
            POOL_SWAP_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /**
     * @dev Provides the list of subscriptions to pause/resume
     */
    function getPausableSubscriptions()
        internal
        pure
        override
        returns (Subscription[] memory)
    {
        Subscription[] memory subscriptions = new Subscription[](5);

        subscriptions[0] = Subscription(
            ETHEREUM_CHAIN_ID,
            address(0),
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        subscriptions[1] = Subscription(
            BINANCE_SMART_CHAIN_ID,
            address(0),
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        subscriptions[2] = Subscription(
            ETHEREUM_CHAIN_ID,
            address(0),
            BRIDGE_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        subscriptions[3] = Subscription(
            ETHEREUM_CHAIN_ID,
            address(0),
            ORACLE_PRICE_UPDATE_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        subscriptions[4] = Subscription(
            ETHEREUM_CHAIN_ID,
            address(0),
            POOL_SWAP_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        return subscriptions;
    }

    /**
     * @dev Adds a contract to the monitoring list
     * @param _contract Address of the contract to monitor
     */
    function addMonitoredContract(address _contract) external onlyOwner {
        monitoredContracts[_contract] = true;
    }

    /**
     * @dev Removes a contract from the monitoring list
     * @param _contract Address of the contract to stop monitoring
     */
    function removeMonitoredContract(address _contract) external onlyOwner {
        monitoredContracts[_contract] = false;
    }

    /**
     * @dev Adds a stablecoin to the monitoring list
     * @param _stablecoin Address of the stablecoin to monitor
     */
    function addMonitoredStablecoin(address _stablecoin) external onlyOwner {
        monitoredStablecoins[_stablecoin] = true;
    }

    /**
     * @dev Removes a stablecoin from the monitoring list
     * @param _stablecoin Address of the stablecoin to stop monitoring
     */
    function removeMonitoredStablecoin(address _stablecoin) external onlyOwner {
        monitoredStablecoins[_stablecoin] = false;
    }

    /**
     * @dev Adds a bridge to the monitoring list
     * @param _bridge Address of the bridge to monitor
     */
    function addMonitoredBridge(address _bridge) external onlyOwner {
        bridgeParams.monitoredBridges[_bridge] = true;
    }

    /**
     * @dev Removes a bridge from the monitoring list
     * @param _bridge Address of the bridge to stop monitoring
     */
    function removeMonitoredBridge(address _bridge) external onlyOwner {
        bridgeParams.monitoredBridges[_bridge] = false;
    }

    /**
     * @dev Adds a token to the volatility monitoring list
     * @param _token Address of the token to monitor
     */
    function addMonitoredToken(address _token) external onlyOwner {
        monitoredTokens[_token] = true;
    }

    /**
     * @dev Removes a token from the volatility monitoring list
     * @param _token Address of the token to stop monitoring
     */
    function removeMonitoredToken(address _token) external onlyOwner {
        monitoredTokens[_token] = false;
    }

    /**
     * @dev Updates exploit detection parameters
     */
    function updateExploitParams(
        uint256 _largeTransferThreshold,
        uint256 _rapidTransferCount,
        uint256 _rapidTransferWindow
    ) external onlyOwner {
        exploitParams.largeTransferThreshold = _largeTransferThreshold;
        exploitParams.rapidTransferCount = _rapidTransferCount;
        exploitParams.rapidTransferWindow = _rapidTransferWindow;
    }

    /**
     * @dev Updates depeg detection parameters
     */
    function updateDepegParams(
        uint256 _priceThreshold,
        uint256 _depegDuration
    ) external onlyOwner {
        depegParams.priceThreshold = _priceThreshold;
        depegParams.depegDuration = _depegDuration;
    }

    /**
     * @dev Updates volatility detection parameters
     */
    function updateVolatilityParams(
        uint256 _volatilityThreshold,
        uint256 _timeWindow
    ) external onlyOwner {
        volatilityParams.volatilityThreshold = _volatilityThreshold;
        volatilityParams.timeWindow = _timeWindow;
    }

    /**
     * @dev React to log events on the monitored chains
     * @param log The log record to process
     */
    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == ERC20_TRANSFER_TOPIC_0) {
            processTokenTransfer(log);
        } else if (log.topic_0 == BRIDGE_TRANSFER_TOPIC_0) {
            processBridgeEvent(log);
        } else if (log.topic_0 == ORACLE_PRICE_UPDATE_TOPIC_0) {
            processPriceUpdate(log);
        } else if (log.topic_0 == POOL_SWAP_TOPIC_0) {
            processPoolSwap(log);
        }
    }

    /**
     * @dev Process a token transfer event
     * @param log The log record containing the transfer
     */
    function processTokenTransfer(LogRecord calldata log) private {
        // Check if we're monitoring the contract
        if (!monitoredContracts[log._contract]) {
            return;
        }

        // Extract transfer amount and check if it's a large transfer
        uint256 amount = abi.decode(log.data, (uint256));

        if (amount >= exploitParams.largeTransferThreshold) {
            // Check for rapid transfers (potential exploit)
            uint256[] storage timestamps = exploitParams
                .tokenTransferTimestamps[log._contract];

            // Add current timestamp
            timestamps.push(block.timestamp);

            // If we have enough transfer records, check for rapid transfers
            if (timestamps.length >= exploitParams.rapidTransferCount) {
                uint256 oldestRelevantIndex = timestamps.length -
                    exploitParams.rapidTransferCount;

                // If transfers happened within the window, signal an exploit
                if (
                    block.timestamp - timestamps[oldestRelevantIndex] <=
                    exploitParams.rapidTransferWindow
                ) {
                    detectExploit(log._contract, block.timestamp);
                }

                // Cleanup old timestamps
                if (timestamps.length > exploitParams.rapidTransferCount * 2) {
                    // This is a simplified cleanup - in production would need proper array management
                    delete exploitParams.tokenTransferTimestamps[log._contract];
                }
            }
        }
    }

    /**
     * @dev Process a bridge event
     * @param log The log record containing the bridge event
     */
    function processBridgeEvent(LogRecord calldata log) private {
        // Only process events from monitored bridges
        if (!bridgeParams.monitoredBridges[log._contract]) {
            return;
        }
        if (
            log.topic_3 ==
            0x0000000000000000000000000000000000000000000000000000000000000001
        ) {
            detectBridgeFailure(log._contract, block.timestamp);
        }
    }

    /**
     * @dev Process a price update event
     * @param log The log record containing the price update
     */
    function processPriceUpdate(LogRecord calldata log) private {
        address token = address(uint160(log.topic_1));
        uint256 price = abi.decode(log.data, (uint256));

        // Check for stablecoin depegs
        if (monitoredStablecoins[token]) {
            processStablecoinPrice(token, price, block.timestamp);
        }

        // Check for high volatility
        if (monitoredTokens[token]) {
            processTokenVolatility(token, price, block.timestamp);
        }
    }

    /**
     * @dev Process a pool swap event
     * @param log The log record containing the swap
     */
    function processPoolSwap(LogRecord calldata log) private {
        // Pool swaps can be used to detect market manipulation or high volatility
        // This would contain more complex logic in a production system
    }

    /**
     * @dev Detect if a stablecoin has depegged
     * @param token The stablecoin address
     * @param price The current price
     * @param timestamp The event timestamp
     */
    function processStablecoinPrice(
        address token,
        uint256 price,
        uint256 timestamp
    ) private {
        // Check if price is below threshold (depeg)
        if (price < depegParams.priceThreshold) {
            // If this is the first time we're seeing the depeg, record the start time
            if (depegParams.tokenDepegStartTime[token] == 0) {
                depegParams.tokenDepegStartTime[token] = timestamp;
            }
            // If depeg has been ongoing for the required duration, trigger claim
            else if (
                timestamp - depegParams.tokenDepegStartTime[token] >=
                depegParams.depegDuration
            ) {
                detectStablecoinDepeg(token, price, timestamp);
                // Reset the counter after triggering
                depegParams.tokenDepegStartTime[token] = 0;
            }
        }
        // Price is back above threshold, reset counter
        else {
            depegParams.tokenDepegStartTime[token] = 0;
        }
    }

    /**
     * @dev Process token price to detect high volatility
     * @param token The token address
     * @param price The current price
     * @param timestamp The event timestamp
     */
    function processTokenVolatility(
        address token,
        uint256 price,
        uint256 timestamp
    ) private {
        uint256 lastPrice = volatilityParams.lastPrice[token];
        uint256 lastTimestamp = volatilityParams.lastPriceTimestamp[token];

        // Skip if we don't have a previous price yet
        if (lastPrice == 0) {
            volatilityParams.lastPrice[token] = price;
            volatilityParams.lastPriceTimestamp[token] = timestamp;
            return;
        }

        // Check if price change occurred within our time window
        if (timestamp - lastTimestamp <= volatilityParams.timeWindow) {
            // Calculate price change percentage
            uint256 priceDifference;
            uint256 changePercentage;

            if (price > lastPrice) {
                priceDifference = price - lastPrice;
                changePercentage = (priceDifference * 1e18) / lastPrice;
            } else {
                priceDifference = lastPrice - price;
                changePercentage = (priceDifference * 1e18) / lastPrice;
            }

            // If change percentage exceeds threshold, trigger volatility detection
            if (changePercentage > volatilityParams.volatilityThreshold) {
                detectHighVolatility(token, lastPrice, price, timestamp);
            }
        }

        // Update last price data
        volatilityParams.lastPrice[token] = price;
        volatilityParams.lastPriceTimestamp[token] = timestamp;
    }

    /**
     * @dev Trigger a claim for a detected exploit
     * @param contractAddress The contract that was exploited
     * @param timestamp The timestamp of the exploit
     */
    function detectExploit(address contractAddress, uint256 timestamp) private {
        emit ExploitDetected(contractAddress, timestamp);

        // Prepare payload for claim trigger
        bytes memory payload = abi.encodeWithSignature(
            "triggerExploitClaim(address,uint256)",
            contractAddress,
            timestamp
        );

        // Send callback to claim trigger contract
        emit Callback(
            SEPOLIA_CHAIN_ID,
            claimTrigger,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    /**
     * @dev Trigger a claim for a detected stablecoin depeg
     * @param stablecoin The stablecoin that depegged
     * @param price The depegged price
     * @param timestamp The timestamp of the depeg
     */
    function detectStablecoinDepeg(
        address stablecoin,
        uint256 price,
        uint256 timestamp
    ) private {
        emit DepegDetected(stablecoin, price, timestamp);

        // Prepare payload for claim trigger
        bytes memory payload = abi.encodeWithSignature(
            "triggerDepegClaim(address,uint256,uint256)",
            stablecoin,
            price,
            timestamp
        );

        // Send callback to claim trigger contract
        emit Callback(
            SEPOLIA_CHAIN_ID,
            claimTrigger,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    /**
     * @dev Trigger a claim for a detected bridge failure
     * @param bridge The bridge that failed
     * @param timestamp The timestamp of the failure
     */
    function detectBridgeFailure(address bridge, uint256 timestamp) private {
        // Only trigger once for a bridge failure
        if (bridgeParams.failureTimestamp[bridge] > 0) {
            return;
        }

        bridgeParams.failureTimestamp[bridge] = timestamp;
        emit BridgeFailureDetected(bridge, timestamp);

        // Prepare payload for claim trigger
        bytes memory payload = abi.encodeWithSignature(
            "triggerBridgeFailureClaim(address,uint256)",
            bridge,
            timestamp
        );

        // Send callback to claim trigger contract
        emit Callback(
            SEPOLIA_CHAIN_ID,
            claimTrigger,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    /**
     * @dev Trigger a claim for detected high volatility
     * @param token The token with high volatility
     * @param oldPrice The previous price
     * @param newPrice The new price
     * @param timestamp The timestamp of the volatility
     */
    function detectHighVolatility(
        address token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    ) private {
        emit HighVolatilityDetected(token, oldPrice, newPrice, timestamp);

        // Prepare payload for claim trigger
        bytes memory payload = abi.encodeWithSignature(
            "triggerVolatilityClaim(address,uint256,uint256,uint256)",
            token,
            oldPrice,
            newPrice,
            timestamp
        );

        // Send callback to claim trigger contract
        emit Callback(
            SEPOLIA_CHAIN_ID,
            claimTrigger,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }
}
