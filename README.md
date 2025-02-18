# Superchain Starter Kit: CrossChainMultisend

> Generated from [superchain-starter](https://github.com/ethereum-optimism/superchain-starter). See the original repository for a more detailed development guide.

Example Superchain app (contract + frontend) that uses interop to send ETH to multiple recipients on a different chain.

## 🔗 Contracts

### [CrossChainMultisend.sol](./contracts/src/CrossChainMultisend.sol)

- Enables sending ETH to multiple recipients on a different chain
- Uses `L2ToL2CrossDomainMessenger` for cross-chain message passing
- Leverages `SuperchainWETH` for cross-chain ETH transfers
- Implements a two-step process:
  1. Bridges ETH to the destination chain using SuperchainWETH
  2. Distributes ETH to multiple recipients on the destination chain
- Includes safety checks for message verification and ETH transfer success

## 📝 Overview

This contract sends two cross-chain messages through the L2ToL2CrossDomainMessenger:

1. (Message 1) to send ETH using SuperchainWETH from source to destination chain - triggered by SuperchainWETH#sendETH
2. (Message 2) to disperse the received ETH to the recipients on the destination chain - triggered by CrossChainMultisend#send

Message 2 depends on the success of Message 1, which is enforced by the `CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash)` check in the relay function. This ensures that ETH bridging is completed before distribution occurs.

## 🎯 Patterns

### 1. Contract deployed on same address on multiple chains

The CrossChainMultisend contract is designed to be deployed at the same address on all chains. This allows the contract to:

- "Trust" that the send message was emitted as a side effect of a specific sequence of events
- Process cross-chain messages from itself on other chains
- Maintain consistent behavior across the Superchain

```solidity
      CrossDomainMessageLib.requireCrossDomainCallback();

      ...

      function requireCrossDomainCallback() internal view {
        requireCallerIsCrossDomainMessenger();

        if (
            IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageSender()
                != address(this)
        ) revert InvalidCrossDomainSender();
    }
```

The above `CrossDomainMessageLib.requireCrossDomainCallback()` performs two checks

1. That the msg.sender is L2ToL2CrossDomainMessenger
2. That the message being sent was originally emitted on the source chain by the same contract address

Without the second check, it will be possible for ANY address on the source chain to send the message. This is undesirable because now there is no guarantee that the message was generated as a result of someone calling `CrossChainMultisend.send`

### 2. Returning msgHash from functions that emit cross domain messages

The contract captures the msgHash from SuperchainWETH's sendETH call and passes it to the destination chain. This enables:

- Verification that the ETH bridge operation completed successfully
- Reliable cross-chain message dependency tracking

This is a pattern for composing cross domain messages. Functions that emit a cross domain message (such as `SuperchainWeth.sendEth`) should return the message hash so that other contracts can consume / depend on it.

This "returning msgHash pattern" is also used in the `CrossChainMultisend.sol`, making it possible for a different contract to compose on this.

```solidity
function send(uint256 _destinationChainId, Send[] calldata _sends) public payable returns (bytes32)
```

### 3. Dependent cross-chain messages

The contract implements a pattern for handling dependent cross-chain messages:

1. First message (ETH bridging) must complete successfully
2. Second message (ETH distribution) verifies the first message's success, otherwise reverts
3. Auto-relayer handles the dependency by waiting for the first message before processing the second

```solidity
CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);
```

The above check calls the L2ToL2CrossDomainMessenger.successfulMessages mapping to check that the message corresponding to msgHash was correctly relayed already.

While you can revert using any custom error, it is recommended that such cases emit

```solidity
error DependentMessageNotSuccessful(bytes32 msgHash)
```

(which [`CrossDomainMessageLib.requireMessageSuccess`](https://github.com/ethereum-optimism/interop-lib/blob/main/src/libraries/CrossDomainMessageLib.sol) does under the hood)

This allows indexers / relayers to realize dependencies between messages, and recognize that a failed relayed message should be retried once the dependent message succeeds at some point in the future.

### 4. Using SuperchainWETH for cross-chain ETH transfers

The contract leverages SuperchainWETH to handle cross-chain ETH transfers:

- Automatically wraps and unwraps ETH as needed
- Provides reliable message hashes for tracking transfers
- Maintains ETH value consistency across chains

The high level flow is:

#### Source chain

`function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_);`

1. converts ETH to SuperchainWETH
2. sends SuperchainWETH (which follows SuperchainERC20 standard) using a crossdomain message

#### Destination chain

`function relayETH(address _from, address _to, uint256 _amount) external;`

1. relays the SuperchainWETH to the destination chain
2. converts the SuperchainWETH to ETH

## 🚀 Getting started

### Prerequisites: Foundry & Node

Follow [this guide](https://book.getfoundry.sh/getting-started/installation) to install Foundry

### 1. Create a new repository using this template:

Click the "Use this template" button above on GitHub, or [generate directly](https://github.com/new?template_name=superchain-starter&template_owner=ethereum-optimism)

### 2. Clone your new repository

```bash
git clone <your-new-repository-url>
cd superchain-starter-multisend
```

### 3. Install dependencies

```bash
pnpm i
```

### 4. Get started

```bash
pnpm dev
```

This command will:

- Start a local Superchain network (1 L1 chain and 2 L2 chains) using [supersim](https://github.com/ethereum-optimism/supersim)
- Launch the frontend development server at (http://localhost:5173)
- Deploy the smart contracts to your local network

Start building on the Superchain!

## 📚 More examples, docs

- Interop recipies / guides: https://docs.optimism.io/app-developers/tutorials/interop
- Superchain Dev Console: https://console.optimism.io/

## ⚖️ License

Files are licensed under the [MIT license](./LICENSE).

<a href="./LICENSE"><img src="https://user-images.githubusercontent.com/35039927/231030761-66f5ce58-a4e9-4695-b1fe-255b1bceac92.png" alt="License information" width="200" /></a>
