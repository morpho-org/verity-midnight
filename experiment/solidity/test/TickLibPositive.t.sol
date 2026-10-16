// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {TickLibPositive} from "../TickLibPositive.sol";
import {TickLib} from "../../vendor/midnight/src/libraries/TickLib.sol";

contract TickLibPositiveTest {
    uint256 private constant MAX_INPUT = 4987541511039073 * 3372;
    TickLibPositive private positive = new TickLibPositive();

    function same(uint256 x) internal view {
        require(positive.wExp(x) == TickLib.wExp(int256(x)), "positive rewrite differs from TickLib");
    }

    function testEndpoints() public view {
        same(0);
        same(1);
        same(1e18);
        same(MAX_INPUT - 1);
        same(MAX_INPUT);
        require(positive.wExp(MAX_INPUT) == 20134595243400876315901952, "max output");
    }

    function testAllPositiveTickInputs() public view {
        for (uint256 tick = 0; tick <= 3372; tick++) {
            same(4987541511039073 * tick);
        }
    }

    function testSegmentAndResidualBoundaries() public view {
        for (uint256 q = 1; q <= 24; q++) {
            uint256 jump = q * 693147180559945309 - 322611214989459870;
            same(jump - 1);
            same(jump);
            same(jump + 1);
            uint256 zeroResidual = q * 693147180559945309;
            same(zeroResidual - 1);
            same(zeroResidual);
            same(zeroResidual + 1);
        }
    }

    function testFuzzMatchesOriginal(uint256 seed) public view {
        same(seed % (MAX_INPUT + 1));
    }
}
