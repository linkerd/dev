//! Smoke test that `aws-lc-sys` and `aws-lc-fips-sys` both compile and statically link for musl.
//! Calling `CRYPTO_library_init` from each crate forces the linker to keep its `bcm` object.

#![warn(missing_docs, clippy::missing_docs_in_private_items)]

/// Initializes both AWS-LC builds so neither static archive is dropped at link time.
fn main() {
    // SAFETY: `CRYPTO_library_init` takes no arguments and is safe to call at any time.
    unsafe {
        aws_lc_sys::CRYPTO_library_init();
        aws_lc_fips_sys::CRYPTO_library_init();
    }
    println!("aws-lc-sys and aws-lc-fips-sys linked and initialized");
}
