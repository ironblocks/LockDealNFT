const timedLockDealProvider = artifacts.require("TimedLockDealProvider")
const nftContract = "0x0000000000000000000000000000000000000000"

module.exports = function (deployer) {
    deployer.deploy(timedLockDealProvider, nftContract)
}
