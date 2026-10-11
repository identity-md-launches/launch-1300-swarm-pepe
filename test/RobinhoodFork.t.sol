// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapCases} from "./SPEPEHook.t.sol";
import {IArbSys} from "../src/SPEPEHook.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Offline runs explicitly skip these tests; select Robinhood with forge test --fork-url.
contract RobinhoodForkTest is SwapCases {
    address internal constant ARB_SYS = address(100);
    bytes4 internal constant ARB_BLOCK_NUMBER = bytes4(keccak256("arbBlockNumber()"));
    uint256 internal rpcLocalBlock;
    uint256 internal rpcParentBlock;

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_largePriceLimitedRequests(bool buy, bool exactInput, uint256 seed, uint8 offset) public override {
        super.testFuzz_largePriceLimitedRequests(buy, exactInput, seed, offset);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_actualFillFees(bool buy, bool exactInput, bool priceLimited, uint96 amount, uint8 offset)
        public
        override
    {
        super.testFuzz_actualFillFees(buy, exactInput, priceLimited, amount, offset);
    }

    function setUp() public {
        // A CLI-selected fork keeps RPC configuration outside test code and the shared environment.
        // Catch only the absence of a fork. A wrong chain, missing contract or failed swap must fail.
        try vm.activeFork() returns (uint256) {}
        catch {
            vm.skip(true);
            return;
        }
        assertEq(block.chainid, 4663);
        assertEq(IERC20Metadata(IMD).symbol(), "IMD");
        assertEq(IERC20Metadata(IMD).decimals(), 18);
        // Nitro-aware Foundry exposes the parent height through NUMBER and the fork's local
        // height through ArbSys. RPC block tags must use the latter. Verify both against RPC.
        uint256 localBlock = IArbSys(ARB_SYS).arbBlockNumber();
        string memory blockTag = _rpcBlockTag(localBlock);
        rpcLocalBlock = abi.decode(
            vm.rpc(
                "eth_call",
                string.concat(
                    '[{"to":"0x0000000000000000000000000000000000000064","data":"',
                    vm.toString(abi.encodePacked(ARB_BLOCK_NUMBER)),
                    '"},"',
                    blockTag,
                    '"]'
                )
            ),
            (uint256)
        );
        rpcParentBlock = abi.decode(
            vm.rpc("eth_call", string.concat('[{"data":"0x4360005260206000f3"},"', blockTag, '"]')), (uint256)
        );
        assertEq(rpcLocalBlock, localBlock, "ArbSys must match the RPC block height");
        assertEq(rpcParentBlock, block.number, "NUMBER must match the RPC parent height");
        assertLt(rpcParentBlock, rpcLocalBlock, "clock semantics changed");
        _setup(true, false, false);
    }

    function _rollLaunchBlock(uint256 number) internal override {
        // Controlled local-block advances leave the native NUMBER opcode's parent height fixed.
        vm.mockCall(ARB_SYS, abi.encodePacked(ARB_BLOCK_NUMBER), abi.encode(number));
    }

    function _rpcBlockTag(uint256 number) private pure returns (string memory) {
        // JSON-RPC quantities are minimal hex, not the 32-byte string parsed as a block hash.
        bytes memory hexNumber = bytes(vm.toString(bytes32(number)));
        uint256 first = 2;
        while (first < hexNumber.length - 1 && hexNumber[first] == "0") {
            ++first;
        }
        bytes memory tag = new bytes(hexNumber.length - first + 2);
        tag[0] = "0";
        tag[1] = "x";
        for (uint256 i = 2; i < tag.length; ++i) {
            tag[i] = hexNumber[first + i - 2];
        }
        return string(tag);
    }

    function test_localBlockClockUsesVerifiedArbSysResult() public {
        assertEq(hook.openedBlock(), rpcLocalBlock);
        assertEq(block.number, rpcParentBlock);
        _rollLaunchBlock(rpcLocalBlock + 10);
        assertEq(hook.feeBps(), 0);
        (,, uint256 fee) = _trade(true, true, 1_000 ether, false);
        assertEq(fee, 0);
        assertEq(block.number, rpcParentBlock);
    }
}
