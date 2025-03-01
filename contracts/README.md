# Contracts

This project implements a cross-chain yield farming system on the OP Stack Superchain, allowing users to stake ETH across different chains and earn yield.


## Development

### Dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

Deploy to multiple chains using either:

1. Super CLI:

```bash
cd ../ && pnpm sup
```

2. Direct Forge script deployment:

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```


## Smart Contracts

### CrossChainMultisend.sol

The main contract that handles cross-chain ETH transfers and interactions with yield farms.

Key features:
- Send ETH between chains using the Superchain native bridge
- Track user balances across different chains
- Interact with yield farms on destination chains
- Withdraw ETH and earned yield back to the source chain

### SuperSimpleETHYieldFarm.sol

A simple yield farm contract that:
- Accepts ETH deposits
- Calculates and distributes yield based on a fixed APY
- Allows users to withdraw their staked ETH plus earned rewards
- Returns the reward amount when withdrawing

### SuperSimpleYieldFarmWithRewards.sol

An enhanced version of the yield farm that:
- Explicitly returns reward amounts from functions
- Includes proper event emissions
- Maintains the same core yield calculation logic

### yieldFarm.sol

A contract that fetches and aggregates yield information from farms across different chains:
- Communicates with yield farms on various chains
- Stores and updates yield rates
- Provides a unified interface to query yield information
- Uses cross-chain messaging to update yield information

## How It Works

1. **Deposit Flow**:
   - User deposits ETH on Chain A
   - ETH is bridged to Chain B
   - On Chain B, the ETH is deposited into a yield farm

2. **Withdrawal Flow**:
   - User initiates a withdrawal from Chain A
   - The system withdraws ETH + earned yield from the farm on Chain B
   - ETH is bridged back to Chain A and returned to the user

3. **Yield Tracking**:
   - The yieldFetcher contract periodically queries yield rates from farms
   - Yield information is stored and made available across chains
   - Users can compare yields before deciding where to stake

## Technical Details

- Uses the Superchain WETH contract for cross-chain ETH transfers
- Leverages the L2-to-L2 Cross Domain Messenger for cross-chain communication
- Implements a simple APY-based yield calculation mechanism
- Tracks user balances across multiple chains