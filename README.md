## LuckTogether Prize Savings Protocol

The [LuckTogether](http://www.lucktogether.com/) Prize Savings Protocol Heco smart contracts.

#### Usage

###### Artifacts

There are deployment artifacts available in the `deployments/` directory.  This includes:

- Builders
- Proxy Factories
- Comptroller
- ProxyAdmin

Prize Pools and Prize Strategies are not included, as they are created using the Builders.

###### ABIs

Application Binary Interfaces for all LuckTogether contracts and related contracts are available in the `abis/` directory.

#### Development

First clone this repository and enter the directory.

Switch to the `master` branch:

```
$ git checkout master
```

Install dependencies:

```
$ yarn
```

We make use of [Hardhat](https://hardhat.dev) and [hardhat-deploy](https://github.com/wighawag/hardhat-deploy)

#### Testing

To run unit & integration tests:

```sh
$ yarn test
```

To run coverage:

```sh
$ yarn coverage
```

To run fuzz tests:

```sh
$ yarn echidna
```

#### Deployment

###### Deploy Locally

Start a local node and deploy the top-level contracts:

```bash
$ yarn start
```

NOTE: When you run this command it will reset the local blockchain.

###### Connect Locally

Start up a [Hardhat Console](https://hardhat.dev/guides/hardhat-console.html):

```bash
$ hardhat console --network localhost
```

Now you can load up the deployed contracts using [hardhat-deploy](https://github.com/wighawag/hardhat-deploy):

```javascript
> await deployments.all()
```

If you want to send transactions, you can get the signers like so:

```javascript
> let signers = await ethers.getSigners()
```

Let's mint some Dai for ourselves:

```javascript
> let dai = await ethers.getContractAt('ERC20Mintable', (await deployments.get('Dai')).address, signers[0])
> await dai.mint(signers[0]._address, ethers.utils.parseEther('10000'))
> ethers.utils.formatEther(await dai.balanceOf(signers[0]._address))
```

###### Deploy to Live Networks

Copy over .envrc.example to .envrc

```
$ cp .envrc.example .envrc
```

Make sure to update the enviroment variables with suitable values.

Now enable the env vars using [direnv](https://direnv.net/docs/installation.html)

```
$ direnv allow
```

Now deploy to a network like so:

```
$ yarn deploy rinkeby
```

It will update the `deployments/` dir.
