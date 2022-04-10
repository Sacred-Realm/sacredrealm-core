// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "../token/interface/IST.sol";
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
    using SafeERC20 for IST;
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

    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;

    uint64 public subscriptionId;
    mapping(uint256 => address) public requestIdToUser;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IST public st;
    ISN public sn;

    string public baseURI;
    uint256 public boxPrice = 100e18;
    address public receivingAddr = 0x0000000000000000000000000000000000000020;

    event SetBaseURI(string uri);
    event BuyBoxes(address indexed user, uint256 amount);
    event OpenBoxes(address indexed user, uint256 amount);

    /**
     * @param manager Initialize Manager Role
     * @param stAddr Initialize ST Address
     * @param snAddr Initialize SN Address
     */
    constructor(
        address manager,
        address stAddr,
        address snAddr
    ) ERC721("Sacred Realm Box", "SB") VRFConsumerBaseV2(vrfCoordinator) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);

        st = IST(stAddr);
        sn = ISN(snAddr);

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
     * @dev Transfer this contract's funds to an address
     */
    function withdraw(uint256 amount, address to)
        external
        onlyRole(MANAGER_ROLE)
    {
        LINKTOKEN.transfer(to, amount);
    }

    /**
     * @dev Users buy the boxes
     */
    function buyBoxes(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");

        st.safeTransferFrom(msg.sender, receivingAddr, amount * boxPrice);

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, totalSupply());
        }

        emit BuyBoxes(msg.sender, amount);
    }

    /**
     * @dev Users open the boxes
     */
    function openBoxes(uint32 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");

        for (uint256 i = 0; i < amount; i++) {
            safeTransferFrom(
                msg.sender,
                receivingAddr,
                tokenOfOwnerByIndex(msg.sender, 0)
            );
        }

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            amount
        );
        requestIdToUser[requestId] = msg.sender;

        emit OpenBoxes(msg.sender, amount);
    }

    /**
     * @dev Safe Transfer From Batch
     */
    function safeTransferFromBatch(
        address from,
        address to,
        uint256[] calldata tokenIds
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
     * @dev Spawn SN to User when get Randomness Response
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        for (uint256 i = 0; i < randomWords.length; i++) {
            sn.spawnSn(
                (randomWords[i] % 11) + 1,
                100,
                4,
                8,
                4,
                requestIdToUser[requestId]
            );
        }
    }
}
