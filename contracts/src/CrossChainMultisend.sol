// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { PredeployAddresses } from '@interop-lib/libraries/PredeployAddresses.sol';
import { CrossDomainMessageLib } from '@interop-lib/libraries/CrossDomainMessageLib.sol';
import { IL2ToL2CrossDomainMessenger } from '@interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol';
import { ISuperchainWETH } from '@interop-lib/interfaces/ISuperchainWETH.sol';
import { SuperchainERC20 } from '@interop-lib/SuperchainERC20.sol';
import { ISuperchainTokenBridge } from '@interop-lib/interfaces/ISuperchainTokenBridge.sol';

error IncorrectValue();

interface IYieldFarm {
  function stake() external payable;
  function withdraw(uint256 _amount) external;
}

contract CrossChainMultisend {
  ISuperchainTokenBridge public constant bridge =
    ISuperchainTokenBridge(0x4200000000000000000000000000000000000028);
  ISuperchainWETH internal immutable superchainWeth =
    ISuperchainWETH(payable(PredeployAddresses.SUPERCHAIN_WETH));
  IL2ToL2CrossDomainMessenger internal immutable l2ToL2CrossDomainMessenger =
    IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  struct ChainBalance {
    uint256 destChainId;
    address toAddress;
    uint256 balance;
  }

  struct Send {
    uint256 sourceChainId;
    address sender;
    address toAddress;
    uint256 amount;
  }

  mapping(address => ChainBalance[]) public userBalances;

  receive() external payable {}

  // Deposit Flow
  function depositETHToOtherChain(
    uint256 _destinationChainId,
    Send calldata _send
  ) public payable returns (bytes32) {

    require(msg.sender == _send.sender, 'These are not your funds!');
    if (msg.value != _send.amount) revert IncorrectValue();
    require(_send.sourceChainId != _destinationChainId, 'You cannot deposit to the same chain, Depsoiting to the same chain is done via frontend');

    _updateBalanceToDepositETH(_send.sender, _destinationChainId, _send.amount, _send.toAddress);

    bytes32 sendWethMsgHash = superchainWeth.sendETH{ value: _send.amount }(
      address(this),
      _destinationChainId
    );

    return
      l2ToL2CrossDomainMessenger.sendMessage(
        _destinationChainId,
        address(this),
        abi.encodeCall(this.relay, (sendWethMsgHash, _send))
      );
  }

  function relay(bytes32 _sendWethMsgHash, Send calldata _send) public {
    CrossDomainMessageLib.requireCrossDomainCallback();
    CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

    IYieldFarm yieldFarm = IYieldFarm(_send.toAddress);
    yieldFarm.stake{ value: _send.amount }();
  }


  //Withdraw ETH flow

  function withdraw(uint256 _withdrawFromChainId, Send calldata _send) public {
    require(msg.sender == _send.sender, 'THESE ARE NOT YOUR FUNDS!');
    require(_updateBalanceToWithdrawETH(_send.sender, _withdrawFromChainId, _send.amount, _send.toAddress), 'Insufficient balance');
    l2ToL2CrossDomainMessenger.sendMessage(
      _withdrawFromChainId,
      address(this),
      abi.encodeCall(this.sendToReturn, (_send))
    );
  }

  function sendToReturn(Send calldata _send) public returns (bytes32) {
    CrossDomainMessageLib.requireCrossDomainCallback();

    IYieldFarm yieldFarm = IYieldFarm(_send.toAddress);
    yieldFarm.withdraw(_send.amount);

    require(address(this).balance >= _send.amount, 'Insufficient contract balance');
    bytes32 sendWethMsgHash = superchainWeth.sendETH{ value: _send.amount }(
      address(this),
      _send.sourceChainId
    );

    return
      l2ToL2CrossDomainMessenger.sendMessage(
        _send.sourceChainId,
        address(this),
        abi.encodeCall(this.relayToReturn, (sendWethMsgHash, _send))
      );
  }

  function relayToReturn(bytes32 _sendWethMsgHash, Send calldata _send) public {
    CrossDomainMessageLib.requireCrossDomainCallback();
    CrossDomainMessageLib.requireMessageSuccess(_sendWethMsgHash);

    address to = _send.sender;
    (bool success, ) = to.call{ value: _send.amount }('');
    require(success, 'ETH transfer failed');
  }




  //Helper functions
  function _updateBalanceToDepositETH(
    address user,
    uint256 destChainId,
    uint256 amount,
    address toAddress
  ) internal {
    ChainBalance[] storage balances = userBalances[user];

    for (uint256 i = 0; i < balances.length; i++) {
      if (balances[i].destChainId == destChainId && balances[i].toAddress == toAddress) {
        balances[i].balance += amount;
        return;
      }
    }
    balances.push(ChainBalance(destChainId, toAddress, amount));
  }


  function _updateBalanceToWithdrawETH(
    address user,
    uint256 destChainId,
    uint256 amount,
    address toAddress
  ) internal returns (bool) {
    ChainBalance[] storage balances = userBalances[user];

    for (uint256 i = 0; i < balances.length; i++) {
      if (balances[i].destChainId == destChainId && balances[i].toAddress == toAddress && balances[i].balance >= amount) {
        balances[i].balance -= amount;
        return true;
      }
    }
    return false;
  }


  function getBalances(address _user) external view returns (ChainBalance[] memory) {
    return userBalances[_user];
  }



}
