const hre = require("hardhat");

const { Framework } = require("@superfluid-finance/sdk-core");
const { ethers, providers } = require("ethers")

require("dotenv")

async function main() {

    //nft address
    const tradableCashflowAddress = "0x4923E640472AdD4E2CA15Ac19fC37776d768B345"

    const url = `${process.env.PRIVATE_RPC}`;
    const customHttpProvider = new providers.JsonRpcProvider(url);

    const sf = await Framework.create({
        chainId: 80001,
        provider: customHttpProvider
    });

    const signer = sf.createSigner({
        privateKey:
            process.env.PRIVATE_KEY,
        provider: customHttpProvider
    });


    const daix = await sf.loadSuperToken("fDAIx");

    const createFlowOperation = sf.cfaV1.createFlow({
        receiver: tradableCashflowAddress,
        superToken: "0x5d8b4c2554aeb7e86f387b4d6c00ac33499ed01f",
        flowRate: "1000000000000"
    });

    const txn = await createFlowOperation.exec(signer);

    const receipt = await txn.wait();

    console.log(receipt);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
    console.error(error)
    process.exitCode = 1
})