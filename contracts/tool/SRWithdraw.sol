// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../token/interface/ISR.sol";

/**
 * @title Sacred Realm Withdraw Contract
 * @author SEALEM-LAB
 * @notice In this contract, players can withdraw SR from the game Sacred Realm
 */
contract SRWithdraw is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for ISR;

    address public treasury;
    address public verifier;
    ISR public sr;

    uint256 public fee = 500;
    uint256 public requestInterval = 5 minutes;
    uint256 public minRequestAmount = 1e5 * 1e18;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct Request {
        uint256 amount;
        bytes32 message;
        uint256 claimTime;
    }
    mapping(address => Request[]) public requests;

    mapping(address => uint256) public userLastRequestTime;
    mapping(address => uint256) public userWithdrawAmount;

    event SetAddrs(address treasury, address verifier, address srAddr);
    event SetData(
        uint256 fee,
        uint256 requestInterval,
        uint256 minRequestAmount
    );
    event RequestWithdrawal(
        address indexed user,
        uint256 requestId,
        uint256 amount,
        bytes32 message
    );
    event Withdraw(
        address indexed user,
        uint256 requestId,
        uint256 amount,
        bytes signature
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Addrs
     */
    function setAddrs(
        address _treasury,
        address _verifier,
        address srAddr
    ) external onlyRole(MANAGER_ROLE) {
        treasury = _treasury;
        verifier = _verifier;
        sr = ISR(srAddr);

        emit SetAddrs(_treasury, _verifier, srAddr);
    }

    /**
     * @dev Set Data
     */
    function setData(
        uint256 _fee,
        uint256 _requestInterval,
        uint256 _minRequestAmount
    ) external onlyRole(MANAGER_ROLE) {
        fee = _fee;
        requestInterval = _requestInterval;
        minRequestAmount = _minRequestAmount;

        emit SetData(_fee, _requestInterval, _minRequestAmount);
    }

    /**
     * @dev Request Withdrawal
     */
    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(
            amount >= minRequestAmount,
            "Amount must >= min request amount"
        );
        require(
            block.timestamp >=
                userLastRequestTime[msg.sender] + requestInterval,
            "Requests are too frequent"
        );

        bytes32 message = ECDSA.toEthSignedMessageHash(
            abi.encodePacked(msg.sender, requests[msg.sender].length, amount)
        );

        requests[msg.sender].push(
            Request({amount: amount, message: message, claimTime: 0})
        );

        userLastRequestTime[msg.sender] = block.timestamp;

        emit RequestWithdrawal(
            msg.sender,
            requests[msg.sender].length - 1,
            amount,
            message
        );
    }

    /**
     * @dev Withdraw
     */
    function withdraw(uint256 requestId, bytes memory signature)
        external
        nonReentrant
    {
        Request storage request = requests[msg.sender][requestId];
        (address _verifier, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(
            request.message,
            signature
        );

        require(
            request.claimTime == 0,
            "You have already withdrawn this request"
        );
        require(
            recoverError == ECDSA.RecoverError.NoError && _verifier == verifier,
            "Signature verification failed"
        );

        request.claimTime = block.timestamp;

        uint256 feeAmount = (request.amount * fee) / 1e4;
        uint256 amount = request.amount - feeAmount;
        sr.safeTransfer(treasury, feeAmount);
        sr.safeTransfer(msg.sender, amount);

        userWithdrawAmount[msg.sender] += amount;

        emit Withdraw(msg.sender, requestId, amount, signature);
    }

    /**
     * @dev Get User Requests Length
     */
    function getUserRequestsLength(address user)
        external
        view
        returns (uint256)
    {
        return requests[user].length;
    }
}
