// This build script is only used for `make zjit-test` for building
// the test binary; ruby builds don't use this.

use std::collections::{HashMap, HashSet};

fn main() {
    use std::env;

    // option_env! automatically registers a rerun-if-env-changed
    if let Some(ruby_build_dir) = option_env!("RUBY_BUILD_DIR") {
        let out_dir = env::var("OUT_DIR").unwrap();

        // Copy libminiruby.a and strip libruby.o to avoid duplicate
        // ZJIT symbols. The partial-linked libruby.o contains a full copy
        // of ZJIT code (hidden symbols + globals) alongside YJIT code.
        // Without removal, the test binary gets two ZJIT runtimes with
        // independent global state.
        let cleaned = format!("{out_dir}/libminiruby.a");
        std::fs::copy(format!("{ruby_build_dir}/libminiruby.a"), &cleaned).unwrap();
        std::process::Command::new("ar")
            .args(["d", &cleaned, "libruby.o"])
            .status()
            .expect("failed to strip libruby.o from archive");

        // Generate no-op C stubs for all YJIT symbols that the remaining
        // archive objects reference. This satisfies the linker without
        // pulling in libruby.o or yjit.o. The stubs are safe because YJIT
        // is never enabled during ZJIT tests.
        generate_yjit_stubs(&cleaned, &out_dir);

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

/// Discover undefined YJIT symbols in the archive and compile a C file
/// with no-op stubs, then insert the resulting object into the archive.
fn generate_yjit_stubs(archive_path: &str, out_dir: &str) {
    let needed = discover_undefined_yjit_symbols(archive_path);
    if needed.is_empty() {
        return;
    }

    let variables = parse_yjit_header_variables();
    let c_source = emit_c_stubs(&needed, &variables);

    let c_path = format!("{out_dir}/yjit_stubs.c");
    let o_path = format!("{out_dir}/yjit_stubs.o");
    std::fs::write(&c_path, c_source).expect("failed to write yjit_stubs.c");

    // Compile with the system C compiler.
    let status = std::process::Command::new("cc")
        .args(["-c", "-o", &o_path, &c_path])
        .status()
        .expect("failed to invoke cc");
    assert!(status.success(), "cc failed to compile yjit_stubs.c");

    // Insert the stub object into the cleaned archive so it participates
    // in normal archive symbol resolution.
    let status = std::process::Command::new("ar")
        .args(["r", archive_path, &o_path])
        .status()
        .expect("failed to insert yjit_stubs.o into archive");
    assert!(status.success(), "ar failed to insert yjit_stubs.o");
}

/// Run `nm -u` on the archive and collect every undefined symbol whose
/// C-level name starts with `rb_yjit_` or equals `Init_builtin_yjit`.
fn discover_undefined_yjit_symbols(archive_path: &str) -> HashSet<String> {
    let output = std::process::Command::new("nm")
        .args(["-u", archive_path])
        .output()
        .expect("failed to run nm");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut symbols = HashSet::new();

    for line in stdout.lines() {
        let sym = line.trim();

        // Skip empty lines, object-file headers ("foo.o:"), and
        // the "U <sym>" format that nm uses for single .o files.
        if sym.is_empty() || sym.ends_with(':') {
            continue;
        }
        let sym = sym.strip_prefix("U ").unwrap_or(sym).trim();

        // Strip the leading underscore that macOS adds to C symbols.
        let c_name = sym.strip_prefix('_').unwrap_or(sym);

        if c_name.starts_with("rb_yjit_") || c_name == "Init_builtin_yjit" {
            symbols.insert(c_name.to_string());
        }
    }

    symbols
}

/// Parse `yjit.h` for `extern <type> <name>;` lines to identify which
/// YJIT symbols are variables (everything else is a function).
fn parse_yjit_header_variables() -> HashMap<String, String> {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let header_path = format!("{manifest_dir}/../yjit.h");
    let header = std::fs::read_to_string(&header_path)
        .unwrap_or_else(|e| panic!("failed to read {header_path}: {e}"));

    let mut vars = HashMap::new();

    for line in header.lines() {
        let line = line.trim();

        // Match lines like: extern uint64_t rb_yjit_call_threshold;
        if let Some(rest) = line.strip_prefix("extern ") {
            if let Some((c_type, name)) = rest.strip_suffix(';').and_then(|s| s.rsplit_once(' ')) {
                let c_type = c_type.trim();
                let name = name.trim();
                if name.starts_with("rb_yjit_") {
                    vars.insert(name.to_string(), c_type.to_string());
                }
            }
        }
    }

    vars
}

/// Emit C source with stub definitions for each symbol.
fn emit_c_stubs(
    symbols: &HashSet<String>,
    variables: &HashMap<String, String>,
) -> String {
    let mut buf = String::from(
        "/* Auto-generated YJIT stubs for zjit-test. Do not edit. */\n\
         #include <stdint.h>\n\
         #include <stdbool.h>\n\n",
    );

    let mut sorted: Vec<&String> = symbols.iter().collect();
    sorted.sort();

    for sym in sorted {
        if let Some(c_type) = variables.get(sym.as_str()) {
            // Variable: emit a zero-initialized definition.
            buf.push_str(&format!("{c_type} {sym} = 0;\n"));
        } else {
            // Function: a void() stub accepts any caller's arguments
            // under the C default argument promotion rules.
            buf.push_str(&format!("void {sym}() {{}}\n"));
        }
    }

    buf
}
