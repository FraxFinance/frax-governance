// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";
import { FraxGuard } from "../src/FraxGuard.sol";

function deployFraxGuard(
    address _fraxGovernorOmega
) returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _constructorParams = abi.encode(_fraxGovernorOmega);
    _contractName = "FraxGuard";
    _address = address(new FraxGuard(_fraxGovernorOmega));
}

contract DeployFraxGuard is BaseScript {
    function run()
        external
        broadcaster
        returns (address _address, bytes memory _constructorParams, string memory _contractName)
    {
        (_address, _constructorParams, _contractName) = deployFraxGuard(Constants.FRAX_GOVERNOR_OMEGA);
    }
}
