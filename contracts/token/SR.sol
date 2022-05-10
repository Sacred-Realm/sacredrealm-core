// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title Sacred Realm
 * @author SEALEM-LAB
 * @notice Contract to supply SR
 */
contract SR is ERC20, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    address public treasury;
    uint256 public fee = 100;

    mapping(address => bool) public isFeeExempt;

    event SetTreasury(address treasury);
    event SetWhiteList(address addr, bool isFeeExempt);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) ERC20("Sacred Realm", "SR") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);

        _mint(manager, 1e10 * 1e18);
    }

    /**
     * @dev Set Treasury
     */
    function setTreasury(address _treasury) external onlyRole(MANAGER_ROLE) {
        treasury = _treasury;

        emit SetTreasury(_treasury);
    }

    /**
     * @dev Set White List
     */
    function setWhiteList(address addr, bool _isFeeExempt)
        external
        onlyRole(MANAGER_ROLE)
    {
        isFeeExempt[addr] = _isFeeExempt;

        emit SetWhiteList(addr, _isFeeExempt);
    }

    /**
     * @dev Transfer
     */
    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev Transfer From
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Total Supply
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Balance Of
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     */
    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance;

        if (!isFeeExempt[from]) {
            uint256 feeAmount = (amount * fee) / 1e4;

            fromBalance = _balances[from];
            require(
                fromBalance >= feeAmount,
                "ERC20: transfer amount exceeds balance"
            );
            unchecked {
                _balances[from] = fromBalance - feeAmount;
            }
            _balances[treasury] += feeAmount;

            emit Transfer(from, treasury, feeAmount);

            amount -= feeAmount;
        }

        fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }
}
