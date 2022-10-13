require("@nomiclabs/hardhat-truffle5")
require("@nomiclabs/hardhat-ethers")
require("hardhat-deploy")

require("dotenv").config();
const GAS_LIMIT = 8000000;
const defaultNetwork = 'mumbai';

module.exports = {
    defaultNetwork: "mumbai",
    networks: {
        hardhat: {
        },
        matic: {
            url: process.env.PRIVATE_RPC,
            accounts: [process.env.PRIVATE_KEY]
        },
        mumbai: {
            url: process.env.PRIVATE_RPC,
            accounts: [process.env.PRIVATE_KEY]
        },
        // kovan: {
        //   url: `${process.env.KOVAN_RPC_URL}`,
        //   accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
        //   gas: GAS_LIMIT,
        //   gasPrice: 11e9, // 10 GWEI
        //   confirmations: 6, // # of confs to wait between deployments. (default: 0)
        //   timeoutBlocks: 50, // # of blocks before a deployment times out  (minimum/default: 50)
        //   skipDryRun: false // Skip dry run before migrations? (default: false for public nets )
        // },
        // rinkeby: {
        //   url: alchemyUrl,
        //   accounts: [`0x${RINKEBY_PRIVATE_KEY}`],
        // },
    },
    namedAccounts: {
        deployer: 0
    },

    etherscan: {
        apiKey: process.env.POLYGONSCAN_API_KEY
    },
    solidity: {
        version: "0.8.14",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },

}
