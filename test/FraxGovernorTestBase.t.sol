// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import {
    GovernorCompatibilityBravo
} from "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { IGovernorTimelock } from "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "frax-std/FraxTest.sol";
import { SafeTestTools, SafeTestLib, SafeInstance, DeployedSafe, ModuleManager } from "safe-tools/SafeTestTools.sol";
import "safe-contracts/GnosisSafe.sol";
import "safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import "safe-tools/CompatibilityFallbackHandler_1_3_0.sol";
import { SignMessageLib } from "safe-contracts/examples/libraries/SignMessage.sol";
import { LibSort } from "solady/utils/LibSort.sol";
import { FraxGovernorAlpha, ConstructorParams } from "../src/FraxGovernorAlpha.sol";
import { FraxGovernorOmega } from "../src/FraxGovernorOmega.sol";
import "../src/VeFxsVotingDelegation.sol";
import "../src/FraxGuard.sol";
import "./mock/FxsMock.sol";
import "./utils/VyperDeployer.sol";
import "../src/interfaces/IFraxGovernorAlpha.sol";
import "../src/interfaces/IFraxGovernorOmega.sol";
import { FraxGovernorBase } from "../src/FraxGovernorBase.sol";
import { deployFraxGuard } from "script/DeployFraxGuard.s.sol";
import { deployVeFxsVotingDelegation } from "script/DeployVeFxsVotingDelegation.s.sol";
import { deployFraxGovernorAlpha, deployTimelockController } from "script/DeployFraxGovernorAlphaAndTimelock.s.sol";
import { deployFraxGovernorOmega } from "script/DeployFraxGovernorOmega.s.sol";
import { deployFraxCompatibilityFallbackHandler } from "script/DeployFraxCompatibilityFallbackHandler.s.sol";
import { deployMockFxs, deployVeFxs } from "../script/test/DeployTestFxs.s.sol";
import { Constants } from "../script/Constants.sol";
import { FraxCompatibilityFallbackHandler } from "../src/FraxCompatibilityFallbackHandler.sol";

contract FraxGovernorTestBase is FraxTest, SafeTestTools {
    using SafeTestLib for SafeInstance;
    using LibSort for address[];

    address[] accounts;
    address[] eoaOwners;

    mapping(address => uint256) addressToPk;

    SafeInstance safe;
    SafeInstance safe2;
    ISafe multisig;
    ISafe multisig2;
    IVeFxsVotingDelegation veFxsVotingDelegation;
    IFraxGovernorAlpha fraxGovernorAlpha;
    TimelockController timelockController;
    IFraxGovernorOmega fraxGovernorOmega;
    FraxGuard fraxGuard;
    FraxCompatibilityFallbackHandler fraxCompatibilityFallbackHandler;
    SignMessageLib signMessageLib;

    ERC20 fxs;
    IVeFxs veFxs;

    address constant bob = address(0xb0b);

    uint256 constant numAccounts = 15;
    uint256 internal constant GUARD_STORAGE_OFFSET =
        33_528_237_782_592_280_163_068_556_224_972_516_439_282_563_014_722_366_175_641_814_928_123_294_921_928;
    uint256 internal constant FALLBACK_HANDLER_OFFSET =
        49_122_629_484_629_529_244_014_240_937_346_711_770_925_847_994_644_146_912_111_677_022_347_558_721_749;
    uint256 FORK_BLOCK = 17_820_607;
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x20c13b0b;
    bytes4 internal constant UPDATED_MAGIC_VALUE = 0x1626ba7e;

    VyperDeployer immutable vyperDeployer = new VyperDeployer();

    function _bytesToAddress(bytes memory b) internal pure returns (address addr) {
        /// @solidity memory-safe-assembly
        assembly {
            addr := mload(add(b, 32))
        }
    }

    function _setupGnosisSafe() internal {
        uint256[] memory _owners = new uint256[](5);
        for (uint256 i = 0; i < eoaOwners.length; ++i) {
            _owners[i] = addressToPk[eoaOwners[i]];
        }
        safe = _setupSafe({ ownerPKs: _owners, threshold: 1, initialBalance: 0 });
        safe2 = _setupSafe({ ownerPKs: _owners, threshold: 1, initialBalance: 0 });
        multisig = ISafe(address(getSafe().safe));
        multisig2 = ISafe(address(getSafe(address(safe2.safe)).safe));
    }

    function _setupDeployAndConfigure() internal {
        signMessageLib = new SignMessageLib();

        (address _veFxsVotingDelegation, , ) = deployVeFxsVotingDelegation(address(veFxs));
        veFxsVotingDelegation = IVeFxsVotingDelegation(_veFxsVotingDelegation);

        (address payable _timelockController, , ) = deployTimelockController(address(this));
        timelockController = TimelockController(_timelockController);

        (address payable _fraxGovernorAlpha, , ) = deployFraxGovernorAlpha(
            address(veFxs),
            _veFxsVotingDelegation,
            _timelockController
        );
        fraxGovernorAlpha = IFraxGovernorAlpha(_fraxGovernorAlpha);

        timelockController.grantRole(timelockController.PROPOSER_ROLE(), _fraxGovernorAlpha);
        timelockController.grantRole(timelockController.EXECUTOR_ROLE(), _fraxGovernorAlpha);
        timelockController.grantRole(timelockController.CANCELLER_ROLE(), _fraxGovernorAlpha);
        timelockController.renounceRole(timelockController.TIMELOCK_ADMIN_ROLE(), address(this));

        address[] memory _safeAllowlist = new address[](2);
        _safeAllowlist[0] = address(multisig);
        _safeAllowlist[1] = address(multisig2);

        address[] memory _delegateCallAllowlist = new address[](1);
        _delegateCallAllowlist[0] = address(signMessageLib);

        (address payable _fraxGovernorOmega, , ) = deployFraxGovernorOmega(
            address(veFxs),
            _veFxsVotingDelegation,
            _safeAllowlist,
            _delegateCallAllowlist,
            _timelockController
        );
        fraxGovernorOmega = IFraxGovernorOmega(_fraxGovernorOmega);

        (address _fraxCompatibilityFallbackHandler, ) = deployFraxCompatibilityFallbackHandler();
        fraxCompatibilityFallbackHandler = FraxCompatibilityFallbackHandler(_fraxCompatibilityFallbackHandler);

        setupFraxFallbackHandler({
            _safe: address(multisig),
            signer: eoaOwners[0],
            _handler: _fraxCompatibilityFallbackHandler
        });
        setupFraxFallbackHandler({
            _safe: address(multisig2),
            signer: eoaOwners[0],
            _handler: _fraxCompatibilityFallbackHandler
        });

        (address _fraxGuard, , ) = deployFraxGuard(_fraxGovernorOmega);
        fraxGuard = FraxGuard(_fraxGuard);

        SafeTestLib.enableModule({ instance: getSafe(address(multisig)), module: address(timelockController) });
        SafeTestLib.enableModule({ instance: getSafe(address(multisig2)), module: address(timelockController) });

        // add frxGovOmega signer
        addSignerToSafe({
            _safe: address(multisig),
            signer: eoaOwners[0],
            newOwner: address(fraxGovernorOmega),
            threshold: 3
        });
        addSignerToSafe({
            _safe: address(multisig2),
            signer: eoaOwners[0],
            newOwner: address(fraxGovernorOmega),
            threshold: 3
        });

        // call setGuard on Safe
        setupFraxGuard({ _safe: address(multisig), signer: eoaOwners[0], _fraxGuard: address(fraxGuard) });
        setupFraxGuard({ _safe: address(multisig2), signer: eoaOwners[0], _fraxGuard: address(fraxGuard) });

        assertEq(getSafe(address(multisig)).safe.getOwners().length, 6, "6 total safe owners");
        assertEq(getSafe(address(multisig)).safe.getThreshold(), 3, "3 signatures required (+ omega)");
        assert(getSafe(address(multisig)).safe.isModuleEnabled(address(timelockController)));
        assertEq(
            address(fraxGuard),
            _bytesToAddress(getSafe(address(multisig)).safe.getStorageAt({ offset: GUARD_STORAGE_OFFSET, length: 1 })),
            "Guard is set"
        );

        assertEq(getSafe(address(multisig2)).safe.getOwners().length, 6, "6 total safe owners");
        assertEq(getSafe(address(multisig2)).safe.getThreshold(), 3, "3 signatures required (+ omega)");
        assert(getSafe(address(multisig2)).safe.isModuleEnabled(address(timelockController)));
        assertEq(
            address(fraxGuard),
            _bytesToAddress(getSafe(address(multisig2)).safe.getStorageAt({ offset: GUARD_STORAGE_OFFSET, length: 1 })),
            "Guard is set"
        );
    }

    function _setupDealAndLockFxs() internal {
        uint256 amount = 100_000e18;

        // Give FXS balances to every account
        for (uint256 i = 0; i < accounts.length; ++i) {
            deal(address(fxs), accounts[i], amount);
            assertEq(fxs.balanceOf(accounts[i]), amount, "account gets FXS");
        }

        // even distribution of lock time / veFXS balance
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            vm.startPrank(account, account);
            fxs.increaseAllowance(address(veFxs), amount);
            veFxs.create_lock(amount, block.timestamp + (365 days * 4) / (i + 1));
            vm.stopPrank();
            assertGt(veFxs.balanceOf(account), amount, "veFXS for an account is always equal to or greater than FXS");
        }

        assertGt(
            veFxs.balanceOf(accounts[0]),
            veFxs.balanceOf(accounts[accounts.length - 1]),
            "Descending veFXS balances"
        );
    }

    function _setupWhaleAccounts() internal {
        accounts.push(Constants.WHALE_0);
        accounts.push(Constants.WHALE_1);
        accounts.push(Constants.WHALE_2);
        accounts.push(Constants.WHALE_3);
        accounts.push(Constants.WHALE_4);
        accounts.push(Constants.WHALE_5);
        accounts.push(Constants.WHALE_6);
        accounts.push(Constants.WHALE_7);
        accounts.push(Constants.WHALE_8);
        accounts.push(Constants.WHALE_9);
    }

    function _forkSetUp() internal {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), FORK_BLOCK);

        address[] memory _accounts = generateAddresses(numAccounts);
        _setupWhaleAccounts();

        for (uint256 i = 0; i < numAccounts; ++i) {
            if (i > 9) {
                eoaOwners.push(_accounts[i]);
            }
        }

        // SafeTestTools' constructor runs before we start the fork test. So we reinitialize
        // all of these here so they exist on our fork
        _initializeSafeTools();

        _setupGnosisSafe();

        fxs = ERC20(Constants.FXS);
        veFxs = IVeFxs(Constants.VE_FXS);
        signMessageLib = SignMessageLib(Constants.SIGN_MESSAGE_LIB);

        veFxsVotingDelegation = IVeFxsVotingDelegation(Constants.VE_FXS_VOTING_DELEGATION);
        timelockController = TimelockController(payable(Constants.FRAX_GOVERNOR_ALPHA_TIMELOCK));
        fraxGovernorAlpha = IFraxGovernorAlpha(Constants.FRAX_GOVERNOR_ALPHA);
        fraxGovernorOmega = IFraxGovernorOmega(Constants.FRAX_GOVERNOR_OMEGA);
        fraxCompatibilityFallbackHandler = FraxCompatibilityFallbackHandler(
            Constants.FRAX_COMPATIBILITY_FALLBACK_HANDLER
        );

        setupFraxFallbackHandler({
            _safe: address(multisig),
            signer: eoaOwners[0],
            _handler: address(fraxCompatibilityFallbackHandler)
        });
        setupFraxFallbackHandler({
            _safe: address(multisig2),
            signer: eoaOwners[0],
            _handler: address(fraxCompatibilityFallbackHandler)
        });

        fraxGuard = FraxGuard(Constants.FRAX_GUARD);

        SafeTestLib.enableModule({ instance: getSafe(address(multisig)), module: address(timelockController) });
        SafeTestLib.enableModule({ instance: getSafe(address(multisig2)), module: address(timelockController) });

        // add frxGovOmega signer
        addSignerToSafe({
            _safe: address(multisig),
            signer: eoaOwners[0],
            newOwner: address(fraxGovernorOmega),
            threshold: 3
        });
        addSignerToSafe({
            _safe: address(multisig2),
            signer: eoaOwners[0],
            newOwner: address(fraxGovernorOmega),
            threshold: 3
        });

        // call setGuard on Safe
        setupFraxGuard({ _safe: address(multisig), signer: eoaOwners[0], _fraxGuard: address(fraxGuard) });
        setupFraxGuard({ _safe: address(multisig2), signer: eoaOwners[0], _fraxGuard: address(fraxGuard) });

        // add test safes to omega allow list through alpha governance
        address[] memory _safeAllowlist = new address[](2);
        _safeAllowlist[0] = address(multisig);
        _safeAllowlist[1] = address(multisig2);

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

        fraxGovernorAlpha.queue(targets, values, calldatas, keccak256(bytes("")));
        vm.warp(fraxGovernorAlpha.proposalEta(pid));

        fraxGovernorAlpha.execute(targets, values, calldatas, keccak256(bytes("")));

        assertEq(getSafe(address(multisig)).safe.getOwners().length, 6, "6 total safe owners");
        assertEq(getSafe(address(multisig)).safe.getThreshold(), 3, "3 signatures required (+ omega)");
        assert(getSafe(address(multisig)).safe.isModuleEnabled(address(timelockController)));
        assertEq(
            address(fraxGuard),
            _bytesToAddress(getSafe(address(multisig)).safe.getStorageAt({ offset: GUARD_STORAGE_OFFSET, length: 1 })),
            "Guard is set"
        );

        assertEq(getSafe(address(multisig2)).safe.getOwners().length, 6, "6 total safe owners");
        assertEq(getSafe(address(multisig2)).safe.getThreshold(), 3, "3 signatures required (+ omega)");
        assert(getSafe(address(multisig2)).safe.isModuleEnabled(address(timelockController)));
        assertEq(
            address(fraxGuard),
            _bytesToAddress(getSafe(address(multisig2)).safe.getStorageAt({ offset: GUARD_STORAGE_OFFSET, length: 1 })),
            "Guard is set"
        );

        mineBlocks(1);
    }

    function setUp() public virtual {
        // Set more realistic timestamps and block numbers
        vm.warp(1_680_000_000);
        vm.roll(17_100_000);

        address[] memory _accounts = generateAddresses(numAccounts);
        for (uint256 i = 0; i < numAccounts; ++i) {
            if (i <= 9) {
                accounts.push(_accounts[i]);
            } else if (i > 9) {
                eoaOwners.push(_accounts[i]);
            }
        }

        _setupGnosisSafe();

        (address _mockFxs, , ) = deployMockFxs();
        fxs = ERC20(_mockFxs);
        deal(address(fxs), Constants.FRAX_TREASURY_2, 3_000_000e18);

        (address _mockVeFxs, , ) = deployVeFxs(vyperDeployer, _mockFxs);
        veFxs = IVeFxs(_mockVeFxs);

        _setupDeployAndConfigure();
        _setupDealAndLockFxs();

        mineBlocks(1);
    }

    // Generic Helpers

    function generateAddresses(uint256 num) public returns (address[] memory _accounts) {
        _accounts = new address[](num);
        for (uint256 i = 0; i < num; ++i) {
            (address account, uint256 pk) = makeAddrAndKey(string(abi.encodePacked(i)));
            _accounts[i] = account;
            addressToPk[account] = pk;
        }
    }

    function sortEoaOwners() public view returns (address[] memory sortedEoas) {
        sortedEoas = new address[](eoaOwners.length);
        for (uint256 i = 0; i < eoaOwners.length; ++i) {
            sortedEoas[i] = eoaOwners[i];
        }
        LibSort.sort(sortedEoas);
    }

    function buildContractPreapprovalSignature(address contractOwner) public pure returns (bytes memory) {
        // GnosisSafe Pre-Validated signature format:
        // {32-bytes hash validator}{32-bytes ignored}{1-byte signature type}
        return abi.encodePacked(uint96(0), uint160(contractOwner), uint256(0), uint8(1));
    }

    function generateEoaSigs(uint256 amount, bytes32 txHash) public view returns (bytes memory sigs) {
        address[] memory sortedEoas = sortEoaOwners();
        for (uint256 i = 0; i < amount; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(addressToPk[sortedEoas[i]], txHash);
            sigs = abi.encodePacked(sigs, r, s, v);
        }
    }

    function generateEoaSigsWrongOrder(uint256 amount, bytes32 txHash) public view returns (bytes memory sigs) {
        address[] memory sortedEoas = sortEoaOwners();
        for (uint256 i = 0; i < amount; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(addressToPk[sortedEoas[i]], txHash);
            sigs = abi.encodePacked(r, s, v, sigs); // backwards
        }
    }

    function generateThreeEoaSigsAndOmegaPreapproval(bytes32 txHash) public view returns (bytes memory sigs) {
        address[] memory sortedAddresses = new address[](4);
        for (uint256 i = 0; i < 3; ++i) {
            sortedAddresses[i] = eoaOwners[i];
        }
        sortedAddresses[3] = address(fraxGovernorOmega);
        LibSort.sort(sortedAddresses);

        for (uint256 i = 0; i < sortedAddresses.length; ++i) {
            if (sortedAddresses[i] != address(fraxGovernorOmega)) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(addressToPk[sortedAddresses[i]], txHash);
                sigs = abi.encodePacked(sigs, r, s, v);
            } else {
                sigs = abi.encodePacked(sigs, buildContractPreapprovalSignature(address(fraxGovernorOmega)));
            }
        }
    }

    function generateMessageDigest(address _safe) public view returns (bytes32 messageDigest, bytes32 safeMessage) {
        bytes32 _EIP_712_DOMAIN_TYPEHASH = keccak256(
            abi.encodePacked(
                "EIP712Domain(",
                "string name,",
                "string version,",
                "uint256 chainId,",
                "address verifyingContract",
                ")"
            )
        );
        bytes32 _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                _EIP_712_DOMAIN_TYPEHASH,
                keccak256(bytes("Fraxswap V2")), //_NAME_HASH
                keccak256(bytes("1")), //_VERSION_HASH
                1, // block.chainid
                0xCCB26b5CC4e1Ce29521DA281a0107A6672bfe099 // verifyingContract
            )
        );
        bytes32 _PERMIT_TYPEHASH = keccak256(
            abi.encodePacked(
                "Permit(",
                "address owner,",
                "address spender,",
                "uint256 value,",
                "uint256 nonce,",
                "uint256 deadline",
                ")"
            )
        );
        bytes32 PERMIT = keccak256(abi.encode(_PERMIT_TYPEHASH, _safe, address(765), 1, 0, block.timestamp + 500));

        messageDigest = keccak256(abi.encodePacked(uint16(0x1901), _DOMAIN_SEPARATOR, PERMIT));
        safeMessage = getSafe(address(multisig)).safe.getMessageHash(bytes.concat(messageDigest));
    }

    function dealCreateLockFxs(address account, uint256 amount) public {
        hoax(Constants.FRAX_TREASURY_2);
        fxs.transfer(account, amount);

        vm.startPrank(account, account);
        fxs.increaseAllowance(address(veFxs), amount);
        veFxs.create_lock(amount, block.timestamp + (365 days * 4));
        vm.stopPrank();
    }

    function setupFraxGuard(address _safe, address signer, address _fraxGuard) public {
        bytes memory data = abi.encodeWithSignature("setGuard(address)", address(_fraxGuard));
        DeployedSafe _dsafe = getSafe(_safe).safe;
        bytes32 txHash = _dsafe.getTransactionHash(
            address(_dsafe),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            payable(address(0)),
            payable(address(0)),
            _dsafe.nonce()
        );

        hoax(signer);
        _dsafe.execTransaction(
            address(_dsafe),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            payable(address(0)),
            payable(address(0)),
            generateEoaSigs(4, txHash)
        );
    }

    function setupFraxFallbackHandler(address _safe, address signer, address _handler) public {
        bytes memory data = abi.encodeWithSignature("setFallbackHandler(address)", address(_handler));
        DeployedSafe _dsafe = getSafe(_safe).safe;
        bytes32 txHash = _dsafe.getTransactionHash(
            address(_dsafe),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            payable(address(0)),
            payable(address(0)),
            _dsafe.nonce()
        );

        hoax(signer);
        _dsafe.execTransaction(
            address(_dsafe),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            payable(address(0)),
            payable(address(0)),
            generateEoaSigs(4, txHash)
        );
    }

    function addSignerToSafe(address _safe, address signer, address newOwner, uint256 threshold) internal {
        bytes memory data = abi.encodeWithSignature("addOwnerWithThreshold(address,uint256)", newOwner, threshold);
        bytes memory sig = buildContractPreapprovalSignature(signer);

        hoax(signer);
        getSafe(_safe).safe.execTransaction(
            address(getSafe(_safe).safe),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            payable(address(0)),
            payable(address(0)),
            sig
        );
    }

    // Creating proposals
    function optimisticTxProposalHash(
        address _safe,
        IFraxGovernorOmega _fraxGovernorOmega,
        bytes memory txData
    ) public pure returns (uint256, address[] memory, uint256[] memory, bytes[] memory) {
        bytes memory data = abi.encodeCall(ISafe.approveHash, keccak256(txData));

        address[] memory targets = new address[](1);
        targets[0] = address(_safe);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        return (
            _fraxGovernorOmega.hashProposal(targets, values, calldatas, keccak256(bytes(""))),
            targets,
            values,
            calldatas
        );
    }

    function createNoOpProposal(
        address _safe,
        address to,
        uint256 nonce
    ) public view returns (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, bytes memory txData) {
        txData = getSafe(_safe).safe.encodeTransactionData(
            to,
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );
        txHash = keccak256(txData);
        args = IFraxGovernorOmega.TxHashArgs(to, 0, "", Enum.Operation.Call, 0, 0, 0, address(0), address(0), nonce);
    }

    function createTransferFxsProposal(
        address _safe,
        uint256 nonce
    ) public view returns (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, bytes memory txData) {
        txData = getSafe(_safe).safe.encodeTransactionData(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );
        txHash = keccak256(txData);
        args = IFraxGovernorOmega.TxHashArgs(
            address(fxs),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", address(this), 100e18),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );
    }

    function createOptimisticTxProposal(
        address _safe,
        IFraxGovernorOmega _fraxGovernorOmega,
        address caller,
        uint256 nonce
    ) public returns (uint256 pid, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, bytes memory txData) = createNoOpProposal(
            _safe,
            address(0),
            nonce
        );

        (pid, targets, values, calldatas) = optimisticTxProposalHash(_safe, _fraxGovernorOmega, txData);

        uint256 delay = _fraxGovernorOmega.votingDelay();
        uint256 period = _fraxGovernorOmega.votingPeriod();

        hoax(caller);
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated({
            proposalId: pid,
            proposer: caller,
            targets: targets,
            values: values,
            signatures: new string[](targets.length),
            calldatas: calldatas,
            voteStart: block.timestamp + delay,
            voteEnd: block.timestamp + delay + period,
            description: ""
        });
        vm.expectEmit(true, true, true, true);
        emit TransactionProposed(_safe, nonce, txHash, pid);
        _fraxGovernorOmega.addTransaction(address(_safe), args, generateEoaSigs(3, txHash));
    }

    function createOptimisticProposal(
        address _safe,
        IFraxGovernorOmega _fraxGovernorOmega,
        address caller,
        uint256 nonce
    ) public returns (uint256 pid, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
        (bytes32 txHash, IFraxGovernorOmega.TxHashArgs memory args, bytes memory txData) = createTransferFxsProposal(
            _safe,
            nonce
        );

        (pid, targets, values, calldatas) = optimisticTxProposalHash(_safe, _fraxGovernorOmega, txData);

        uint256 delay = _fraxGovernorOmega.votingDelay();
        uint256 period = _fraxGovernorOmega.$safeVotingPeriod(_safe) != 0
            ? _fraxGovernorOmega.$safeVotingPeriod(_safe)
            : _fraxGovernorOmega.votingPeriod();

        hoax(caller);
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated({
            proposalId: pid,
            proposer: caller,
            targets: targets,
            values: values,
            signatures: new string[](targets.length),
            calldatas: calldatas,
            voteStart: block.timestamp + delay,
            voteEnd: block.timestamp + delay + period,
            description: ""
        });
        vm.expectEmit(true, true, true, true);
        emit TransactionProposed(_safe, nonce, txHash, pid);
        _fraxGovernorOmega.addTransaction(address(_safe), args, generateEoaSigs(3, txHash));
    }

    function genericAlphaSafeProposalData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) public pure returns (bytes memory) {
        return abi.encodeCall(ModuleManager.execTransactionFromModule, (to, value, data, operation));
    }

    function swapOwnerProposalHash(
        IFraxGovernorAlpha _fraxGovernorAlpha,
        ISafe _safe,
        address prevOwner,
        address oldOwner,
        address newOwner
    ) public pure returns (uint256, address[] memory, uint256[] memory, bytes[] memory) {
        bytes memory data = genericAlphaSafeProposalData(
            address(_safe),
            0,
            abi.encodeWithSignature("swapOwner(address,address,address)", prevOwner, oldOwner, newOwner),
            Enum.Operation.Call
        );

        address[] memory targets = new address[](1);
        targets[0] = address(_safe);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        return (
            _fraxGovernorAlpha.hashProposal(targets, values, calldatas, keccak256(bytes(""))),
            targets,
            values,
            calldatas
        );
    }

    struct CreateSwapOwnerProposalParams {
        IFraxGovernorAlpha _fraxGovernorAlpha;
        ISafe _safe;
        address proposer;
        address prevOwner;
        address oldOwner;
    }

    function createSwapOwnerProposal(
        CreateSwapOwnerProposalParams memory params
    ) public returns (uint256 pid, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
        (pid, targets, values, calldatas) = swapOwnerProposalHash(
            params._fraxGovernorAlpha,
            params._safe,
            params.prevOwner,
            params.oldOwner,
            params.proposer
        );
        vm.startPrank(params.proposer);
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated({
            proposalId: pid,
            proposer: params.proposer,
            targets: targets,
            values: values,
            signatures: new string[](targets.length),
            calldatas: calldatas,
            voteStart: block.timestamp + params._fraxGovernorAlpha.votingDelay(),
            voteEnd: block.timestamp +
                params._fraxGovernorAlpha.votingDelay() +
                params._fraxGovernorAlpha.votingPeriod(),
            description: ""
        });
        params._fraxGovernorAlpha.propose(targets, values, calldatas, "");
        vm.stopPrank();
    }

    function votePassingAlphaQuorum(uint256 proposalId) public {
        for (uint256 i = 0; i < 4; ++i) {
            hoax(accounts[i]);
            fraxGovernorAlpha.castVote(proposalId, uint8(GovernorCompatibilityBravo.VoteType.For));
        }
    }

    // Events

    event TransactionProposed(address indexed safe, uint256 nonce, bytes32 indexed txHash, uint256 indexed proposalId);
    event SignMsg(bytes32 indexed msgHash);

    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingDelayBlocksSet(uint256 oldVotingDelayBlocks, uint256 newVotingDelayBlocks);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event VeFxsVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);
    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitThreshold, uint256 newShortCircuitThreshold);
    event TimelockChange(address oldTimelock, address newTimelock);
    event ProposalExtended(uint256 indexed proposalId, uint64 extendedDeadline);
    event LateQuorumVoteExtensionSet(uint64 oldVoteExtension, uint64 newVoteExtension);
    event SafeVotingPeriodSet(address safe, uint256 oldSafeVotingPeriod, uint256 newSafeVotingPeriod);

    event AddToSafeAllowlist(address indexed safe);
    event RemoveFromSafeAllowlist(address indexed safe);
    event AddToDelegateCallAllowlist(address contractAddress);
    event RemoveFromDelegateCallAllowlist(address contractAddress);

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 voteStart,
        uint256 voteEnd,
        string description
    );
    event ProposalCanceled(uint256 proposalId);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}
