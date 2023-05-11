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

    // Assert that we can individual voting weight in the past
    function testGetPastVotes() public {
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(IVeFxsVotingDelegation.TimestampInFuture.selector);
        veFxsVotingDelegation.getPastVotes(accounts[0].account, block.timestamp);

        assertEq(
            veFxs.balanceOf(accounts[0].account, block.timestamp - 1),
            veFxsVotingDelegation.getPastVotes(accounts[0].account, block.timestamp - 1)
        );
    }

    // Assert that total supply with block numbers work as expected
    function testGetPastTotalSupply() public {
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + (1 days / BLOCK_TIME));

        vm.expectRevert(IVeFxsVotingDelegation.BlockNumberInFuture.selector);
        veFxsVotingDelegation.getPastTotalSupply(block.timestamp);

        assertEq(veFxsVotingDelegation.getPastTotalSupply(block.number - 1), veFxs.totalSupplyAt(block.number - 1));
    }

    // Can't vote if you have no weight
    function testCantVoteZeroWeight() public {
        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        (uint256 pid2, , , ) = createRealVetoTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        vm.expectRevert("GovernorCountingFractional: no weight");
        fraxGovernorAlpha.castVote(pid, 0);

        vm.expectRevert("GovernorCountingFractional: no weight");
        fraxGovernorOmega.castVote(pid2, 0);
    }

    // Assert that users with no veFXS locks / balances have 0 voting weight
    function testNoLockGetVotesReturnsZero() public {
        // has lock started after, -13 because we move forward 12 at end of test setup
        assertEq(0, veFxsVotingDelegation.getVotes(accounts[0].account, block.timestamp - 13));

        // never locked
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

        vm.warp(veFxs.locked(accounts[0].account).end);

        hoax(accounts[0].account);
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
        ) = createRealVetoTxProposal(
                address(multisig),
                fraxGovernorOmega,
                bob,
                getSafe(address(multisig)).safe.nonce()
            );

        hoax(bob);
        vm.expectRevert(IFraxGovernorOmega.CannotCancelOptimisticTransaction.selector);
        fraxGovernorOmega.cancel(targets, values, calldatas, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorOmega.state(pid)));
    }

    // Various reverts in propose function for Omega
    function testBadProposeOmega() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";

        vm.startPrank(accounts[0].account);
        vm.expectRevert("Governor: invalid proposal length");
        fraxGovernorOmega.propose(targets, values, calldatas, "");

        uint256[] memory values2 = new uint256[](1);
        bytes[] memory calldatas2 = new bytes[](2);

        vm.expectRevert("Governor: invalid proposal length");
        fraxGovernorOmega.propose(targets, values2, calldatas2, "");

        address[] memory targets0 = new address[](0);
        uint256[] memory values0 = new uint256[](0);
        bytes[] memory calldatas0 = new bytes[](0);

        vm.expectRevert("Governor: empty proposal");
        fraxGovernorOmega.propose(targets0, values0, calldatas0, "");

        fraxGovernorOmega.propose(targets, values2, calldatas, "");
        vm.expectRevert("Governor: proposal already exists");
        fraxGovernorOmega.propose(targets, values2, calldatas, "");

        vm.stopPrank();
    }

    // Various reverts in propose function for Alpha
    function testBadProposeAlpha() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";

        vm.startPrank(accounts[0].account);
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

    // Revert on Omega propose() when a registered Gnosis Safe is the target
    // This is undesirable because Omega would be able to call safe.approveHash() and any other
    // owner functions outside of the Frax Team addTransaction() flow.
    function testCantCallProposeOmegaBadTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        targets[0] = address(multisig);

        hoax(eoaOwners[0].account);
        vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.DisallowedTarget.selector, address(multisig)));
        fraxGovernorOmega.propose(targets, values, calldatas, "");
    }

    // Cannot call addTransaction() for a safe that isnt registered
    function testAddAbortTransactionSafeNotAllowlisted() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            address(getSafe(address(multisig)).safe),
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0].account);
        vm.expectRevert(FraxGovernorBase.Unauthorized.selector);
        fraxGovernorOmega.addTransaction(bob, args, generateThreeEOASigs(txHash));

        hoax(eoaOwners[0].account);
        vm.expectRevert(FraxGovernorBase.Unauthorized.selector);
        fraxGovernorOmega.abortTransaction(bob, generateThreeEOASigs(txHash));
    }

    // Cannot call addTransaction() for a safe that already had addTransaction() called for that nonce
    function testAddTransactionNonceReserved() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0].account);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateThreeEOASigs(txHash));

        hoax(eoaOwners[0].account);
        vm.expectRevert(IFraxGovernorOmega.NonceReserved.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateThreeEOASigs(txHash));
    }

    // Cannot call addTransaction() for a safe where the nonce is already beyond the provided one
    function testAddTransactionNonceBelowCurrent() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce() - 1
        );

        hoax(eoaOwners[0].account);
        vm.expectRevert(IFraxGovernorOmega.WrongNonce.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, generateThreeEOASigs(txHash));
    }

    // Cannot call addTransaction() with invalid signatures
    function testAddAbortTransactionBadSignatures() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            bob,
            getSafe(address(multisig)).safe.nonce()
        );

        vm.startPrank(eoaOwners[0].account);
        vm.expectRevert(IFraxGovernorOmega.WrongSafeSignatureType.selector);
        fraxGovernorOmega.addTransaction(address(multisig), args, "");

        vm.expectRevert(IFraxGovernorOmega.WrongSafeSignatureType.selector);
        fraxGovernorOmega.abortTransaction(address(multisig), "");

        vm.expectRevert("GS026");
        fraxGovernorOmega.addTransaction(address(multisig), args, generateThreeEoaSigsWrongOrder(txHash));

        vm.expectRevert("GS026");
        fraxGovernorOmega.abortTransaction(address(multisig), generateThreeEoaSigsWrongOrder(txHash));

        vm.stopPrank();
    }

    // Cannot call addTransaction() with the safe as a target
    function testDisallowedTxTargets() public {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args) = createNoOpProposal(
            address(getSafe(address(multisig)).safe),
            address(getSafe(address(multisig)).safe),
            getSafe(address(multisig)).safe.nonce()
        );

        hoax(eoaOwners[0].account);
        vm.expectRevert(abi.encodeWithSelector(IFraxGovernorOmega.DisallowedTarget.selector, address(multisig)));
        fraxGovernorOmega.addTransaction(address(multisig), args, generateThreeEOASigs(txHash));
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

        hoax(bob);
        vm.expectRevert(FraxGovernorBase.SenderVotingWeightBelowProposalThreshold.selector);
        fraxGovernorOmega.propose(targets, values, calldatas, "");
    }

    // Test a safe swap owner proposal that no one votes on
    function testSwapOwnerNoVotes() public {
        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;
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

        assert(multisig.isOwner(oldOwner));
        assertFalse(multisig.isOwner(proposer));

        assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay());
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + 1);
        assertEq(uint256(IGovernor.ProposalState.Active), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp - 1 + fraxGovernorAlpha.votingPeriod());
        vm.roll(block.number + fraxGovernorOmega.votingPeriod() / BLOCK_TIME);

        assertEq(uint256(IGovernor.ProposalState.Active), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + 1);
        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorAlpha.state(pid)));

        vm.expectRevert("Governor: proposal not successful");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertFalse(multisig.isOwner(proposer));
        assert(multisig.isOwner(prevOwner));
        assert(multisig.isOwner(oldOwner));
    }

    // Test that frax gov proposals do not reach an expired state
    function testSwapOwnerDoesntExpire() public {
        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;
        assertFalse(multisig.isOwner(proposer));

        address account = accounts[0].account;
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(account, 21_000_000e18);

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

        assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        assertEq(uint256(IGovernor.ProposalState.Active), uint256(fraxGovernorAlpha.state(pid)));

        hoax(account);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        vm.warp(block.timestamp + fraxGovernorAlpha.votingPeriod());
        vm.roll(block.number + fraxGovernorAlpha.votingPeriod() / BLOCK_TIME);
        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + 1000 days);
        vm.roll(block.number + (1000 days / BLOCK_TIME));
        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));

        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorAlpha.state(pid)));

        assertFalse(multisig.isOwner(oldOwner));
        assert(multisig.isOwner(prevOwner));
        assert(multisig.isOwner(proposer));
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
                    eoaOwners[i].account,
                    getSafe(address(multisig)).safe.nonce() + i
                );

            assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorOmega.state(pid)));

            vm.warp(block.timestamp + fraxGovernorOmega.votingDelay());
            vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

            assertEq(uint256(IGovernor.ProposalState.Pending), uint256(fraxGovernorOmega.state(pid)));

            vm.warp(block.timestamp + 1);
            assertEq(uint256(IGovernor.ProposalState.Active), uint256(fraxGovernorOmega.state(pid)));

            vm.warp(block.timestamp - 1 + fraxGovernorOmega.votingPeriod());
            vm.roll(block.number + fraxGovernorOmega.votingPeriod() / BLOCK_TIME);

            assertEq(uint256(IGovernor.ProposalState.Active), uint256(fraxGovernorOmega.state(pid)));

            vm.warp(block.timestamp + 1);
            assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pid)));

            fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));
            assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorOmega.state(pid)));
        }
    }

    // Alpha and Omega proposals work independent of one another
    function testOverlappingSwapVeto() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        address account = accounts[0].account;
        dealLockMoreFxs(account, 1_005_585e18);

        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        address accountB = accounts[1].account;
        dealLockMoreFxs(accountB, 50_000_000e18);

        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;
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

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        hoax(accountB);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        hoax(account);
        fraxGovernorOmega.castVote(pidV, uint8(GovernorCompatibilityBravo.VoteType.For));

        // Voting is done for veto tx, it was successful
        vm.warp(block.timestamp + fraxGovernorOmega.votingPeriod());
        vm.roll(block.number + fraxGovernorOmega.votingPeriod() / BLOCK_TIME);

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));
        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pidV)));

        // execute swap owner
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        // Execute veto tx
        fraxGovernorOmega.execute(targetsV, valuesV, calldatasV, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorAlpha.state(pid)));
        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorOmega.state(pidV)));
    }

    // Can resolve optimistic proposals out of order if necessary
    function testMisorderExecSuccess() public {
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();

        // put 100 FXS in safe to transfer later in proposal
        deal(address(fxs), address(getSafe(address(multisig)).safe), 100e18);

        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        address account = accounts[0].account;
        dealLockMoreFxs(account, 1_005_585e18);

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createRealVetoTxProposal(address(multisig), fraxGovernorOmega, address(this), startNonce);

        (uint256 pidV, , , ) = createOptimisticTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            startNonce + 1
        );

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        assertEq(veFxsVotingDelegation.getVotes(account, block.timestamp), veFxs.balanceOf(accounts[0].account));

        hoax(account);
        fraxGovernorOmega.castVote(pidV, uint8(GovernorCompatibilityBravo.VoteType.Against));

        // Voting is done for both.
        vm.warp(block.timestamp + fraxGovernorOmega.votingPeriod());
        vm.roll(block.number + fraxGovernorOmega.votingPeriod() / BLOCK_TIME);

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pid)));
        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorOmega.state(pidV)));

        (bytes32 successHash, ) = createTransferFxsProposal(address(multisig), multisig.nonce());
        (bytes32 rejectionHash, ) = createNoOpProposal(address(multisig), address(multisig), startNonce + 1);

        // Owner cannot execute before Omega approves
        vm.startPrank(accounts[0].account);
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
            generateFourEoaSigs(successHash) // try with 4/6 EOA owner signatures
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
            generateThreeEoaSigsAndOmega(successHash)
        );

        // Owner can execute because Omega already approved
        vm.startPrank(accounts[0].account);
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
            generateThreeEoaSigsAndOmega(successHash)
        );

        assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 1);
        assertEq(fxs.balanceOf(address(this)), 100e18);

        (bytes32 txHash2, ) = createNoOpProposal(
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
            generateThreeEoaSigsAndOmega(txHash2)
        );
        vm.stopPrank();

        assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 2);
    }

    // Alpha works with multiple gnosis safes
    function testManyMultisigsAlpha() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;

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

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        vm.startPrank(accounts[0].account);
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));
        assert(fraxGovernorAlpha.hasVoted(pid, accounts[0].account));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));

        fraxGovernorAlpha.castVote(pid2, uint8(GovernorCompatibilityBravo.VoteType.For));

        vm.warp(block.timestamp + fraxGovernorAlpha.votingPeriod());
        vm.roll(block.number + fraxGovernorAlpha.votingPeriod() / BLOCK_TIME);

        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorAlpha.state(pid)));
        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid2)));

        vm.stopPrank();
    }

    // Omega works with multiple gnosis safes
    function testManyMultisigsOmega() public {
        // put 100 FXS in safe to transfer later in proposal
        deal(address(fxs), address(multisig), 100e18);
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();
        uint256 startNonce2 = getSafe(address(multisig2)).safe.nonce();

        (
            uint256 pid,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = createRealVetoTxProposal(
                address(multisig),
                fraxGovernorOmega,
                address(this),
                getSafe(address(multisig)).safe.nonce()
            );

        (uint256 pid2, , , ) = createRealVetoTxProposal(
            address(multisig2),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig2)).safe.nonce()
        );

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        vm.startPrank(accounts[0].account);
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));
        assert(fraxGovernorOmega.hasVoted(pid, accounts[0].account));

        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Abstain));

        fraxGovernorOmega.castVote(pid2, uint8(GovernorCompatibilityBravo.VoteType.Against));

        vm.stopPrank();

        vm.warp(block.timestamp + fraxGovernorOmega.votingPeriod());
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks());

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pid)));
        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorOmega.state(pid2)));

        {
            (bytes32 txHash, ) = createTransferFxsProposal(address(multisig), multisig.nonce());
            fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));

            vm.startPrank(accounts[0].account);

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
                generateThreeEoaSigsAndOmega(txHash)
            );
            vm.stopPrank();
            assertEq(getSafe(address(multisig)).safe.nonce(), startNonce + 1);
        }

        (bytes32 rejectTxHash, ) = createNoOpProposal(address(multisig2), address(multisig2), multisig2.nonce());
        fraxGovernorOmega.rejectTransaction(address(multisig2), multisig2.nonce());

        vm.startPrank(accounts[0].account);
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
            generateThreeEoaSigsAndOmega(rejectTxHash)
        );
        vm.stopPrank();
        assertEq(getSafe(address(multisig2)).safe.nonce(), startNonce2 + 1);
    }

    // Frax Team can abort proposals
    function testAbortTeamTx() public {
        uint256 startNonce = getSafe(address(multisig)).safe.nonce();

        (uint256 pid, , , ) = createRealVetoTxProposal(address(multisig), fraxGovernorOmega, address(this), startNonce);

        (bytes32 originalTxHash, ) = createTransferFxsProposal(address(multisig), startNonce);

        (bytes32 abortTxHash, ) = createNoOpProposal(address(multisig), address(multisig), startNonce);

        hoax(accounts[0].account);
        vm.expectEmit(true, true, true, true);
        emit ProposalCanceled(pid);
        fraxGovernorOmega.abortTransaction(address(multisig), generateThreeEOASigs(abortTxHash));

        vm.expectRevert(IFraxGovernorOmega.ProposalAlreadyCanceled.selector);
        fraxGovernorOmega.abortTransaction(address(multisig), generateThreeEOASigs(abortTxHash));

        assertEq(uint256(IGovernor.ProposalState.Canceled), uint256(fraxGovernorOmega.state(pid)));

        hoax(accounts[0].account);
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
            generateThreeEoaSigsAndOmega(abortTxHash)
        );

        assertEq(startNonce + 1, multisig.nonce());

        hoax(accounts[0].account);
        vm.expectRevert("Governor: vote not currently active");
        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + fraxGovernorOmega.votingPeriod() + 1);
        vm.roll(
            block.number + (fraxGovernorOmega.$votingDelayBlocks() + fraxGovernorOmega.votingPeriod() / BLOCK_TIME)
        );

        vm.startPrank(accounts[0].account);
        vm.expectRevert(IFraxGovernorOmega.WrongProposalState.selector);
        fraxGovernorOmega.rejectTransaction(address(multisig), startNonce);

        vm.expectRevert("GS026"); // Can't execute, nonce has moved beyond and Omega hasn't approved
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
            generateThreeEoaSigsAndOmega(originalTxHash)
        );

        (bytes32 originalTxHashReplay, ) = createTransferFxsProposal(address(multisig), multisig.nonce());

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
            generateFourEoaSigs(originalTxHashReplay)
        );

        vm.expectRevert("GS025"); // Can't execute Omega hasn't approved
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
            generateThreeEoaSigsAndOmega(originalTxHashReplay)
        );

        vm.stopPrank();
    }

    // Short circuit success works on Alpha
    function testAlphaProposeEarlySuccess() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorAlpha), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));

        // majorityFor allows skipping delay
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 100e18);
        assertEq(fxs.balanceOf(address(fraxGovernorAlpha)), 0);
        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorAlpha.state(pid)));
    }

    // Short circuit failure works on Alpha
    function testAlphaProposeEarlyFailure() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorAlpha), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));

        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorAlpha.state(pid)));

        vm.expectRevert("Governor: proposal not successful");
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 0);
        assertEq(fxs.balanceOf(address(fraxGovernorAlpha)), 100e18);
        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorAlpha.state(pid)));
    }

    // Short circuit success works on Omega
    function testOmegaProposeEarlySuccess() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorOmega), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorOmega.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pid)));

        // majorityFor allows skipping delay
        fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 100e18);
        assertEq(fxs.balanceOf(address(fraxGovernorOmega)), 0);
        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorOmega.state(pid)));
    }

    // Short circuit failure works on Omega
    function testOmegaProposeEarlyFailure() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorOmega), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorOmega.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.Against));

        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorOmega.state(pid)));

        vm.expectRevert("Governor: proposal not successful");
        fraxGovernorOmega.execute(targets, values, calldatas, keccak256(bytes("")));
        vm.stopPrank();

        assertEq(fxs.balanceOf(bob), 0);
        assertEq(fxs.balanceOf(address(fraxGovernorOmega)), 100e18);
        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorOmega.state(pid)));
    }

    // Regular success conditions with quorum for alpha
    function testAlphaProposeSuccess() public {
        //Drop alpha quorum lower so we can actually hit the non shortcircuit codepath
        hoax(address(fraxGovernorAlpha));
        fraxGovernorAlpha.updateQuorumNumerator(10);

        deal(address(fxs), address(fraxGovernorAlpha), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
        vm.stopPrank();

        vm.warp(block.timestamp + fraxGovernorAlpha.votingPeriod());

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));
    }

    // Regular success conditions with quorum for Omega, non optimistic proposal
    function testOmegaProposeSuccess() public {
        deal(address(fxs), address(fraxGovernorOmega), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorOmega.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        fraxGovernorOmega.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));
        vm.stopPrank();

        vm.warp(block.timestamp + fraxGovernorOmega.votingPeriod());
        vm.roll(block.number + fraxGovernorOmega.votingPeriod() / BLOCK_TIME);

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorOmega.state(pid)));
    }

    // Regular failure conditions for Omega, non optimistic proposal
    function testOmegaProposeDefeated() public {
        deal(address(fxs), address(fraxGovernorOmega), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorOmega.propose(targets, values, calldatas, "");
        vm.stopPrank();

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + fraxGovernorOmega.votingPeriod() + 1);
        vm.roll(
            block.number + fraxGovernorOmega.$votingDelayBlocks() + (fraxGovernorOmega.votingPeriod() / BLOCK_TIME)
        );

        assertEq(uint256(IGovernor.ProposalState.Defeated), uint256(fraxGovernorOmega.state(pid)));
    }

    // Can cancel Alpha proposals before the voting period starts
    function testAlphaProposeCancel() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorAlpha), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        fraxGovernorAlpha.cancel(targets, values, calldatas, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Canceled), uint256(fraxGovernorAlpha.state(pid)));

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);

        vm.expectRevert("Governor: too late to cancel");
        fraxGovernorAlpha.cancel(targets, values, calldatas, keccak256(bytes("")));

        vm.stopPrank();
    }

    // Can cancel vanilla propose() proposal before voting period on Omega
    function testOmegaProposeCancelNotVeto() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        deal(address(fxs), address(fraxGovernorOmega), 100e18); // Wrongfully sent to governor

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(fxs);
        calldatas[0] = abi.encodeWithSelector(ERC20.transfer.selector, bob, 100e18);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorOmega.propose(targets, values, calldatas, "");

        fraxGovernorOmega.cancel(targets, values, calldatas, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Canceled), uint256(fraxGovernorOmega.state(pid)));

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);

        vm.expectRevert("Governor: too late to cancel");
        fraxGovernorOmega.cancel(targets, values, calldatas, keccak256(bytes("")));

        vm.stopPrank();
    }

    // Only Alpha can update quorum numerator
    function testAlphaUpdateQuorumNumerator() public {
        uint256 alphaQuorum = fraxGovernorAlpha.quorumNumerator();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.updateQuorumNumerator(alphaQuorum + 1);

        assertEq(fraxGovernorAlpha.quorumNumerator(), alphaQuorum);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated({ oldQuorumNumerator: alphaQuorum, newQuorumNumerator: alphaQuorum + 1 });
        fraxGovernorAlpha.updateQuorumNumerator(alphaQuorum + 1);

        assertEq(fraxGovernorAlpha.quorumNumerator(), alphaQuorum + 1);
    }

    // Only Alpha can update quorum numerator
    function testOmegaUpdateQuorumNumerator() public {
        uint256 omegaQuorum = fraxGovernorOmega.quorumNumerator();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.updateQuorumNumerator(omegaQuorum + 1);

        assertEq(fraxGovernorOmega.quorumNumerator(), omegaQuorum);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated({ oldQuorumNumerator: omegaQuorum, newQuorumNumerator: omegaQuorum + 1 });
        fraxGovernorOmega.updateQuorumNumerator(omegaQuorum + 1);

        assertEq(fraxGovernorOmega.quorumNumerator(), omegaQuorum + 1);
    }

    // Actual test for setting an Omega governance paramter through an Alpha propose()
    function testOmegaSetVotingQuorumThroughAlphaGovernance() public {
        // increase locked FXS amount, so veFXS amount is slightly above quorum()
        dealLockMoreFxs(accounts[0].account, 21_000_000e18);

        uint256 omegaQuorum = fraxGovernorOmega.quorumNumerator();

        address[] memory targets = new address[](1);
        targets[0] = address(fraxGovernorOmega);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateQuorumNumerator(uint256)", omegaQuorum + 1);

        vm.startPrank(accounts[0].account);
        uint256 pid = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        fraxGovernorAlpha.castVote(pid, uint8(GovernorCompatibilityBravo.VoteType.For));

        vm.stopPrank();

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(pid)));

        vm.expectEmit(true, true, true, true);
        emit QuorumNumeratorUpdated({ oldQuorumNumerator: omegaQuorum, newQuorumNumerator: omegaQuorum + 1 });
        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(fraxGovernorOmega.quorumNumerator(), omegaQuorum + 1);
    }

    // Only Alpha can update short circuit numerator
    function testAlphaSetShortCircuitThreshold() public {
        uint256 alphaShortCircuitThreshold = fraxGovernorAlpha.shortCircuitNumerator();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.updateShortCircuitNumerator(alphaShortCircuitThreshold + 1);

        assertEq(fraxGovernorAlpha.shortCircuitNumerator(), alphaShortCircuitThreshold);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: alphaShortCircuitThreshold,
            newShortCircuitThreshold: alphaShortCircuitThreshold + 1
        });
        fraxGovernorAlpha.updateShortCircuitNumerator(alphaShortCircuitThreshold + 1);

        assertEq(fraxGovernorAlpha.shortCircuitNumerator(), alphaShortCircuitThreshold + 1);
        assertEq(fraxGovernorOmega.shortCircuitNumerator(block.timestamp - 1), alphaShortCircuitThreshold);
    }

    // Only Alpha can update short circuit numerator
    function testOmegaSetShortCircuitThreshold() public {
        uint256 omegaShortCircuitThreshold = fraxGovernorOmega.shortCircuitNumerator();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.updateShortCircuitNumerator(omegaShortCircuitThreshold + 1);

        assertEq(fraxGovernorOmega.shortCircuitNumerator(), omegaShortCircuitThreshold);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: omegaShortCircuitThreshold,
            newShortCircuitThreshold: omegaShortCircuitThreshold + 1
        });
        fraxGovernorOmega.updateShortCircuitNumerator(omegaShortCircuitThreshold + 1);

        assertEq(fraxGovernorOmega.shortCircuitNumerator(), omegaShortCircuitThreshold + 1);
        assertEq(fraxGovernorOmega.shortCircuitNumerator(block.timestamp - 1), omegaShortCircuitThreshold);
    }

    // Can't increase shortcircuit threshold past 100
    function testShortCircuitNumeratorFailure() public {
        uint256 omegaDenom = fraxGovernorAlpha.quorumDenominator();

        hoax(address(fraxGovernorAlpha));
        vm.expectRevert(FraxGovernorBase.ShortCircuitNumeratorGreaterThanQuorumDenominator.selector);
        fraxGovernorOmega.updateShortCircuitNumerator(omegaDenom + 1);

        uint256 alphaDenom = fraxGovernorAlpha.quorumDenominator();
        hoax(address(fraxGovernorAlpha));
        vm.expectRevert(FraxGovernorBase.ShortCircuitNumeratorGreaterThanQuorumDenominator.selector);
        fraxGovernorAlpha.updateShortCircuitNumerator(alphaDenom + 1);
    }

    // Only Alpha can update VeFxsVotingDelegation contract
    function testAlphaSetVeFxsVotingDelegation() public {
        address alphaVeFxsVotingDelegation = fraxGovernorAlpha.token();
        address newVotingDelegation = address(1);

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorAlpha.token(), alphaVeFxsVotingDelegation);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: alphaVeFxsVotingDelegation,
            newVotingDelegation: newVotingDelegation
        });
        fraxGovernorAlpha.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorAlpha.token(), newVotingDelegation);
    }

    // Only Alpha can update VeFxsVotingDelegation contract
    function testOmegaSetVeFxsVotingDelegation() public {
        address omegaVeFxsVotingDelegation = fraxGovernorOmega.token();
        address newVotingDelegation = address(1);

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorOmega.token(), omegaVeFxsVotingDelegation);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: omegaVeFxsVotingDelegation,
            newVotingDelegation: newVotingDelegation
        });
        fraxGovernorOmega.setVeFxsVotingDelegation(newVotingDelegation);

        assertEq(fraxGovernorOmega.token(), newVotingDelegation);
    }

    // Only Alpha can update Voting delay
    function testAlphaSetVotingDelay() public {
        uint256 alphaVotingDelay = fraxGovernorAlpha.votingDelay();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingDelay(alphaVotingDelay + 1);

        assertEq(fraxGovernorAlpha.votingDelay(), alphaVotingDelay);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingDelaySet({ oldVotingDelay: alphaVotingDelay, newVotingDelay: alphaVotingDelay + 1 });
        fraxGovernorAlpha.setVotingDelay(alphaVotingDelay + 1);

        assertEq(fraxGovernorAlpha.votingDelay(), alphaVotingDelay + 1);
    }

    // Only Alpha can update Voting delay
    function testOmegaSetVotingDelay() public {
        uint256 omegaVotingDelay = fraxGovernorOmega.votingDelay();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.setVotingDelay(omegaVotingDelay + 1);

        assertEq(fraxGovernorOmega.votingDelay(), omegaVotingDelay);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingDelaySet({ oldVotingDelay: omegaVotingDelay, newVotingDelay: omegaVotingDelay + 1 });
        fraxGovernorOmega.setVotingDelay(omegaVotingDelay + 1);

        assertEq(fraxGovernorOmega.votingDelay(), omegaVotingDelay + 1);
    }

    // Only Alpha can update Voting delay in block
    function testAlphaSetVotingDelayBlocks() public {
        uint256 alphaVotingDelayBlocks = fraxGovernorAlpha.$votingDelayBlocks();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingDelayBlocks(alphaVotingDelayBlocks + 1);

        assertEq(fraxGovernorAlpha.$votingDelayBlocks(), alphaVotingDelayBlocks);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingDelayBlocksSet({
            oldVotingDelayBlocks: alphaVotingDelayBlocks,
            newVotingDelayBlocks: alphaVotingDelayBlocks + 1
        });
        fraxGovernorAlpha.setVotingDelayBlocks(alphaVotingDelayBlocks + 1);

        assertEq(fraxGovernorAlpha.$votingDelayBlocks(), alphaVotingDelayBlocks + 1);
    }

    // Only Alpha can update Voting delay in blocks
    function testOmegaSetVotingDelayBlocks() public {
        uint256 omegaVotingDelayBlocks = fraxGovernorOmega.$votingDelayBlocks();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.setVotingDelayBlocks(omegaVotingDelayBlocks + 1);

        assertEq(fraxGovernorOmega.$votingDelayBlocks(), omegaVotingDelayBlocks);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingDelayBlocksSet({
            oldVotingDelayBlocks: omegaVotingDelayBlocks,
            newVotingDelayBlocks: omegaVotingDelayBlocks + 1
        });
        fraxGovernorOmega.setVotingDelayBlocks(omegaVotingDelayBlocks + 1);

        assertEq(fraxGovernorOmega.$votingDelayBlocks(), omegaVotingDelayBlocks + 1);
    }

    // Only Alpha can update Voting period
    function testAlphaSetVotingPeriod() public {
        uint256 alphaVotingPeriod = fraxGovernorAlpha.votingPeriod();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingPeriod(alphaVotingPeriod + 1);

        assertEq(fraxGovernorAlpha.votingPeriod(), alphaVotingPeriod);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingPeriodSet({ oldVotingPeriod: alphaVotingPeriod, newVotingPeriod: alphaVotingPeriod + 1 });
        fraxGovernorAlpha.setVotingPeriod(alphaVotingPeriod + 1);

        assertEq(fraxGovernorAlpha.votingPeriod(), alphaVotingPeriod + 1);
    }

    // Only Alpha can update Voting period
    function testOmegaSetVotingPeriod() public {
        uint256 omegaVotingPeriod = fraxGovernorOmega.votingPeriod();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.setVotingPeriod(omegaVotingPeriod + 1);

        assertEq(fraxGovernorOmega.votingPeriod(), omegaVotingPeriod);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit VotingPeriodSet({ oldVotingPeriod: omegaVotingPeriod, newVotingPeriod: omegaVotingPeriod + 1 });
        fraxGovernorOmega.setVotingPeriod(omegaVotingPeriod + 1);

        assertEq(fraxGovernorOmega.votingPeriod(), omegaVotingPeriod + 1);
    }

    // Only Alpha can update proposal threshold
    function testAlphaSetProposalThreshold() public {
        uint256 alphaProposalThreshold = fraxGovernorAlpha.proposalThreshold();

        vm.expectRevert("Governor: onlyGovernance");
        fraxGovernorAlpha.setVotingPeriod(alphaProposalThreshold + 1);

        assertEq(fraxGovernorAlpha.proposalThreshold(), alphaProposalThreshold);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit ProposalThresholdSet({
            oldProposalThreshold: alphaProposalThreshold,
            newProposalThreshold: alphaProposalThreshold + 1
        });
        fraxGovernorAlpha.setProposalThreshold(alphaProposalThreshold + 1);

        assertEq(fraxGovernorAlpha.proposalThreshold(), alphaProposalThreshold + 1);
    }

    // Only Alpha can update proposal threshold
    function testOmegaSetProposalThreshold() public {
        uint256 omegaProposalThreshold = fraxGovernorOmega.proposalThreshold();

        hoax(address(fraxGovernorOmega));
        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.setProposalThreshold(omegaProposalThreshold + 1);

        assertEq(fraxGovernorOmega.proposalThreshold(), omegaProposalThreshold);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit ProposalThresholdSet({
            oldProposalThreshold: omegaProposalThreshold,
            newProposalThreshold: omegaProposalThreshold + 1
        });
        fraxGovernorOmega.setProposalThreshold(omegaProposalThreshold + 1);

        assertEq(fraxGovernorOmega.proposalThreshold(), omegaProposalThreshold + 1);
    }

    // Only Alpha can change Omega safe configuration
    function testAddSafesToAllowlist() public {
        SafeConfig[] memory _safeConfigs = new SafeConfig[](2);
        _safeConfigs[0] = SafeConfig({ safe: bob, requiredSignatures: 3 });
        _safeConfigs[1] = SafeConfig({ safe: address(0xabcd), requiredSignatures: 4 });

        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.updateSafes(_safeConfigs);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit SafeConfigUpdate(_safeConfigs[0].safe, 0, _safeConfigs[0].requiredSignatures);
        vm.expectEmit(true, true, true, true);
        emit SafeConfigUpdate(_safeConfigs[1].safe, 0, _safeConfigs[1].requiredSignatures);
        fraxGovernorOmega.updateSafes(_safeConfigs);

        assertEq(_safeConfigs[0].requiredSignatures, fraxGovernorOmega.$safeRequiredSignatures(_safeConfigs[0].safe));
        assertEq(_safeConfigs[1].requiredSignatures, fraxGovernorOmega.$safeRequiredSignatures(_safeConfigs[1].safe));
    }

    // Only Alpha can change Omega safe configuration
    function testRemoveSafesFromAllowlist() public {
        SafeConfig[] memory _safeConfigs = new SafeConfig[](2);
        _safeConfigs[0] = SafeConfig({ safe: address(multisig), requiredSignatures: 0 });
        _safeConfigs[1] = SafeConfig({ safe: address(0xabcd), requiredSignatures: 0 });

        vm.expectRevert(IFraxGovernorOmega.NotGovernorAlpha.selector);
        fraxGovernorOmega.updateSafes(_safeConfigs);

        uint256 multiSigRequiredSignatures = fraxGovernorOmega.$safeRequiredSignatures(_safeConfigs[0].safe);

        hoax(address(fraxGovernorAlpha));
        vm.expectEmit(true, true, true, true);
        emit SafeConfigUpdate(_safeConfigs[0].safe, multiSigRequiredSignatures, _safeConfigs[0].requiredSignatures);
        vm.expectEmit(true, true, true, true);
        emit SafeConfigUpdate(_safeConfigs[1].safe, 0, _safeConfigs[1].requiredSignatures);
        fraxGovernorOmega.updateSafes(_safeConfigs);

        assertEq(0, fraxGovernorOmega.$safeRequiredSignatures(_safeConfigs[0].safe));
        assertEq(0, fraxGovernorOmega.$safeRequiredSignatures(_safeConfigs[1].safe));
    }

    // Fractional voting works as expected on Alpha
    function testFractionalVotingAlpha() public {
        address proposer = accounts[5].account;
        address prevOwner = accounts[3].account;
        address oldOwner = accounts[4].account;

        (uint256 pid, , , ) = createSwapOwnerProposal(
            CreateSwapOwnerProposalParams({
                _fraxGovernorAlpha: fraxGovernorAlpha,
                _safe: multisig,
                proposer: proposer,
                prevOwner: prevOwner,
                oldOwner: oldOwner
            })
        );

        vm.warp(block.timestamp + fraxGovernorAlpha.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorAlpha.$votingDelayBlocks() + 1);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0].account, fraxGovernorAlpha.proposalSnapshot(pid));

        // against, for, abstain
        bytes memory params = abi.encodePacked(
            uint128((weight * 50) / 100),
            uint128((weight * 10) / 100) + 1,
            uint128((weight * 40) / 100)
        );

        hoax(accounts[0].account);
        fraxGovernorAlpha.castVoteWithReasonAndParams(pid, 0, "reason", params);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorAlpha.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes);
        assertGt(abstainVotes, forVotes);
        assertEq(weight, againstVotes + forVotes + abstainVotes);

        bytes memory params2 = abi.encodePacked(uint128(1), uint128(0), uint128(0));

        hoax(accounts[0].account);
        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorAlpha.castVoteWithReasonAndParams(pid, 0, "reason", params2);
    }

    // Fractional voting works as expected on Omega
    function testFractionalVotingOmega() public {
        (uint256 pid, , , ) = createRealVetoTxProposal(
            address(multisig),
            fraxGovernorOmega,
            address(this),
            getSafe(address(multisig)).safe.nonce()
        );

        vm.warp(block.timestamp + fraxGovernorOmega.votingDelay() + 1);
        vm.roll(block.number + fraxGovernorOmega.$votingDelayBlocks() + 1);

        uint256 weight = veFxsVotingDelegation.getVotes(accounts[0].account, fraxGovernorOmega.proposalSnapshot(pid));

        // against, for, abstain
        bytes memory params = abi.encodePacked(
            uint128((weight * 50) / 100),
            uint128((weight * 10) / 100) + 1,
            uint128((weight * 40) / 100)
        );

        hoax(accounts[0].account);
        fraxGovernorOmega.castVoteWithReasonAndParams(pid, 0, "reason", params);
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = fraxGovernorOmega.proposalVotes(pid);

        assertGt(againstVotes, abstainVotes);
        assertGt(abstainVotes, forVotes);
        assertEq(weight, againstVotes + forVotes + abstainVotes);

        bytes memory params2 = abi.encodePacked(uint128(1), uint128(0), uint128(0));

        hoax(accounts[0].account);
        vm.expectRevert("GovernorCountingFractional: all weight cast");
        fraxGovernorOmega.castVoteWithReasonAndParams(pid, 0, "reason", params2);
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
        (bytes32 txHash1, IFraxGovernorOmega.TxHashArgs memory args1) = createTransferFxsProposal(
            address(multisig),
            currentNonce
        );
        (bytes32 txHash2, IFraxGovernorOmega.TxHashArgs memory args2) = createTransferFxsProposal(
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
        signatures[0] = generateThreeEOASigs(txHash1);
        signatures[1] = generateThreeEOASigs(txHash2);

        fraxGovernorOmega.batchAddTransaction(teamSafes, args, signatures);
    }
}
