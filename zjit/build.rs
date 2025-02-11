fn main() {
    // TODO search for the .a. On else path, print hint to use make instead
    let ruby_build_dir = "/Users/alan/ruby/build-O0";

    println!("cargo:rustc-link-lib=static:-bundle=miniruby");
    println!("cargo:rerun-if-changed={}/libminiruby.a", ruby_build_dir);
    println!("cargo:rustc-link-lib=framework=CoreFoundation");
    println!("cargo:rustc-link-lib=dl");
    println!("cargo:rustc-link-lib=objc");
    println!("cargo:rustc-link-lib=pthread");
    println!("cargo:rustc-link-search=native={ruby_build_dir}");
}
