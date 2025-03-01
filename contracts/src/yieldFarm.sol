pragma solidity ^0.8.0;

import { IL2ToL2CrossDomainMessenger } from '@interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol';
import { PredeployAddresses } from '@interop-lib/libraries/PredeployAddresses.sol';

interface ISuperSimpleETHYieldFarm {
    // Read-only functions (public variables in the original contract become 'view' functions in the interface)
    function apy() external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function stakedAmount(address user) external view returns (uint256);
    function lastUpdate(address user) external view returns (uint256);

    // Stake ETH (payable function)
    function stake() external payable;

    // Withdraw ETH and claim rewards
    function withdraw(uint256 _amount) external;

    // Returns the current liquidity rate (same as 'apy' in this example)
    function getLiquidityRate() external view returns (uint256);

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
}

// fetches yield from SuperSimpleETHYieldFarm
contract yieldFetcher {
    IL2ToL2CrossDomainMessenger internal immutable l2ToL2CrossDomainMessenger =
    IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    struct YieldFarm {
        address farm; // address of the farm
        uint256 yield;
        uint256 sourceChainId;
    }
    
    mapping(uint256 => mapping(address => YieldFarm)) public farms;
    mapping(uint256 => address[]) public farmsByChain;
    uint256[] public chainIds;

    function sendResult(uint256 _destinationChainId, address _farm, uint256 _yield) public {
        l2ToL2CrossDomainMessenger.sendMessage(_destinationChainId, address(this), abi.encodeCall(this.storeResult ,(_farm, _yield)));
    }

    
    function setResult(address _farm, uint256 _yield, uint256 _sourceChainId) public {
        if (farms[_sourceChainId][_farm].farm == address(0)) {
            farms[_sourceChainId][_farm].yield = _yield;
            farms[_sourceChainId][_farm].farm = _farm;
            farms[_sourceChainId][_farm].sourceChainId = _sourceChainId;
            farmsByChain[_sourceChainId].push(_farm);
            chainIds.push(_sourceChainId);
            return;
        } 

        farms[_sourceChainId][_farm].yield = _yield;
        farms[_sourceChainId][_farm].farm = _farm;
        farms[_sourceChainId][_farm].sourceChainId = _sourceChainId;

        farmsByChain[_sourceChainId].push(_farm);
        chainIds.push(_sourceChainId);
    }

    function storeResult(address _farm, uint256 _yield) public {
        uint256 sourceChainId = l2ToL2CrossDomainMessenger.crossDomainMessageSource();
        setResult(_farm, _yield, sourceChainId);
    }

    function handleResult(address _farm) public {
        uint256 apy = ISuperSimpleETHYieldFarm(_farm).getLiquidityRate();
        uint256 destinationChainId = l2ToL2CrossDomainMessenger.crossDomainMessageSource();
        sendResult(destinationChainId, _farm, apy);
    }

    function updateYields(address[] memory _farms, uint256[] memory _chainId) public returns (bool) {
        for (uint256 i; i < _farms.length; i++) {
            l2ToL2CrossDomainMessenger.sendMessage(
                _chainId[i], // destination chain id
                address(this), // sender
                abi.encodeCall(this.handleResult, _farms[i])
            );
        }
        return true;
    }
}