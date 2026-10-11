// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SPEPE} from "../src/SPEPE.sol";

contract SPEPETest is Test {
    SPEPE token;

    function setUp() public {
        token = new SPEPE();
    }

    function test_entirePolicySupplyBelongsToDeployer() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "Swarm Pepe");
        assertEq(token.symbol(), "SPEPE");
    }

    function test_noMintOrAdminEntryPointsEvenForDeployer() public {
        bytes4[6] memory selectors = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("setOwner(address)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("initialize(address)")),
            bytes4(keccak256("setMinter(address)"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            (bool ok,) = address(token).call(abi.encodeWithSelector(selectors[i], address(this), 1 ether));
            assertFalse(ok);
        }
        assertEq(token.totalSupply(), 1e27);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_allowanceAndTransferConserveSupply(uint256 amount) public {
        amount = bound(amount, 0, 1e27);
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), 1e27 - amount);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), 1e27);
    }
}
