// This build script is only used for `make zjit-test` for building
// the test binary; ruby builds don't use this.
fn main() {
    use std::env;

    // option_env! automatically registers a rerun-if-env-changed
    if let Some(ruby_build_dir) = option_env!("RUBY_BUILD_DIR") {
        let out_dir = env::var("OUT_DIR").unwrap();

        // Copy libminiruby.a and strip libruby.o to avoid duplicate
        // ZJIT symbols. The partial-linked libruby.o contains a full copy
        // of ZJIT code (hidden symbols + globals) alongside YJIT code.
        // Without removal, the test binary gets two ZJIT runtimes with
        // independent global state. YJIT stubs in yjit_stubs.rs satisfy
        // the C code's YJIT symbol references instead.
        let cleaned = format!("{out_dir}/libminiruby.a");
        std::fs::copy(format!("{ruby_build_dir}/libminiruby.a"), &cleaned).unwrap();
        std::process::Command::new("ar")
            .args(["d", &cleaned, "libruby.o"])
            .status()
            .expect("failed to strip libruby.o from archive");

        println!("cargo:rustc-link-search=native={out_dir}");
        println!("cargo:rustc-link-lib=static:-bundle=miniruby");
        println!("cargo:rerun-if-changed={ruby_build_dir}/libminiruby.a");

        // System libraries that libminiruby needs. Has to be
        // ordered after -lminiruby above.
        let link_flags = env::var("RUBY_LD_FLAGS").unwrap();

        let mut split_iter = link_flags.split(" ");
        while let Some(token) = split_iter.next() {
            if token == "-framework" {
                if let Some(framework) = split_iter.next() {
                    println!("cargo:rustc-link-lib=framework={framework}");
                }
            } else if let Some(lib_name) = token.strip_prefix("-l") {
                println!("cargo:rustc-link-lib={lib_name}");
            }
        }
    }
}
