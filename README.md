# Lendies Solidity

This project contains the solidity contracts used in Lendies. It comes with [Hardhat Tool-Box](https://hardhat.org/hardhat-runner/docs/getting-started#overview) for easy deployment and testing.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
GAS_REPORT=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.js
```

### To deploy this contracts in the mumbai testnet:


Install `dotenv` locally:

```shell
npm install dotenv --save
```

Create a `.env` file in the root of your project:


```dosini
PRIVATE_KEY="YOURS3CRETKEY"
POLYGONSCAN_API_KEY="YOURSECRETKEYGOESHERE"
```

> **_NOTE:_**  The POLYGONSCAN_API_KEY is to verify your contract. You can generate an API key by [creating an account](https://polygonscan.com/register)

### Compiling the contract

To compile the contract, you first need to install Hardhat Toolbox:

```shell
npm install --save-dev @nomicfoundation/hardhat-toolbox @nomiclabs/hardhat-ethers
```

#### Run to compile:

```shell
npx hardhat compile
```

#### Run to test:

```shell
npx hardhat test
```

#### Run tu deploy on matic network:

```shell
npx hardhat run scripts/deploy.js --network matic
```


The contract will be deployed on Matic's Mumbai Testnet, and you can check the deployment status here: https://mumbai.polygonscan.com/

#### To verify your contract(optional):

```shell
npm install --save-dev @nomiclabs/hardhat-etherscan
npx hardhat verify --network matic 0x4b75233D4FacbAa94264930aC26f9983e50C11AF
```
