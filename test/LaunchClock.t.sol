// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @dev Models Nitro's independent child-chain clock; NUMBER remains controlled by vm.roll.
contract MockArbSysClock {
    uint256 public arbBlockNumber;

    function setBlockNumber(uint256 number) external {
        arbBlockNumber = number;
    }
}

contract LaunchClockTest is LaunchFixture {
    address internal constant ARB_SYS = address(100);
    uint256 internal constant LOCAL_OPEN = 86_000_000;
    uint256 internal constant PARENT_OPEN = 26_000_000;
    MockArbSysClock internal clock = MockArbSysClock(ARB_SYS);

    function setUp() public {
        vm.roll(PARENT_OPEN);
        vm.etch(ARB_SYS, type(MockArbSysClock).runtimeCode);
        clock.setBlockNumber(LOCAL_OPEN);
        _setup(false, true, false);
    }

    function test_initializationRecordsLocalBlock() public view {
        assertEq(hook.openedBlock(), LOCAL_OPEN);
        assertEq(hook.feeBps(), 3000);
    }

    function test_feeExpiresWhenLocalBlocksAdvanceWhileParentStalls() public {
        clock.setBlockNumber(LOCAL_OPEN + 10);
        assertEq(block.number, PARENT_OPEN);
        assertEq(hook.feeBps(), 0);
        (,, uint256 fee) = _trade(true, true, 1_000 ether, false);
        assertEq(fee, 0);
        assertEq(_refundClaims(), 0);
        assertTrue(hook.limitActive(), "block fee expiry must not end the timestamp buy limit");
    }

    function test_parentAdvanceDoesNotExpireLocalBlockFee() public {
        vm.roll(PARENT_OPEN + 50);
        assertEq(hook.feeBps(), 3000);
        (,, uint256 fee) = _trade(false, true, 1_000 ether, false);
        assertGt(fee, 0);
    }

    function test_eachLocalBlockDecaysFeeForRealSwaps() public {
        for (uint256 offset; offset <= 11; ++offset) {
            clock.setBlockNumber(LOCAL_OPEN + offset);
            assertEq(hook.feeBps(), offset < 10 ? 3000 - 300 * offset : 0);
            _trade(true, true, 1_000 ether, false);
            _trade(false, false, 1_000 ether, true);
        }
        assertEq(block.number, PARENT_OPEN);
    }

    function test_buyLimitStillUsesTimestamp() public {
        vm.warp(hook.openedAt() + 3600);
        assertFalse(hook.limitActive());
        assertEq(hook.feeBps(), 3000);
        (BalanceDelta net,,) = _trade(true, false, hook.maxBuy() + 1, false);
        assertEq(uint256(_launched(net)), hook.maxBuy() + 1);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_independentClocks(uint8 localOffset, uint16 parentOffset) public {
        uint256 elapsed = bound(localOffset, 0, 50);
        clock.setBlockNumber(LOCAL_OPEN + elapsed);
        vm.roll(PARENT_OPEN + parentOffset);
        assertEq(hook.feeBps(), elapsed < 10 ? 3000 - 300 * elapsed : 0);
        _trade(true, false, 100 ether, false);
    }
}
