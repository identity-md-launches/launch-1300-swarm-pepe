// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapCases} from "./SPEPEHook.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Offline runs explicitly skip these tests; use ROBINHOOD_RPC_URL to run against the chain.
contract RobinhoodForkTest is SwapCases {
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_actualFillFees(bool buy, bool exactInput, bool priceLimited, uint96 amount, uint8 offset)
        public
        override
    {
        super.testFuzz_actualFillFees(buy, exactInput, priceLimited, amount, offset);
    }

    function setUp() public {
        string memory url = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        uint256 forkBlock = vm.envOr("ROBINHOOD_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(url);
        else vm.createSelectFork(url, forkBlock);
        assertEq(block.chainid, 4663);
        assertEq(IERC20Metadata(IMD).symbol(), "IMD");
        assertEq(IERC20Metadata(IMD).decimals(), 18);
        _setup(true, false, false);
    }
}
