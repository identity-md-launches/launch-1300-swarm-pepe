// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapCases} from "./SPEPEHook.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Offline runs explicitly skip these tests; select Robinhood with forge test --fork-url.
contract RobinhoodForkTest is SwapCases {
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
        _setup(true, false, false);
    }
}
