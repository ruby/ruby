fn main() {
    use std::env;

    // option_env! automatically registers a rerun-if-env-changed
    if let Some(ruby_build_dir) = option_env!("RUBY_BUILD_DIR") {
        // Link against libminiruby
        println!("cargo:rustc-link-search=native={ruby_build_dir}");
        println!("cargo:rustc-link-lib=static:-bundle=miniruby");

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
