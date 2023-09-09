const ERC20Mock = artifacts.require('ERC20Mock')
const ISavingsDai = artifacts.require('ISavingsDai')

async function getSavingsDaiContracts() {
  const dai = await ERC20Mock.at('0x0a4dBaF9656Fd88A32D087101Ee8bf399f4bd55f')
  const sDai = await ISavingsDai.at('0x83F20F44975D03b1b09e64809B757c47f942BEeA')
  return { dai, sDai }
}

module.exports = getSavingsDaiContracts
