// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

contract SuperSimpleETHYieldFarm is ISuperSimpleETHYieldFarm {
  uint256 public apy; // Annual Percentage Yield (in percentage)
  uint256 public totalStaked; // Total ETH staked

  mapping(address => uint256) public stakedAmount; // User's staked ETH
  mapping(address => uint256) public lastUpdate; // Last update timestamp

  uint256 constant SECONDS_PER_YEAR = 31536000; // Seconds in a year

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);

  constructor(uint256 _apy) {
    apy = _apy;
  }

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
  function withdraw(uint256 _amount) external {
    require(stakedAmount[msg.sender] >= _amount, 'Not enough staked');

    sendReward(msg.sender);

    stakedAmount[msg.sender] -= _amount;
    lastUpdate[msg.sender] = block.timestamp;
    totalStaked -= _amount;

    payable(msg.sender).transfer(_amount);

    emit Withdrawn(msg.sender, _amount);
  }

  // Calculate and send rewards
  function sendReward(address _user) private {
    uint256 timeElapsed = block.timestamp - lastUpdate[_user];
    uint256 reward = (stakedAmount[_user] * apy * timeElapsed) / (SECONDS_PER_YEAR * 100);

    if (reward > 0 && address(this).balance >= reward) {
      payable(_user).transfer(reward);
    }
  }

  function getLiquidityRate() public view returns (uint256) {
    return apy;
  }

  receive() external payable {}
}
