fn main() {
    use std::env;

    // TODO search for the .a. On else path, print hint to use make instead
    if let Ok(ruby_build_dir) = env::var("RUBY_BUILD_DIR") {
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

        println!("cargo:rustc-link-lib=static:-bundle=miniruby");
        println!("cargo:rustc-link-search=native={ruby_build_dir}");
    }
}
