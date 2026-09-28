//! Gas benchmarks of `u252` (`[0, P - 1]` in one felt) against `u256`, `u128`, raw `felt252` and
//! a `[0, 2^251 - 1]` newtype, 100 repetitions per test.
//! Per-operation cost = (test - matching baseline) / 100, see `GAS.md`.
//! Budgets are `#[available_gas(l2_gas: N)]` with `N = ceil(1.05 * measured sierra gas)`.

// Core imports

use core::felt252_div;
use core::num::traits::{OverflowingMul, WrappingAdd, WrappingMul, WrappingSub, Zero};

// Internal imports

use starknet::storage_access::StorePacking;
use crate::bits::Bits;
use crate::integer::{PRIME, U252Trait, u252};

// Constants

const REPS: u8 = 100;
/// Wide operands: `A` has 250 bits, `B` 237 bits, `A + B < P`, `A > B`.
const A: felt252 = 0x2468ace02468ace02468ace02468ace02468ace02468ace02468ace02468ace;
const B: felt252 = 0x13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf1357;
const A_HIGH: u128 = 0x2468ace02468ace02468ace02468ace;
const A_LOW: u128 = 0x2468ace02468ace02468ace02468ace;
const B_HIGH: u128 = 0x13579bdf13579bdf13579bdf1357;
const B_LOW: u128 = 0x9bdf13579bdf13579bdf13579bdf1357;
/// Shift operand, 221 bits: `C * 2^17 < 2^251`.
const C: felt252 = 0x13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf;
const C_HIGH: u128 = 0x13579bdf13579bdf13579bdf;
const C_LOW: u128 = 0x13579bdf13579bdf13579bdf13579bdf;
/// 2^128 + 1: adds `n` to both limbs.
const LIMBS_ONE: felt252 = 0x100000000000000000000000000000001;
/// Narrow operand, below 2^128.
const N: felt252 = 0x13579bdf13579bdf;
/// Shift of the shift benchmarks.
const SHIFT: u8 = 17;
/// 2^17.
const POW_SHIFT: u256 = 0x20000;
/// 2^123, bound of the high limb of a value below 2^251.
const TWO_POW_123: u128 = 0x8000000000000000000000000000000;

// Operands, identical integers in every representation

// Both limbs vary with `n` so that no comparison or conversion folds at compile time:
// `fa(n) = A + n * (2^128 + 1)` is the integer `ua(n)`.

#[inline(always)]
fn fa(n: u8) -> felt252 {
    A + n.into() * LIMBS_ONE
}

#[inline(always)]
fn fb(n: u8) -> felt252 {
    B + n.into() * LIMBS_ONE
}

#[inline(always)]
fn fc(n: u8) -> felt252 {
    C + n.into() * LIMBS_ONE
}

#[inline(always)]
fn ua(n: u8) -> u256 {
    u256 { low: A_LOW + n.into(), high: A_HIGH + n.into() }
}

#[inline(always)]
fn ub(n: u8) -> u256 {
    u256 { low: B_LOW + n.into(), high: B_HIGH + n.into() }
}

#[inline(always)]
fn uc(n: u8) -> u256 {
    u256 { low: C_LOW + n.into(), high: C_HIGH + n.into() }
}

// Losing variants and the `[0, 2^251 - 1]` candidate

/// Checked add through the integer sum of both splits (loser).
#[inline]
fn add_via_sum(x: u252, y: u252) -> u252 {
    let sum: u256 = x.into() + y.into();
    assert(sum < PRIME, 'u252_add Overflow');
    x.wrapping_add(y)
}

/// Checked sub comparing both operand splits (loser).
#[inline]
fn sub_via_operands(x: u252, y: u252) -> u252 {
    assert(Into::<u252, u256>::into(x) >= y.into(), 'u252_sub Overflow');
    x.wrapping_sub(y)
}

/// Checked left shift, low limb times `2^-count` cast to `u128` as in `shr_exact` (loser: the
/// inverse costs a second table lookup).
#[inline]
fn shl_inv_cast(x: u252, count: u8) -> u252 {
    let product = x.value() * Bits::pow(count);
    let bits: u256 = product.into();
    let exact: Option<u128> = (bits.low.into() * Bits::inv(count)).try_into();
    assert(exact.is_some(), 'u252_shl Overflow');
    product.into()
}

/// Checked left shift, mask split to a `u256` and a two-limb AND (loser, first version).
#[inline]
fn shl_mask_u256(x: u252, count: u8) -> u252 {
    let pow = Bits::pow(count);
    let product = x.value() * pow;
    let bits: u256 = product.into();
    let mask: u256 = (pow - 1).into();
    assert((bits & mask).is_zero(), 'u252_shl Overflow');
    product.into()
}

/// Checked mul through the `u256` overflowing product compared to P (loser).
#[inline]
fn mul_u256_product(x: u252, y: u252) -> u252 {
    let (product, overflow) = Into::<u252, u256>::into(x).overflowing_mul(y.into());
    assert(!overflow && product < PRIME, 'u252_mul Overflow');
    x.wrapping_mul(y)
}

/// Exact right shift checked by a mask cast and a limb AND (loser).
#[inline]
fn shr_exact_and(x: u252, count: u8) -> u252 {
    let bits: u256 = x.into();
    let mask: u128 = (Bits::pow(count) - 1).try_into().unwrap();
    assert(bits.low & mask == 0, 'u252_shr Inexact');
    (x.value() * Bits::inv(count)).into()
}

/// Ordered comparison, high limbs first, written by hand.
#[inline]
fn lt_manual(x: u252, y: u252) -> bool {
    let a: u256 = x.into();
    let b: u256 = y.into();
    if a.high == b.high {
        a.low < b.low
    } else {
        a.high < b.high
    }
}

/// Checked left shift through a `u256` product compared to P (loser).
#[inline]
fn shl_via_u256(x: u252, count: u8) -> u252 {
    let pow = Bits::pow(count);
    let (product, overflow) = Into::<u252, u256>::into(x).overflowing_mul(pow.into());
    assert(!overflow && product < PRIME, 'u252_shl Overflow');
    (x.value() * pow).into()
}

/// DivRem by a divisor below 2^64: remainder from u128 divisions, quotient by an exact field
/// division (loser).
#[inline]
fn div_rem_felt(x: u252, divisor: NonZero<u128>) -> (u252, u128) {
    let bits: u256 = x.into();
    let (_, high) = DivRem::div_rem(bits.high, divisor);
    let (_, low) = DivRem::div_rem(bits.low, divisor);
    let (_, shift) = DivRem::div_rem(0xffffffffffffffffffffffffffffffff, divisor);
    let d: u128 = divisor.into();
    let shift = if shift + 1 == d {
        0
    } else {
        shift + 1
    };
    let (_, remainder) = DivRem::div_rem(high * shift + low, divisor);
    let quotient = felt252_div(
        x.value() - remainder.into(), Into::<u128, felt252>::into(d).try_into().unwrap(),
    );
    (quotient.into(), remainder)
}

/// Candidate `[0, 2^251 - 1]`: `Into<felt252, _>` cannot be infallible, only `TryInto`.
#[derive(Copy, Drop)]
struct U251 {
    value: felt252,
}

#[generate_trait]
impl U251Impl of U251Trait {
    /// Range proof: split, then the high limb below 2^123.
    #[inline]
    fn try_new(value: felt252) -> Option<U251> {
        let bits: u256 = value.into();
        if bits.high < TWO_POW_123 {
            Some(U251 { value })
        } else {
            None
        }
    }

    /// `2 * MAX > P`: the field sum alone cannot tell `t` from `t - P`, both splits are needed.
    #[inline]
    fn add(self: U251, other: U251) -> U251 {
        let sum: u256 = Into::<felt252, u256>::into(self.value) + other.value.into();
        assert(sum.high < TWO_POW_123, 'u251_add Overflow');
        U251 { value: self.value + other.value }
    }

    #[inline]
    fn sub(self: U251, other: U251) -> U251 {
        let a: u256 = self.value.into();
        assert(a >= other.value.into(), 'u251_sub Overflow');
        U251 { value: self.value - other.value }
    }

    #[inline]
    fn lt(self: U251, other: U251) -> bool {
        Into::<felt252, u256>::into(self.value) < other.value.into()
    }
}

// Baselines

#[test]
#[available_gas(l2_gas: 149090)]
fn bench_u252_baseline_loop() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 221855)]
fn bench_u252_baseline_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fa(n) + fb(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 354911)]
fn bench_u252_baseline_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ua(n).low.into() + ub(n).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 257198)]
fn bench_u252_baseline_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).into() + (B_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 180275)]
fn bench_u252_baseline_shift() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fc(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 246803)]
fn bench_u252_baseline_shift_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += uc(n).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 197946)]
fn bench_u252_baseline_u128_one() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 169880)]
fn bench_u252_baseline_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += N + n.into();
    }
    assert!(acc != 0);
}

// Checked add

#[test]
#[available_gas(l2_gas: 549297)]
fn bench_u252_add_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) + ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 285264)]
fn bench_u252_add_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((A_LOW + n.into()) + (B_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 221855)]
fn bench_u252_add_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fa(n) + fb(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 665165)]
fn bench_u252_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x + y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 483515)]
fn bench_u252_add_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += (x + x).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 890915)]
fn bench_u252_add_via_sum() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += add_via_sum(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 859415)]
fn bench_u251_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        acc += x.add(y).value;
    }
    assert!(acc != 0);
}

// Checked sub

#[test]
#[available_gas(l2_gas: 557613)]
fn bench_u252_sub_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) - ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 285264)]
fn bench_u252_sub_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((B_LOW + n.into()) - (A_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 665165)]
fn bench_u252_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x - y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 686165)]
fn bench_u252_sub_via_operands() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += sub_via_operands(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 686165)]
fn bench_u251_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        acc += x.sub(y).value;
    }
    assert!(acc != 0);
}

// Wrapping add and sub

#[test]
#[available_gas(l2_gas: 528507)]
fn bench_u252_wrapping_add_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ua(n).wrapping_add(ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 338279)]
fn bench_u252_wrapping_add_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).wrapping_add(B_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 221855)]
fn bench_u252_wrapping_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += x.wrapping_add(y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 221855)]
fn bench_u252_wrapping_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += x.wrapping_sub(y).value();
    }
    assert!(acc != 0);
}

// Shifts by 2^17

#[test]
#[available_gas(l2_gas: 1712865)]
fn bench_u252_shl_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (uc(n) * POW_SHIFT).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 334625)]
fn bench_u252_shl_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::shl(fc(n), SHIFT);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 723461)]
fn bench_u252_shl() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += x.shl(SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2170865)]
fn bench_u252_shl_via_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_via_u256(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 765965)]
fn bench_u252_shl_inv_cast() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_inv_cast(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 916136)]
fn bench_u252_shl_mask_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_mask_u256(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 754961)]
fn bench_u252_shl_high() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += x.shl(SHIFT + 128).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 913553)]
fn bench_u252_shr_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) / POW_SHIFT).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 345020)]
fn bench_u252_shr_exact_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::shr_exact(fc(n) * 0x20000, SHIFT);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 632615)]
fn bench_u252_shr_exact() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (fc(n) * 0x20000).into();
        acc += x.shr_exact(SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 877811)]
fn bench_u252_shr_exact_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (fc(n) * 0x20000).into();
        acc += shr_exact_and(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 867311)]
fn bench_u252_shr() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        acc += x.shr(SHIFT).value();
    }
    assert!(acc != 0);
}

// DivRem by 7

#[test]
#[available_gas(l2_gas: 923948)]
fn bench_u252_divrem_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (q, r) = DivRem::div_rem(ua(n), 7);
        acc += q.low.into() + r.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 362187)]
fn bench_u252_divrem_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (q, r) = DivRem::div_rem(A_LOW + n.into(), 7);
        acc += q.into() + r.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1090415)]
fn bench_u252_divrem() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let (q, r) = x.div_rem(7);
        acc += q.value() + r.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1351865)]
fn bench_u252_divrem_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let (q, r) = div_rem_felt(x, 7);
        acc += q.value() + r.into();
    }
    assert!(acc != 0);
}

// Comparisons

#[test]
#[available_gas(l2_gas: 441189)]
fn bench_u252_eq_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if ua(n) == ub(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 253040)]
fn bench_u252_eq_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if fa(n) == fb(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 253040)]
fn bench_u252_eq() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if x == y {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 448466)]
fn bench_u252_lt_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if ub(n) < ua(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 337239)]
fn bench_u252_lt_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if (A_LOW + n.into()) < (B_LOW + n.into()) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 676715)]
fn bench_u252_lt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if y < x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 546420)]
fn bench_u252_lt_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = ((N + n.into()).into(), N.into());
        if y < x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 694565)]
fn bench_u252_lt_manual() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if lt_manual(y, x) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 676715)]
fn bench_u251_lt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        if y.lt(x) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 697715)]
fn bench_u252_le() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if y <= x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 211460)]
fn bench_u252_is_zero_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if fa(n) == 0 {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 211460)]
fn bench_u252_is_zero() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        if x.is_zero() {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

// Bitwise

#[test]
#[available_gas(l2_gas: 605441)]
fn bench_u252_and_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) & ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 605441)]
fn bench_u252_or_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) | ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 605441)]
fn bench_u252_xor_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) ^ ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 414593)]
fn bench_u252_and_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((A_LOW + n.into()) & (B_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 862775)]
fn bench_u252_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x & y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 957086)]
fn bench_u252_or() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x | y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 957086)]
fn bench_u252_xor() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x ^ y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 815367)]
fn bench_u252_bit_test_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if Bits::get(ua(n), 2 * n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 928284)]
fn bench_u252_bit_test() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        if x.bit(2 * n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 442733)]
fn bench_u252_bit_set_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::set(fb(n), 2 * n + 50);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 975513)]
fn bench_u252_bit_set() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        acc += x.set_bit(2 * n + 50).value();
    }
    assert!(acc != 0);
}

// Conversions

#[test]
#[available_gas(l2_gas: 180275)]
fn bench_u252_from_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        acc += x.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 349430)]
fn bench_u252_to_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let bits: u256 = x.into();
        acc += bits.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 255927)]
fn bench_u252_to_u256_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        let bits: u256 = x.into();
        acc += bits.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 358029)]
fn bench_u252_from_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = ua(n).try_into().unwrap();
        acc += x.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 197946)]
fn bench_u252_from_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (A_LOW + n.into()).into();
        acc += x.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 198335)]
fn bench_u252_to_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        let value: u128 = x.try_into().unwrap();
        acc += value.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 159485)]
fn bench_u252_from_u8() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = n.into();
        acc += x.value() + 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 215618)]
fn bench_u252_to_u8() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = n.into();
        let value: u8 = x.try_into().unwrap();
        acc += value.into() + 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 419780)]
fn bench_u251_from_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += U251Trait::try_new(fa(n)).unwrap().value;
    }
    assert!(acc != 0);
}

// Serde and storage packing

#[test]
#[available_gas(l2_gas: 243380)]
fn bench_u252_serde() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let mut out = array![];
        x.serialize(ref out);
        let mut span = out.span();
        let back: u252 = Serde::deserialize(ref span).unwrap();
        acc += back.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 461003)]
fn bench_u252_serde_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let mut out = array![];
        ua(n).serialize(ref out);
        let mut span = out.span();
        let back: u256 = Serde::deserialize(ref span).unwrap();
        acc += back.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 180275)]
fn bench_u252_store_packing() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let back: u252 = StorePacking::unpack(StorePacking::pack(x));
        acc += back.value();
    }
    assert!(acc != 0);
}

// Checked mul

#[test]
#[available_gas(l2_gas: 1825131)]
fn bench_u252_mul_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ub(n) * (n.into() + 3)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1367615)]
fn bench_u252_mul() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        let y: u252 = (n + 3).into();
        acc += (x * y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2085321)]
fn bench_u252_mul_u256_product() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        let y: u252 = (n + 3).into();
        acc += mul_u256_product(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1214315)]
fn bench_u252_mul_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += (x * x).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 249921)]
fn bench_u252_mul_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fb(n) * (n + 3).into();
    }
    assert!(acc != 0);
}
