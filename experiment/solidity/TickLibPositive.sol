// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice Unsigned, non-recursive version of TickLib.wExp for the positive tick range.
/// @dev Intended domain: 0 <= x <= 4987541511039073 * (6744 / 2).
/// This is a separate implementation; equivalence to TickLib is not assumed by the Lean spec.
contract TickLibPositive {
    function wExp(uint256 x) external pure returns (uint256) {
        uint256 ln2 = 693147180559945309;
        uint256 offset = 322611214989459870;
        uint256 wad = 1000000000000000000;
        uint256 q = (x + offset) / ln2;
        uint256 pivot = q * ln2;
        // The original signed residual can be negative even when x is positive.
        uint256 magnitude = x >= pivot ? x - pivot : pivot - x;
        uint256 secondTerm = magnitude * magnitude / (2 * wad);
        uint256 thirdMagnitude = secondTerm * magnitude / (3 * wad);
        // Signed division truncates toward zero, so a negative cubic term is
        // exactly the negation of thirdMagnitude.
        uint256 expR = x >= pivot
            ? wad + magnitude + secondTerm + thirdMagnitude
            : wad - magnitude + secondTerm - thirdMagnitude;
        return expR * pow2(q);
    }

    /// @dev Returns 2**q for q <= 31. The intended wExp domain gives q <= 24.
    /// Avoids shifts, exponentiation, loops and unchecked blocks, which are
    /// outside the pinned solidity_import frontend's supported subset.
    function pow2(uint256 q) internal pure returns (uint256) {
        uint256 r16 = q >= 16 ? q - 16 : q;
        uint256 r8 = r16 >= 8 ? r16 - 8 : r16;
        uint256 r4 = r8 >= 4 ? r8 - 4 : r8;
        uint256 r2 = r4 >= 2 ? r4 - 2 : r4;
        uint256 f16 = q >= 16 ? 65536 : 1;
        uint256 f8 = r16 >= 8 ? 256 : 1;
        uint256 f4 = r8 >= 4 ? 16 : 1;
        uint256 f2 = r4 >= 2 ? 4 : 1;
        uint256 f1 = r2 >= 1 ? 2 : 1;
        return f16 * f8 * f4 * f2 * f1;
    }
}
