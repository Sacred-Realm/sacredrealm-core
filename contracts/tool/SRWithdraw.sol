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

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => mapping(uint256 => bool)) usedNonces;

    event SetAddrs(address treasury, address verifier, address srAddr);
    event SetFee(uint256 fee);
    event Withdraw(
        address indexed user,
        uint256 amount,
        uint256 nonce,
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
     * @dev Set Fee
     */
    function setFee(uint256 _fee) external onlyRole(MANAGER_ROLE) {
        fee = _fee;

        emit SetFee(_fee);
    }

    /**
     * @dev Claim Payment
     */
    function claimPayment(
        uint256 amount,
        uint256 nonce,
        bytes memory signature
    ) external nonReentrant {
        require(
            !usedNonces[msg.sender][nonce],
            "You have already withdrawn this payment"
        );
        usedNonces[msg.sender][nonce] = true;

        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(msg.sender, amount, nonce, this))
        );

        (address _verifier, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(
            message,
            signature
        );

        require(
            recoverError == ECDSA.RecoverError.NoError && _verifier == verifier,
            "Signature verification failed"
        );

        uint256 feeAmount = (amount * fee) / 1e4;
        sr.safeTransfer(treasury, feeAmount);

        amount -= feeAmount;
        sr.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, nonce, signature);
    }
}
