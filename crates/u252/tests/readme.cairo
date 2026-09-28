//! The examples of `README.md`, compiled against the public API (integration test, as for a
//! dependent package).

use core::num::traits::{Bounded, CheckedAdd, WrappingAdd};
use uint252::bits::Bits;
use uint252::{PRIME, U252Trait, u252};

#[test]
#[available_gas(l2_gas: 59751)]
fn test_readme_usage() {
    // Conversions with `felt252` are free, both ways
    let x: u252 = 0x2a.into();
    let raw: felt252 = x.into();
    assert!(raw == 0x2a);
    assert!(x.value() == raw);
    assert!(U252Trait::new(raw) == x);
    // Checked arithmetic on the integers `[0, P - 1]`
    let max: u252 = Bounded::MAX;
    assert!(max.checked_add(x).is_none());
    assert!(max.wrapping_add(x).value() == 0x29);
    assert!(x + x == 84_u8.into());
    assert!(x < max);
    // Shifts and bits
    assert!(x.shl(3) == 336_u16.into());
    assert!(x.shr(1) == 21_u8.into());
    assert!(x.bit(1) && !x.bit(0));
    assert!(x.set_bit(0) == 43_u8.into());
    let (quotient, remainder) = x.div_rem(5);
    assert!(quotient == 8_u8.into() && remainder == 2);
    // The canonical integer
    let wide: u256 = max.into();
    assert!(wide == PRIME - 1);
}

#[test]
#[available_gas(l2_gas: 29015)]
fn test_readme_bits() {
    assert!(Bits::pow(10) == 1024);
    assert!(Bits::pow(10) * Bits::inv(10) == 1);
    assert!(Bits::shr_exact(Bits::shl(0b101, 7), 7) == 0b101);
    assert!(Bits::get(Bits::set(0, 200).into(), 200));
}

#[test]
#[available_gas(l2_gas: 20097)]
#[should_panic(expected: 'u252_add Overflow')]
fn test_readme_add_overflow() {
    let max: u252 = Bounded::MAX;
    let one: u252 = 1_u8.into();
    max + one;
}
