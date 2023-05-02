To run tests you need to create a virtual env and install vyper 0.2.12. This is because we're using VyperDeployer,
which will deploy the actual veFXS.vy contract.

Steps:
```bash
virtualenv -p python --no-site-packages ~/vyper-venv # or python3 -m venv ~/vyper-venv
source ~/vyper-venv/bin/activate
cd ~/vyper-venv
pip install vyper==0.2.12
cd $PROJECT_DIR
forge test
```

Coverage:
`forge coverage --report lcov && genhtml lcov.info -o report --branch-coverage && open report/index.html`

Deploy (make sure to update Constants):

Deploying MockVeFxs on arbi:
1. remix
2. Install vyper remix plugin
3. bump veFXS.py version to 0.2.16
4. Deploy through remix
5. Verify on arbiscan, remix will give you abi encoded parameters

[//]: # (forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url $GOERLI_RPC_URL --broadcast --chain 5 -vvvvv)
 ```bash
forge script script/test/DeployTestFxs.s.sol:DeployTestFxs --fork-url http://localhost:8545 --broadcast
forge script script/test/DeployTestnet.s.sol:DeployTestnet --fork-url http://localhost:8545 --broadcast
 ```
forge script script/test/DeployTestFxs.s.sol:DeployTestFxs --rpc-url $ARBI_RPC_URL -vvvvv --verify --etherscan-api-key $ARBISCAN_KEY --verifier-url $ARBISCAN_API_URL
forge script script/test/DeployTestnet.s.sol:DeployTestnet --rpc-url $ARBI_RPC_URL -vvvvv --verify --etherscan-api-key $ARBISCAN_KEY --verifier-url $ARBISCAN_API_URL

# TODO
