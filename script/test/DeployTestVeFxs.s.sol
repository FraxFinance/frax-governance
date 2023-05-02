// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "script/Constants.sol";
import "src/interfaces/IVeFxs.sol";
import "test/VyperDeployer.sol";

function deployVeFxs(
    VyperDeployer vyperDeployer,
    address _mockFxs
) returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _contractName = "veFxs";
    _constructorParams = abi.encode(_mockFxs, _contractName, "1");
    _address = address(vyperDeployer.deployContract(_contractName, _constructorParams));
}

//TODO: doesnt actually work, I manually deployed this through remix
//contract DeployTestVeFxs is BaseScript {
//    VyperDeployer immutable vyperDeployer = new VyperDeployer();
//
//    function setUp() public override {
//        super.setUp();
//        vm.allowCheatcodes(address(vyperDeployer));
//    }
//
//    function run()
//        external
//        broadcaster
//        returns (address _address, bytes memory _constructorParams, string memory _contractName) {
//        (_address, _constructorParams, _contractName) = deployVeFxs(vyperDeployer, Constants.ARBITRUM_TEST_MOCK_FXS);
//
//        console.log("_contractName:", _contractName);
//        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
//        console.logBytes(_constructorParams);
//        console.log("_address:", _address);
//    }
//}
