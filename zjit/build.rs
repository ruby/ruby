//! this links against libruby.a
//! workaround for https://github.com/rust-lang/cargo/issues/1581#issuecomment-1216924878
fn main() {
    // TODO search for the .a. On else path, print hint to use make instead
    println!("cargo:rustc-link-lib=static:-bundle=ruby.3.5-static");
    println!("cargo:rustc-link-lib=framework=CoreFoundation");
    println!("cargo:rustc-link-lib=dl");
    println!("cargo:rustc-link-lib=objc");
    println!("cargo:rustc-link-lib=pthread");
    println!("cargo:rustc-link-search=native=/Users/alan/ruby/build-O0"); ////
}
