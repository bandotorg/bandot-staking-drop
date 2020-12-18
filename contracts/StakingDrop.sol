// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingDrop is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable hbtcAddress; //hbtc的地址
    address public immutable bdtAddress; //奖励的token
    uint256 public immutable bonusStartAt; //活动开始时间

    /* ========== CONSTANTS ========== */

    uint256 public constant BONUS_DURATION = 32 days;
    uint256 public constant MAX_CLAIM_DURATION = 8 days;
    uint256 public constant TOTAL_BDT_REWARDS = 10000000 ether;

    mapping(address => uint256) public myDeposit; //存的数量
    mapping(address => uint256) public myRewards; //领取的奖励
    mapping(address => uint256) public myLastClaimedAt; //最后领取的时间

    uint256 public claimedRewards; //发的奖励的总数
    uint256 public totalDeposit; //总抵押数

    event Deposit(address indexed sender, uint256 amount);
    event Withdrawal(address indexed sender, uint256 amount);
    event Claimed(address indexed sender, uint256 amount, uint256 claimed);

    constructor(
        address hbtcAddress_,
        address bdtAddress_,
        uint256 bonusStartAt_
    ) public Ownable() {
        require(hbtcAddress_ != address(0), "StakingDrop: hbtcAddress_ is zero address");
        require(bdtAddress_ != address(0), "StakingDrop: bdtAddress_ is zero address");

        hbtcAddress = hbtcAddress_;
        bdtAddress = bdtAddress_;
        bonusStartAt = bonusStartAt_;
    }

    function withdraw(uint256 amount) external {
        if (block.timestamp < bonusStartAt.add(BONUS_DURATION)) return;
        require(amount > 0, "StakingDrop: amount should greater than zero");

        claimRewards();
        myDeposit[msg.sender] = myDeposit[msg.sender].sub(amount);
        totalDeposit = totalDeposit.sub(amount);

        require(IERC20(hbtcAddress).transfer(msg.sender, amount), "StakingDrop: withdraw transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    function deposit(uint256 _value) external {
        if (block.timestamp < bonusStartAt) return;
        if (block.timestamp > bonusStartAt.add(BONUS_DURATION)) return;
        require(_value > 0, "StakingDrop: _value should greater than zero");

        claimRewards();
        myDeposit[msg.sender] = myDeposit[msg.sender].add(_value);
        totalDeposit = totalDeposit.add(_value);

        require(IERC20(hbtcAddress).transferFrom(msg.sender, address(this), _value), "StakingDrop: deposit transferFrom failed");

        emit Deposit(msg.sender, _value);
    }

    function claimRewards() public {
        // claim must start from bonusStartAt
        if (block.timestamp < bonusStartAt) {
            if (myLastClaimedAt[msg.sender] < bonusStartAt) {
                myLastClaimedAt[msg.sender] = bonusStartAt;
            }
            return;
        }
        if (myLastClaimedAt[msg.sender] >= bonusStartAt) {
            uint256 rewards = getIncrementalRewards(msg.sender);
            myRewards[msg.sender] = myRewards[msg.sender].add(rewards);
            claimedRewards = claimedRewards.add(rewards);

            require(IERC20(bdtAddress).transfer(msg.sender, rewards), "StakingDrop: claimRewards transfer failed");

            emit Claimed(msg.sender, myRewards[msg.sender], claimedRewards);
        }
        myLastClaimedAt[msg.sender] = block.timestamp >
            bonusStartAt.add(BONUS_DURATION)
            ? bonusStartAt.add(BONUS_DURATION)
            : block.timestamp;
    }

    function getTotalRewards() public view returns (uint256) {
        if (block.timestamp < bonusStartAt) {
            return 0;
        }
        uint256 duration = block.timestamp.sub(bonusStartAt);
        if (duration > BONUS_DURATION) {
            return TOTAL_BDT_REWARDS;
        }
        return TOTAL_BDT_REWARDS.mul(duration).div(BONUS_DURATION);
    }

    function getIncrementalRewards(address target)
        public
        view
        returns (uint256)
    {
        uint256 totalRewards = getTotalRewards();
        if (
            myLastClaimedAt[target] < bonusStartAt ||
            totalDeposit == 0 ||
            totalRewards == 0
        ) {
            return 0;
        }
        uint256 remainingRewards = totalRewards.sub(claimedRewards);
        uint256 myDuration = block.timestamp > bonusStartAt.add(BONUS_DURATION)
            ? bonusStartAt.add(BONUS_DURATION).sub(myLastClaimedAt[target])
            : block.timestamp.sub(myLastClaimedAt[target]);
        if (myDuration > MAX_CLAIM_DURATION) {
            myDuration = MAX_CLAIM_DURATION;
        }
        uint256 rewards = remainingRewards
            .mul(myDeposit[target])
            .div(totalDeposit)
            .mul(myDuration)
            .div(MAX_CLAIM_DURATION);
        return rewards;
    }
}