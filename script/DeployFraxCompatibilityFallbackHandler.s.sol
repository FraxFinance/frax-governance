// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { FraxCompatibilityFallbackHandler } from "../src/FraxCompatibilityFallbackHandler.sol";
import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";

function deployFraxCompatibilityFallbackHandler() returns (address _address, string memory _contractName) {
    _contractName = "FraxCompatibilityFallbackHandler";
    _address = address(new FraxCompatibilityFallbackHandler());
}

contract DeployFraxCompatibilityFallbackHandler is BaseScript {
    function run() external broadcaster returns (address _address, string memory _contractName) {
        (_address, _contractName) = deployFraxCompatibilityFallbackHandler();
    }
}
