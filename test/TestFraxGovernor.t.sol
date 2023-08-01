// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FraxGovernorTestBase.t.sol";

contract TestFraxGovernor is FraxGovernorTestBase {
    // Reverts on non-existent proposalId
    function testStateInvalidProposalId() public {
        vm.expectRevert("Governor: unknown proposal id");
        fraxGovernorAlpha.state(0);
        vm.expectRevert("Governor: unknown proposal id");
        fraxGovernorOmega.state(0);
    }

    // Make sure Frax Guard supports necessary interfaces
    function testFraxGuardInterface() public view {
        assert(fraxGuard.supportsInterface(0xe6d7a83a));
        assert(fraxGuard.supportsInterface(0x01ffc9a7));
    }

    // Make sure FraxGovernorAlpha supports necessary interfaces
    function testFraxGovernorAlphaInterface() public view {
        assert(fraxGovernorAlpha.supportsInterface(type(IGovernorTimelock).interfaceId));
    }

    // All contracts return proper CLOCK_MODE() and clock()
    function testClockMode() public {
        assertEq(fraxGovernorAlpha.CLOCK_MODE(), "mode=timestamp");
        assertEq(fraxGovernorOmega.CLOCK_MODE(), "mode=timestamp");
        assertEq(veFxsVotingDelegation.CLOCK_MODE(), "mode=timestamp");
        assertEq(fraxGovernorAlpha.clock(), block.timestamp);
        assertEq(fraxGovernorOmega.clock(), block.timestamp);
        assertEq(veFxsVotingDelegation.clock(), block.timestamp);
    }

    // All contract return proper COUNTING_MODE() string
    function testCountingMode() public {
        assertEq(
            fraxGovernorAlpha.COUNTING_MODE(),
            "support=bravo&quorum=against,abstain&quorum=for,abstain&params=fractional"
        );
        assertEq(
            fraxGovernorOmega.COUNTING_MODE(),
            "support=bravo&quorum=against,abstain&quorum=for,abstain&params=fractional"
        );
    }

    // Assert that we can get individual voting weight in the past
    function testGetPastVotes() public {
        mineBlocksBySecond(1 days);

        vm.expectRevert(IVeFxsVotingDelegation.TimestampInFuture.selector);
        veFxsVotingDelegation.getPastVotes(accounts[0], block.timestamp);

        assertEq(
            veFxs.balanceOf(accounts[0], block.timestamp - 1),
            veFxsVotingDelegation.getPastVotes(accounts[0], block.timestamp - 1),
            "Both functions return same amount at same timestamp in past"
        );
    }

    // Assert that total supply with block numbers work as expected
    function testGetPastTotalSupply() public {
        mineBlocksBySecond(1 days);

        vm.expectRevert(IVeFxsVotingDelegation.BlockNumberInFuture.selector);
        veFxsVotingDelegation.getPastTotalSupply(block.timestamp);

        assertEq(
            veFxsVotingDelegation.getPastTotalSupply(block.number - 1),
            veFxs.totalSupplyAt(block.number - 1),
            "Both functions return same amount at same block.number in past"
        );
    }

    // Can't vote if you have no weight
    function testCantVoteZeroWeight() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        (uint256 pid2, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("GovernorCountingFractional: no weight");
        fraxGovernorAlpha.castVote(pid, 0);

        vm.expectRevert("GovernorCountingFractional: no weight");
        fraxGovernorOmega.castVote(pid2, 0);
    }

    // Assert that users with no veFXS locks / balances have 0 voting weight
    function testNoLockGetVotesReturnsZero() public {
        // lock started after provided timestamp
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0], block.timestamp - (365 days * 2)));

        // never locked user has no voting weight
        assertEq(0, veFxsVotingDelegation.getVotes(address(0x123), block.timestamp));
    }

    // Test the revert case for quorum() where there is no proposal at the provided timestamp
    function testQuorumInvalidTimepoint() public {
        vm.expectRevert(FraxGovernorBase.InvalidTimepoint.selector);
        fraxGovernorOmega.quorum(block.timestamp);

        vm.expectRevert(FraxGovernorBase.InvalidTimepoint.selector);
        fraxGovernorAlpha.quorum(block.timestamp);
    }

    // Test the revert case for shortCircuitThreshold() where there is no proposal at the provided timestamp
    function testShortCircuitInvalidTimepoint() public {
        vm.expectRevert(FraxGovernorBase.InvalidTimepoint.selector);
        fraxGovernorOmega.shortCircuitThreshold(block.timestamp);

        vm.expectRevert(FraxGovernorBase.InvalidTimepoint.selector);
        fraxGovernorAlpha.shortCircuitThreshold(block.timestamp);
    }

    // Revert when a user tries to delegate with an expired lock
    function testNoLockDelegateReverts() public {
        hoax(address(0x123));
        vm.expectRevert(IVeFxsVotingDelegation.CantDelegateLockExpired.selector);
        veFxsVotingDelegation.delegate(bob);

        vm.warp(veFxs.locked(accounts[0]).end);

        hoax(accounts[0]);
        vm.expectRevert(IVeFxsVotingDelegation.CantDelegateLockExpired.selector);
        veFxsVotingDelegation.delegate(bob);
    }

    // Cannot call cancel() on an AddTransaction() proposal
    function testCantCancelAddTransactionProposal() public {
        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createOptimisticProposal(
                address(multisig),
                fraxGovernorOmega,
                bob,
                getSafe(address(multisig)).safe.nonce()
            );

        hoax(bob);
        vm.expectRevert(IFraxGovernorOmega.CannotCancelOptimisticTransaction.selector);
        fraxGovernorOmega.cancel(targets, values, calldatas, keccak256(bytes("")));

        assertEq(
            uint256(IGovernor.ProposalState.Pending),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is pending"
        );
    }

    // Various reverts in propose function for Alpha
    function testBadProposeAlpha() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";

        vm.startPrank(accounts[0]);
        vm.expectRevert("Governor: invalid proposal length");
        fraxGovernorAlpha.propose(targets, values, calldatas, "");

        uint256[] memory values2 = new uint256[](1);
        bytes[] memory calldatas2 = new bytes[](2);

        vm.expectRevert("Governor: invalid proposal length");
        fraxGovernorAlpha.propose(targets, values2, calldatas2, "");

        address[] memory targets0 = new address[](0);
        uint256[] memory values0 = new uint256[](0);
        bytes[] memory calldatas0 = new bytes[](0);

        vm.expectRevert("Governor: empty proposal");
        fraxGovernorAlpha.propose(targets0, values0, calldatas0, "");

        fraxGovernorAlpha.propose(targets, values2, calldatas, "");
        vm.expectRevert("Governor: proposal already exists");
        fraxGovernorAlpha.propose(targets, values2, calldatas, "");

        vm.stopPrank();
    }

    // Cannot call addTransaction() for a safe that isnt registered
    function testAddAbortTransactionSafeNotAllowlisted() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            address(getSafe(address(multisig)).safe),
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0]);
        vm.expectRevert(FraxGovernorBase.Unauthorized.selector);
        fraxGovernorOmega.addTransaction(bob, args, generateEoaSigs(3, txHash));

        hoax(eoaOwners[0]);
        vm.expectRevert(FraxGovernorBase.Unauthorized.selector);
        fraxGovernorOmega.abortTransaction(bob, generateEoaSigs(3, txHash));
    }

    // Cannot call addTransaction() for a safe that already had addTransaction() called for that nonce
    function testAddTransactionNonceReserved() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0]);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigs(3, txHash));

        hoax(eoaOwners[0]);
        vm.expectRevert(IFraxGovernorOmega.NonceReserved.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigs(3, txHash));
    }

    // Cannot call addTransaction() for a safe where the nonce is already beyond the provided one
    function testAddTransactionNonceBelowCurrent() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce() - 1
        );

        hoax(eoaOwners[0]);
        vm.expectRevert(IFraxGovernorOmega.WrongNonce.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigs(3, txHash));
    }

    // Cannot call addTransaction() with invalid signatures
    function testAddAbortTransactionBadSignatures() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce()
        );

        vm.startPrank(eoaOwners[0]);
        vm.expectRevert("GS020");
        fraxGovernorOmega.addTransaction(address(multisig), args, "");

        vm.expectRevert("GS020");
        fraxGovernorOmega.abortTransaction(address(multisig), "");

        vm.expectRevert("GS026");
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigsWrongOrder(3, txHash));

        vm.expectRevert("GS026");
        fraxGovernorOmega.abortTransaction(address(multisig), generateEoaSigsWrongOrder(3, txHash));

        bytes memory sigs;
        address[] memory sortedAddresses = new address[](3);
        for (uint256 i = 0; i < 2; ++i) {
            sortedAddresses[i] = eoaOwners[i];
        }
        sortedAddresses[2] = address(fraxGovernorOmega);
        LibSort.sort(sortedAddresses);

        for (uint256 i = 0; i < sortedAddresses.length; ++i) {
            if (sortedAddresses[i] != address(fraxGovernorOmega)) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(addressToPk[sortedAddresses[i]], txHash);
                sigs = abi.encodePacked(sigs, r, s, v);
            } else {
                sigs = abi.encodePacked(sigs, buildContractPreapprovalSignature(address(fraxGovernorOmega)));
            }
        }

        vm.expectRevert(IFraxGovernorOmega.WrongSafeSignatureType.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, sigs);

        vm.stopPrank();
    }

    // Cannot call addTransaction() with the safe as a target
    function testDisallowedTxTargets() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            address(getSafe(address(multisig)).safe),
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.DisallowedTarget.selector, address(multisig)));
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigs(3, txHash));
    }

    // Cannot call addTransaction() with non-allowlisted Safe delegatecall
    function testDisallowedDelegateCall() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce()
        );

        args.operation = Enum.Operation.DelegateCall;

        hoax(eoaOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.DelegateCallNotAllowed.selector, bob));
        fraxGovernorOmega.addTransaction(address(multisig), args, generateEoaSigs(3, txHash));
    }

    // Only veFXS holders can call propose
    function testCantCallProposeNotVeFxsHolder() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        hoax(bob);
        vm.expectRevert(FraxGovernorBase.SenderVotingWeightBelowProposalThreshold.selector);
        fraxGovernorAlpha.propose(targets, values, calldatas, "");
    }

    // Test a safe swap owner proposal that no one votes on
    function testSwapOwnerNoVotes() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];
        assertFalse(multisig.isOwner(proposer), "Proposer is not an owner");

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createSwapOwnerProposal(
                CreateSwapOwnerProposalParams({
                    _fraxGovernorAlpha: fraxGovernorAlpha,
                    _safe: multisig,
                    proposer: proposer,
                    prevOwner: prevOwner,
                    oldOwner: oldOwner
                })
            );

        assert(multisig.isOwner(oldOwner));
        assertFalse(multisig.isOwner(proposer));

        assertEq(
            uint256(IGovernor.ProposalState.Pending),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is pending"
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay());
        vm.roll(block.number + 1);

        assertEq(
            uint256(IGovernor.ProposalState.Pending),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is pending"
        );

        vm.warp(block.timestamp + 1);
        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod() - 1);

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        vm.warp(block.timestamp + 1);
        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is defeated"
        );

        vm.expectRevert("Governor: proposal not successful");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertFalse(multisig.isOwner(proposer), "Proposer is still not an owner, proposal failed");
        assertTrue(multisig.isOwner(prevOwner), "still owner");
        assertTrue(multisig.isOwner(oldOwner), "still owner");
    }

    // Test that frax gov proposals do not reach an expired state
    function testSwapOwnerDoesntExpire() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];
        assertFalse(multisig.isOwner(proposer));

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createSwapOwnerProposal(
                CreateSwapOwnerProposalParams({
                    _fraxGovernorAlpha: fraxGovernorAlpha,
                    _safe: multisig,
                    proposer: proposer,
                    prevOwner: prevOwner,
                    oldOwner: oldOwner
                })
            );
        assertTrue(multisig.isOwner(oldOwner), "oldOwner is an owner");
        assertFalse(multisig.isOwner(proposer), "proposer is not an owner");

        assertEq(
            uint256(IGovernor.ProposalState.Pending),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is pending"
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());
        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        mineBlocksBySecond(1000 days);
        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is executed"
        );

        assertFalse(multisig.isOwner(oldOwner), "old owner is no longer an owner");
        assertTrue(multisig.isOwner(prevOwner), "prevOwner is still an owner");
        assertTrue(multisig.isOwner(proposer), "proposer is now an owner");
    }

    // Test that all owners can call addTransaction() and that optimistic proposals default succeed
    function testOwnerAddNewTransaction() public {
        for (uint256 i = 0; i < eoaOwners.length; ++i) {
            (
                uint256 pid,
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = createOptimisticTxProposal(
                    address(multisig),
                    fraxGovernorOmega,
                    eoaOwners[i],
                    getSafe(address(multisig)).safe.nonce() + i
                );

            assertEq(
                uint256(IGovernor.ProposalState.Pending),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is pending"
            );

            mineBlocksBySecond(fraxGovernorOmega.votingDelay());
            vm.roll(block.number + 1);

            assertEq(
                uint256(IGovernor.ProposalState.Pending),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is pending"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(IGovernor.ProposalState.Active),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is active"
            );

            mineBlocksBySecond(fraxGovernorOmega.votingPeriod() - 1);

            assertEq(
                uint256(IGovernor.ProposalState.Active),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is active"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(IGovernor.ProposalState.Succeeded),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is succeeded"
            );

            fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));
            assertEq(
                uint256(IGovernor.ProposalState.Executed),
                uint256(fraxGovernorOmega.state(pid)),
                "Proposal state is executed"
            );
        }
    }

    // Alpha and Omega proposals work independent of one another
    function testOverlappingSwapVeto() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];
        assertFalse(multisig.isOwner(proposer), "proposer is not an owner");

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createSwapOwnerProposal(
                CreateSwapOwnerProposalParams({
                    _fraxGovernorAlpha: fraxGovernorAlpha,
                    _safe: multisig,
                    proposer: proposer,
                    prevOwner: prevOwner,
                    oldOwner: oldOwner
                })
            );

        // modules dont increase the nonce so we can use the current nonce for both
        (
            uint256 pidV,
            address[] memory targetsV,
            uint256[] memory valuesV,
            bytes[] memory calldatasV
        ) = createOptimisticTxProposal(
                address(multisig),
                fraxGovernorOmega,
                address(this),
                getSafe(address(multisig)).safe.nonce()
            );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        hoax(accounts[0]);
        fraxGovernorOmega.castVote(pidV, uint8(GovernorCompatibilityBravo.VoteType.For));

        // Voting is done for optimistic tx, it was successful
        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(pidV)),
            "Proposal state is succeeded"
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod() - fraxGovernorOmega.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        // execute swap owner
        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        assertEq(
            uint256(IGovernor.ProposalState.Queued),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is queued"
        );
        vm.warp(fraxGovernorAlpha.proposalEta(pid));
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        // Execute veto tx
        fraxGovernorOmega.execute(targetsV, valuesV, calldatasV, keccak256(bytes("")));

        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is executed"
        );
        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(fraxGovernorOmega.state(pidV)),
            "Proposal state is executed"
        );
    }

    // Can resolve optimistic proposals out of order if necessary
    function testMisorderExecSuccess() public {
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();

        // put 100 FXS in safe to transfer later in proposal
        hoax(Constants.FRAX_TREASURY_2);
        fxs.transfer(address(getSafe(address(multisig)).safe), 100e18);

        address account = accounts[0];

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createOptimisticProposal(address(multisig), fraxGovernorOmega, address(this), startNonce);

        (uint256 pidV, , , ) = createOptimisticTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            startNonce + 1
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        assertEq(
            veFxsVotingDelegation.getVotes(account, block.timestamp),
            veFxs.balanceOf(accounts[0]),
            "getVotes balance is equal to veFXS balance"
        );

        hoax(account);
        fraxGovernorOmega.castVote(pidV, uint8(GovernorCompatibilityBravo.VoteType.Against));

        // Voting is done for both.
        mineBlocksBySecond(fraxGovernorOmega.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is succeeded"
        );
        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorOmega.state(pidV)),
            "Proposal state is defeated"
        );

        (bytes32 successHash, , ) = createTransferFxsProposal(address(multisig), multisig.nonce());
        (bytes32 rejectionHash, , ) = createNoOpProposal(address(multisig), address(multisig), startNonce + 1);

        // Owner cannot execute before Omega approves
        vm.startPrank(eoaOwners[0]);
        vm.expectRevert(FraxGuard.Unauthorized.selector);
        getSafe(address(multisig)).safe.execTransaction(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(4, successHash) // try with 4/6 EOA owner signatures
        );
        vm.stopPrank();

        fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));

        // Omega to approve the veto hash
        fraxGovernorOmega.rejectTransaction(address(multisig), startNonce + 1);

        // can't reject twice
        vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.TransactionAlreadyApproved.selector, rejectionHash));
        fraxGovernorOmega.rejectTransaction(address(multisig), startNonce + 1);

        // Non safe owner cannot execute
        vm.expectRevert(FraxGuard.Unauthorized.selector);
        getSafe(address(multisig)).safe.execTransaction(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, successHash)
        );

        // Owner can execute because Omega already approved
        vm.startPrank(eoaOwners[0]);
        getSafe(address(multisig)).safe.execTransaction(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, successHash)
        );

        assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 1, "Execution incremented the nonce");
        assertEq(fxs.balanceOf(address(this)), 100e18, "tokens successfully sent");

        (bytes32 txHash2, , ) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            address(multisig),
            startNonce + 1
        );

        //Execute 0 eth transfer to increment nonce of safe for veto'ed proposal
        getSafe(address(multisig)).safe.execTransaction(
            address(multisig),
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, txHash2)
        );
        vm.stopPrank();

        assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 2, "Execution incremented the nonce");
    }

    // Alpha works with multiple gnosis safes
    function testManyMultisigsAlpha() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        (uint256 pid2, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig2,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        hoax(accounts[0]);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));
        assertTrue(fraxGovernorAlpha.hasVoted(pid, accounts[0]), "Account voted");

        hoax(accounts[0]);
        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));

        votePassingAlphaQuorum(pid2);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is defeated"
        );
        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid2)),
            "Proposal state is succeeded"
        );
    }

    // Omega works with multiple gnosis safes
    function testManyMultisigsOmega() public {
        // put 100 FXS in safe to transfer later in proposal
        hoax(Constants.FRAX_TREASURY_2);
        fxs.transfer(address(multisig), 100e18);

        uint256 startNonce = getSafe(address(multisig)).safe.nonce();
        uint256 startNonce2 = getSafe(address(multisig2)).safe.nonce();

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createOptimisticProposal(
                address(multisig),
                fraxGovernorOmega,
                address(this),
                getSafe(address(multisig)).safe.nonce()
            );

        (uint256 pid2, , , ) = createOptimisticProposal(
            address(multisig2),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig2)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        vm.startPrank(accounts[0]);
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));
        assertTrue(fraxGovernorOmega.hasVoted(pid, accounts[0]), "Account voted");

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));

        fraxGovernorOmega.castVote(pid2, uint8(GovernorCompatibilityBravo.VoteType.Against));

        vm.stopPrank();

        mineBlocksBySecond(fraxGovernorOmega.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is succeeded"
        );
        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorOmega.state(pid2)),
            "Proposal state is defeated"
        );

        {
            (bytes32 txHash, , ) = createTransferFxsProposal(address(multisig), multisig.nonce());
            fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));

            vm.startPrank(eoaOwners[0]);

            getSafe(address(multisig)).safe.execTransaction(
                address(fxs),
                0,
                abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
                Enum.Operation.Call,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                generateEoaSigs(3, txHash)
            );
            vm.stopPrank();
            assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 1, "Execution incremented the nonce");
        }

        (bytes32 rejectTxHash, , ) = createNoOpProposal(address(multisig2), address(multisig2), multisig2.nonce());
        fraxGovernorOmega.rejectTransaction(address(multisig2), multisig2.nonce());

        vm.startPrank(eoaOwners[0]);
        getSafe(address(multisig2)).safe.execTransaction(
            address(multisig2),
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, rejectTxHash)
        );
        vm.stopPrank();
        assertEq(getSafe(address(multisig2)).safe.nonce(), startNonce2 + 1, "Execution incremented the nonce");
    }

    // Frax Team can abort proposals
    function testAbortTeamTx() public {
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();

        (uint256 pid, , , ) = createOptimisticProposal(address(multisig), fraxGovernorOmega, address(this), startNonce);

        (bytes32 originalTxHash, , ) = createTransferFxsProposal(address(multisig), startNonce);

        (bytes32 abortTxHash, , ) = createNoOpProposal(address(multisig), address(multisig), startNonce);

        vm.startPrank(eoaOwners[0]);

        vm.expectEmit(true, true, true, true);
        emit ProposalCanceled(pid);
        fraxGovernorOmega.abortTransaction(address(multisig), generateEoaSigs(3, abortTxHash));

        vm.expectRevert(IFraxGovernorOmega.ProposalAlreadyCanceled.selector);
        fraxGovernorOmega.abortTransaction(address(multisig), generateEoaSigs(3, abortTxHash));

        assertEq(
            uint256(IGovernor.ProposalState.Canceled),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is canceled"
        );

        getSafe(address(multisig)).safe.execTransaction(
            address(multisig),
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, abortTxHash)
        );

        assertEq(startNonce + 1, multisig.nonce(), "Execution incremented the nonce");

        vm.expectRevert("Governor: vote not currently active");
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + fraxGovernorOmega.votingPeriod() + 1);
        vm.roll(block.number + 1);

        vm.expectRevert(IFraxGovernorOmega.WrongProposalState.selector);
        fraxGovernorOmega.rejectTransaction(address(multisig), startNonce);

        vm.expectRevert(); // Can't execute, nonce has moved beyond and Omega hasn't approved
        getSafe(address(multisig)).safe.execTransaction(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, originalTxHash)
        );

        (bytes32 originalTxHashReplay, , ) = createTransferFxsProposal(address(multisig), multisig.nonce());

        vm.expectRevert(FraxGuard.Unauthorized.selector); // Can't execute Omega hasn't approved
        getSafe(address(multisig)).safe.execTransaction(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            generateEoaSigs(3, originalTxHashReplay)
        );

        vm.stopPrank();
    }

    // Short circuit success works on Alpha
    function testAlphaProposeEarlySuccess() public {
        _testAlphaSetShortCircuitThreshold(10); // Set short circuit lower for the purp[ose of this test

        // put 100 FXS in timelockController to transfer later in proposal
        hoax(Constants.FRAX_TREASURY_2);
        fxs.transfer(address(timelockController), 100e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));

        // majorityFor allows skipping delay but still timelock
        vm.warp(fraxGovernorAlpha.proposalEta(pid));
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 100e18, "Bob received FXS");
        assertEq(fxs.balanceOf(address(timelockController)), 0, "TimelockController has no FXS");
        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is executed"
        );
    }

    // Short circuit failure works on Alpha
    function testAlphaProposeEarlyFailure() public {
        _testAlphaSetShortCircuitThreshold(10); // Set short circuit lower for the purp[ose of this test

        // put 100 FXS in timelockController to transfer later in proposal
        hoax(Constants.FRAX_TREASURY_2);
        fxs.transfer(address(timelockController), 100e18);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));

        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is defeated"
        );

        vm.expectRevert("Governor: proposal not successful");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 0, "Bob received no FXS");
        assertEq(fxs.balanceOf(address(timelockController)), 100e18, "TimelockController still has FXS");
        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is defeated"
        );
    }

    // Short circuit success works on Omega
    function testOmegaProposeEarlySuccess() public virtual {
        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createOptimisticProposal(
                address(multisig),
                fraxGovernorOmega,
                address(this),
                getSafe(address(multisig)).safe.nonce()
            );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        for (uint256 i = 0; i < accounts.length; ++i) {
            if (uint256(fraxGovernorOmega.state(pid)) == uint256(IGovernor.ProposalState.Active)) {
                hoax(accounts[i]);
                fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
            }
        }

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(
            uint256(IGovernor.ProposalState.Executed),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is executed"
        );
    }

    // Short circuit success works on Omega
    function testOmegaProposeEarlyFailure() public virtual {
        (uint256 pid, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        for (uint256 i = 0; i < accounts.length; ++i) {
            if (uint256(fraxGovernorOmega.state(pid)) == uint256(IGovernor.ProposalState.Active)) {
                hoax(accounts[i]);
                fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));
            }
        }

        assertEq(
            uint256(IGovernor.ProposalState.Defeated),
            uint256(fraxGovernorOmega.state(pid)),
            "Proposal state is defeated"
        );
    }

    // Regular success conditions with quorum for alpha
    function testAlphaProposeSuccess() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
        vm.stopPrank();

        hoax(accounts[1]);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        hoax(accounts[2]);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );
    }

    // Cannot vanilla propose with Omega, reverts
    function testOmegaProposeRevert() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.startPrank(accounts[0]);
        vm.expectRevert(IFraxGovernorOmega.CannotPropose.selector);
        fraxGovernorOmega.propose(targets, values, calldatas, "");
    }

    // Cannot vanilla cancel with Omega, reverts
    function testOmegaCancelRevert() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.startPrank(accounts[0]);
        vm.expectRevert(IFraxGovernorOmega.CannotCancelOptimisticTransaction.selector);
        fraxGovernorOmega.cancel(targets, values, calldatas, keccak256(bytes("")));
    }

    // Cannot call relay with Omega, reverts
    function testOmegaRelayRevert() public {
        vm.startPrank(accounts[0]);
        vm.expectRevert(IFraxGovernorOmega.CannotRelay.selector);
        fraxGovernorOmega.relay(address(0), 0, bytes(""));
    }

    // Can cancel Alpha proposals before the voting period starts
    function testAlphaProposeCancel() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        fraxGovernorAlpha.cancel(targets, values, calldatas, keccak256(bytes("")));

        assertEq(
            uint256(IGovernor.ProposalState.Canceled),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is canceled"
        );
        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("Governor: too late to cancel");
        fraxGovernorAlpha.cancel(targets, values, calldatas, keccak256(bytes("")));

        vm.stopPrank();
    }

    // Only Alpha can update quorum numerator
    function testAlphaUpdateQuorumNumerator() public {
        uint256 alphaQuorum = fraxGovernorAlpha.quorumNumerator();

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateQuorumNumerator(uint256)", alphaQuorum + 1);

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.updateQuorumNumerator(alphaQuorum + 1);

        assertEq(fraxGovernorAlpha.quorumNumerator(), alphaQuorum, "value didn't change");

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated({ oldQuorumNumerator: alphaQuorum, newQuorumNumerator: alphaQuorum + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.quorumNumerator(), alphaQuorum + 1, "value changed");
    }

    // Actual test for setting an Omega governance parameter through an Alpha propose()
    function testOmegaUpdateQuorumNumerator() public {
        uint256 omegaQuorum = fraxGovernorOmega.quorumNumerator();

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateQuorumNumerator(uint256)", omegaQuorum + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated({ oldQuorumNumerator: omegaQuorum, newQuorumNumerator: omegaQuorum + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.quorumNumerator(), omegaQuorum + 1, "value changed");
    }

    // Only Alpha can update timelock value
    function testAlphaUpdateTimelock() public {
        address timelock = fraxGovernorAlpha.$timelock();
        address newTimelock = address(1);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateTimelock(address)", newTimelock);

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.updateTimelock(newTimelock);

        assertEq(fraxGovernorAlpha.$timelock(), timelock, "value didn't change");

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit TimelockChange({ oldTimelock: timelock, newTimelock: newTimelock });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.$timelock(), newTimelock, "value changed");
    }

    // Only Alpha can update timelock value
    function testAlphaUpdateVoteExtension() public {
        uint64 voteExtension = fraxGovernorAlpha.$voteExtension();
        uint64 newVoteExtension = voteExtension + 1;

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setLateQuorumVoteExtension(uint64)", newVoteExtension);

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setLateQuorumVoteExtension(newVoteExtension);

        assertEq(fraxGovernorAlpha.$voteExtension(), voteExtension, "value didn't change");

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit LateQuorumVoteExtensionSet({ oldVoteExtension: voteExtension, newVoteExtension: newVoteExtension });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.$voteExtension(), newVoteExtension, "value changed");
    }

    function _testAlphaSetShortCircuitThreshold(uint256 newShortCircuit) internal {
        uint256 alphaShortCircuitThreshold = fraxGovernorAlpha.shortCircuitNumerator();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.updateShortCircuitNumerator(newShortCircuit);

        assertEq(fraxGovernorAlpha.shortCircuitNumerator(), alphaShortCircuitThreshold, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateShortCircuitNumerator(uint256)", newShortCircuit);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: alphaShortCircuitThreshold,
            newShortCircuitThreshold: newShortCircuit
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.shortCircuitNumerator(), newShortCircuit, "value changed");
        assertEq(
            fraxGovernorAlpha.shortCircuitNumerator(block.timestamp - 1),
            alphaShortCircuitThreshold,
            "old value preserved for old timestamps"
        );
    }

    // Only Alpha can update short circuit numerator
    function testAlphaSetShortCircuitThreshold() public {
        _testAlphaSetShortCircuitThreshold(fraxGovernorAlpha.shortCircuitNumerator() - 1);
    }

    // Only Alpha can update short circuit numerator
    function testOmegaSetShortCircuitThreshold() public {
        uint256 omegaShortCircuitThreshold = fraxGovernorOmega.shortCircuitNumerator();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.updateShortCircuitNumerator(omegaShortCircuitThreshold + 1);

        assertEq(fraxGovernorOmega.shortCircuitNumerator(), omegaShortCircuitThreshold, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateShortCircuitNumerator(uint256)", omegaShortCircuitThreshold + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: omegaShortCircuitThreshold,
            newShortCircuitThreshold: omegaShortCircuitThreshold + 1
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.shortCircuitNumerator(), omegaShortCircuitThreshold + 1, "value changed");
        assertEq(
            fraxGovernorOmega.shortCircuitNumerator(block.timestamp - 1),
            omegaShortCircuitThreshold,
            "old value preserved for old timestamps"
        );
    }

    // Can't increase shortcircuit threshold past 100
    function testAlphaShortCircuitNumeratorFailure() public {
        uint256 alphaDenom = fraxGovernorAlpha.quorumDenominator();

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateShortCircuitNumerator(uint256)", alphaDenom + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Can't increase shortcircuit threshold past 100
    function testOmegaShortCircuitNumeratorFailure() public {
        uint256 omegaDenom = fraxGovernorAlpha.quorumDenominator();

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateShortCircuitNumerator(uint256)", omegaDenom + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Only Alpha can update VeFxsVotingDelegation contract
    function testAlphaSetVeFxsVotingDelegation() public {
        address alphaVeFxsVotingDelegation = fraxGovernorAlpha.token();
        address newVotingDelegation = address(1);

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorAlpha.token(), alphaVeFxsVotingDelegation, "value didnt change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVeFxsVotingDelegation(address)", newVotingDelegation);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: alphaVeFxsVotingDelegation,
            newVotingDelegation: newVotingDelegation
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.token(), newVotingDelegation, "value changed");
    }

    // Only Alpha can update VeFxsVotingDelegation contract
    function testOmegaSetVeFxsVotingDelegation() public {
        address omegaVeFxsVotingDelegation = fraxGovernorOmega.token();
        address newVotingDelegation = address(1);

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorOmega.token(), omegaVeFxsVotingDelegation, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVeFxsVotingDelegation(address)", newVotingDelegation);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: omegaVeFxsVotingDelegation,
            newVotingDelegation: newVotingDelegation
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.token(), newVotingDelegation, "value changed");
    }

    // Only Alpha can update Voting delay
    function testAlphaSetVotingDelay() public {
        uint256 alphaVotingDelay = fraxGovernorAlpha.votingDelay();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingDelay(alphaVotingDelay + 1);

        assertEq(fraxGovernorAlpha.votingDelay(), alphaVotingDelay, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingDelay(uint256)", alphaVotingDelay + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VotingDelaySet({ oldVotingDelay: alphaVotingDelay, newVotingDelay: alphaVotingDelay + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.votingDelay(), alphaVotingDelay + 1, "value changed");
    }

    // Only Alpha can update Voting delay
    function testOmegaSetVotingDelay() public {
        uint256 omegaVotingDelay = fraxGovernorOmega.votingDelay();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setVotingDelay(omegaVotingDelay + 1);

        assertEq(fraxGovernorOmega.votingDelay(), omegaVotingDelay, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingDelay(uint256)", omegaVotingDelay + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VotingDelaySet({ oldVotingDelay: omegaVotingDelay, newVotingDelay: omegaVotingDelay + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.votingDelay(), omegaVotingDelay + 1, "value changed");
    }

    // Only Alpha can update Voting delay in block
    function testAlphaSetVotingDelayBlocks() public {
        uint256 alphaVotingDelayBlocks = fraxGovernorAlpha.$votingDelayBlocks();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingDelayBlocks(alphaVotingDelayBlocks + 1);

        assertEq(fraxGovernorAlpha.$votingDelayBlocks(), alphaVotingDelayBlocks, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingDelayBlocks(uint256)", alphaVotingDelayBlocks + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingDelayBlocksSet({
            oldVotingDelayBlocks: alphaVotingDelayBlocks,
            newVotingDelayBlocks: alphaVotingDelayBlocks + 1
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.$votingDelayBlocks(), alphaVotingDelayBlocks + 1, "value changed");
    }

    // Only Alpha can update Voting delay in blocks
    function testOmegaSetVotingDelayBlocks() public {
        uint256 omegaVotingDelayBlocks = fraxGovernorOmega.$votingDelayBlocks();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setVotingDelayBlocks(omegaVotingDelayBlocks + 1);

        assertEq(fraxGovernorOmega.$votingDelayBlocks(), omegaVotingDelayBlocks, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingDelayBlocks(uint256)", omegaVotingDelayBlocks + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VotingDelayBlocksSet({
            oldVotingDelayBlocks: omegaVotingDelayBlocks,
            newVotingDelayBlocks: omegaVotingDelayBlocks + 1
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.$votingDelayBlocks(), omegaVotingDelayBlocks + 1, "value changed");
    }

    // Only Alpha can update Voting period
    function testAlphaSetVotingPeriod() public {
        uint256 alphaVotingPeriod = fraxGovernorAlpha.votingPeriod();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingPeriod(alphaVotingPeriod + 1);

        assertEq(fraxGovernorAlpha.votingPeriod(), alphaVotingPeriod, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingPeriod(uint256)", alphaVotingPeriod + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VotingPeriodSet({ oldVotingPeriod: alphaVotingPeriod, newVotingPeriod: alphaVotingPeriod + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.votingPeriod(), alphaVotingPeriod + 1, "value changed");
    }

    // Only Alpha can update Voting period
    function testOmegaSetVotingPeriod() public {
        uint256 omegaVotingPeriod = fraxGovernorOmega.votingPeriod();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setVotingPeriod(omegaVotingPeriod + 1);

        assertEq(fraxGovernorOmega.votingPeriod(), omegaVotingPeriod, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setVotingPeriod(uint256)", omegaVotingPeriod + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit VotingPeriodSet({ oldVotingPeriod: omegaVotingPeriod, newVotingPeriod: omegaVotingPeriod + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.votingPeriod(), omegaVotingPeriod + 1, "value changed");
    }

    // Only Alpha can update Safe Voting period
    function testOmegaSetSafeVotingPeriod() public {
        uint256 newSafeVotingPeriod = 1 days;

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setSafeVotingPeriod(address(multisig), newSafeVotingPeriod);

        assertEq(fraxGovernorOmega.$safeVotingPeriod(address(multisig)), 0, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setSafeVotingPeriod(address,uint256)",
            address(multisig),
            newSafeVotingPeriod
        );

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit SafeVotingPeriodSet({
            safe: address(multisig),
            oldSafeVotingPeriod: 0,
            newSafeVotingPeriod: newSafeVotingPeriod
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.$safeVotingPeriod(address(multisig)), newSafeVotingPeriod, "value changed");

        (uint256 pid2, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            multisig.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorOmega.state(pid2)),
            "Proposal state is Active"
        );

        mineBlocksBySecond(fraxGovernorOmega.$safeVotingPeriod(address(multisig)));

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(pid2)),
            "Proposal state is Succeeded, at configured voting period. Default value would be later."
        );
    }

    // Only Alpha can update proposal threshold
    function testAlphaSetProposalThreshold() public {
        uint256 alphaProposalThreshold = fraxGovernorAlpha.proposalThreshold();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingPeriod(alphaProposalThreshold + 1);

        assertEq(fraxGovernorAlpha.proposalThreshold(), alphaProposalThreshold, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorAlpha);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setProposalThreshold(uint256)", alphaProposalThreshold + 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit ProposalThresholdSet({
            oldProposalThreshold: alphaProposalThreshold,
            newProposalThreshold: alphaProposalThreshold + 1
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorAlpha.proposalThreshold(), alphaProposalThreshold + 1, "value changed");
    }

    // Only Alpha can update proposal threshold
    function testOmegaSetProposalThreshold() public {
        uint256 omegaProposalThreshold = fraxGovernorOmega.proposalThreshold();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.setProposalThreshold(omegaProposalThreshold - 1);

        assertEq(fraxGovernorOmega.proposalThreshold(), omegaProposalThreshold, "value didn't change");

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setProposalThreshold(uint256)", omegaProposalThreshold - 1);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit ProposalThresholdSet({
            oldProposalThreshold: omegaProposalThreshold,
            newProposalThreshold: omegaProposalThreshold - 1
        });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.proposalThreshold(), omegaProposalThreshold - 1, "value changed");
    }

    // Only Alpha can change Omega safe configuration
    function testAddSafesToAllowlist() public {
        address[] memory _safeAllowlist = new address[](2);
        _safeAllowlist[0] = bob;
        _safeAllowlist[1] = address(0xabcd);

        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.addToSafeAllowlist(_safeAllowlist);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IFraxGovernorOmega.addToSafeAllowlist.selector, _safeAllowlist);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit AddToSafeAllowlist(_safeAllowlist[0]);
        vm.expectEmit(true, true, true, true);
        emit AddToSafeAllowlist(_safeAllowlist[1]);
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(1, fraxGovernorOmega.$safeAllowlist(_safeAllowlist[0]), "First configuration is set");
        assertEq(1, fraxGovernorOmega.$safeAllowlist(_safeAllowlist[1]), "Second configuration is set");
    }

    // Revert if safe is already allowlisted
    function testAddSafesToAllowlistAlreadyAllowlisted() public {
        address[] memory _safeAllowlist = new address[](1);
        _safeAllowlist[0] = address(multisig);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IFraxGovernorOmega.addToSafeAllowlist.selector, _safeAllowlist);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        //vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.AlreadyOnSafeAllowlist.selector, address(multisig)));
        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Only Alpha can change Omega safe configuration
    function testRemoveSafesFromAllowlist() public {
        address[] memory _safesToRemove = new address[](2);
        _safesToRemove[0] = address(multisig);
        _safesToRemove[1] = address(multisig2);

        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.removeFromSafeAllowlist(_safesToRemove);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IFraxGovernorOmega.removeFromSafeAllowlist.selector, _safesToRemove);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit RemoveFromSafeAllowlist(_safesToRemove[0]);
        vm.expectEmit(true, true, true, true);
        emit RemoveFromSafeAllowlist(_safesToRemove[1]);
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(0, fraxGovernorOmega.$safeAllowlist(_safesToRemove[0]), "First configuration is unset");
        assertEq(0, fraxGovernorOmega.$safeAllowlist(_safesToRemove[1]), "Second configuration is unset");
    }

    // Revert if safe is already not on the allowlist
    function testRemoveSafesFromAllowlistAlreadyNotOnAllowlist() public {
        address[] memory _safesToRemove = new address[](1);
        _safesToRemove[0] = address(0xabcd);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IFraxGovernorOmega.removeFromSafeAllowlist.selector, _safesToRemove);

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        //vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.NotOnSafeAllowlist.selector, address(0xabcd)));
        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Only Alpha can change Omega safe configuration
    function testAddDelegateCallToAllowlist() public {
        address[] memory _delegateCallAllowlist = new address[](2);
        _delegateCallAllowlist[0] = bob;
        _delegateCallAllowlist[1] = address(0xabcd);

        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.addToDelegateCallAllowlist(_delegateCallAllowlist);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IFraxGovernorOmega.addToDelegateCallAllowlist.selector,
            _delegateCallAllowlist
        );

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit AddToDelegateCallAllowlist(_delegateCallAllowlist[0]);
        vm.expectEmit(true, true, true, true);
        emit AddToDelegateCallAllowlist(_delegateCallAllowlist[1]);
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(1, fraxGovernorOmega.$delegateCallAllowlist(_delegateCallAllowlist[0]), "First configuration is set");
        assertEq(1, fraxGovernorOmega.$delegateCallAllowlist(_delegateCallAllowlist[1]), "Second configuration is set");
    }

    // Revert if safe is already allowlisted
    function testAddDelegateCallToAllowlistAlreadyAllowlisted() public {
        address[] memory _delegateCallAllowlist = new address[](1);
        _delegateCallAllowlist[0] = address(signMessageLib);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IFraxGovernorOmega.addToDelegateCallAllowlist.selector,
            _delegateCallAllowlist
        );

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        //vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.AlreadyOnDelegateCallAllowlist.selector, address(signMessageLib)));
        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Only Alpha can change Omega safe configuration
    function testRemoveDelegateCallFromAllowlist() public {
        address[] memory _delegateCallToRemove = new address[](1);
        _delegateCallToRemove[0] = address(signMessageLib);

        vm.expectRevert(IFraxGovernorOmega.NotTimelockController.selector);
        fraxGovernorOmega.removeFromDelegateCallAllowlist(_delegateCallToRemove);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IFraxGovernorOmega.removeFromDelegateCallAllowlist.selector,
            _delegateCallToRemove
        );

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        vm.expectEmit(true, true, true, true);
        emit RemoveFromDelegateCallAllowlist(_delegateCallToRemove[0]);
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(0, fraxGovernorOmega.$delegateCallAllowlist(_delegateCallToRemove[0]), "Configuration is unset");
    }

    // Revert if safe is already not on the allowlist
    function testRemoveDelegateCallFromAllowlistAlreadyNotOnAllowlist() public {
        address[] memory _delegateCallToRemove = new address[](1);
        _delegateCallToRemove[0] = address(0xabcd);

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IFraxGovernorOmega.removeFromDelegateCallAllowlist.selector,
            _delegateCallToRemove
        );

        hoax(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(pid);

        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        //vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.NotOnDelegateCallAllowlist.selector, address(0xabcd)));
        vm.expectRevert("TimelockController: underlying transaction reverted");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
    }

    // Fractional voting works as expected on Alpha
    function testFractionalVotingAlpha() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0], fraxGovernorAlpha.proposalSnapshot(pid));
        uint256 againstWeight = (weight * 50) / 100;
        uint256 forWeight = (weight * 10) / 100;
        uint256 abstainWeight = (weight * 40) / 100;

        uint256 delta = weight - (againstWeight + forWeight + abstainWeight);

        vm.startPrank(accounts[0]);

        // against, for, abstain
        bytes memory params = abi.encodePacked(
            uint128(againstWeight),
            uint128(forWeight + delta),
            uint128(abstainWeight)
        );

        fraxGovernorAlpha.castVoteWithReasonAndParams(pid, 0, "reason", params);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorAlpha.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes, "Against votes is largest");
        assertGt(abstainVotes, forVotes, "Abstain votes is second largest");
        assertEq(weight, againstVotes + forVotes + abstainVotes, "All 3 = total voting weight");

        bytes memory params2 = abi.encodePacked(uint128(1), uint128(0), uint128(0));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVoteWithReasonAndParams(pid, 0, "reason", params2);

        bytes memory params3 = abi.encodePacked(uint128(0), uint128(0), uint128(0));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVoteWithReasonAndParams(pid, 0, "reason", params3);
        vm.stopPrank();
    }

    // Fractional voting works as expected on Omega
    function testFractionalVotingOmega() public {
        (uint256 pid, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0], fraxGovernorOmega.proposalSnapshot(pid));
        uint256 againstWeight = (weight * 50) / 100;
        uint256 forWeight = (weight * 10) / 100;
        uint256 abstainWeight = (weight * 40) / 100;

        uint256 delta = weight - (againstWeight + forWeight + abstainWeight);

        vm.startPrank(accounts[0]);

        // against, for, abstain
        bytes memory params = abi.encodePacked(
            uint128(againstWeight),
            uint128(forWeight + delta),
            uint128(abstainWeight)
        );

        fraxGovernorOmega.castVoteWithReasonAndParams(pid, 0, "reason", params);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorOmega.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes, "Against votes is largest");
        assertGt(abstainVotes, forVotes, "abstain votes is second largest");
        assertEq(weight, againstVotes + forVotes + abstainVotes, "All 3 = total voting weight");

        bytes memory params2 = abi.encodePacked(uint128(1), uint128(0), uint128(0));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVoteWithReasonAndParams(pid, 0, "reason", params2);

        bytes memory params3 = abi.encodePacked(uint128(0), uint128(0), uint128(0));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVoteWithReasonAndParams(pid, 0, "reason", params3);
        vm.stopPrank();
    }

    function testFractionalVotingBySigAlpha() public {
        // start local and fork test at same point in time
        vm.warp(1_690_900_429);
        vm.roll(FORK_BLOCK + 100);

        dealCreateLockFxs(eoaOwners[0], 100e18);

        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        bytes memory params;

        uint256 weight = veFxsVotingDelegation.getVotes(eoaOwners[0], fraxGovernorAlpha.proposalSnapshot(pid));
        {
            uint256 againstWeight = (weight * 50) / 100;
            uint256 forWeight = (weight * 10) / 100;
            uint256 abstainWeight = (weight * 40) / 100;

            uint256 delta = weight - (againstWeight + forWeight + abstainWeight);

            // against, for, abstain
            params = abi.encodePacked(
                uint128(againstWeight),
                uint128(forWeight + delta),
                uint128(abstainWeight),
                uint128(0)
            );
        }

        uint8 v;
        bytes32 r;
        bytes32 s;

        {
            (
                ,
                string memory name,
                string memory version,
                uint256 chainId,
                address verifyingContract,
                ,

            ) = fraxGovernorAlpha.eip712Domain();

            bytes32 TYPE_HASH = keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            );
            bytes32 domainSeparator = keccak256(
                abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
            );
            bytes32 structHash = keccak256(
                abi.encode(
                    fraxGovernorAlpha.EXTENDED_BALLOT_TYPEHASH(),
                    pid,
                    0,
                    keccak256(bytes("reason")),
                    keccak256(params)
                )
            );
            bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
            (v, r, s) = vm.sign(addressToPk[eoaOwners[0]], digest);
        }

        fraxGovernorAlpha.castVoteWithReasonAndParamsBySig({
            proposalId: pid,
            support: 0,
            reason: "reason",
            params: params,
            v: v,
            r: r,
            s: s
        });
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorAlpha.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes, "Against votes is largest");
        assertGt(abstainVotes, forVotes, "abstain votes is second largest");
        assertEq(weight, againstVotes + forVotes + abstainVotes, "All 3 = total voting weight");

        // Can't replay
        vm.expectRevert("GovernorCountingFractional: signature has already been used");
        fraxGovernorAlpha.castVoteWithReasonAndParamsBySig({
            proposalId: pid,
            support: 0,
            reason: "reason",
            params: params,
            v: v,
            r: r,
            s: s
        });
    }

    function testVotingBySigAlpha() public {
        dealCreateLockFxs(eoaOwners[0], 100e18);

        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint8 v;
        bytes32 r;
        bytes32 s;

        {
            (
                ,
                string memory name,
                string memory version,
                uint256 chainId,
                address verifyingContract,
                ,

            ) = fraxGovernorAlpha.eip712Domain();

            bytes32 TYPE_HASH = keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            );
            bytes32 domainSeparator = keccak256(
                abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
            );
            bytes32 structHash = keccak256(
                abi.encode(fraxGovernorAlpha.BALLOT_TYPEHASH(), pid, uint8(GovernorCompatibilityBravo.VoteType.Against))
            );
            bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
            (v, r, s) = vm.sign(addressToPk[eoaOwners[0]], digest);
        }

        fraxGovernorAlpha.castVoteBySig({
            proposalId: pid,
            support: uint8(GovernorCompatibilityBravo.VoteType.Against),
            v: v,
            r: r,
            s: s
        });
        (uint256 againstVotes, , ) = fraxGovernorAlpha.proposalVotes(pid);

        assertGt(againstVotes, 0, "Voting against by sig worked");

        // Can't replay
        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVoteBySig({
            proposalId: pid,
            support: uint8(GovernorCompatibilityBravo.VoteType.Against),
            v: v,
            r: r,
            s: s
        });
    }

    function testFractionalVotingBySigOmega() public {
        // start local and fork test at same point in time
        vm.warp(1_690_900_429);
        vm.roll(FORK_BLOCK + 100);

        dealCreateLockFxs(eoaOwners[0], 100e18);

        (uint256 pid, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);
        bytes memory params;

        uint256 weight = veFxsVotingDelegation.getVotes(eoaOwners[0], fraxGovernorOmega.proposalSnapshot(pid));
        {
            uint256 againstWeight = (weight * 50) / 100;
            uint256 forWeight = (weight * 10) / 100;
            uint256 abstainWeight = (weight * 40) / 100;

            uint256 delta = weight - (againstWeight + forWeight + abstainWeight);
            // against, for, abstain
            params = abi.encodePacked(
                uint128(againstWeight),
                uint128(forWeight + delta),
                uint128(abstainWeight),
                uint128(0)
            );
        }
        uint8 v;
        bytes32 r;
        bytes32 s;

        {
            (
                ,
                string memory name,
                string memory version,
                uint256 chainId,
                address verifyingContract,
                ,

            ) = fraxGovernorOmega.eip712Domain();

            bytes32 TYPE_HASH = keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            );
            bytes32 domainSeparator = keccak256(
                abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
            );
            bytes32 structHash = keccak256(
                abi.encode(
                    fraxGovernorOmega.EXTENDED_BALLOT_TYPEHASH(),
                    pid,
                    0,
                    keccak256(bytes("reason")),
                    keccak256(params)
                )
            );
            bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
            (v, r, s) = vm.sign(addressToPk[eoaOwners[0]], digest);
        }

        fraxGovernorOmega.castVoteWithReasonAndParamsBySig({
            proposalId: pid,
            support: 0,
            reason: "reason",
            params: params,
            v: v,
            r: r,
            s: s
        });
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorOmega.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes, "Against votes is largest");
        assertGt(abstainVotes, forVotes, "abstain votes is second largest");
        assertEq(weight, againstVotes + forVotes + abstainVotes, "All 3 = total voting weight");

        // Can't replay
        vm.expectRevert("GovernorCountingFractional: signature has already been used");
        fraxGovernorOmega.castVoteWithReasonAndParamsBySig({
            proposalId: pid,
            support: 0,
            reason: "reason",
            params: params,
            v: v,
            r: r,
            s: s
        });
    }

    function testVotingBySigOmega() public {
        dealCreateLockFxs(eoaOwners[0], 100e18);

        (uint256 pid, , , ) = createOptimisticProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint8 v;
        bytes32 r;
        bytes32 s;

        {
            (
                ,
                string memory name,
                string memory version,
                uint256 chainId,
                address verifyingContract,
                ,

            ) = fraxGovernorOmega.eip712Domain();

            bytes32 TYPE_HASH = keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            );
            bytes32 domainSeparator = keccak256(
                abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
            );
            bytes32 structHash = keccak256(
                abi.encode(fraxGovernorOmega.BALLOT_TYPEHASH(), pid, uint8(GovernorCompatibilityBravo.VoteType.Against))
            );
            bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
            (v, r, s) = vm.sign(addressToPk[eoaOwners[0]], digest);
        }

        fraxGovernorOmega.castVoteBySig({
            proposalId: pid,
            support: uint8(GovernorCompatibilityBravo.VoteType.Against),
            v: v,
            r: r,
            s: s
        });
        (uint256 againstVotes, , ) = fraxGovernorOmega.proposalVotes(pid);

        assertGt(againstVotes, 0, "Voting against by sig worked");

        // Can't replay
        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVoteBySig({
            proposalId: pid,
            support: uint8(GovernorCompatibilityBravo.VoteType.Against),
            v: v,
            r: r,
            s: s
        });
    }

    // batchAddTransaction() revert condition test
    function testAddTransactionBatchFailure() public {
        address[] memory teamSafes = new address[](0);
        IFraxGovernorOmega.TxHashArgs[] memory args = new IFraxGovernorOmega.TxHashArgs[](1);
        bytes[] memory signatures = new bytes[](1);

        vm.expectRevert(IFraxGovernorOmega.BadBatchArgs.selector);
        fraxGovernorOmega.batchAddTransaction(teamSafes, args, signatures);
    }

    // Successful batchAddTransaction()
    function testAddTransactionBatch() public {
        uint256 currentNonce = multisig.nonce();
        (bytes32 txHash1, IFraxGovernorOmega.TxHashArgs memory args1, ) = createTransferFxsProposal(
            address(multisig),
            currentNonce
        );
        (bytes32 txHash2, IFraxGovernorOmega.TxHashArgs memory args2, ) = createTransferFxsProposal(
            address(multisig),
            currentNonce + 1
        );

        address[] memory teamSafes = new address[](2);
        teamSafes[0] = address(multisig);
        teamSafes[1] = address(multisig);

        IFraxGovernorOmega.TxHashArgs[] memory args = new IFraxGovernorOmega.TxHashArgs[](2);
        args[0] = args1;
        args[1] = args2;

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = generateEoaSigs(3, txHash1);
        signatures[1] = generateEoaSigs(3, txHash2);

        fraxGovernorOmega.batchAddTransaction(teamSafes, args, signatures);
    }

    // Revert condition for bulk cast vote Alpha
    function testBulkCastVoteRevertAlpha() public {
        uint256[] memory proposalIds = new uint256[](2);
        uint8[] memory support = new uint8[](1);

        vm.expectRevert(FraxGovernorBase.ParamLengthsNotEqual.selector);
        fraxGovernorAlpha.bulkCastVote(proposalIds, support);
    }

    // Revert condition for bulk cast vote Omega
    function testBulkCastVoteRevertOmega() public {
        uint256[] memory proposalIds = new uint256[](1);
        uint8[] memory support = new uint8[](2);

        vm.expectRevert(FraxGovernorBase.ParamLengthsNotEqual.selector);
        fraxGovernorOmega.bulkCastVote(proposalIds, support);
    }

    // Bulk cast vote works for Alpha
    function testBulkCastVoteAlpha() public {
        address proposer = accounts[0];
        address prevOwner = eoaOwners[0];
        address oldOwner = eoaOwners[4];

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        (uint256 pid2, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: accounts[1],
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        uint256[] memory proposalIds = new uint256[](2);
        uint8[] memory support = new uint8[](2);

        proposalIds[0] = pid;
        proposalIds[1] = pid2;
        support[0] = uint8(GovernorCompatibilityBravo.VoteType.For);
        support[1] = uint8(GovernorCompatibilityBravo.VoteType.Against);

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint256 weight = veFxsVotingDelegation.getPastVotes(accounts[0], fraxGovernorAlpha.proposalSnapshot(pid));

        hoax(accounts[0]);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(accounts[0], pid, uint8(GovernorCompatibilityBravo.VoteType.For), weight, "");
        vm.expectEmit(true, true, true, true);
        emit VoteCast(accounts[0], pid2, uint8(GovernorCompatibilityBravo.VoteType.Against), weight, "");
        fraxGovernorAlpha.bulkCastVote(proposalIds, support);
    }

    // Bulk cast vote works for Omega
    function testBulkCastVoteOmega() public {
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();

        (uint256 pid, , , ) = createOptimisticTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            startNonce + 1
        );

        (uint256 pid2, , , ) = createOptimisticTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            startNonce + 2
        );

        uint256[] memory proposalIds = new uint256[](2);
        uint8[] memory support = new uint8[](2);

        proposalIds[0] = pid;
        proposalIds[1] = pid2;
        support[0] = uint8(GovernorCompatibilityBravo.VoteType.For);
        support[1] = uint8(GovernorCompatibilityBravo.VoteType.Against);

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        uint256 weight = veFxsVotingDelegation.getPastVotes(accounts[0], fraxGovernorOmega.proposalSnapshot(pid));

        hoax(accounts[0]);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(accounts[0], pid, uint8(GovernorCompatibilityBravo.VoteType.For), weight, "");
        vm.expectEmit(true, true, true, true);
        emit VoteCast(accounts[0], pid2, uint8(GovernorCompatibilityBravo.VoteType.Against), weight, "");
        fraxGovernorOmega.bulkCastVote(proposalIds, support);
    }

    // Alpha's voting period gets extended when quorum is reached within lateQuorumVoteExtension() at earliest point
    function testAlphaLateQuorumExtensionFirstSecond() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        uint64 extension = fraxGovernorAlpha.lateQuorumVoteExtension();

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + fraxGovernorAlpha.votingPeriod() - extension + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
        vm.stopPrank();

        hoax(accounts[1]);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        hoax(accounts[2]);
        vm.expectEmit(true, true, true, true);
        emit ProposalExtended({ proposalId: pid, extendedDeadline: uint64(block.timestamp) + extension });
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(extension - 1);
        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(2);
        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );
    }

    // Alpha's voting period gets extended when quorum is reached within lateQuorumVoteExtension() at latest point
    function testAlphaLateQuorumExtensionLastSecond() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        uint64 extension = fraxGovernorAlpha.lateQuorumVoteExtension();

        vm.startPrank(accounts[0]);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + fraxGovernorAlpha.votingPeriod());

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
        vm.stopPrank();

        hoax(accounts[1]);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        hoax(accounts[2]);
        vm.expectEmit(true, true, true, true);
        emit ProposalExtended({ proposalId: pid, extendedDeadline: uint64(block.timestamp) + extension });
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(extension);
        assertEq(
            uint256(IGovernor.ProposalState.Active),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is active"
        );

        mineBlocksBySecond(1);
        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(pid)),
            "Proposal state is succeeded"
        );
    }

    // Safe won't eip1271 sign if Omega or Alpha haven't signed
    function testIsValidSignatureFailureNoOmegaNoalpha() public {
        (bytes32 messageDigest, bytes32 safeMessage) = generateMessageDigest(address(multisig));

        vm.expectRevert("Hash not approved");
        getSafe(address(multisig)).safe.isValidSignature(bytes.concat(messageDigest), generateEoaSigs(4, safeMessage));
    }

    function testAddTransactionSignatureOmega() public {
        uint256 nonce = multisig.nonce();
        (bytes32 messageDigest, bytes32 safeMessage) = generateMessageDigest(address(multisig));
        bytes memory data = abi.encodeCall(SignMessageLib.signMessage, (bytes.concat(messageDigest)));

        bytes32 txHash = getSafe(address(multisig)).safe.getTransactionHash({
            to: address(signMessageLib),
            value: 0,
            data: data,
            operation: Enum.Operation.DelegateCall,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: address(0),
            _nonce: nonce
        });

        IFraxGovernorOmega.TxHashArgs memory args = IFraxGovernorOmega.TxHashArgs({
            to: address(signMessageLib),
            value: 0,
            data: data,
            operation: Enum.Operation.DelegateCall,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: address(0),
            _nonce: nonce
        });

        uint256 optimisticProposalId = fraxGovernorOmega.addTransaction(
            address(multisig),
            args,
            generateEoaSigs(3, txHash)
        );

        mineBlocksBySecond(fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + 1);

        hoax(accounts[0]);
        fraxGovernorOmega.castVote(optimisticProposalId, uint8(GovernorCompatibilityBravo.VoteType.For));

        // Voting is done for optimistic tx, it was successful
        mineBlocksBySecond(fraxGovernorOmega.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorOmega.state(optimisticProposalId)),
            "Proposal state is succeeded"
        );
        {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory calldatas = new bytes[](1);

            targets[0] = address(multisig);
            calldatas[0] = abi.encodeCall(GnosisSafe.approveHash, (txHash));

            fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));
        }
        vm.startPrank(eoaOwners[0]);
        vm.expectEmit(true, true, true, true);
        emit SignMsg(safeMessage);
        getSafe(address(multisig)).safe.execTransaction({
            to: address(signMessageLib),
            value: 0,
            data: data,
            operation: Enum.Operation.DelegateCall,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            signatures: generateEoaSigs(3, txHash)
        });
        vm.stopPrank();

        assertEq(
            getSafe(address(multisig)).safe.signedMessages(safeMessage),
            1,
            "safeMessage is marked as signed after passing governance"
        );
        assertEq(
            getSafe(address(multisig)).safe.isValidSignature(
                bytes.concat(messageDigest),
                "" // We don't care about the signatures
            ),
            EIP1271_MAGIC_VALUE,
            "Successfully validate signature"
        );
        assertEq(
            getSafe(address(multisig)).safe.isValidSignature(
                messageDigest,
                "" // We don't care about the signatures
            ),
            UPDATED_MAGIC_VALUE,
            "Test both function selectors"
        );
    }

    function testAddTransactionSignatureAlpha() public {
        (bytes32 messageDigest, bytes32 safeMessage) = generateMessageDigest(address(multisig));
        bytes memory data = abi.encodeCall(SignMessageLib.signMessage, (bytes.concat(messageDigest)));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(multisig);
        calldatas[0] = genericAlphaSafeProposalData({
            to: address(signMessageLib),
            value: 0,
            data: data,
            operation: Enum.Operation.DelegateCall
        });

        hoax(accounts[0]);
        uint256 proposalId = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        mineBlocksBySecond(fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + 1);

        votePassingAlphaQuorum(proposalId);

        // Voting is done for tx, it was successful
        mineBlocksBySecond(fraxGovernorAlpha.votingPeriod());

        assertEq(
            uint256(IGovernor.ProposalState.Succeeded),
            uint256(fraxGovernorAlpha.state(proposalId)),
            "Proposal state is succeeded"
        );

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(proposalId));
        vm.expectEmit(true, true, true, true);
        emit SignMsg(safeMessage);
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(
            getSafe(address(multisig)).safe.signedMessages(safeMessage),
            1,
            "safeMessage is marked as signed after passing governance"
        );
        assertEq(
            getSafe(address(multisig)).safe.isValidSignature(
                bytes.concat(messageDigest),
                "" // We don't care about the signatures
            ),
            EIP1271_MAGIC_VALUE,
            "Successfully validate signature, don't need EOA approval"
        );
        assertEq(
            getSafe(address(multisig)).safe.isValidSignature(
                messageDigest,
                "" // We don't care about the signatures
            ),
            UPDATED_MAGIC_VALUE,
            "Test both function selectors"
        );
    }
}
