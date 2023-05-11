// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./FraxGovernorTestBase.t.sol";

contract TestFraxGovernorUpgrade is FraxGovernorTestBase {
    IFraxGovernorAlpha fraxGovernorAlphaUpgrade;
    IFraxGovernorOmega fraxGovernorOmegaUpgrade;
    FraxGuard fraxGuardUpgrade;

    function setUp() public override {
        super.setUp();

        (address payable _fraxGovernorAlpha, , ) = deployFraxGovernorAlpha(
            address(veFxs),
            address(veFxsVotingDelegation)
        );
        fraxGovernorAlphaUpgrade = IFraxGovernorAlpha(_fraxGovernorAlpha);

        SafeConfig[] memory _safeConfigs = new SafeConfig[](1);
        _safeConfigs[0] = SafeConfig({ safe: address(multisig), requiredSignatures: 3 });

        (address payable _fraxGovernorOmega, , ) = deployFraxGovernorOmega(
            address(veFxs),
            address(veFxsVotingDelegation),
            _safeConfigs,
            _fraxGovernorAlpha
        );
        fraxGovernorOmegaUpgrade = IFraxGovernorOmega(_fraxGovernorOmega);

        (address _fraxGuard, , ) = deployFraxGuard(_fraxGovernorOmega);
        fraxGuardUpgrade = FraxGuard(_fraxGuard);
    }

    // create and execute proposal to remove old frxGov from multisig and set up with new frxGov
    function testUpgradeGovernance() public {
        address[] memory targets = new address[](5);
        uint256[] memory values = new uint256[](5);
        bytes[] memory calldatas = new bytes[](5);
        DeployedSafe _safe = getSafe(address(multisig)).safe;

        // Switch fraxGuard to new one
        targets[0] = address(multisig);
        calldatas[0] = genericAlphaSafeProposalData(
            address(multisig),
            0,
            abi.encodeWithSignature("setGuard(address)", address(fraxGuardUpgrade)),
            Enum.Operation.Call
        );

        // Add new alpha as module
        targets[1] = address(multisig);
        calldatas[1] = genericAlphaSafeProposalData(
            address(multisig),
            0,
            abi.encodeWithSignature("enableModule(address)", address(fraxGovernorAlphaUpgrade)),
            Enum.Operation.Call
        );

        // Swap owner oldOmega to new omega
        targets[2] = address(multisig);
        calldatas[2] = genericAlphaSafeProposalData(
            address(multisig),
            0,
            abi.encodeWithSignature(
                "swapOwner(address,address,address)",
                address(0x1), // prevOwner
                address(fraxGovernorOmega), // oldOwner
                address(fraxGovernorOmegaUpgrade) // newOwner
            ),
            Enum.Operation.Call
        );

        // Remove safe from old omega allowlist
        SafeConfig[] memory _safeConfigs = new SafeConfig[](1);
        _safeConfigs[0] = SafeConfig({ safe: address(multisig), requiredSignatures: 0 });

        targets[3] = address(fraxGovernorOmega);
        calldatas[3] = abi.encodeWithSelector(IFraxGovernorOmega.updateSafes.selector, _safeConfigs);

        // Remove old alpha as module
        targets[4] = address(multisig);
        calldatas[4] = genericAlphaSafeProposalData(
            address(multisig),
            0,
            abi.encodeWithSignature(
                "disableModule(address,address)",
                address(fraxGovernorAlphaUpgrade), // prevModule
                address(fraxGovernorAlpha) // module
            ),
            Enum.Operation.Call
        );

        hoax(accounts[0].account);
        uint256 proposalId = fraxGovernorAlpha.propose(targets, values, calldatas, "");

        vm.warp(block.timestamp + fraxGovernorAlpha.votingPeriod());
        vm.roll(block.number + fraxGovernorAlpha.votingPeriod() / BLOCK_TIME);

        for (uint256 i = 0; i < accounts.length; ++i) {
            if (uint256(fraxGovernorAlpha.state(proposalId)) == uint256(IGovernor.ProposalState.Active)) {
                hoax(accounts[i].account);
                fraxGovernorAlpha.castVote(proposalId, uint8(GovernorCompatibilityBravo.VoteType.For));
            }
        }

        assertEq(uint256(IGovernor.ProposalState.Succeeded), uint256(fraxGovernorAlpha.state(proposalId)));

        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(uint256(IGovernor.ProposalState.Executed), uint256(fraxGovernorAlpha.state(proposalId)));

        // Frax Guard is the new one
        assertEq(
            address(fraxGuardUpgrade),
            _bytesToAddress(_safe.getStorageAt({ offset: GUARD_STORAGE_OFFSET, length: 1 }))
        );

        // New Alpha is a module
        assert(_safe.isModuleEnabled(address(fraxGovernorAlphaUpgrade)));

        // old Omega not owner
        assertFalse(_safe.isOwner(address(fraxGovernorOmega)));

        // new Omega is owner
        assert(_safe.isOwner(address(fraxGovernorOmegaUpgrade)));

        // Removed safe from old omega allowlist
        assertEq(fraxGovernorOmega.$safeRequiredSignatures(address(multisig)), 0);

        // old alpha removed as module
        assertFalse(_safe.isModuleEnabled(address(fraxGovernorAlpha)));

        assertEq(_safe.getOwners().length, 6);
        assertEq(_safe.getThreshold(), 4);
    }
}
