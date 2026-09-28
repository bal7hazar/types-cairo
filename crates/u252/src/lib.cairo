pub mod bits;
pub mod integer;
pub use integer::{PRIME, U252Trait, u252};

#[cfg(test)]
pub mod tests {
    pub mod bench_u252;
}
