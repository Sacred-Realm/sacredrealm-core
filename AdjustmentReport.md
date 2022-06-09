## GLOBAL-01 | Solidity Version Not Recommended

We will adjust the version of solidity to 0.7.6 when deploying the contract


## BDB-01 | Centralization Risk In BondDepository.sol

We will use DAO voting and multisig wallet to change these parameters


## BDB-02 | Potential Flashloan Attack

We currently only have one liquidity pool for our tokens, so we cannot use LINK's oracles for the time being. Using TWAP will increase the cost of our project and increase the risk of user arbitrage. Therefore, our current plan is to monitor abnormal data and set the account with abnormal data as a blacklist.


## BDB-03 | Mismatch Of The Price

Our LP has only 2 cases, one consists of BUSD and the other consists of WBNB


## BDB-04 | Third Party Dependencies

Except for pancake's routing contracts, LP trading pairs and treasury's multi-signature wallets are managed by our team


## BDB-05 | Unknown Selling Token

STLP will not be modified under normal circumstances, unless there is an unexpected situation, it will be modified through DAO voting


## BDB-06 | Potential Sandwich Attacks

When a user makes a large and quick exchange on the official website, we will pop up a pop-up window for a risk reminder. It is recommended to go to the DEX to set a low slippage for exchange.


## BDB-07 | Source Of The Selling Token

We will ensure that the amount of ST in the contract is sufficient when we start each bond sale


## BDB-08 | Variables That Could Be Declared As constant

We have resolved this issue in this commit


## BDB-09 | Redundant Code In The Function Claim()

To prevent unexpected situations, the ST contract address is not stored in the contract


## BDB-10 | Recommended Explicit Validity Checks

We have resolved this issue in this commit


## BDB-11 | Divide Before Multiply

Our interest rates are designed to be rounded


## INV-01 | Centralization Risk In Inviting.sol

We will use DAO voting and multisig wallet to change these parameters


## INV-02 | Logic Issue On

Our invitation mechanism is designed to be bound only once


## POO-01 | Lack Of Reasonable Boundary

We have resolved this issue in this commit


## POO-02 | Missing Zero Address Validation

We have resolved this issue in this commit


## POO-03 | Financial Models

1. We will ensure that LP liquidity is not too small to reduce the risk of flash loan attacks
2. We will use DAO voting and multisig wallet to change these parameters
3. Only this bond protocol will produce ST tokens, which can maximize price stability
4. Before the project is officially launched, we will add sub-coin output to the pledge contract


## STS-01 | Centralization Risk In STStaking.sol

We will use DAO voting and multisig wallet to change these parameters