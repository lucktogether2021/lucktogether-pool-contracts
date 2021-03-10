const { deploy1820 } = require('deploy-eip-1820')

const debug = require('debug')('ptv3:deploy.js')

const chainName = (chainId) => {
  switch(chainId) {
    case 1: return 'Mainnet';
    case 3: return 'Ropsten';
    case 4: return 'Rinkeby';
    case 5: return 'Goerli';
    case 42: return 'Kovan';
    case 31337: return 'HardhatEVM';
    default: return 'Unknown';
  }
}

module.exports = async (hardhat) => {
  const { getNamedAccounts, deployments, getChainId, ethers } = hardhat
  const { deploy } = deployments

  const harnessDisabled = !!process.env.DISABLE_HARNESS

  let {
    deployer,
    rng,
    adminAccount,
    comptroller,
    reserveRegistry
  } = await getNamedAccounts()
  const chainId = parseInt(await getChainId(), 10)
  const isLocal = [1, 3, 4, 42, 77, 99].indexOf(chainId) == -1
  // 31337 is unit testing, 1337 is for coverage
  const isTestEnvironment = chainId === 31337 || chainId === 1337

  const signer = await ethers.provider.getSigner(deployer)

  console.log("\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
  console.log("PoolTogether Pool Contracts - Deploy Script")
  console.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n")

  const locus = isLocal ? 'local' : 'remote'
  console.log(`  Deploying to Network: ${chainName(chainId)} (${locus})`)

  if (!adminAccount) {
    console.log("  Using deployer as adminAccount;")
    adminAccount = signer._address
  }
  console.log("\n  adminAccount:  ", adminAccount)

  await deploy1820(signer)

  console.log(`deployer is ${deployer}`)

  if (isLocal) {
    console.log("\n  Deploying RNGService...")
    const rngServiceMockResult = await deploy("RNGServiceMock", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
    rng = rngServiceMockResult.address

    console.log("\n  Deploying Dai...")
    const daiResult = await deploy("Dai", {
      args: [
        'DAI Test Token',
        'DAI'
      ],
      contract: 'ERC20Mintable',
      from: deployer,
      skipIfAlreadyDeployed: true
    })

    console.log("\n  Deploying cDai...")
    // should be about 20% APR
    let supplyRate = '8888888888888'
    await deploy("cDai", {
      args: [
        daiResult.address,
        supplyRate
      ],
      contract: 'CTokenMock',
      from: deployer,
      skipIfAlreadyDeployed: true
    })

    await deploy("yDai", {
      args: [
        daiResult.address
      ],
      contract: 'yVaultMock',
      from: deployer,
      skipIfAlreadyDeployed: true
    })

    // Display Contract Addresses
    console.log("\n  Local Contract Deployments;\n")
    console.log("  - RNGService:       ", rng)
    console.log("  - Dai:              ", daiResult.address)
  }

  const DripStrategyResult = await deploy("DripRatePerSecondAttenuationStrategy", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  const tokenFaucetResult = await deploy("TokenFaucet", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  if (!reserveRegistry) {
    // if not set by named config
    const reserveResult = await deploy("Reserve", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
    const reserveContract = await hardhat.ethers.getContractAt(
      "Reserve",
      reserveResult.address,
      signer
    )
    // if (adminAccount !== deployer) {
    //   await reserveContract.transferOwnership(adminAccount)
    // }

    const reserveRegistryResult = await deploy("ReserveRegistry", {
      contract: 'Registry',
      from: deployer,
      skipIfAlreadyDeployed: true
    })
    const reserveRegistryContract = await hardhat.ethers.getContractAt(
      "Registry",
      reserveRegistryResult.address,
      signer
    )
    if (await reserveRegistryContract.lookup() != reserveResult.address) {
      await reserveRegistryContract.register(reserveResult.address)
    }
    // if (adminAccount !== deployer) {
    //   await reserveRegistryContract.transferOwnership(adminAccount)
    // }

    reserveRegistry = reserveRegistryResult.address
    console.log(`  Created new reserve registry ${reserveRegistry}`)
  } else {
    console.log(`  Using existing reserve registry ${reserveRegistry}`)
  }

  let permitAndDepositDaiResult
  console.log("\n  Deploying PermitAndDepositDai...")
  permitAndDepositDaiResult = await deploy("PermitAndDepositDai", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  console.log("\n  Deploying CompoundPrizePoolProxyFactory...")
  let compoundPrizePoolProxyFactoryResult
  if (isTestEnvironment && !harnessDisabled) {
    compoundPrizePoolProxyFactoryResult = await deploy("CompoundPrizePoolProxyFactory", {
      contract: 'CompoundPrizePoolHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  } else {
    compoundPrizePoolProxyFactoryResult = await deploy("CompoundPrizePoolProxyFactory", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  }

  let yVaultPrizePoolProxyFactoryResult
  if (isTestEnvironment && !harnessDisabled) {
    yVaultPrizePoolProxyFactoryResult = await deploy("yVaultPrizePoolProxyFactory", {
      contract: 'yVaultPrizePoolHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  } else {
    yVaultPrizePoolProxyFactoryResult = await deploy("yVaultPrizePoolProxyFactory", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  }

  console.log("\n  Deploying ControlledTokenProxyFactory...")
  const controlledTokenProxyFactoryResult = await deploy("ControlledTokenProxyFactory", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  console.log("\n  Deploying TicketProxyFactory...")
  const ticketProxyFactoryResult = await deploy("TicketProxyFactory", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  
  let stakePrizePoolProxyFactoryResult
  if (isTestEnvironment && !harnessDisabled) {
    console.log("\n  Deploying StakePrizePoolHarnessProxyFactory...")
    stakePrizePoolProxyFactoryResult = await deploy("StakePrizePoolProxyFactory", {
      contract: 'StakePrizePoolHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  }
  else{
    console.log("\n  Deploying StakePrizePoolProxyFactory...")
    stakePrizePoolProxyFactoryResult = await deploy("StakePrizePoolProxyFactory", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  }

  console.log("\n  Deploying UnsafeTokenListenerDelegatorProxyFactory...")
  const unsafeTokenListenerDelegatorProxyFactoryResult = await deploy("UnsafeTokenListenerDelegatorProxyFactory", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  let multipleWinnersProxyFactoryResult
  console.log("\n  Deploying MultipleWinnersProxyFactory...")
  if (isTestEnvironment && !harnessDisabled) {
    multipleWinnersProxyFactoryResult = await deploy("MultipleWinnersProxyFactory", {
      contract: 'MultipleWinnersHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  } else {
    multipleWinnersProxyFactoryResult = await deploy("MultipleWinnersProxyFactory", {
      from: deployer,
      skipIfAlreadyDeployed: true
    })
  }

  console.log("\n  Deploying SingleRandomWinnerProxyFactory...")
  const singleRandomWinnerProxyFactoryResult = await deploy("SingleRandomWinnerProxyFactory", {
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  console.log("\n  Deploying ControlledTokenBuilder...")
  const controlledTokenBuilderResult = await deploy("ControlledTokenBuilder", {
    args: [
      controlledTokenProxyFactoryResult.address,
      ticketProxyFactoryResult.address
    ],
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  console.log("\n  Deploying MultipleWinnersBuilder...")
  const multipleWinnersBuilderResult = await deploy("MultipleWinnersBuilder", {
    args: [
      multipleWinnersProxyFactoryResult.address,
      controlledTokenBuilderResult.address,
    ],
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  console.log("\n  Deploying PoolWithMultipleWinnersBuilder...")
  const poolWithMultipleWinnersBuilderResult = await deploy("PoolWithMultipleWinnersBuilder", {
    args: [
      reserveRegistry,
      compoundPrizePoolProxyFactoryResult.address,
      stakePrizePoolProxyFactoryResult.address,
      multipleWinnersBuilderResult.address
    ],
    from: deployer,
    skipIfAlreadyDeployed: true
  })

  // Display Contract Addresses
  console.log("\n  Contract Deployments Complete!\n")
  console.log("  - TicketProxyFactory:             ", ticketProxyFactoryResult.address)
  console.log("  - Reserve Registry:               ", reserveRegistry)
  // console.log("  - Comptroller:                    ", comptrollerAddress)
  console.log("  - DripStrategyResult:      ", DripStrategyResult.address)
  console.log("  - TokenFaucet: ", tokenFaucetResult.address)
  console.log("  - UnsafeTokenListenerDelegatorProxyFactory ", unsafeTokenListenerDelegatorProxyFactoryResult.address)
  console.log("  - CompoundPrizePoolProxyFactory:  ", compoundPrizePoolProxyFactoryResult.address)
  console.log("  - StakePrizePoolProxyFactory:     ", stakePrizePoolProxyFactoryResult.address)
  console.log("  - SingleRandomWinnerProxyFactory  ", singleRandomWinnerProxyFactoryResult.address)
  console.log("  - ControlledTokenProxyFactory:    ", controlledTokenProxyFactoryResult.address)
  console.log("  - ControlledTokenBuilder:         ", controlledTokenBuilderResult.address)
  console.log("  - MultipleWinnersBuilder:         ", multipleWinnersBuilderResult.address)
  console.log("  - PoolWithMultipleWinnersBuilder: ", poolWithMultipleWinnersBuilderResult.address)
  if (permitAndDepositDaiResult) {
    console.log("  - PermitAndDepositDai:            ", permitAndDepositDaiResult.address)
  }

  console.log("\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n")
};
