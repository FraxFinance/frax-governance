// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./FraxGovernorTestBase.t.sol";

contract TestFraxGovernorDelegation is FraxGovernorTestBase {
    address constant bill = address(1);
    address constant alice = address(2);

    //TODO: remove when done prod test
    function rsv(bytes memory signature) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    //TODO: remove when done prod test
    function testFoo() public view {
        //        console.logBytes(abi.encodeWithSignature("setGuard(address)", 0x736D83B624f451D331A794A188974Ef2f12E547a));
        console.logBytes32(keccak256(bytes("")));
        console.logBytes32(keccak256(bytes('""')));
        //        console.logBytes32(keccak256(bytes('"hi"')));
        //        console.logBytes32(keccak256(bytes("0x")));
        //        console.logBytes32(keccak256(bytes("hello")));

        address one = 0x7C821575524C9E68a40Ab068809Dd7C8B38e99C0;
        bytes memory signature = bytes(
            "0xa91a2a3f3d6c7ba4998321cd9fed24a65650d64214901c8efe1dfb109f405a6e33fd1c3248146fb64ae591eca843a7cb33fbf2b76ec73a70c125114ccfebd63c1c"
        );
        address two = 0x022993dc0F5d31dE4aAB79903ad1B8239F09e58d;
        //            bytes memory sigTwo = bytes("0xbe5e07b3b1266ab8832ca2dc66139708346b2fb242d7a34cd2a7721d4c7624665bb723ddd043de334e8f1a1e46fa5f95d92c5d5f6e55951d5a9dd58ba759be5e1c");
        address three = 0xbE388F85AA7DAF4c210EF04fe52332f3a96cB85c;
        //            bytes memory sigThree = bytes("0x8d35b75bf768479130e8b3dd871e155b7c3154f3f4f3d32a5cfe1df30282122c250955ed66c5e465a3769f95f48d430b1e00f34771422ffeac0ba98d5f842e5f1c");
        console.log(one > two);
        console.log(one > three);
        console.log(two > three);
        //
        (bytes32 r, bytes32 s, uint8 v) = rsv(signature);
        //        console.logBytes32(r);
        //        console.logBytes32(s);
        //        console.log(v);

        //            bytes32 r;
        //            bytes32 s;
        //            uint8 v;
        //     ecrecover takes the signature parameters, and the only way to get them
        //     currently is to use assembly.
        // @solidity memory-safe-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        //
        //        console.logBytes(
        //            abi.encodePacked(
        //                bytes(
        //                    "0xbe5e07b3b1266ab8832ca2dc66139708346b2fb242d7a34cd2a7721d4c7624665bb723ddd043de334e8f1a1e46fa5f95d92c5d5f6e55951d5a9dd58ba759be5e1c"
        //                ),
        //                bytes(
        //                    "0x8d35b75bf768479130e8b3dd871e155b7c3154f3f4f3d32a5cfe1df30282122c250955ed66c5e465a3769f95f48d430b1e00f34771422ffeac0ba98d5f842e5f1c"
        //                ),
        //                bytes(
        //                    "0xa91a2a3f3d6c7ba4998321cd9fed24a65650d64214901c8efe1dfb109f405a6e33fd1c3248146fb64ae591eca843a7cb33fbf2b76ec73a70c125114ccfebd63c1c"
        //                )
        //            )
        //        );
        //        console.logBytes(bytes(""));
        //        console.logBytes32(keccak256(bytes("")));
        //        console.logBytes(
        //            abi.encodeWithSelector(
        //                FraxGovernorOmega.rejectTransaction.selector,
        //                0x63B7448D9695Bb595833C9fCd5B3bB5E56F36864,
        //                2
        //            )
        //        );

        //send 1 mockFXS from safe to EOA
        //        bytes memory data = genericAlphaSafeProposalData(
        //            0x6B83c4f3a6729Fb7D5e19b720092162DF439f567,
        //            0,
        //            abi.encodeWithSignature("transfer(address,uint256)", 0x36bf2289deb0bAb8382648FCae56ae66d5a1d3fE, 1e18),
        //            Enum.Operation.Call
        //        );
        //        console.logBytes(data);

        //        console.logBytes(abi.encodeWithSignature("balanceOf(address)", address(0)));

        //            IFraxGovernorAlpha(0x1C4d6ba999cd1a54491e2c5c44738a0D3fF48841),
        //            ISafe(0x13200Df0a4960F7db118f81cc2A9788cE5Bae17A)

        // against, for, abstain
        bytes memory params = abi.encodePacked(uint128(1), uint128(18_228_335_145_547_467_954_446), uint128(1));
        console.logBytes(params);

        //        address[] memory a = new address[](1);
        //        a[0] = address(1);
        //        console.logBytes(abi.encodeWithSignature("addSafesToAllowlist(address[])", a));
        //        console.logBytes(abi.encodeWithSignature("removeSafesFromAllowlist(address[])", a));
        //        (, uint256 a) = abi.decode(
        //            bytes(
        //                "0x65fc3873000000000000000000000000000000000000000000000031a80dbad2f1d000000000000000000000000000000000000000000000000000000000000066299d00"
        //            ),
        //            (uint256, uint256)
        //        );
        //        console.log(a);

        //        console.logBytes(
        //            genericAlphaSafeProposalData(
        //                address(0x00a0dBcA63BD158D7cAa9b37EE92dD9C3bc102e0),
        //                0,
        //                abi.encodeWithSignature(
        //                    "addOwnerWithThreshold(address,uint256)",
        //                    0x827Fa6bB9C9F22FE4a2D3A1d857aD6221796BCC1,
        //                    4
        //                ),
        //                Enum.Operation.Call
        //            )
        //        );

        //        console.logBytes(
        //            abi.encodeWithSignature("setVeFxsVotingDelegation(address)", 0x319A15d67398C1011DFaB5FD5295ddE244d92Bf8)
        //        );
    }

    // Revert if user tries to delegate to themselves with their own address instead of with address(0)
    function testIncorrectSelfDelegation() public {
        hoax(accounts[0].account);
        vm.expectRevert(IVeFxsVotingDelegation.IncorrectSelfDelegation.selector);
        veFxsVotingDelegation.delegate(accounts[0].account);
    }

    // Assert that this account has weight themselves when they haven't delegated
    function testNoDelegationHasWeight() public {
        assertEq(veFxsVotingDelegation.getVotes(accounts[0].account), veFxs.balanceOf(accounts[0].account));
    }

    // delegate() reverts when the lock is expired
    function testCantDelegateLockExpired() public {
        // - 1 days because DelegateCheckpoints are written 1 day in the future
        vm.warp(veFxs.locked(accounts[1].account).end - 1 days);

        hoax(accounts[1].account);
        vm.expectRevert(IVeFxsVotingDelegation.CantDelegateLockExpired.selector);
        veFxsVotingDelegation.delegate(bob);
    }

    // Account should have no weight at the end of their veFXS lock
    function testNoWeightAfterLockExpires() public {
        vm.warp(veFxs.locked(accounts[0].account).end);
        assertEq(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
    }

    // Test all cases for veFxsVotingDelegation.calculateExpirations();
    function testWriteNewCheckpointForExpirations() public {
        vm.startPrank(accounts[0].account);
        veFxsVotingDelegation.calculateExpirations(accounts[0].account);

        // hasnt delegated no checkpoints
        vm.expectRevert(IVeFxsVotingDelegation.NoExpirations.selector);
        veFxsVotingDelegation.writeNewCheckpointForExpirations(accounts[0].account);

        veFxsVotingDelegation.delegate(bob);

        //checkpoint timestamps are identical
        vm.expectRevert(IVeFxsVotingDelegation.NoExpirations.selector);
        veFxsVotingDelegation.writeNewCheckpointForExpirations(bob);

        // last instant before function will work
        vm.warp(veFxs.locked(accounts[0].account).end - 1 days - 1);

        //total expired FXS == 0
        vm.expectRevert(IVeFxsVotingDelegation.NoExpirations.selector);
        veFxsVotingDelegation.writeNewCheckpointForExpirations(bob);

        vm.warp(veFxs.locked(accounts[0].account).end - 1 days);

        uint256 weight = veFxsVotingDelegation.getVotes(bob);

        //total expired FXS != 0
        veFxsVotingDelegation.writeNewCheckpointForExpirations(bob);
        // same before and after writing this checkpoint
        assertEq(weight, veFxsVotingDelegation.getVotes(bob));

        vm.warp(veFxs.locked(accounts[0].account).end - 1);

        assertGt(veFxsVotingDelegation.getVotes(bob), 0);

        vm.warp(veFxs.locked(accounts[0].account).end);

        assertEq(0, veFxsVotingDelegation.getVotes(bob));

        vm.stopPrank();
    }

    // getCheckpoint() works
    function testCheckpoints() public {
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        assertEq(bob, veFxsVotingDelegation.delegates(accounts[0].account));

        IVeFxsVotingDelegation.DelegateCheckpoint memory dc = veFxsVotingDelegation.getCheckpoint(bob, 0);
        assertEq(dc.timestamp, ((block.timestamp / 1 days) * 1 days) + 1 days);
        assertEq(dc.normalizedBias, 14_316_438_356_164_118_764_800);
        assertEq(dc.normalizedSlope, 7_927_447_995_941);
        assertEq(dc.totalFxs, 1000e18);
    }

    // delegates() works
    function testDelegates() public {
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        assertEq(bob, veFxsVotingDelegation.delegates(accounts[0].account));
    }

    // Revert delegateBySig when expiry is in the past
    function testDelegateBySigBadExpiry() public {
        hoax(accounts[0].account);
        vm.expectRevert(IVeFxsVotingDelegation.SignatureExpired.selector);
        veFxsVotingDelegation.delegateBySig(address(0), 0, block.timestamp - 1, 0, "", "");
    }

    // delegateBySig() works as expected
    function testDelegateBySig() public {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,

        ) = veFxsVotingDelegation.eip712Domain();
        bytes32 TYPE_HASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
        );
        bytes32 structHash = keccak256(
            abi.encode(veFxsVotingDelegation.DELEGATION_TYPEHASH(), bill, 0, block.timestamp)
        );
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaOwners[0].pk, digest);

        // call it works
        veFxsVotingDelegation.delegateBySig(bill, 0, block.timestamp, v, r, s);

        // call it again same args nonce throws
        vm.expectRevert(IVeFxsVotingDelegation.InvalidSignatureNonce.selector);
        veFxsVotingDelegation.delegateBySig(bill, 0, block.timestamp, v, r, s);

        // assert nonce incremented and delegate for signer is who we said
        assertEq(1, veFxsVotingDelegation.$nonces(eoaOwners[0].account));
        assertEq(bill, veFxsVotingDelegation.delegates(eoaOwners[0].account));
    }

    // Revert if trying to delegate to yourself if you're already delegated to yourself
    function testAlreadyDelegatedToSelf() public {
        vm.startPrank(accounts[0].account);

        vm.expectRevert(IVeFxsVotingDelegation.AlreadyDelegatedToSelf.selector);
        veFxsVotingDelegation.delegate(address(0));

        vm.stopPrank();
    }

    // Revert if delegator has already delegated this epoch. DelegateCheckpoint epochs last 24 hours.
    function testAlreadyDelegatedThisEpoch() public {
        vm.startPrank(accounts[0].account);

        veFxsVotingDelegation.delegate(address(1));

        //instant before next epoch
        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days - 1);

        vm.expectRevert(IVeFxsVotingDelegation.AlreadyDelegatedThisEpoch.selector);
        veFxsVotingDelegation.delegate(address(2));

        vm.stopPrank();
    }

    // Test transition phase between calling delegate() and delegation going into effect at the next epoch.
    function testUndelegateReturnsWeight() public {
        vm.startPrank(accounts[0].account);

        vm.expectEmit(true, true, true, true);
        emit DelegateVotesChanged(
            bob,
            0,
            veFxsVotingDelegation.getVotes(accounts[0].account, ((block.timestamp / 1 days) * 1 days) + 1 days)
        );
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(accounts[0].account, address(0), bob);
        veFxsVotingDelegation.delegate(bob);

        // not in effect yet
        assertGt(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        assertEq(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts);

        // first delegation in effect
        assertEq(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);

        vm.expectEmit(true, true, true, true);
        emit DelegateVotesChanged(
            bob,
            veFxsVotingDelegation.getVotes(bob, ((block.timestamp / 1 days) * 1 days) + 1 days),
            0
        );
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(accounts[0].account, bob, address(0));
        veFxsVotingDelegation.delegate(address(0));

        // first delegation still in effect until next epoch
        assertEq(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);

        vm.warp(delegationStarts + 1 days);

        // undelegate in effect
        assertGt(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        assertEq(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        vm.stopPrank();
    }

    // Delegating to the same user again without modifying the veFXS contract will not change their weight
    function testDoubleDelegate() public {
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;
        vm.warp(delegationStarts);

        uint256 weight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        assertGt(weight, 0);

        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 delegationStarts2 = delegationStarts + 1 days;
        vm.warp(delegationStarts2);
        // delegating again does not add extra weight
        assertGt(weight, veFxsVotingDelegation.getVotes(bob, block.timestamp));
    }

    // Ensure delegator doesn't get voting power when switching delegation from account A to account B
    function testNoDoubleVotingWeight() public {
        // delegate to A
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts + 1);

        // move delegation to B
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bill);

        vm.warp(delegationStarts + 1 days - 1);

        // Bob still has voting power until next epoch
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        // Bill should still have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(bill, block.timestamp));
        // Delegator should still have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));

        vm.warp(delegationStarts + 1 days);

        // Bob should have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));
        // Bill should now have voting power
        assertGt(veFxsVotingDelegation.getVotes(bill, block.timestamp), 0);
        // Delegator should still have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));
    }

    // Voting weight works as expected including self delegations
    function testNoDoubleVotingWeightSelfDelegate() public {
        // delegate to A
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts);

        // delegate to self
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(address(0));

        // Bob should have voting power
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        // Delegator should have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));

        vm.warp(delegationStarts + 1 days);

        // Delegator has voting power
        assertGt(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        // Bob no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        // delegate to A
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        // Delegator has voting power
        assertGt(veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp), 0);
        // Bob no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        vm.warp(delegationStarts + 2 days);

        // Bob should have voting power
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        // Delegator should have no voting power
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));
    }

    // User can increase their veFXS lock time and the math is the same as a new lock with same duration and amount
    function testRelockRedelegate() public {
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        deal(address(fxs), bill, 1000e18);
        vm.startPrank(bill, bill);
        fxs.increaseAllowance(address(veFxs), 1000e18);
        vm.stopPrank();

        uint256 lockEnds = veFxs.locked(accounts[0].account).end;

        // the calls to create_lock round differently. Take the weight at + 4 days instead of + 1 days so they're equal
        uint256 delegationStarts = ((block.timestamp / 1 days) * 1 days) + 4 days;
        vm.warp(delegationStarts);

        uint256 weight = veFxsVotingDelegation.getVotes(bob, block.timestamp);

        vm.warp(block.timestamp + 365 days);

        uint256 weight2 = veFxsVotingDelegation.getVotes(bob, block.timestamp);

        assertGt(weight, weight2);

        // original increases their lock time
        hoax(accounts[0].account, accounts[0].account);
        veFxs.increase_unlock_time(block.timestamp + (365 days * 4));

        // new delegator creates a lock with same end
        vm.startPrank(bill, bill);
        veFxs.create_lock(1000e18, block.timestamp + 365 days * 4);
        veFxsVotingDelegation.delegate(alice);
        vm.stopPrank();

        uint256 lockEnds2 = veFxs.locked(accounts[0].account).end;

        // Bob's weight hasn't changed yet
        assertEq(weight2, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        // Bob's weight still hasn't changed yet, won;t change until next epoch
        assertEq(weight2, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        uint256 delegationStarts2 = ((block.timestamp / 1 days) * 1 days) + 1 days;

        vm.warp(delegationStarts2);

        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), weight2);
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), weight);

        vm.warp(lockEnds);
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        vm.warp(lockEnds2 - 1);
        assertGt(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
        // math is equivalent to someone else locking same amount, same duration, at same instant
        assertEq(
            veFxsVotingDelegation.getVotes(bob, block.timestamp),
            veFxsVotingDelegation.getVotes(alice, block.timestamp)
        );
        vm.warp(lockEnds2);
        assertEq(veFxsVotingDelegation.getVotes(bob, block.timestamp), 0);
    }

    // Delegating back to yourself works as expected factoring in enxpirations
    function testExpirationDelegationDoesntDoubleSubtract() public {
        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 expiration = veFxs.locked(accounts[1].account).end;

        vm.warp(expiration - 1 days);

        //account 1 write the expiration checkpoint
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);

        hoax(accounts[1].account, accounts[1].account);
        veFxs.increase_unlock_time(block.timestamp + 365 days);

        //expiration and checkpoint in effect
        vm.warp(expiration);

        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(address(0));

        //self delegation now in effect
        vm.warp(expiration + 1 days);

        assertEq(veFxsVotingDelegation.getVotes(bob), veFxs.balanceOf(accounts[0].account));
    }

    // Testing for a bug that was fixed. Essentially when delegator A moves their delegation from B -> C after their
    // original lock expires, B still had some voting power in a specific window that they shouldn't.
    function testExpiredLockRedelegateNoVotingWeight() public {
        // A->B at time t
        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(bob);

        uint256 expiration = veFxs.locked(accounts[1].account).end;

        // A's lock expires at time t + 1
        // assume proposal with voting snapshot at time t + 2
        vm.warp(expiration + 3);

        // A relocks at time t+3 and delegates to C
        vm.startPrank(accounts[1].account, accounts[1].account);
        veFxs.withdraw();
        fxs.increaseAllowance(address(veFxs), fxs.balanceOf(accounts[1].account));
        veFxs.create_lock(fxs.balanceOf(accounts[1].account), block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.warp(expiration + 4);

        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(bill);

        // B "votes" on prop with weight that they shouldn't have
        assertEq(0, veFxsVotingDelegation.getVotes(bob, expiration + 2));
    }

    // Fuzz test for proper voting weights with delegations
    function testFuzzVotingPowerMultiDelegation(uint256 ts) public {
        ts = bound(ts, block.timestamp + 1, veFxs.locked(accounts[1].account).end - 1 days - 1);
        // mirrored from FraxGovernorOmega::_writeCheckpoint
        uint256 tsRoundedToCheckpoint = ((ts / 1 days) * 1 days) + 1 days;

        vm.warp(ts);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp);
        uint256 weightA = veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp);

        assertGt(weight, 0);
        assertGt(weightA, 0);

        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);
        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(bob);

        // original still has weight before delegation
        assertLe(weight, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp - 1));
        // original still has weight until next checkpoint time
        assertEq(weight, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));

        // original still has weight before delegation
        assertLe(weightA, veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp - 1));
        // original still has weight until next checkpoint time
        assertEq(weightA, veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp));

        // delegatee has no weight before delegation
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp - 1));
        // delegatee has no weight until the next checkpoint time
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        vm.warp(tsRoundedToCheckpoint - 1);

        // original still has weight until the next checkpoint Time
        uint256 weight2 = veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp);
        assertGt(weight2, 0);
        assertGe(weight, weight2);

        uint256 weightA2 = veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp);
        assertGt(weightA2, 0);
        assertGe(weightA, weightA2);

        //delegatee has no weight until the next checkpoint time
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        vm.warp(tsRoundedToCheckpoint);

        // original's delegation hits in so they have no weight
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp));
        // original's delegation hits in so they have no weight
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp));

        uint256 bobWeight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        // original's delegation hits in so delegatee has their weight
        assertGt(bobWeight, weight2);
        assertGe(weight2 + weightA2, bobWeight);
    }

    // Fuzz asserts that our delegated weight calculations == veFxs.balanceOf() at all time points before lock expiry.
    function testFuzzFirstVotingPowerExpiration(uint256 ts) public {
        hoax(accounts[0].account);
        veFxsVotingDelegation.delegate(bob);
        hoax(accounts[1].account);
        veFxsVotingDelegation.delegate(bob);

        ts = bound(ts, veFxs.locked(accounts[1].account).end, veFxs.locked(accounts[0].account).end - 1); //lock expiry

        vm.warp(ts);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp);
        uint256 veFxsBalance = veFxs.balanceOf(accounts[0].account, block.timestamp);
        uint256 weightA = veFxsVotingDelegation.getVotes(accounts[1].account, block.timestamp);
        uint256 delegateWeight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        assertEq(weight, 0);
        assertEq(weightA, 0);
        // veFxs.balanceOf will return the amount of FXS you have when your lock expires. We want it to go to zero,
        // because a user could lock FXS, delegate, time passes, lock expires, withdraw FXS but the delegate would
        // still have voting power to mitigate this, delegated voting power goes to 0 when the lock expires.
        assertEq(delegateWeight, veFxsBalance);
    }

    // Fuzz asserts that our delegated weight calculations == veFxs.balanceOf() at all time points before lock expiry.
    // with various amounts
    function testFuzzDelegationVeFxsEquivalenceBeforeExpiration(uint256 amount, uint256 ts) public {
        amount = bound(amount, 100e18, 50_000_000e18);

        deal(address(fxs), bill, amount);
        deal(address(fxs), alice, amount);
        assertEq(fxs.balanceOf(bill), amount);
        assertEq(fxs.balanceOf(alice), amount);

        vm.startPrank(bill, bill);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.startPrank(alice, alice);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        hoax(bill);
        veFxsVotingDelegation.delegate(bob);
        hoax(alice);
        veFxsVotingDelegation.delegate(bob);

        uint256 nowRoundedToCheckpoint = ((block.timestamp / 1 days) * 1 days) + 1 days;

        ts = bound(ts, nowRoundedToCheckpoint, veFxs.locked(bill).end - 1); //lock expiry

        vm.warp(ts);

        uint256 weight = veFxsVotingDelegation.getVotes(bill, block.timestamp);
        uint256 veFxsBalance = veFxs.balanceOf(bill, block.timestamp);
        uint256 weightA = veFxsVotingDelegation.getVotes(alice, block.timestamp);
        uint256 veFxsBalanceA = veFxs.balanceOf(alice, block.timestamp);
        uint256 delegateWeight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        assertEq(weight, 0);
        assertEq(weightA, 0);
        assertEq(veFxsBalance + veFxsBalanceA, delegateWeight);
    }

    // Fuzz asserts all weight expired at various time points following veFXS lock expiry
    function testFuzzDelegationVeFxsAfterExpiry(uint256 amount, uint256 ts) public {
        amount = bound(amount, 100e18, 50_000_000e18);

        deal(address(fxs), bill, amount);
        deal(address(fxs), alice, amount);
        assertEq(fxs.balanceOf(bill), amount);
        assertEq(fxs.balanceOf(alice), amount);

        vm.startPrank(bill, bill);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        vm.startPrank(alice, alice);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();

        hoax(bill);
        veFxsVotingDelegation.delegate(bob);
        hoax(alice);
        veFxsVotingDelegation.delegate(bob);

        ts = bound(ts, veFxs.locked(bill).end, veFxs.locked(bill).end + (365 days * 10));

        vm.warp(ts);

        uint256 weight = veFxsVotingDelegation.getVotes(bill, block.timestamp);
        uint256 weightA = veFxsVotingDelegation.getVotes(alice, block.timestamp);
        uint256 delegateWeight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        assertEq(weight, 0);
        assertEq(weightA, 0);
        assertEq(delegateWeight, 0);
    }

    // Fuzz expirations with various amounts
    function testFuzzCheckpointExpiration(uint256 amount) public {
        amount = bound(amount, 100e18, 50_000_000e18);
        uint256 start = ((block.timestamp / 1 days) * 1 days) + 1 days;
        vm.warp(start);

        deal(address(fxs), bill, amount);
        vm.startPrank(bill, bill);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        veFxsVotingDelegation.delegate(bob);
        vm.stopPrank();

        deal(address(fxs), alice, amount);
        vm.startPrank(alice, alice);
        fxs.increaseAllowance(address(veFxs), amount);
        vm.stopPrank();

        // the calls to create_lock round differently. Take the weight at + 2 days instead of + 1 days so they're equal
        vm.warp(start + 2 days);

        uint256 weight = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        uint256 end = veFxs.locked(bill).end;

        vm.warp(end);

        vm.startPrank(alice, alice);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        veFxsVotingDelegation.delegate(bob);
        vm.stopPrank();

        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));

        vm.warp(((end / 1 days) * 1 days) + 1 days);
        // test expiration worked correctly
        assertEq(weight, veFxsVotingDelegation.getVotes(bob, block.timestamp));
    }

    // Fuzz tests expirations with different amounts and different lock expiry
    function testFuzzMultiDurationMultiAmount(uint256 amount, uint256 amount2, uint256 ts, uint256 ts2) public {
        amount = bound(amount, 100e18, 50_000_000e18);
        amount2 = bound(amount2, 100e18, 50_000_000e18);
        ts = bound(ts, block.timestamp + 30 days, block.timestamp + (365 days * 4));
        ts2 = bound(ts2, block.timestamp + 30 days, block.timestamp + (365 days * 4));

        deal(address(fxs), bill, amount);
        deal(address(fxs), alice, amount2);
        assertEq(fxs.balanceOf(bill), amount);
        assertEq(fxs.balanceOf(alice), amount2);

        vm.startPrank(bill, bill);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, ts);
        vm.stopPrank();

        vm.startPrank(alice, alice);
        fxs.increaseAllowance(address(veFxs), amount2);
        veFxs.create_lock(amount2, ts2);
        vm.stopPrank();

        hoax(bill);
        veFxsVotingDelegation.delegate(bob);
        hoax(alice);
        veFxsVotingDelegation.delegate(bob);

        uint256 billEnd = veFxs.locked(bill).end;
        uint256 aliceEnd = veFxs.locked(alice).end;

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days);
        uint256 weight = veFxsVotingDelegation.getVotes(bob, block.timestamp);

        vm.warp(billEnd < aliceEnd ? billEnd : aliceEnd);
        uint256 weight2 = veFxsVotingDelegation.getVotes(bob, block.timestamp);
        assertGt(weight, weight2);

        vm.warp(billEnd > aliceEnd ? billEnd : aliceEnd);
        assertEq(0, veFxsVotingDelegation.getVotes(bob, block.timestamp));
        // equal in case they expire at the same time
        assertGe(weight2, veFxsVotingDelegation.getVotes(bob, block.timestamp));
    }

    // Testing for overflow of packed structs
    function testBoundsOfDelegationStructs() public {
        vm.warp(1_680_274_875 + (365 days * 100)); // move time forward so bias is larger
        uint256 amount = 10_000e18;
        uint256 totalVeFxs;
        address delegate = address(uint160(1_000_000));

        for (uint256 i = 100; i < 15_100; ++i) {
            address account = address(uint160(i));
            deal(address(fxs), account, amount);

            vm.startPrank(account, account);
            fxs.increaseAllowance(address(veFxs), amount);
            veFxs.create_lock(amount, block.timestamp + (365 days * 4));

            veFxsVotingDelegation.delegate(delegate);
            vm.stopPrank();
        }

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days);

        for (uint256 i = 100; i < 15_100; ++i) {
            address account = address(uint160(i));
            totalVeFxs += veFxs.balanceOf(account, block.timestamp);
        }
        assertEq(totalVeFxs, veFxsVotingDelegation.getVotes(delegate, block.timestamp));

        uint256 lockEnd = veFxs.locked(address(uint160(100))).end;
        (uint256 bias, uint128 fxs, uint128 slope) = veFxsVotingDelegation.$expirations(delegate, lockEnd);
        assertLt(bias, type(uint96).max);
        assertLt(fxs, type(uint96).max);
        assertLt(slope, type(uint64).max);

        vm.warp(lockEnd);

        // expirations are properly accounted for
        assertEq(0, veFxsVotingDelegation.getVotes(delegate, block.timestamp));
    }

    // Create a ton of random checkpoints
    function testFuzzManyCheckpoints(uint256 daysDelta, uint256 timestamp) public {
        daysDelta = bound(daysDelta, 3 days, 60 days);
        timestamp = bound(timestamp, 604_800, 126_748_800); // startTs, endTs

        vm.warp(((block.timestamp / 1 days) * 1 days) + 1 days); // 604800
        //        uint256 startTs = block.timestamp;
        //        uint256 endTs = startTs + 365 days * 4;

        uint256 amount = 10_000e18;
        address delegate = address(uint160(1_000_000));

        for (uint256 i = 100; i < (365 * 4) + 100; i += daysDelta / 1 days) {
            address account = address(uint160(i));
            deal(address(fxs), account, amount);

            vm.startPrank(account, account);
            fxs.increaseAllowance(address(veFxs), amount);
            veFxs.create_lock(amount, block.timestamp + (365 days * 4));

            veFxsVotingDelegation.delegate(delegate);
            vm.stopPrank();
            // Go forward daysDelta days
            vm.warp(block.timestamp + daysDelta);

            assert(veFxsVotingDelegation.getVotes(delegate, timestamp + daysDelta) >= 0);
        }
    }
}
