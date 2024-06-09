// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SucrStaking is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable sucrToken;
    uint256 public interestRate; // APY in basis points (100 = 1%)
    uint256 public constant SECONDS_IN_YEAR = 31536000; // 365 days

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lastRewardTime;
        uint256 interestRateAtStake; // Store the interest rate when user stakes
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public totalOwnerDeposits;
    uint256 public totalInterestPaid;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 reward);
    event InterestRateChanged(uint256 oldRate, uint256 newRate);
    event TokensAdded(uint256 amount);
    event EmergencyWithdraw(uint256 amount);

    constructor(address _sucrToken, uint256 _initialInterestRate, address _owner) Ownable(_owner) {
        require(_sucrToken != address(0), "Invalid token address");
        sucrToken = IERC20(_sucrToken);
        interestRate = _initialInterestRate;
        totalOwnerDeposits = 0;
        totalInterestPaid = 0;
    
}

    function stake(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Cannot stake 0");
        
        Stake storage userStake = stakes[msg.sender];
        if (userStake.amount > 0) {
            _claimReward(msg.sender);
        }

        sucrToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        userStake.amount += _amount;
        userStake.startTime = block.timestamp;
        userStake.lastRewardTime = block.timestamp;
        userStake.interestRateAtStake = interestRate;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount >= _amount, "Insufficient staked amount");

        uint256 reward = _claimReward(msg.sender);
        
        userStake.amount -= _amount;
        totalStaked -= _amount;
        
        sucrToken.safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount, reward);
    }

    function claimReward() external nonReentrant {
        uint256 reward = _claimReward(msg.sender);
        emit RewardClaimed(msg.sender, reward);
    }

    function _claimReward(address _user) internal returns (uint256) {
        Stake storage userStake = stakes[_user];
        uint256 reward = calculateReward(_user);

        if (reward > 0) {
            userStake.lastRewardTime = block.timestamp;
            sucrToken.safeTransfer(_user, reward);
            userStake.interestRateAtStake = interestRate; // Update to current rate for future rewards
            totalInterestPaid += reward;
        }

        return reward;
    }

    function calculateReward(address _user) public view returns (uint256) {
        Stake storage userStake = stakes[_user];
        if (userStake.amount == 0) return 0;

        uint256 timeStaked = block.timestamp - userStake.lastRewardTime;
        return (userStake.amount * userStake.interestRateAtStake * timeStaked) / (SECONDS_IN_YEAR * 10000);
    }

    function getStakedAmount(address _user) external view returns (uint256) {
        return stakes[_user].amount;
    }

    function getRewardsEarned(address _user) external view returns (uint256) {
        return calculateReward(_user);
    }

    function getInterestRate() external view returns (uint256) {
        return interestRate;
    }

    function setInterestRate(uint256 _newRate) external onlyOwner {
        uint256 oldRate = interestRate;
        interestRate = _newRate;
        emit InterestRateChanged(oldRate, _newRate);
    }

    function addTokens(uint256 _amount) external onlyOwner {
        sucrToken.safeTransferFrom(msg.sender, address(this), _amount);
        totalOwnerDeposits += _amount;
        emit TokensAdded(_amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 withdrawableAmount = totalOwnerDeposits > totalInterestPaid ? totalOwnerDeposits - totalInterestPaid : 0;
        require(withdrawableAmount > 0, "No tokens available for emergency withdrawal");
        sucrToken.safeTransfer(owner(), withdrawableAmount);
        totalOwnerDeposits -= withdrawableAmount;
        emit EmergencyWithdraw(withdrawableAmount);
    }
}
