// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { PredeployAddresses } from '@interop-lib/libraries/PredeployAddresses.sol';
import { CrossDomainMessageLib } from '@interop-lib/libraries/CrossDomainMessageLib.sol';
import { IL2ToL2CrossDomainMessenger } from '@interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol';
import { ISuperchainWETH } from '@interop-lib/interfaces/ISuperchainWETH.sol';
import { SuperchainERC20 } from '@interop-lib/SuperchainERC20.sol';
import { ISuperchainTokenBridge } from '@interop-lib/interfaces/ISuperchainTokenBridge.sol';

error IncorrectValue();

contract CrossChainMultisend {
  // Updated structure with renamed chainId field
  struct ChainBalance {
    uint256 destChainId; // renamed from chainId
    uint256 balance;
    address yieldFarmAddress;
  }

  // Mapping from address to array of chain balances
  mapping(address => ChainBalance[]) public userBalances;

  // Updated event with renamed parameter
  event BalanceUpdated(
    address indexed user,
    uint256 indexed destChainId, // renamed from chainId
    uint256 amount,
    address yieldFarmAddress
  );

  // Updated Send struct with sourceChainId
  struct Send {
    address to;
    uint256 amount;
    address sender;
    address yieldFarmAddress;
    uint256 sourceChainId; // Added sourceChainId
    address asset; // Underlying erc20 token to be sent
  }

  ISuperchainTokenBridge public constant bridge =
    ISuperchainTokenBridge(0x4200000000000000000000000000000000000028);
  ISuperchainWETH internal immutable superchainWeth =
    ISuperchainWETH(payable(PredeployAddresses.SUPERCHAIN_WETH));
  IL2ToL2CrossDomainMessenger internal immutable l2ToL2CrossDomainMessenger =
    IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  receive() external payable {}

  // Updated helper function with renamed parameter
  function _updateChainBalance(
    address user,
    uint256 destChainId, // renamed from chainId
    uint256 amount,
    address yieldFarmAddress,
    bool isWithdraw
  ) internal {
    ChainBalance[] storage balances = userBalances[user];

    // Try to find and update existing chain balance
    for (uint256 i = 0; i < balances.length; i++) {
      if (
        balances[i].destChainId == destChainId // && balances[i].yieldFarmAddress == yieldFarmAddress
      ) {
        // renamed from chainId
        if (isWithdraw) {
          require(amount <= balances[i].balance, 'IMPOSSIBLE WITHDRAW AMOUNT');
          balances[i].balance -= amount;
        } else {
          balances[i].balance += amount;
        }
        emit BalanceUpdated(user, destChainId, balances[i].balance, yieldFarmAddress);
        return;
      }
    }

    // If chain not found, add new entry
    balances.push(ChainBalance(destChainId, amount, yieldFarmAddress)); // renamed from chainId
    emit BalanceUpdated(user, destChainId, amount, yieldFarmAddress);
  }

  function send(
    uint256 _destinationChainId,
    Send[] calldata _sends
  ) public payable returns (bytes32) {
    uint256 totalAmount;
    for (uint256 i; i < _sends.length; i++) {
      require(msg.sender == _sends[i].sender, 'THESE ARE NOT YOUR FUNDS!');

      totalAmount += _sends[i].amount;
      // Update sender's balance with yieldFarmAddress
      _updateChainBalance(
        _sends[i].sender,
        _destinationChainId,
        _sends[i].amount,
        _sends[i].yieldFarmAddress,
        false
      );
    }

    if (msg.value != totalAmount) revert IncorrectValue();

    bytes32 sendWethMsgHash = superchainWeth.sendETH{ value: totalAmount }(
      address(this),
      _destinationChainId
    );

    return
      l2ToL2CrossDomainMessenger.sendMessage(
        _destinationChainId,
        address(this),
        abi.encodeCall(this.relay, (sendWethMsgHash, _sends))
      );
  }

  function sendToReturn(
    Send[] calldata _sends
  ) public returns (bytes32) {
    CrossDomainMessageLib.requireCrossDomainCallback();
    require(address(this).balance >= _sends[0].amount, "Insufficient contract balance");
    bytes32 sendWethMsgHash = superchainWeth.sendETH{ value: _sends[0].amount }(
      address(this),
      _sends[0].sourceChainId
    );

    return l2ToL2CrossDomainMessenger.sendMessage(
      _sends[0].sourceChainId,
      address(this),
      abi.encodeCall(this.relayToReturn, (sendWethMsgHash, _sends))
    );
  }


  function _withdrawTokens(Send calldata _sends) internal returns (bool) {
    require(msg.sender == _sends.sender, 'THESE ARE NOT YOUR FUNDS!');

    SuperchainERC20(_sends.asset).approve(address(bridge), _sends.amount);
    bridge.sendERC20(
      address(_sends.asset),
      _sends.sender, // Send back to this contract on source chain
      _sends.amount,
      _sends.sourceChainId // Use sourceChainId from Send struct
    );

    return true;
  }

  event RelayExecuted(address[] senders, address[] yieldFarmAddresses);

  function withdraw(
    uint256 _withdrawFromChainId,
    Send[] calldata _sends
  ) public {
    
      l2ToL2CrossDomainMessenger.sendMessage(
        _withdrawFromChainId,
        address(this),
        abi.encodeCall(this.sendToReturn, (_sends))
      );

      // this calls send on the opposite chain with the message _sends[i]
      // TODO -> Add a check to ensure that the user has enough balance to withdraw

      /*
      bytes32 sendWethMsgHash = superchainWeth.sendETH{ value: 0 }(
      address(this),
      _withdrawFromChainId
      );

      return l2ToL2CrossDomainMessenger.sendMessage(
        _withdrawFromChainId,
        address(this),
        abi.encodeCall(this.sendToReturn, (sendWethMsgHash, _sends))
      );
      */

      /* 
      _updateChainBalance(
        _sends[0].sender,
        _withdrawFromChainId,
        _sends[0].amount,
        _sends[0].yieldFarmAddress, // why do we need this?
        true // it is a withdraw
      );
      */
  
  }

  function relay(bytes32 _sendWethMsgHash, Send[] calldata _sends) public {
    CrossDomainMessageLib.requireCrossDomainCallback();
    // CrossDomainMessageLib.requireMessageSuccess uses a special error signature that the
    // auto-relayer performs special handling on. The auto-relayer parses the _sendWethMsgHash
    // and waits for the _sendWethMsgHash to be relayed before relaying this message.
    CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

    address[] memory senders = new address[](_sends.length);
    address[] memory yieldFarmAddresses = new address[](_sends.length);

    for (uint256 i; i < _sends.length; i++) {
      address to = _sends[i].to;
      // use .call for example purpose, but not recommended in production.
      (bool success,) = to.call{value: _sends[i].amount}("");
      require(success, "ETH transfer failed");
      senders[i] = _sends[i].sender;
      yieldFarmAddresses[i] = _sends[i].yieldFarmAddress;
    }

    emit RelayExecuted(senders, yieldFarmAddresses);
  }

  function relayToReturn(bytes32 _sendWethMsgHash, Send[] calldata _sends) public {
    CrossDomainMessageLib.requireCrossDomainCallback();
    CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

    for (uint256 i; i < _sends.length; i++) {
      address to = _sends[i].sender;
      // use .call for example purpose, but not recommended in production.
      (bool success,) = to.call{value: _sends[i].amount}("");
      require(success, "ETH transfer failed");
    }
  }

  // Get all chain balances for a user
  function getBalances(address _user) external view returns (ChainBalance[] memory) {
    return userBalances[_user];
  }
}
