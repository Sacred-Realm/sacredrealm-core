// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tool/interface/IPancakePair.sol";
import "../tool/interface/IPancakeRouter.sol";

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

    uint256 public priceUpdateInterval = 5 minutes;

    IPancakePair public STLP;
    uint256 public stPrice;
    uint256 public stPriceCursor;
    uint256 public stPriceLastUpdateTime;
    uint256[12] public stPriceArr;

    uint256 public bondCount;
    mapping(uint256 => IPancakePair) public LP;
    mapping(uint256 => address) public receivingAddr;
    mapping(uint256 => uint256) public bondMaxSupplyLp;
    mapping(uint256 => uint256) public bondRate;
    mapping(uint256 => uint256) public bondTerm;
    mapping(uint256 => uint256) public bondConclusion;

    mapping(uint256 => uint256) public lpPrice;
    mapping(uint256 => uint256) public lpPriceCursor;
    mapping(uint256 => uint256) public lpPriceLastUpdateTime;
    mapping(uint256 => uint256[12]) public lpPriceArr;
    mapping(uint256 => uint256) public bondSoldLpAmount;

    mapping(address => uint256) public userOrderCount;
    mapping(address => mapping(uint256 => uint256)) public userOrderBondId;
    mapping(address => mapping(uint256 => uint256)) public userOrderLpAmount;
    mapping(address => mapping(uint256 => uint256)) public userOrderUsdPayout;
    mapping(address => mapping(uint256 => uint256)) public userOrderExpiry;
    mapping(address => mapping(uint256 => uint256)) public userOrderClaimTime;

    event SetPriceUpdateInterval(uint256 interval);
    event SetSTLP(address stlpAddr);
    event CreateBond(
        uint256 bondId,
        address lpAddr,
        address receivingAddr,
        uint256 bondMaxSupplyLp,
        uint256 bondRate,
        uint256 bondTerm,
        uint256 bondConclusion
    );
    event Bond(
        address indexed user,
        uint256 bondId,
        uint256 orderId,
        uint256 lpAmount,
        uint256 lpPrice,
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
     * @dev Set ST LP
     */
    function setSTLP(address stlpAddr) external onlyRole(MANAGER_ROLE) {
        STLP = IPancakePair(stlpAddr);

        emit SetSTLP(stlpAddr);
    }

    /**
     * @dev Create Bond
     */
    function createBond(
        address lpAddr,
        address _receivingAddr,
        uint256 _bondMaxSupplyLp,
        uint256 _bondRate,
        uint256 _bondTerm,
        uint256 _bondConclusion
    ) external onlyRole(MANAGER_ROLE) {
        LP[bondCount] = IPancakePair(lpAddr);
        receivingAddr[bondCount] = _receivingAddr;
        bondMaxSupplyLp[bondCount] = _bondMaxSupplyLp;
        bondRate[bondCount] = _bondRate;
        bondTerm[bondCount] = _bondTerm;
        bondConclusion[bondCount] = _bondConclusion;

        emit CreateBond(
            bondCount,
            lpAddr,
            _receivingAddr,
            _bondMaxSupplyLp,
            _bondRate,
            _bondTerm,
            _bondConclusion
        );

        bondCount++;
    }

    /**
     * @dev Bond
     */
    function bond(
        uint256 bondId,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 lpAmount
    ) external payable nonReentrant {
        (address token0, address token1) = updateLpPrice(bondId);

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

        require(lpAmount > 0, "LP Amount must > 0");
        require(
            getBondLeftSupplyLp(bondId) >= lpAmount,
            "Not enough bond LP supply"
        );
        require(
            receivingAddr[bondId] != address(0),
            "The receiving address of this bond has not been set"
        );
        require(bondRate[bondId] > 0, "The rate of this bond has not been set");
        require(bondTerm[bondId] > 0, "The term of this bond has not been set");
        require(block.timestamp < bondConclusion[bondId], "Bond concluded");
        require(lpAmount <= getBondMaxSize(bondId), "Max size exceeded");

        IERC20(address(LP[bondId])).safeTransferFrom(
            msg.sender,
            receivingAddr[bondId],
            lpAmount
        );

        uint256 expiry = bondTerm[bondId] + block.timestamp;
        uint256 usdPayout = (lpPrice[bondId] * lpAmount * bondRate[bondId]) /
            1e18 /
            1e4;

        userOrderBondId[msg.sender][userOrderCount[msg.sender]] = bondId;
        userOrderLpAmount[msg.sender][userOrderCount[msg.sender]] = lpAmount;
        userOrderUsdPayout[msg.sender][userOrderCount[msg.sender]] = usdPayout;
        userOrderExpiry[msg.sender][userOrderCount[msg.sender]] = expiry;

        bondSoldLpAmount[bondId] += lpAmount;

        emit Bond(
            msg.sender,
            bondId,
            userOrderCount[msg.sender],
            lpAmount,
            lpPrice[bondId],
            usdPayout,
            expiry
        );

        userOrderCount[msg.sender]++;
    }

    /**
     * @dev Claim
     */
    function claim(uint256[] memory orderIds) external nonReentrant {
        (address token0, address token1) = updateStPrice();

        uint256 usdPayout;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (
                block.timestamp >= userOrderExpiry[msg.sender][orderIds[i]] &&
                userOrderClaimTime[msg.sender][orderIds[i]] == 0
            ) {
                userOrderClaimTime[msg.sender][orderIds[i]] = block.timestamp;
                usdPayout += userOrderUsdPayout[msg.sender][orderIds[i]];
            }
        }

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
        for (uint256 i = 0; i < bondCount; i++) {
            if (block.timestamp < bondConclusion[i]) length++;
        }

        uint256[] memory bondIds = new uint256[](length);
        uint256 index;
        for (uint256 i = 0; i < bondCount; i++) {
            if (block.timestamp < bondConclusion[i]) {
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
        uint256 length;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (userOrderClaimTime[user][i] == 0) length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (userOrderClaimTime[user][i] == 0) {
                orderIds[index] = i;
                usdPayout += userOrderUsdPayout[user][i];
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
        uint256 length;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (userOrderClaimTime[user][i] > 0) length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (userOrderClaimTime[user][i] > 0) {
                orderIds[index] = i;
                usdPayout += userOrderUsdPayout[user][i];
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
        uint256 length;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (
                block.timestamp >= userOrderExpiry[user][i] &&
                userOrderClaimTime[user][i] == 0
            ) length++;
        }

        uint256[] memory orderIds = new uint256[](length);
        uint256 usdPayout;
        uint256 index;
        for (uint256 i = 0; i < userOrderCount[user]; i++) {
            if (
                block.timestamp >= userOrderExpiry[user][i] &&
                userOrderClaimTime[user][i] == 0
            ) {
                orderIds[index] = i;
                usdPayout += userOrderUsdPayout[user][i];
                index++;
            }
        }

        return (orderIds, usdPayout);
    }

    /**
     * @dev Update Lp Price
     */
    function updateLpPrice(uint256 bondId) public returns (address, address) {
        (address token0, address token1) = getLPTokensAddrs(LP[bondId]);

        if (
            block.timestamp >=
            lpPriceLastUpdateTime[bondId] + priceUpdateInterval
        ) {
            (uint112 reserve0, uint112 reserve1, ) = LP[bondId].getReserves();
            lpPriceArr[bondId][lpPriceCursor[bondId]] =
                (2 *
                    (token0 == BUSD || token0 == WBNB ? reserve0 : reserve1) *
                    1e18) /
                LP[bondId].totalSupply();
            if (token0 == WBNB || token1 == WBNB) {
                address[] memory path = new address[](2);
                path[0] = WBNB;
                path[1] = BUSD;
                uint256 wbnbPrice = router.getAmountsOut(1e18, path)[1];
                lpPriceArr[bondId][lpPriceCursor[bondId]] =
                    (lpPriceArr[bondId][lpPriceCursor[bondId]] * wbnbPrice) /
                    1e18;
            }

            lpPriceCursor[bondId]++;
            if (lpPriceCursor[bondId] == 12) lpPriceCursor[bondId] = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < 10; i++) {
                if (lpPriceArr[bondId][i] > 0) {
                    sum += lpPriceArr[bondId][i];
                    count++;
                }
            }
            lpPrice[bondId] = sum / count;

            lpPriceLastUpdateTime[bondId] = block.timestamp;
        }

        emit UpdateLpPrice(LP[bondId], token0, token1, lpPrice[bondId]);

        return (token0, token1);
    }

    /**
     * @dev Update ST Price
     */
    function updateStPrice() public returns (address, address) {
        (address token0, address token1) = getLPTokensAddrs(STLP);

        if (block.timestamp >= stPriceLastUpdateTime + priceUpdateInterval) {
            if (token0 == WBNB) {
                address[] memory path = new address[](3);
                path[0] = token1;
                path[1] = WBNB;
                path[2] = BUSD;
                stPriceArr[stPriceCursor] = router.getAmountsOut(1e18, path)[2];
            } else if (token1 == WBNB) {
                address[] memory path = new address[](3);
                path[0] = token0;
                path[1] = WBNB;
                path[2] = BUSD;
                stPriceArr[stPriceCursor] = router.getAmountsOut(1e18, path)[2];
            } else if (token0 == BUSD) {
                address[] memory path = new address[](2);
                path[0] = token1;
                path[1] = BUSD;
                stPriceArr[stPriceCursor] = router.getAmountsOut(1e18, path)[1];
            } else {
                address[] memory path = new address[](2);
                path[0] = token0;
                path[1] = BUSD;
                stPriceArr[stPriceCursor] = router.getAmountsOut(1e18, path)[1];
            }

            stPriceCursor++;
            if (stPriceCursor == 12) stPriceCursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < 10; i++) {
                if (stPriceArr[i] > 0) {
                    sum += stPriceArr[i];
                    count++;
                }
            }
            stPrice = sum / count;

            stPriceLastUpdateTime = block.timestamp;
        }

        emit UpdateStPrice(STLP, token0, token1, stPrice);

        return (token0, token1);
    }

    /**
     * @dev Get Bond Left Supply LP
     */
    function getBondLeftSupplyLp(uint256 bondId) public view returns (uint256) {
        return bondMaxSupplyLp[bondId] - bondSoldLpAmount[bondId];
    }

    /**
     * @dev Get Bond Max Size
     */
    function getBondMaxSize(uint256 bondId) public view returns (uint256) {
        return
            (bondMaxSupplyLp[bondId] * 1 days) /
            (bondConclusion[bondId] - block.timestamp);
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
}
