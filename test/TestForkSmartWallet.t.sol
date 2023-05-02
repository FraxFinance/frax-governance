// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "frax-std/FraxTest.sol";
import { IVeFxs } from "../src/interfaces/IVeFxs.sol";
import { IVeFxsVotingDelegation } from "../src/interfaces/IVeFxsVotingDelegation.sol";
import { deployVeFxsVotingDelegation } from "../script/DeployFraxGovernance.s.sol";

contract TestForkSmartWallet is FraxTest {
    //    address _fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    //    address _veFxs = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
    //    address _frxVoterProxy = 0x59CFCD384746ec3035299D90782Be065e466800B;
    //    address _frxVoterProxyOperator = 0x569f5B842B5006eC17Be02B8b94510BA8e79FbCa;
    //    address _delegate = address(123);
    //
    //    IVeFxsVotingDelegation veFxsVotingDelegation;
    //    IVeFxs veFxs;
    //
    //    function setUp() public {
    //        IVeFxs veFxs = IVeFxs(_veFxs);
    //        (address _veFxsVotingDelegation, , ) = deployVeFxsVotingDelegation(_veFxs);
    //        veFxsVotingDelegation = IVeFxsVotingDelegation(_veFxsVotingDelegation);
    //    }
    //
    //    // prepend function name with test to run this
    //    function testForkSmartWalletDelegate() public { //--fork-block-number 17173610
    //        hoax(_frxVoterProxyOperator);
    //        (bool success, bytes memory data) = _frxVoterProxy.call(
    //            abi.encodeWithSignature("execute(address,uint256,bytes)",
    //            address(veFxsVotingDelegation),
    //            0,
    //            abi.encodeWithSignature("delegate(address)", _delegate))
    //        );
    //
    //        assertTrue(success);
    //        assertEq(_delegate, veFxsVotingDelegation.delegates(_frxVoterProxy));
    //    }
}
