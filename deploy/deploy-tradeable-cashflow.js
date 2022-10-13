require("@nomiclabs/hardhat-ethers")

//kovan addresses - change if using a different network
const host = "0xEB796bdb90fFA0f28255275e16936D25d3418603"
const fDAIx = "0x5d8b4c2554aeb7e86f387b4d6c00ac33499ed01f"

//your address here...
const owner = "0x86ca23Ac60499b4E8069c439aC6FDFd897362834"

//to deploy, run yarn hardhat deploy --network kovan

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments

    const { deployer } = await getNamedAccounts()
    console.log(deployer)

    await deploy("TradeableCashflow", {
        from: deployer,
        args: [owner, "Tradeable Cashflow", "TCF", host, fDAIx],
        log: true
    })
}
module.exports.tags = ["TradeableCashflow"]
