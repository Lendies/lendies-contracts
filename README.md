# Lendies Solidity

This project contains the solidity contracts used in Lendies. It comes with [Hardhat Tool-Box](https://hardhat.org/hardhat-runner/docs/getting-started#overview) for easy deployment and testing.

Clone the repo:

```shell
git clone git@github.com:Lendies/lendies-contracts.git
```

To initialize the project its recommended by hardhat to use npm:

npm
```shell
npm i 
```

yarn
```bash
yarn
```

## Solidity Contracts:

### Redirect All

The [redirect all contract](./contracts/RedirectAll.sol) contains the
logic that can "react" to the creation, updating, and deletion of a stream via
a callback. These callbacks redirect any incoming stream to a given receiver's
address.

### Tradeable Cash Flow

The [tradable cashflow contract](./contracts/TradeableCashflow.sol) contains
ERC721 NFT logic, inheriting Open Zeppelin's implementations. It also inherits
the `RedirectAll.sol` logic. In this implementation, the receiver of the stream
is changed on-transfer through the Open Zeppelin ERC721 `_beforeTransfer` hook.

### Lendies Core

The [lendies core contract](./contracts/LendiesCore.sol) contains the login for the creation of Loans. It is possible for a Borrower to request a loan (Filling the Amount, Desired Monthly Payment, and Maximum Interest Rate), which is published as an event and is publicly visible. Loaners can make an offer on the request (Setting their preferred interest rate). If a borrower accepts this offer, the amount will be transfered from the Loaner to the Borrower, and a cashstream will be opened from the Borrower to the Loaner with the predefinied monthly payment and interest rate as parameters.


### To deploy this contracts in the mumbai testnet:

Create a `.env` file in the root of your project:

```dosini
PRIVATE_KEY="YourSecretKey"
POLYGONSCAN_API_KEY="YouRApiKey"
PRIVATE_RPC="PrivateRPCURL"
```

> **_NOTE:_**  The POLYGONSCAN_API_KEY is required. You can generate an API key by [creating an account](https://polygonscan.com/register)

### Compiling the contracts

#### Run to compile:

```shell
npx hardhat compile
```

#### Run to test:

```shell
npx hardhat test
```

#### Run to deploy on matic network:

```shell
npx hardhat run scripts/deploy.js --network matic
```


The contract will be deployed on Matic's Mumbai Testnet, and you can check the deployment status here: https://mumbai.polygonscan.com/

#### To verify your contract (optional):

```shell
npm install --save-dev @nomiclabs/hardhat-etherscan
npx hardhat verify --network matic 0x4b75233D4FacbAa94264930aC26f9983e50C11AF
```
