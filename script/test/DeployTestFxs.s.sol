// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "script/Constants.sol";
import "test/FxsMock.sol";

function deployMockFxs() returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _contractName = "MockFxs";
    string memory _symbol = "FXSM";
    _constructorParams = abi.encode(_contractName, _symbol);
    _address = address(new FxsMock(_contractName, _symbol));
}

contract DeployTestFxs is BaseScript {
    function run()
        external
        broadcaster
        returns (address _address, bytes memory _constructorParams, string memory _contractName)
    {
        (_address, _constructorParams, _contractName) = deployMockFxs();
        //        console.log("_contractName:", _contractName);
        //        console.log("_constructorParams:", string(abi.encode(_constructorParams)));
        //        console.logBytes(_constructorParams);
        //        console.log("_address:", _address);
    }
}
