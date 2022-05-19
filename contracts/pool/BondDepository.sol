// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tool/interface/IPancakePair.sol";
import "../tool/interface/IPancakeRouter.sol";
import "./interface/IInviting.sol";
import "./interface/ISTStaking.sol";

/**
 * @title Bond Depository
 * @author SEALEM-LAB
 * @notice Contract to supply Bond
 */
contract BondDepository is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // testnet: 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7
    address public BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    // testnet: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // testnet: 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
    IPancakeRouter public router =
        IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    uint256 public bondDynamicRate = 1;
    uint256 public bondBaseRate = 500;

    uint256 public inviteBuyDynamicRate = 10;
    uint256 public inviteStakeDynamicRate = 10;
    uint256 public stakeDynamicRate = 10;
    uint256 public extraMaxRate = 3000;

    uint256 public taxDynamicRate = 1;
    uint256 public taxBaseRate = 10;
    uint256 public taxMaxRate = 1000;

    address public treasury;
    IPancakePair public STLP;
    IInviting public inviting;
    ISTStaking public stStaking;

    struct Market {
        IPancakePair LP;
        address receivingAddr;
        uint256 maxSupplyLp;
        uint256 userMaxLpBuyAmount;
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
        public userEpochUsdPayinBeforeTax;
    mapping(address => mapping(uint256 => uint256))
        public affiliateEpochUsdPayinBeforeTax;
    mapping(address => mapping(uint256 => uint256)) public userEpochLpBuyAmount;

    mapping(address => bool) public isBlackListed;

    event SetRate(
        uint256 bondDynamicRate,
        uint256 bondBaseRate,
        uint256 inviteBuyDynamicRate,
        uint256 inviteStakeDynamicRate,
        uint256 stakeDynamicRate,
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
        uint256 userMaxLpBuyAmount,
        uint256 bondTerm,
        uint256 bondConclusion
    );
    event CloseBond(uint256 bondId);
    event SetBlackList(address[] users, bool isBlackListed);
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

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Rate
     */
    function setRate(
        uint256 _bondDynamicRate,
        uint256 _bondBaseRate,
        uint256 _inviteBuyDynamicRate,
        uint256 _inviteStakeDynamicRate,
        uint256 _stakeDynamicRate,
        uint256 _extraMaxRate,
        uint256 _taxDynamicRate,
        uint256 _taxBaseRate,
        uint256 _taxMaxRate
    ) external onlyRole(MANAGER_ROLE) {
        require(_taxMaxRate <= 5000, "The tax max rate cannot exceed 50%");

        bondDynamicRate = _bondDynamicRate;
        bondBaseRate = _bondBaseRate;
        inviteBuyDynamicRate = _inviteBuyDynamicRate;
        inviteStakeDynamicRate = _inviteStakeDynamicRate;
        stakeDynamicRate = _stakeDynamicRate;
        extraMaxRate = _extraMaxRate;
        taxDynamicRate = _taxDynamicRate;
        taxBaseRate = _taxBaseRate;
        taxMaxRate = _taxMaxRate;

        emit SetRate(
            _bondDynamicRate,
            _bondBaseRate,
            _inviteBuyDynamicRate,
            _inviteStakeDynamicRate,
            _stakeDynamicRate,
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
        uint256 userMaxLpBuyAmount,
        uint256 term,
        uint256 conclusion
    ) external onlyRole(MANAGER_ROLE) {
        markets.push(
            Market({
                LP: IPancakePair(lpAddr),
                receivingAddr: receivingAddr,
                maxSupplyLp: maxSupplyLp,
                userMaxLpBuyAmount: userMaxLpBuyAmount,
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
            userMaxLpBuyAmount,
            term,
            conclusion
        );
    }

    /**
     * @dev Close Bond
     */
    function closeBond(uint256 bondId) external onlyRole(MANAGER_ROLE) {
        markets[bondId].conclusion = block.timestamp;

        emit CloseBond(bondId);
    }

    /**
     * @dev Set Black List
     */
    function setBlackList(address[] memory users, bool _isBlackListed)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < users.length; i++) {
            isBlackListed[users[i]] = _isBlackListed;
        }

        emit SetBlackList(users, _isBlackListed);
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
        (address token0, address token1) = getLPTokensAddrs(markets[bondId].LP);

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
        require(!isBlackListed[msg.sender], "This account is abnormal");

        (address token0, address token1) = getLPTokensAddrs(STLP);

        Order[] storage order = orders[msg.sender];
        uint256 usdPayout;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (
                block.timestamp >= order[orderIds[i]].expiry &&
                order[orderIds[i]].claimTime == 0
            ) {
                order[orderIds[i]].claimTime = block.timestamp;
                usdPayout += order[orderIds[i]].usdPayout;
            }
        }

        uint256 stPrice = getStPrice();
        uint256 stPayout = (usdPayout * 1e18) / stPrice;

        IERC20(token0 == BUSD || token0 == WBNB ? token1 : token0).safeTransfer(
                msg.sender,
                stPayout
            );

        emit Claim(msg.sender, orderIds, usdPayout, stPrice, stPayout);
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
        uint256 currentLiquidity = getLpLiquidity(bondId);
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
    function getUserInviteBuyLevelInfo(address user, uint256 bondId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentEpochBuyAmount = affiliateEpochUsdPayinBeforeTax[user][
            bondId
        ];
        uint256 currentRate = getUserInviteBuyRate(user, bondId);
        uint256 level = currentRate / inviteBuyDynamicRate;
        uint256 nextLevelBuyAmount = (level + 1) * 1e21;
        uint256 upgradeNeededBuyAmount = nextLevelBuyAmount -
            currentEpochBuyAmount;
        uint256 progress = ((1e21 - upgradeNeededBuyAmount) * 1e4) / 1e21;

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
            getStPrice()) / 1e18;
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
            getStPrice()) / 1e18;
        uint256 currentRate = getUserStakeRate(user);
        uint256 level = currentRate / stakeDynamicRate;
        uint256 nextLevelStakeAmount = (level + 1) * 1e21;
        uint256 upgradeNeededStakeAmount = nextLevelStakeAmount -
            currentStakeAmount;
        uint256 progress = ((1e21 - upgradeNeededStakeAmount) * 1e4) / 1e21;

        return (currentRate, level, upgradeNeededStakeAmount, progress);
    }

    /**
     * @dev Get LP Liquidity
     */
    function getLpLiquidity(uint256 bondId) public view returns (uint256) {
        (address token0, address token1) = getLPTokensAddrs(markets[bondId].LP);
        (uint256 reserve0, uint256 reserve1, ) = markets[bondId]
            .LP
            .getReserves();

        if (token0 == WBNB || token1 == WBNB) {
            address[] memory path = new address[](2);
            path[0] = WBNB;
            path[1] = BUSD;
            uint256 wbnbPrice = router.getAmountsOut(1e18, path)[1];
            if (token0 == WBNB) {
                reserve0 = (reserve0 * wbnbPrice) / 1e18;
            } else {
                reserve1 = (reserve1 * wbnbPrice) / 1e18;
            }
        }

        return 2 * (token0 == BUSD || token0 == WBNB ? reserve0 : reserve1);
    }

    /**
     * @dev Get Lp Price
     */
    function getLpPrice(uint256 bondId) public view returns (uint256) {
        return
            (getLpLiquidity(bondId) * 1e18) / markets[bondId].LP.totalSupply();
    }

    /**
     * @dev Get ST Price
     */
    function getStPrice() public view returns (uint256) {
        (address token0, address token1) = getLPTokensAddrs(STLP);

        if (token0 == WBNB) {
            address[] memory path = new address[](3);
            path[0] = token1;
            path[1] = WBNB;
            path[2] = BUSD;
            return router.getAmountsOut(1e18, path)[2];
        } else if (token1 == WBNB) {
            address[] memory path = new address[](3);
            path[0] = token0;
            path[1] = WBNB;
            path[2] = BUSD;
            return router.getAmountsOut(1e18, path)[2];
        } else if (token0 == BUSD) {
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = BUSD;
            return router.getAmountsOut(1e18, path)[1];
        } else {
            address[] memory path = new address[](2);
            path[0] = token0;
            path[1] = BUSD;
            return router.getAmountsOut(1e18, path)[1];
        }
    }

    /**
     * @dev Get Bond Left Supply LP
     */
    function getBondLeftSupplyLp(uint256 bondId) public view returns (uint256) {
        return markets[bondId].maxSupplyLp - markets[bondId].soldLpAmount;
    }

    /**
     * @dev Get User Left Lp Can Buy
     */
    function getUserLeftLpCanBuy(address user, uint256 bondId)
        public
        view
        returns (uint256)
    {
        return
            markets[bondId].userMaxLpBuyAmount -
            userEpochLpBuyAmount[user][bondId];
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
    function getUserInviteBuyRate(address user, uint256 bondId)
        public
        view
        returns (uint256)
    {
        return
            (affiliateEpochUsdPayinBeforeTax[user][bondId] / 1e21) *
            inviteBuyDynamicRate;
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
            ((stStaking.affiliateStakedST(user) * getStPrice()) / 1e18 / 1e21) *
            inviteStakeDynamicRate;
    }

    /**
     * @dev Get User Stake Rate
     */
    function getUserStakeRate(address user) public view returns (uint256) {
        return
            ((stStaking.userStakedST(user) * getStPrice()) / 1e18 / 1e21) *
            stakeDynamicRate;
    }

    /**
     * @dev Get User Extra Rates
     */
    function getUserExtraRates(address user, uint256 bondId)
        public
        view
        returns (uint256[4] memory)
    {
        uint256[4] memory rates;

        rates[0] = getUserInviteBuyRate(user, bondId);
        rates[1] = getUserInviteStakeRate(user);
        rates[2] = getUserStakeRate(user);

        rates[3] = rates[0] + rates[1] + rates[2];
        rates[3] = rates[3] > extraMaxRate ? extraMaxRate : rates[3];

        return rates;
    }

    /**
     * @dev Get User Tax Rate
     */
    function getUserTaxRate(address user, uint256 bondId)
        public
        view
        returns (uint256)
    {
        uint256 rate = (userEpochUsdPayinBeforeTax[user][bondId] / 1e21) *
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
        require(lpAmount > 0, "LP Amount must > 0");
        require(getBondLeftSupplyLp(bondId) > 0, "Not enough bond LP supply");
        if (lpAmount > getBondLeftSupplyLp(bondId))
            lpAmount = getBondLeftSupplyLp(bondId);
        require(
            getUserLeftLpCanBuy(msg.sender, bondId) > 0,
            "User's purchase reaches the limit"
        );
        if (lpAmount > getUserLeftLpCanBuy(msg.sender, bondId))
            lpAmount = getUserLeftLpCanBuy(msg.sender, bondId);
        require(
            markets[bondId].receivingAddr != address(0),
            "The receiving address of this bond has not been set"
        );
        require(
            markets[bondId].term > 0,
            "The term of this bond has not been set"
        );
        require(block.timestamp < markets[bondId].conclusion, "Bond concluded");

        Market storage market = markets[bondId];
        uint256 lpPrice = getLpPrice(bondId);

        uint256 UsdPayinBeforeTax = (lpAmount * lpPrice) / 1e18;
        userEpochUsdPayinBeforeTax[msg.sender][bondId] += UsdPayinBeforeTax;

        address userInviter = inviting.bindInviter(inviter);
        if (userInviter != address(0)) {
            affiliateEpochUsdPayinBeforeTax[userInviter][
                bondId
            ] += UsdPayinBeforeTax;
        }

        uint256 taxRate = getUserTaxRate(msg.sender, bondId);
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

        uint256 bondRate = getBondRate(getLpLiquidity(bondId));
        uint256[4] memory extraRates = getUserExtraRates(msg.sender, bondId);
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
        updateUserBuyAmount(msg.sender, bondId, lpAmount);

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

    /**
     * @dev Update User Buy Amount
     */
    function updateUserBuyAmount(
        address user,
        uint256 bondId,
        uint256 lpAmount
    ) private {
        userEpochLpBuyAmount[user][bondId] += lpAmount;
    }
}
