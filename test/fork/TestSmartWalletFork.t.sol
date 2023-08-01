// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "frax-std/FraxTest.sol";
import { IVeFxsVotingDelegation } from "../../src/interfaces/IVeFxsVotingDelegation.sol";
import { deployVeFxsVotingDelegation } from "../../script/DeployVeFxsVotingDelegation.s.sol";
import { Constants } from "../../script/Constants.sol";

contract TestSmartWalletFork is FraxTest {
    address constant _frxVoterProxy = 0x59CFCD384746ec3035299D90782Be065e466800B;
    address constant _frxVoterProxyOperator = 0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa;
    address constant _delegate = address(123);

    IVeFxsVotingDelegation veFxsVotingDelegation;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 17_173_610);

        (address _veFxsVotingDelegation, , ) = deployVeFxsVotingDelegation(Constants.VE_FXS);
        veFxsVotingDelegation = IVeFxsVotingDelegation(_veFxsVotingDelegation);
    }

    // Assert that Frax voter proxy can delegate
    function testSmartWalletDelegateFork() public {
        assertEq(address(0), veFxsVotingDelegation.delegates(_frxVoterProxy), "Frax voter proxy is not yet delegating");

        hoax(_frxVoterProxyOperator);
        (bool success, ) = _frxVoterProxy.call(
            abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                address(veFxsVotingDelegation),
                0,
                abi.encodeWithSignature("delegate(address)", _delegate)
            )
        );

        assertTrue(success, "Call succeeded");
        assertEq(_delegate, veFxsVotingDelegation.delegates(_frxVoterProxy), "Frax voter proxy can delegate");
    }
}
