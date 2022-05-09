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
    uint256 public baseRate = 10;
    uint256 public taxRate = 10;

    address public treasury;
    IPancakePair public STLP;

    struct Note {
        uint256 value;
        uint256 cursor;
        uint256 lastUpdateTime;
        uint256[12] valueArr;
    }
    Note public stPrice;
    Note[] public bondRates;
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
        uint256 usdPayout;
        uint256 expiry;
        uint256 claimTime;
    }
    mapping(address => Order[]) public orders;

    mapping(address => mapping(uint256 => uint256))
        public userMonthlyUsdPayinBeforeTax;

    event SetPriceUpdateInterval(uint256 interval);
    event SetRate(uint256 baseRate, uint256 taxRate);
    event SetAddrs(address treasury, address stlpAddr);
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
    event UpdateBondRate(
        IPancakePair lp,
        address token0,
        address token1,
        uint256 bondRate
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
    function setRate(uint256 _baseRate, uint256 _taxRate)
        external
        onlyRole(MANAGER_ROLE)
    {
        baseRate = _baseRate;
        taxRate = _taxRate;

        emit SetRate(_baseRate, _taxRate);
    }

    /**
     * @dev Set Addrs
     */
    function setAddrs(address _treasury, address stlpAddr)
        external
        onlyRole(MANAGER_ROLE)
    {
        treasury = _treasury;
        STLP = IPancakePair(stlpAddr);

        emit SetAddrs(_treasury, stlpAddr);
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
        uint256 lpAmount
    ) external payable nonReentrant {
        updateBondRate(bondId);
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

        bond(bondId, lpAmount);
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
     * @dev Update Bond Rate
     */
    function updateBondRate(uint256 bondId) public {
        Note storage note = bondRates[bondId];

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
                ((2 *
                    (token0 == BUSD || token0 == WBNB ? reserve0 : reserve1)) /
                    1e22) *
                baseRate +
                100;

            note.cursor++;
            if (note.cursor == 12) note.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < 12; i++) {
                if (note.valueArr[i] > 0) {
                    sum += note.valueArr[i];
                    count++;
                }
            }
            note.value = sum / count;

            note.lastUpdateTime = block.timestamp;

            emit UpdateBondRate(markets[bondId].LP, token0, token1, note.value);
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
            if (note.cursor == 12) note.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < 12; i++) {
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
            if (stPrice.cursor == 12) stPrice.cursor = 0;

            uint256 sum;
            uint256 count;
            for (uint256 i = 0; i < 12; i++) {
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
     * @dev Get User Tax Rate
     */
    function getUserTaxRate(address user) public view returns (uint256) {
        uint256 rate = (userMonthlyUsdPayinBeforeTax[user][
            block.timestamp / 30 days
        ] / 1e21) *
            taxRate +
            100;
        return rate > 5000 ? 5000 : rate;
    }

    /**
     * @dev Bond
     */
    function bond(uint256 bondId, uint256 lpAmount) private {
        Market storage market = markets[bondId];
        Note memory lpPrice = lpPrices[bondId];
        Note memory bondRate = bondRates[bondId];

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

        userMonthlyUsdPayinBeforeTax[msg.sender][block.timestamp / 30 days] +=
            (lpAmount * lpPrice.value) /
            1e18;

        uint256 userTaxRate = getUserTaxRate(msg.sender);
        uint256 lpAmountTax = (lpAmount * userTaxRate) / 1e4;
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

        uint256 usdPayout = (lpAmountPay *
            lpPrice.value *
            (1e4 + bondRate.value)) /
            1e18 /
            1e4;

        Order memory order = Order({
            bondId: bondId,
            lpAmount: lpAmount,
            lpPrice: lpPrice.value,
            taxRate: userTaxRate,
            bondRate: bondRate.value,
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
            order.usdPayout,
            order.expiry
        );
    }
}
