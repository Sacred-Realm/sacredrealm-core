// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "../tool/interface/IPancakePair.sol";
import "../tool/interface/IPancakeRouter.sol";
import "./interface/IInviting.sol";
import "./interface/ISTStaking.sol";

/**
 * @title Bond Depository
 * @author SEALEM-LAB
 * @notice Contract to supply Bond
 */
contract BondDepository is
    AccessControlEnumerable,
    ReentrancyGuard,
    KeeperCompatibleInterface
{
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // testnet: 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7
    address public BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    // testnet: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // testnet: 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
    IPancakeRouter public router =
        IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // testnet: 30 minutes
    uint256 public epoch = 2 weeks;

    uint256 public priceUpdateInterval = 5 minutes;

    uint256 public bondDynamicRate = 1;
    uint256 public bondBaseRate = 500;

    uint256 public inviteBuyDynamicRate = 10;
    uint256 public stakeDynamicRate = 10;
    uint256 public inviteStakeDynamicRate = 10;
    uint256 public extraMaxRate = 3000;

    uint256 public taxDynamicRate = 1;
    uint256 public taxBaseRate = 10;
    uint256 public taxMaxRate = 1000;

    address public treasury;
    IPancakePair public STLP;
    IInviting public inviting;
    ISTStaking public stStaking;

    struct Note {
        uint256 value;
        uint256 cursor;
        uint256 lastUpdateTime;
        uint256[12] valueArr;
    }
    Note public stPrice;
    Note[] public lpLiquidity;
    Note[] public lpPrices;

    struct Market {
        IPancakePair LP;
        address receivingAddr;
        uint256 maxSupplyLp;
        uint256 term;
        uint256 conclusion;
        uint256 soldLpAmount;
    }
    Market[] public markets;

    struct Order {
        uint256 bondId;
        uint256 lpAmount;
        uint256 lpPrice;
        uint256 taxRate;
        uint256 bondRate;
        uint256[4] extraRates;
        uint256 usdPayout;
        uint256 expiry;
        uint256 claimTime;
    }
    mapping(address => Order[]) public orders;

    mapping(address => mapping(uint256 => uint256))
        public userMonthlyUsdPayinBeforeTax;
    mapping(address => mapping(uint256 => uint256))
        public affiliateMonthlyUsdPayinBeforeTax;

    event SetPriceUpdateInterval(uint256 interval);
    event SetRate(
        uint256 bondDynamicRate,
        uint256 bondBaseRate,
        uint256 inviteBuyDynamicRate,
        uint256 stakeDynamicRate,
        uint256 inviteStakeDynamicRate,
        uint256 extraMaxRate,
        uint256 taxDynamicRate,
        uint256 taxBaseRate,
        uint256 taxMaxRate
    );
    event SetAddrs(
        address treasury,
        address stlpAddr,
        address invitingAddr,
        address stStakingAddr
    );
    event Create(
        uint256 bondId,
        address lpAddr,
        address receivingAddr,
        uint256 bondMaxSupplyLp,
        uint256 bondTerm,
        uint256 bondConclusion
    );
    event Bond(
        address indexed user,
        uint256 orderId,
        uint256 bondId,
        uint256 lpAmount,
        uint256 lpPrice,
        uint256 userTaxRate,
        uint256 bondRate,
        uint256[4] extraRates,
        uint256 usdPayout,
        uint256 expiry
    );
    event Claim(
        address indexed user,
        uint256[] orderIds,
        uint256 usdPayout,
        uint256 stPrice,
        uint256 stPayout
    );
    event UpdateLpLiquidity(
        IPancakePair lp,
        address token0,
        address token1,
        uint256 liquidity
    );
    event UpdateLpPrice(
        IPancakePair lp,
        address token0,
        address token1,
        uint256 lpPrice
    );
    event UpdateStPrice(
        IPancakePair stlp,
        address token0,
        address token1,
        uint256 stPrice
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Price Update Interval
     */
    function setPriceUpdateInterval(uint256 interval)
        external
        onlyRole(MANAGER_ROLE)
    {
        priceUpdateInterval = interval;

        emit SetPriceUpdateInterval(interval);
    }

    /**
     * @dev Set Rate
     */
    function setRate(
        uint256 _bondDynamicRate,
        uint256 _bondBaseRate,
        uint256 _inviteBuyDynamicRate,
        uint256 _stakeDynamicRate,
        uint256 _inviteStakeDynamicRate,
        uint256 _extraMaxRate,
        uint256 _taxDynamicRate,
        uint256 _taxBaseRate,
        uint256 _taxMaxRate
    ) external onlyRole(MANAGER_ROLE) {
        bondDynamicRate = _bondDynamicRate;
        bondBaseRate = _bondBaseRate;
        inviteBuyDynamicRate = _inviteBuyDynamicRate;
        stakeDynamicRate = _stakeDynamicRate;
        inviteStakeDynamicRate = _inviteStakeDynamicRate;
        extraMaxRate = _extraMaxRate;
        taxDynamicRate = _taxDynamicRate;
        taxBaseRate = _taxBaseRate;
        taxMaxRate = _taxMaxRate;

        emit SetRate(
            _bondDynamicRate,
            _bondBaseRate,
            _inviteBuyDynamicRate,
            _stakeDynamicRate,
            _inviteStakeDynamicRate,
            _extraMaxRate,
            _taxDynamicRate,
            _taxBaseRate,
            _taxMaxRate
        );
    }

    /**
     * @dev Set Addrs
     */
    function setAddrs(
        address _treasury,
        address stlpAddr,
        address invitingAddr,
        address stStakingAddr
    ) external onlyRole(MANAGER_ROLE) {
        treasury = _treasury;
        STLP = IPancakePair(stlpAddr);
        inviting = IInviting(invitingAddr);
        stStaking = ISTStaking(stStakingAddr);

        emit SetAddrs(_treasury, stlpAddr, invitingAddr, stStakingAddr);
    }

    /**
     * @dev Create
     */
    function create(
        address lpAddr,
        address receivingAddr,
        uint256 maxSupplyLp,
        uint256 term,
        uint256 conclusion
    ) external onlyRole(MANAGER_ROLE) {
        markets.push(
            Market({
                LP: IPancakePair(lpAddr),
                receivingAddr: receivingAddr,
                maxSupplyLp: maxSupplyLp,
                term: term,
                conclusion: conclusion,
                soldLpAmount: 0
            })
        );

        emit Create(
            markets.length - 1,
            lpAddr,
            receivingAddr,
            maxSupplyLp,
            term,
            conclusion
        );
    }

    /**
     * @dev Swap And Add Liquidity And Bond
     */
    function swapAndAddLiquidityAndBond(
        uint256 bondId,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 lpAmount,
        address inviter
    ) external payable nonReentrant {
        updateLpLiquidity(bondId);
        (address token0, address token1) = updateLpPrice(bondId);
        updateStPrice();

        if (lpAmount == 0) {
            if (token0Amount > 0 && token1Amount == 0) {
                address[] memory path = new address[](2);
                path[0] = token0;
                path[1] = token1;
                if (path[0] == WBNB) {
                    token1Amount = router.swapExactETHForTokens(
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                } else if (path[1] == WBNB) {
                    token1Amount = router.swapExactTokensForETH(
                        token0Amount /= 2,
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                } else {
                    token1Amount = router.swapExactTokensForTokens(
                        token0Amount /= 2,
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                }
            } else if (token1Amount > 0 && token0Amount == 0) {
                address[] memory path = new address[](2);
                path[0] = token1;
                path[1] = token0;
                if (path[0] == WBNB) {
                    token0Amount = router.swapExactETHForTokens(
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                } else if (path[1] == WBNB) {
                    token0Amount = router.swapExactTokensForETH(
                        token1Amount /= 2,
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                } else {
                    token0Amount = router.swapExactTokensForTokens(
                        token1Amount /= 2,
                        0,
                        path,
                        msg.sender,
                        block.timestamp
                    )[1];
                }
            }

            if (token0 == WBNB) {
                (, , lpAmount) = router.addLiquidityETH(
                    token1,
                    token1Amount,
                    0,
                    0,
                    msg.sender,
                    block.timestamp
                );
            } else if (token1 == WBNB) {
                (, , lpAmount) = router.addLiquidityETH(
                    token0,
                    token0Amount,
                    0,
                    0,
                    msg.sender,
                    block.timestamp
                );
            } else {
                (, , lpAmount) = router.addLiquidity(
                    token0,
                    token1,
                    token0Amount,
                    token1Amount,
                    0,
                    0,
                    msg.sender,
                    block.timestamp
                );
            }
        }

        bond(bondId, lpAmount, inviter);
    }

    /**
     * @dev Claim
     */
    function claim(uint256[] memory orderIds) external nonReentrant {
        (address token0, address token1) = updateStPrice();

        Order[] storage order = orders[msg.sender];
        uint256 usdPayout;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (block.timestamp >= order[i].expiry && order[i].claimTime == 0) {
                order[i].claimTime = block.timestamp;
                usdPayout += order[i].usdPayout;
            }
        }

        uint256 stPayout = (usdPayout * 1e18) / stPrice.value;

        IERC20(token0 == BUSD || token0 == WBNB ? token1 : token0).safeTransfer(
                msg.sender,
                stPayout
            );

        emit Claim(msg.sender, orderIds, usdPayout, stPrice.value, stPayout);
    }

    /**
     * @dev Perform Up Keep
     */
    function performUpkeep(bytes calldata) external override {
        updateLpLiquidity(markets.length - 1);
        updateLpPrice(markets.length - 1);
        updateStPrice();
    }

    /**
     * @dev Get Active Bonds
     */
    function getActiveBonds() external view returns (uint256[] memory) {
        uint256 length;
        for (uint256 i = 0; i < markets.length; i++) {
            if (block.timestamp < markets[i].conclusion) length++;
        }

        uint256[] memory bondIds = new uint256[](length);
        uint256 index;
        for (uint256 i = 0; i < markets.length; i++) {
            if (block.timestamp < markets[i].conclusion) {
                bondIds[index] = i;
                index++;
            }
        }

        return bondIds;
    }

    /**
     * @dev Get User Unclaimed Orders
     */
    function getUserUnclaimedOrders(address user)
        external
        view
        returns (uint256[] memory, uint256)
    {
        Order[] memory order = orders[user];

        uint256 length;
        for (uint256 i = 0; i < order.length; i++) {
            if (order[i].claimTime == 0) length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < order.length; i++) {
            if (order[i].claimTime == 0) {
                orderIds[index] = i;
                usdPayout += order[i].usdPayout;
                index++;
            }
        }

        return (orderIds, usdPayout);
    }

    /**
     * @dev Get User Claimed Orders
     */
    function getUserClaimedOrders(address user)
        external
        view
        returns (uint256[] memory, uint256)
    {
        Order[] memory order = orders[user];

        uint256 length;
        for (uint256 i = 0; i < order.length; i++) {
            if (order[i].claimTime > 0) length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < order.length; i++) {
            if (order[i].claimTime > 0) {
                orderIds[index] = i;
                usdPayout += order[i].usdPayout;
                index++;
            }
        }

        return (orderIds, usdPayout);
    }

    /**
     * @dev Get User Claimable Orders
     */
    function getUserClaimableOrders(address user)
        external
        view
        returns (uint256[] memory, uint256)
    {
        Order[] memory order = orders[user];

        uint256 length;
        for (uint256 i = 0; i < order.length; i++) {
            if (block.timestamp >= order[i].expiry && order[i].claimTime == 0)
                length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < order.length; i++) {
            if (block.timestamp >= order[i].expiry && order[i].claimTime == 0) {
                orderIds[index] = i;
                usdPayout += order[i].usdPayout;
                index++;
            }
        }

        return (orderIds, usdPayout);
    }

    /**
     * @dev Get Markets Length
     */
    function getMarketsLength() external view returns (uint256) {
        return markets.length;
    }

    /**
     * @dev Get User Orders Length
     */
    function getUserOrdersLength(address user) external view returns (uint256) {
        return orders[user].length;
    }

    /**
     * @dev Get ST Price Value Arr
     */
    function getSTPriceValueArr() external view returns (uint256[12] memory) {
        return stPrice.valueArr;
    }

    /**
     * @dev Get LP Liquidity Value Arr
     */
    function getLpLiquidityValueArr(uint256 bondId)
        external
        view
        returns (uint256[12] memory)
    {
        return lpLiquidity[bondId].valueArr;
    }

    /**
     * @dev Get LP Price Value Arr
     */
    function getLpPriceValueArr(uint256 bondId)
        external
        view
        returns (uint256[12] memory)
    {
        return lpPrices[bondId].valueArr;
    }

    /**
     * @dev Get User Order Extra Rates
     */
    function getUserOrderExtraRates(address user, uint256 orderId)
        external
        view
        returns (uint256[4] memory)
    {
        return orders[user][orderId].extraRates;
    }

    /**
     * @dev Get Basic Rate Level Info
     */
    function getBasicRateLevelInfo(uint256 bondId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentLiquidity = lpLiquidity[bondId].value;
        uint256 level = (currentLiquidity / 1e22);
        uint256 nextLevelLiquidity = (level + 1) * 1e22;
        uint256 upgradeNeededLiquidity = nextLevelLiquidity - currentLiquidity;
        uint256 progress = ((1e22 - upgradeNeededLiquidity) * 1e4) / 1e22;

        return (
            getBondRate(currentLiquidity),
            level,
            upgradeNeededLiquidity,
            progress
        );
    }

    /**
     * @dev Get User Invite Buy Rate Level Info
     */
    function getUserInviteBuyLevelInfo(address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentMonthBuyAmount = affiliateMonthlyUsdPayinBeforeTax[user][
            block.timestamp / epoch
        ];
        uint256 currentRate = getUserInviteBuyRate(user);
        uint256 level = currentRate / inviteBuyDynamicRate;
        uint256 nextLevelBuyAmount = (level + 1) * 1e21;
        uint256 upgradeNeededBuyAmount = nextLevelBuyAmount -
            currentMonthBuyAmount;
        uint256 progress;
        if (upgradeNeededBuyAmount <= 1e21) {
            progress = ((1e21 - upgradeNeededBuyAmount) * 1e4) / 1e21;
        } else {
            progress = (currentMonthBuyAmount * 1e4) / (level * 1e21);
        }

        return (currentRate, level, upgradeNeededBuyAmount, progress);
    }

    /**
     * @dev Get User Invite Stake Rate Level Info
     */
    function getUserInviteStakeLevelInfo(address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentStakeAmount = (stStaking.affiliateStakedST(user) *
            stPrice.value) / 1e18;
        uint256 currentRate = getUserInviteStakeRate(user);
        uint256 level = currentRate / inviteStakeDynamicRate;
        uint256 nextLevelStakeAmount = (level + 1) * 1e21;
        uint256 upgradeNeededStakeAmount = nextLevelStakeAmount -
            currentStakeAmount;
        uint256 progress = ((1e21 - upgradeNeededStakeAmount) * 1e4) / 1e21;

        return (currentRate, level, upgradeNeededStakeAmount, progress);
    }

    /**
     * @dev Get User Stake Rate Level Info
     */
    function getUserStakeLevelInfo(address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentStakeAmount = (stStaking.userStakedST(user) *
            stPrice.value) / 1e18;
        uint256 currentRate = getUserStakeRate(user);
        uint256 level = currentRate / stakeDynamicRate;
        uint256 nextLevelStakeAmount = (level + 1) * 1e21;
        uint256 upgradeNeededStakeAmount = nextLevelStakeAmount -
            currentStakeAmount;
        uint256 progress = ((1e21 - upgradeNeededStakeAmount) * 1e4) / 1e21;

        return (currentRate, level, upgradeNeededStakeAmount, progress);
    }

    /**
     * @dev Get Current Epoch Time
     */
    function getCurrentEpochTime() external view returns (uint256, uint256) {
        uint256 startTime = (block.timestamp / epoch) * epoch;
        uint256 endTime = startTime + epoch;
        return (startTime, endTime);
    }

    /**
     * @dev Check Up Keep
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded =
            block.timestamp >=
            lpLiquidity[markets.length - 1].lastUpdateTime +
                priceUpdateInterval ||
            block.timestamp >=
            lpPrices[markets.length - 1].lastUpdateTime + priceUpdateInterval ||
            block.timestamp >= stPrice.lastUpdateTime + priceUpdateInterval;
        performData;
    }

    /**
     * @dev Update LP Liquidity
     */
    function updateLpLiquidity(uint256 bondId) public {
        Note storage note = lpLiquidity[bondId];

        if (block.timestamp >= note.lastUpdateTime + priceUpdateInterval) {
            (address token0, address token1) = getLPTokensAddrs(
                markets[bondId].LP
            );
            (uint112 reserve0, uint112 reserve1, ) = markets[bondId]
                .LP
                .getReserves();
            if (token0 == WBNB || token1 == WBNB) {
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = BUSD;
                uint256 wbnbPrice = router.getAmountsOut(1e18, path)[1];
                if (token0 == WBNB) {
                    reserve0 = uint112((reserve0 * wbnbPrice) / 1e18);
                } else {
                    reserve1 = uint112((reserve1 * wbnbPrice) / 1e18);
                }
            }
            note.valueArr[note.cursor] =
                2 *
                (token0 == BUSD || token0 == WBNB ? reserve0 : reserve1);

            note.cursor++;
            if (note.cursor == note.valueArr.length) note.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < note.valueArr.length; i++) {
                if (note.valueArr[i] > 0) {
                    sum += note.valueArr[i];
                    count++;
                }
            }
            note.value = sum / count;

            note.lastUpdateTime = block.timestamp;

            emit UpdateLpLiquidity(
                markets[bondId].LP,
                token0,
                token1,
                note.value
            );
        }
    }

    /**
     * @dev Update Lp Price
     */
    function updateLpPrice(uint256 bondId) public returns (address, address) {
        (address token0, address token1) = getLPTokensAddrs(markets[bondId].LP);
        Note storage note = lpPrices[bondId];

        if (block.timestamp >= note.lastUpdateTime + priceUpdateInterval) {
            (uint112 reserve0, uint112 reserve1, ) = markets[bondId]
                .LP
                .getReserves();
            note.valueArr[note.cursor] =
                (2 *
                    (token0 == BUSD || token0 == WBNB ? reserve0 : reserve1) *
                    1e18) /
                markets[bondId].LP.totalSupply();
            if (token0 == WBNB || token1 == WBNB) {
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = BUSD;
                uint256 wbnbPrice = router.getAmountsOut(1e18, path)[1];
                note.valueArr[note.cursor] =
                    (note.valueArr[note.cursor] * wbnbPrice) /
                    1e18;
            }

            note.cursor++;
            if (note.cursor == note.valueArr.length) note.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < note.valueArr.length; i++) {
                if (note.valueArr[i] > 0) {
                    sum += note.valueArr[i];
                    count++;
                }
            }
            note.value = sum / count;

            note.lastUpdateTime = block.timestamp;

            emit UpdateLpPrice(markets[bondId].LP, token0, token1, note.value);
        }

        return (token0, token1);
    }

    /**
     * @dev Update ST Price
     */
    function updateStPrice() public returns (address, address) {
        (address token0, address token1) = getLPTokensAddrs(STLP);

        if (block.timestamp >= stPrice.lastUpdateTime + priceUpdateInterval) {
            if (token0 == WBNB) {
                address[] memory path = new address[](3);
                path[0] = token1;
                path[1] = WBNB;
                path[2] = BUSD;
                stPrice.valueArr[stPrice.cursor] = router.getAmountsOut(
                    1e18,
                    path
                )[2];
            } else if (token1 == WBNB) {
                address[] memory path = new address[](3);
                path[0] = token0;
                path[1] = WBNB;
                path[2] = BUSD;
                stPrice.valueArr[stPrice.cursor] = router.getAmountsOut(
                    1e18,
                    path
                )[2];
            } else if (token0 == BUSD) {
                address[] memory path = new address[](2);
                path[0] = token1;
                path[1] = BUSD;
                stPrice.valueArr[stPrice.cursor] = router.getAmountsOut(
                    1e18,
                    path
                )[1];
            } else {
                address[] memory path = new address[](2);
                path[0] = token0;
                path[1] = BUSD;
                stPrice.valueArr[stPrice.cursor] = router.getAmountsOut(
                    1e18,
                    path
                )[1];
            }

            stPrice.cursor++;
            if (stPrice.cursor == stPrice.valueArr.length) stPrice.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < stPrice.valueArr.length; i++) {
                if (stPrice.valueArr[i] > 0) {
                    sum += stPrice.valueArr[i];
                    count++;
                }
            }
            stPrice.value = sum / count;

            stPrice.lastUpdateTime = block.timestamp;

            emit UpdateStPrice(STLP, token0, token1, stPrice.value);
        }

        return (token0, token1);
    }

    /**
     * @dev Get Bond Left Supply LP
     */
    function getBondLeftSupplyLp(uint256 bondId) public view returns (uint256) {
        return markets[bondId].maxSupplyLp - markets[bondId].soldLpAmount;
    }

    /**
     * @dev Get Bond Max Size
     */
    function getBondMaxSize(uint256 bondId) public view returns (uint256) {
        return
            (markets[bondId].maxSupplyLp * 1 days) /
            (markets[bondId].conclusion - block.timestamp);
    }

    /**
     * @dev Get LP Tokens Addrs
     */
    function getLPTokensAddrs(IPancakePair lp)
        public
        view
        returns (address, address)
    {
        return (lp.token0(), lp.token1());
    }

    /**
     * @dev Get Bond Rate
     */
    function getBondRate(uint256 liquidity) public view returns (uint256) {
        return (liquidity / 1e22) * bondDynamicRate + bondBaseRate;
    }

    /**
     * @dev Get User Invite Buy Rate
     */
    function getUserInviteBuyRate(address user) public view returns (uint256) {
        uint256 lastMonthrate = (affiliateMonthlyUsdPayinBeforeTax[user][
            (block.timestamp - epoch) / epoch
        ] / 1e21) * inviteBuyDynamicRate;
        uint256 currentMonthrate = (affiliateMonthlyUsdPayinBeforeTax[user][
            block.timestamp / epoch
        ] / 1e21) * inviteBuyDynamicRate;
        return
            lastMonthrate > currentMonthrate ? lastMonthrate : currentMonthrate;
    }

    /**
     * @dev Get User Invite Stake Rate
     */
    function getUserInviteStakeRate(address user)
        public
        view
        returns (uint256)
    {
        return
            ((stStaking.affiliateStakedST(user) * stPrice.value) /
                1e18 /
                1e21) * inviteStakeDynamicRate;
    }

    /**
     * @dev Get User Stake Rate
     */
    function getUserStakeRate(address user) public view returns (uint256) {
        return
            ((stStaking.userStakedST(user) * stPrice.value) / 1e18 / 1e21) *
            stakeDynamicRate;
    }

    /**
     * @dev Get User Extra Rates
     */
    function getUserExtraRates(address user)
        public
        view
        returns (uint256[4] memory)
    {
        uint256[4] memory rates;

        rates[0] = getUserInviteBuyRate(user);
        rates[1] = getUserInviteStakeRate(user);
        rates[2] = getUserStakeRate(user);

        rates[3] = rates[0] + rates[1] + rates[2];
        rates[3] = rates[3] > extraMaxRate ? extraMaxRate : rates[3];

        return rates;
    }

    /**
     * @dev Get User Tax Rate
     */
    function getUserTaxRate(address user) public view returns (uint256) {
        uint256 rate = (userMonthlyUsdPayinBeforeTax[user][
            block.timestamp / epoch
        ] / 1e21) *
            taxDynamicRate +
            taxBaseRate;
        return rate > taxMaxRate ? taxMaxRate : rate;
    }

    /**
     * @dev Bond
     */
    function bond(
        uint256 bondId,
        uint256 lpAmount,
        address inviter
    ) private {
        Market storage market = markets[bondId];
        uint256 lpPrice = lpPrices[bondId].value;

        require(lpAmount > 0, "LP Amount must > 0");
        require(
            getBondLeftSupplyLp(bondId) >= lpAmount,
            "Not enough bond LP supply"
        );
        require(
            market.receivingAddr != address(0),
            "The receiving address of this bond has not been set"
        );
        require(market.term > 0, "The term of this bond has not been set");
        require(block.timestamp < market.conclusion, "Bond concluded");
        require(lpAmount <= getBondMaxSize(bondId), "Max size exceeded");

        uint256 UsdPayinBeforeTax = (lpAmount * lpPrice) / 1e18;
        userMonthlyUsdPayinBeforeTax[msg.sender][
            block.timestamp / epoch
        ] += UsdPayinBeforeTax;

        address userInviter = inviting.bindInviter(inviter);
        if (userInviter != address(0)) {
            affiliateMonthlyUsdPayinBeforeTax[userInviter][
                block.timestamp / epoch
            ] += UsdPayinBeforeTax;
        }

        uint256 taxRate = getUserTaxRate(msg.sender);
        uint256 lpAmountTax = (lpAmount * taxRate) / 1e4;
        uint256 lpAmountPay = lpAmount - lpAmountTax;

        IERC20(address(market.LP)).safeTransferFrom(
            msg.sender,
            treasury,
            lpAmountTax
        );
        IERC20(address(market.LP)).safeTransferFrom(
            msg.sender,
            market.receivingAddr,
            lpAmountPay
        );

        uint256 bondRate = getBondRate(lpLiquidity[bondId].value);
        uint256[4] memory extraRates = getUserExtraRates(msg.sender);
        uint256 usdPayout = (lpAmountPay *
            lpPrice *
            (1e4 + bondRate + extraRates[3])) /
            1e18 /
            1e4;

        Order memory order = Order({
            bondId: bondId,
            lpAmount: lpAmount,
            lpPrice: lpPrice,
            taxRate: taxRate,
            bondRate: bondRate,
            extraRates: extraRates,
            usdPayout: usdPayout,
            expiry: market.term + block.timestamp,
            claimTime: 0
        });
        orders[msg.sender].push(order);

        market.soldLpAmount += lpAmount;

        emit Bond(
            msg.sender,
            orders[msg.sender].length - 1,
            order.bondId,
            order.lpAmount,
            order.lpPrice,
            order.taxRate,
            order.bondRate,
            order.extraRates,
            order.usdPayout,
            order.expiry
        );
    }
}
