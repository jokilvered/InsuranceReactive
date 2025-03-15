# Cross-Chain Insurance Protocol

An advanced decentralized insurance protocol that leverages the Reactive Network to monitor risk indicators across multiple blockchains and automatically process claims without requiring manual intervention.

## Overview

The Cross-Chain Insurance Protocol represents a significant advancement in on-chain insurance, removing the traditional claims process entirely by leveraging reactive smart contracts to monitor for insurable events in real-time across multiple blockchains.

### Key Features

- **Real-time Risk Monitoring**: Continuously observes smart contracts, stablecoins, bridges, and markets for signs of risk events
- **Automated Claims Processing**: Immediately executes payouts when qualifying events are detected without requiring user action
- **Cross-Chain Coverage**: Monitors and provides protection for assets across multiple blockchains
- **Dynamic Risk Assessment**: Adjusts premiums based on real-time risk indicators collected from on-chain data
- **Multiple Coverage Types**: Offers protection against smart contract exploits, stablecoin depegs, bridge failures, and market volatility

## Architecture

The protocol consists of several integrated components that work across both the destination chain(s) and the Reactive Network:

### Destination Chain Contracts

- **InsurancePool.sol**: Manages capital pools, policy purchases, and claim payouts
- **PolicyManager.sol**: Handles policy creation, management, and claims verification
- **RiskModel.sol**: Calculates premiums based on risk parameters and collects risk data
- **RiskDataCollector.sol**: Gathers and processes on-chain risk metrics
- **ClaimTrigger.sol**: Receives callbacks from reactive contracts to process claims

### Reactive Network Contracts

- **InsuranceEventListener.sol**: Monitors for insurable events across chains including:
  - Smart contract exploit patterns
  - Stablecoin price deviations
  - Bridge security events
  - Market volatility spikes

## Coverage Types

### Smart Contract Exploit Coverage
Automatically compensates users when the protocol detects abnormal behavior indicating an exploit, such as:
- Large/rapid transfers of funds
- Unusual access patterns
- Known exploit signatures

### Stablecoin Depeg Insurance
Provides protection when a stablecoin's price deviates from its peg for a specified duration:
- Monitors price feeds across DEXs and oracles
- Triggers payouts when price thresholds are violated
- Adjusts premiums based on historical stability

### Bridge Security Coverage
Offers protection against bridge failures or exploits:
- Monitors bridge contracts for security events
- Processes claims when unauthorized fund movements are detected
- Adjusts risk parameters based on bridge security features

### Market Volatility Protection
Activates downside protection during extreme market conditions:
- Tracks rapid price movements of covered assets
- Triggers claims during significant market dislocations
- Uses historical volatility for premium calculation

## Technical Implementation

The protocol leverages the Reactive Network's unique capabilities:
1. **Event Subscriptions**: Monitors specific event signatures across multiple chains
2. **Reactive VM Processing**: Analyzes events to detect insurable incidents
3. **Cross-Chain Callbacks**: Triggers claim processing on destination chains
4. **State Management**: Maintains detailed records of risk parameters and policy data

## Getting Started

### Prerequisites

- Node.js and npm
- Hardhat development environment
- Access to Reactive Network RPC endpoint
- Private keys for deployment

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/cross-chain-insurance.git
cd cross-chain-insurance
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

### Deployment

1. Deploy destination chain contracts:
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

2. Deploy reactive network contracts:
```bash
forge create src/InsuranceEventListener.sol:InsuranceEventListener --legacy --rpc-url $REACTIVE_RPC --private-key $REACTIVE_PRIVATE_KEY --value 0.01ether --constructor-args CLAIM_TRIGGER_ADDRESS
```

3. Configure contract relationships:
```bash
npx hardhat run scripts/configure.js --network sepolia
```

## Testing

Run tests for destination chain contracts:
```bash
npx hardhat test
```

Test the reactive network components (requires Reactive Network access):
```bash
forge test --match-contract InsuranceEventListenerTest --rpc-url $REACTIVE_RPC
```

## Future Development

- **Risk Oracle Integration**: Connect with decentralized risk assessment oracles
- **Multi-Chain Capital Pools**: Enable liquidity sharing across insurance pools on different chains
- **Governance Framework**: Add DAO governance for parameter adjustments and protocol upgrades
- **Premium Tokenization**: Create transferable premium tokens representing insurance positions

## License

GPL-2.0-or-later

## Acknowledgments

- [Reactive Network](https://github.com/Reactive-Network/reactive-smart-contract-demos) for providing the reactive smart contract infrastructure
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) for secure contract libraries