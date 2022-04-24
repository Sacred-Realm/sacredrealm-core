// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "../token/interface/ISN.sol";

/**
 * @title Sacred Realm Box
 * @author SEALEM-LAB
 * @notice Contract to supply SB
 */
contract SB is
    ERC721Enumerable,
    AccessControlEnumerable,
    ReentrancyGuard,
    VRFConsumerBaseV2
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    VRFCoordinatorV2Interface public COORDINATOR;
    LinkTokenInterface public LINKTOKEN;

    // testnet: 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f
    address public vrfCoordinator = 0xc587d9053cd1118f25F645F9E08BB98c9712A4EE;

    // testnet: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06
    address public link_token_contract =
        0x404460C6A5EdE2D891e8297795264fDe62ADBB75;

    // testnet: 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314
    bytes32 public keyHash =
        0x114f3da0a805b6a67d6e9cd2ec746f7028f1b7376365af575cfea3550dd1aa04;

    uint32 public callbackGasLimit = 200000;
    uint16 public requestConfirmations = 3;

    uint64 public subscriptionId;
    mapping(uint256 => address) public requestIdToUser;
    mapping(uint256 => uint256[]) public requestIdToSbIds;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    ISN public sn;

    string public baseURI;

    mapping(uint256 => uint256) public sbIdToType;

    mapping(uint256 => uint256) public boxTokenPrices;
    mapping(uint256 => address) public tokenAddrs;
    mapping(uint256 => address) public receivingAddrs;
    mapping(uint256 => uint256) public hourlyBuyLimits;
    mapping(uint256 => bool) public whiteListFlags;
    mapping(uint256 => uint256[]) public starProbabilities;
    mapping(uint256 => uint256[]) public powerProbabilities;
    mapping(uint256 => uint256[]) public placeProbabilities;

    mapping(uint256 => uint256) public boxesMaxSupply;
    mapping(uint256 => uint256) public totalBoxesLength;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        public userHourlyBoxesLength;
    mapping(uint256 => EnumerableSet.AddressSet) private whiteList;

    event SetBaseURI(string uri);
    event SetSN(address snAddr);
    event SetVrfInfo(
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    );
    event SetBoxInfo(
        uint256 boxType,
        uint256 boxTokenPrice,
        address tokenAddr,
        address receivingAddr,
        uint256 hourlyBuylimit,
        bool whiteListFlag,
        uint256[] starProbability,
        uint256[] powerProbability,
        uint256[] placeProbability
    );
    event AddBoxesMaxSupply(uint256 supply, uint256 boxType);
    event AddWhiteList(uint256 boxType, address[] whiteUsers);
    event RemoveWhiteList(uint256 boxType, address[] whiteUsers);
    event BuyBoxes(address indexed user, uint256 amount, uint256 boxType);
    event OpenBoxes(address indexed user, uint256 amount);
    event SpawnSns(
        address indexed user,
        uint256 amount,
        uint256[] snIds,
        uint256[] boxTypes,
        uint256[][] attr
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager)
        ERC721("Sacred Realm Box", "SB")
        VRFConsumerBaseV2(vrfCoordinator)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(link_token_contract);
        subscriptionId = COORDINATOR.createSubscription();
        COORDINATOR.addConsumer(subscriptionId, address(this));
    }

    /**
     * @dev Allows the manager to set the base URI to be used for all token IDs
     */
    function setBaseURI(string memory uri) external onlyRole(MANAGER_ROLE) {
        baseURI = uri;

        emit SetBaseURI(uri);
    }

    /**
     * @dev Set SN Address
     */
    function setSN(address snAddr) external onlyRole(MANAGER_ROLE) {
        sn = ISN(snAddr);

        emit SetSN(snAddr);
    }

    /**
     * @dev Set VRF Info
     */
    function setVrfInfo(
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyRole(MANAGER_ROLE) {
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;

        emit SetVrfInfo(_keyHash, _callbackGasLimit, _requestConfirmations);
    }

    /**
     * @dev Set Box Info
     */
    function setBoxInfo(
        uint256 boxType,
        uint256 boxTokenPrice,
        address tokenAddr,
        address receivingAddr,
        uint256 hourlyBuyLimit,
        bool whiteListFlag,
        uint256[] memory starProbability,
        uint256[] memory powerProbability,
        uint256[] memory placeProbability
    ) external onlyRole(MANAGER_ROLE) {
        boxTokenPrices[boxType] = boxTokenPrice;
        tokenAddrs[boxType] = tokenAddr;
        receivingAddrs[boxType] = receivingAddr;
        hourlyBuyLimits[boxType] = hourlyBuyLimit;
        whiteListFlags[boxType] = whiteListFlag;
        starProbabilities[boxType] = starProbability;
        powerProbabilities[boxType] = powerProbability;
        placeProbabilities[boxType] = placeProbability;

        emit SetBoxInfo(
            boxType,
            boxTokenPrice,
            tokenAddr,
            receivingAddr,
            hourlyBuyLimit,
            whiteListFlag,
            starProbability,
            powerProbability,
            placeProbability
        );
    }

    /**
     * @dev Add Boxes Max Supply
     */
    function addBoxesMaxSupply(uint256 supply, uint256 boxType)
        external
        onlyRole(MANAGER_ROLE)
    {
        boxesMaxSupply[boxType] += supply;

        emit AddBoxesMaxSupply(supply, boxType);
    }

    /**
     * @dev Add White List
     */
    function addWhiteList(uint256 boxType, address[] memory whiteUsers)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < whiteUsers.length; i++) {
            whiteList[boxType].add(whiteUsers[i]);
        }

        emit AddWhiteList(boxType, whiteUsers);
    }

    /**
     * @dev Remove White List
     */
    function removeWhiteList(uint256 boxType, address[] memory whiteUsers)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < whiteUsers.length; i++) {
            whiteList[boxType].remove(whiteUsers[i]);
        }

        emit RemoveWhiteList(boxType, whiteUsers);
    }

    /**
     * @dev Assumes this contract owns link
     */
    function topUpSubscription(uint256 amount) external onlyRole(MANAGER_ROLE) {
        LINKTOKEN.transferAndCall(
            address(COORDINATOR),
            amount,
            abi.encode(subscriptionId)
        );
    }

    /**
     * @dev Users buy the boxes
     */
    function buyBoxes(uint256 amount, uint256 boxType)
        external
        payable
        nonReentrant
    {
        require(amount > 0, "Amount must > 0");
        require(
            getUserHourlyBoxesLeftSupply(
                boxType,
                msg.sender,
                block.timestamp
            ) >= amount,
            "Amount exceeds the hourly buy limit"
        );
        require(
            getBoxesLeftSupply(boxType) >= amount,
            "Not enough boxes supply"
        );
        require(
            boxTokenPrices[boxType] > 0,
            "The box price of this box has not been set"
        );
        require(
            receivingAddrs[boxType] != address(0),
            "The receiving address of this box has not been set"
        );
        require(
            starProbabilities[boxType].length == 11,
            "The star probability of this box has not been set"
        );
        require(
            powerProbabilities[boxType].length == 5,
            "The power probability of this box has not been set"
        );
        require(
            placeProbabilities[boxType].length == 8,
            "The place probability of this box has not been set"
        );
        if (whiteListFlags[boxType]) {
            require(
                whiteList[boxType].contains(msg.sender),
                "Your address must be on the whitelist"
            );
        }

        uint256 price = amount * boxTokenPrices[boxType];
        if (tokenAddrs[boxType] == address(0)) {
            require(msg.value == price, "Price mismatch");
            payable(receivingAddrs[boxType]).transfer(price);
        } else {
            IERC20 token = IERC20(tokenAddrs[boxType]);
            token.safeTransferFrom(msg.sender, receivingAddrs[boxType], price);
        }

        for (uint256 i = 0; i < amount; i++) {
            sbIdToType[totalSupply()] = boxType;
            _safeMint(msg.sender, totalSupply());
        }

        userHourlyBoxesLength[msg.sender][boxType][
            block.timestamp / 3600
        ] += amount;
        totalBoxesLength[boxType] += amount;

        emit BuyBoxes(msg.sender, amount, boxType);
    }

    /**
     * @dev Users open the boxes
     */
    function openBoxes(uint256[] memory sbIds) external nonReentrant {
        require(sbIds.length > 0, "Amount must > 0");

        for (uint256 i = 0; i < sbIds.length; i++) {
            safeTransferFrom(
                msg.sender,
                0x0000000000000000000000000000000000000020,
                sbIds[i]
            );
        }

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            uint32(sbIds.length)
        );
        requestIdToUser[requestId] = msg.sender;
        requestIdToSbIds[requestId] = sbIds;

        emit OpenBoxes(msg.sender, sbIds.length);
    }

    /**
     * @dev Safe Transfer From Batch
     */
    function safeTransferFromBatch(
        address from,
        address to,
        uint256[] memory tokenIds
    ) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            safeTransferFrom(from, to, tokenIds[i]);
        }
    }

    /**
     * @dev Returns a list of token IDs owned by `user` given a `cursor` and `size` of its token list
     */
    function tokensOfOwnerBySize(
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > balanceOf(user) - cursor) {
            length = balanceOf(user) - cursor;
        }

        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = tokenOfOwnerByIndex(user, cursor + i);
        }

        return (values, cursor + length);
    }

    /**
     * @dev Get White List Existence
     */
    function getWhiteListExistence(uint256 boxType, address user)
        external
        view
        returns (bool)
    {
        return whiteList[boxType].contains(user);
    }

    /**
     * @dev Get Boxes Left Supply
     */
    function getBoxesLeftSupply(uint256 boxType) public view returns (uint256) {
        return boxesMaxSupply[boxType] - totalBoxesLength[boxType];
    }

    /**
     * @dev Get User Hourly Boxes Left Supply
     */
    function getUserHourlyBoxesLeftSupply(
        uint256 boxType,
        address user,
        uint256 timestamp
    ) public view returns (uint256) {
        return
            hourlyBuyLimits[boxType] -
            userHourlyBoxesLength[user][boxType][timestamp / 3600];
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for a token ID
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    /**
     * @dev IERC165-supportsInterface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerable, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get Level
     */
    function getLevel(uint256[] memory array, uint256 random)
        public
        pure
        returns (uint256)
    {
        uint256 accProbability;
        uint256 level;
        for (uint256 i = 0; i < array.length; i++) {
            accProbability += array[i];
            if (random < accProbability) {
                level = i;
                break;
            }
        }
        return level + 1;
    }

    /**
     * @dev Spawn SN to User when get Randomness Response
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        uint256[] memory snIds = new uint256[](randomWords.length);
        uint256[] memory boxTypes = new uint256[](randomWords.length);
        uint256[][] memory attr = new uint256[][](randomWords.length);
        uint256[] memory att = new uint256[](5);

        for (uint256 i = 0; i < randomWords.length; i++) {
            boxTypes[i] = sbIdToType[requestIdToSbIds[requestId][i]];

            att[0] = getLevel(
                starProbabilities[boxTypes[i]],
                randomWords[i] % 1e4
            );
            att[1] =
                ((getLevel(
                    powerProbabilities[boxTypes[i]],
                    (randomWords[i] % 1e8) / 1e4
                ) - 1) * 20) +
                ((((randomWords[i] % 1e12) / 1e8) % 20) + 1);
            att[2] = ((randomWords[i] % 1e16) / 1e12) % 4;
            att[3] = getLevel(
                placeProbabilities[boxTypes[i]],
                (randomWords[i] % 1e20) / 1e16
            );
            att[4] = ((randomWords[i] % 1e24) / 1e20) % 4;

            attr[i] = att;

            snIds[i] = sn.spawnSn(attr[i], requestIdToUser[requestId]);
        }

        emit SpawnSns(
            requestIdToUser[requestId],
            randomWords.length,
            snIds,
            boxTypes,
            attr
        );
    }
}
