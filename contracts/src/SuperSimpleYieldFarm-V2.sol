// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract SuperSimpleETHYieldFarm {
  uint256 public apy; // Annual Percentage Yield (in percentage)
  uint256 public totalStaked; // Total ETH staked

  mapping(address => uint256) public stakedAmount; // User's staked ETH
  mapping(address => uint256) public lastUpdate; // Last update timestamp

  uint256 constant SECONDS_PER_YEAR = 31536000; // Seconds in a year

  constructor(uint256 _apy) {
    apy = _apy;
  }

    // Events
event Staked(address indexed user, uint256 amount);
event Withdrawn(address indexed user, uint256 amount);


  // Stake ETH
  function stake() external payable {
    require(msg.value > 0, 'Must send ETH');

    if (stakedAmount[msg.sender] > 0) {
      sendReward(msg.sender);
    }

    stakedAmount[msg.sender] += msg.value;
    lastUpdate[msg.sender] = block.timestamp;
    totalStaked += msg.value;

    emit Staked(msg.sender, msg.value);
  }

  // Withdraw ETH and claim rewards
  function withdraw(uint256 _amount) external returns (uint256) {
    require(stakedAmount[msg.sender] >= _amount, 'Not enough staked');

    uint256 reward = sendReward(msg.sender);

    stakedAmount[msg.sender] -= _amount;
    lastUpdate[msg.sender] = block.timestamp;
    totalStaked -= _amount;

    payable(msg.sender).transfer(_amount);

    emit Withdrawn(msg.sender, _amount);
    
    return reward;
  }

  // Calculate and send rewards
  function sendReward(address _user) private returns (uint256) {
    uint256 timeElapsed = block.timestamp - lastUpdate[_user];
    uint256 reward = (stakedAmount[_user] * apy * timeElapsed) / (SECONDS_PER_YEAR * 100);

    if (reward > 0 && address(this).balance >= reward) {
      payable(_user).transfer(reward);
    }
    return reward;
  }

  function getLiquidityRate() public view returns (uint256) {
    return apy;
  }

  receive() external payable {}
}