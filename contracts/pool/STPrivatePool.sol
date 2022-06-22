// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ST Private Pool Contract
 * @author SEALEM-LAB
 * @notice In this contract private round users can harvest ST
 */
contract STPrivatePool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public st;

    uint256 public constant blockPerDay = 28800;
    uint256 public constant blockPerYear = blockPerDay * 365;
    uint256 public constant blockPerQuarter = blockPerYear / 4;

    uint256 public constant stStartBlock = 19169300;
    uint256 public constant releasedTotalToken = 7e6 * 1e18;
    uint256 public constant releaseTerm = 10 * blockPerQuarter;
    uint256 public constant releaseStartBlock = stStartBlock - blockPerQuarter;
    uint256 public constant releaseEndBlock = releaseStartBlock + releaseTerm;
    uint256 public constant tokenPerBlock = releasedTotalToken / releaseTerm;

    uint256 public lastRewardBlock = releaseStartBlock;

    uint256 public stake;
    uint256 public accTokenPerStake;
    uint256 public releasedToken;
    uint256 public harvestedToken;

    mapping(address => uint256) public userStake;
    mapping(address => uint256) public userLastAccTokenPerStake;
    mapping(address => uint256) public userStoredToken;
    mapping(address => uint256) public userHarvestedToken;

    event HarvestToken(address indexed user, uint256 amount);

    /**
     * @param stAddr Initialize ST Address
     * @param userAddrs Initialize users
     * @param userStakes Initialize user stake
     */
    constructor(
        address stAddr,
        address[] memory userAddrs,
        uint256[] memory userStakes
    ) {
        require(
            userAddrs.length == userStakes.length,
            "Data length does not match"
        );

        st = IERC20(stAddr);

        for (uint256 i = 0; i < userAddrs.length; i++) {
            userStake[userAddrs[i]] += userStakes[i];
            stake += userStakes[i];
        }
    }

    /**
     * @dev Harvest Token
     */
    function harvestToken() external nonReentrant {
        updatePool();

        uint256 pendingToken = (userStake[msg.sender] *
            (accTokenPerStake - userLastAccTokenPerStake[msg.sender])) / 1e18;
        uint256 amount = userStoredToken[msg.sender] + pendingToken;
        require(amount > 0, "Not enough token to harvest");

        userStoredToken[msg.sender] = 0;
        userLastAccTokenPerStake[msg.sender] = accTokenPerStake;
        userHarvestedToken[msg.sender] += amount;
        harvestedToken += amount;

        st.safeTransfer(msg.sender, amount);

        emit HarvestToken(msg.sender, amount);
    }

    /**
     * @dev Get Token Total Rewards of a User
     */
    function getTokenTotalRewards(address user)
        external
        view
        returns (uint256)
    {
        return userHarvestedToken[user] + getTokenRewards(user);
    }

    /**
     * @dev Update Pool
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 rewardsBlock = releaseEndBlock < block.number
            ? releaseEndBlock
            : releaseStartBlock +
                ((
                    block.number > releaseStartBlock
                        ? block.number - releaseStartBlock
                        : 0
                ) / blockPerQuarter) *
                blockPerQuarter;
        if (rewardsBlock > lastRewardBlock && stake > 0) {
            uint256 amount = tokenPerBlock * (rewardsBlock - lastRewardBlock);
            accTokenPerStake += (amount * 1e18) / stake;
            releasedToken += amount;
        }

        lastRewardBlock = rewardsBlock;
    }

    /**
     * @dev Get Token Rewards of a User
     */
    function getTokenRewards(address user) public view returns (uint256) {
        uint256 accTokenPerStakeTemp = accTokenPerStake;
        uint256 rewardsBlock = releaseEndBlock < block.number
            ? releaseEndBlock
            : releaseStartBlock +
                ((
                    block.number > releaseStartBlock
                        ? block.number - releaseStartBlock
                        : 0
                ) / blockPerQuarter) *
                blockPerQuarter;
        if (rewardsBlock > lastRewardBlock && stake > 0) {
            accTokenPerStakeTemp +=
                (tokenPerBlock * (rewardsBlock - lastRewardBlock) * 1e18) /
                stake;
        }

        return
            userStoredToken[user] +
            ((userStake[user] *
                (accTokenPerStakeTemp - userLastAccTokenPerStake[user])) /
                1e18);
    }
}
