const { ethers } = require("hardhat");
require("dotenv")

//To deploy use:
//npx hardhat run --network <your-network> scripts/tradeableCashflow.js

async function main() {

    const NFTName = "Tradeable Cashflow";
    const NFTSymbol = "TCF";

    const { deployer } = await ethers.getSigners()

    //Mumbai addresses - change if using a different network (visit: https://docs.superfluid.finance/superfluid/developers/networks)
    const host = "0xEB796bdb90fFA0f28255275e16936D25d3418603"
    const fDAIx = "0x5d8b4c2554aeb7e86f387b4d6c00ac33499ed01f"

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const owner = deployer.address;
    const TradeableCashflowNFT = await ethers.getContractFactory("TradeableCashflow");
    const token = await TradeableCashflowNFT.deploy(owner, NFTName, NFTSymbol, host, fDAIx);

    console.log("TradeableCashflowNFT address:", token.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });