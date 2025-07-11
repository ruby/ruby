# ZJIT: ADVANCED RUBY JIT PROTOTYPE

## Build Instructions

To build ZJIT on macOS:
```
./autogen.sh
./configure --enable-zjit=dev --prefix=$HOME/.rubies/ruby-zjit --disable-install-doc --with-opt-dir="$(brew --prefix openssl):$(brew --prefix readline):$(brew --prefix libyaml)"
make -j miniruby
```

## Useful dev commands

To view YARV output for code snippets:
```
./miniruby --dump=insns -e0
```

To run code snippets with ZJIT:
```
./miniruby --zjit -e0
```

You can also try https://www.rubyexplorer.xyz/ to view Ruby YARV disasm output with syntax highlighting
in a way that can be easily shared with other team members.

## Testing

Make sure you have a `--enable-zjit=dev` build, and run `brew install cargo-nextest` first.

### make zjit-test-all

This command runs all ZJIT tests: `make zjit-test` and `test/ruby/test_zjit.rb`.

```
make zjit-test-all
```

### make zjit-test

This command runs Rust unit tests.

```
make zjit-test
```

You can also run a single test case by specifying the function name:

```
make zjit-test ZJIT_TESTS=test_putobject
```

If you expect that your changes cause tests to fail and they do, you can have
`expect-test` fix the expected value for you by putting `UPDATE_EXPECT=1`
before your test command, like so:

```
UPDATE_EXPECT=1 make zjit-test ZJIT_TESTS=test_putobject
```

Test changes will be reviewed alongside code changes.

<details>

<summary>Setting up zjit-test</summary>

ZJIT uses `cargo-nextest` for Rust unit tests instead of `cargo test`.
`cargo-nextest` runs each test in its own process, which is valuable since
CRuby only supports booting once per process, and most APIs are not thread
safe. Use `brew install cargo-nextest` to install it on macOS, otherwise, refer
to <https://nexte.st/docs/installation/pre-built-binaries/> for installation
instructions.

Since it uses Cargo, you'll also need a `configure --enable-zjit=dev ...` build
for `make zjit-test`. Since the tests need to link against CRuby, directly
calling `cargo test`, or `cargo nextest` likely won't build. Make sure to
use `make`.

</details>

### test/ruby/test\_zjit.rb

This command runs Ruby execution tests.

```
make test-all TESTS="test/ruby/test_zjit.rb"
```

You can also run a single test case by matching the method name:

```
make test-all TESTS="test/ruby/test_zjit.rb -n TestZJIT#test_putobject"
```

## ZJIT Glossary

This glossary contains terms that are helpful for understanding ZJIT.

Please note that some terms may appear in CRuby internals too but with different meanings.

| Term | Definition |
| ---  | -----------|
| HIR | High-level Intermediate Representation. High-level (Ruby semantics) graph representation in static single-assignment (SSA) form |
| LIR | Low-level Intermediate Representation. Low-level IR used in the backend for assembly generation |
| SSA | Static Single Assignment. A form where each variable is assigned exactly once |
| `opnd` | Operand. An operand to an IR instruction (can be register, memory, immediate, etc.) |
| `dst` | Destination. The output operand of an instruction where the result is stored |
| VReg | Virtual Register. A virtual register that gets lowered to physical register or memory |
| `insn_id` | Instruction ID. An index of an instruction in a function |
| `block_id` | The index of a basic block, which effectively acts like a pointer |
| `branch` | Control flow edge between basic blocks in the compiled code |
| `cb` | Code Block. Memory region for generated machine code |
| `entry` | The starting address of compiled code for an ISEQ |
| Patch Point | Location in generated code that can be modified later in case assumptions get invalidated |
| Frame State | Captured state of the Ruby stack frame at a specific point for deoptimization |
| Guard | A run-time check that ensures assumptions are still valid |
| `invariant` | An assumption that JIT code relies on, requiring invalidation if broken |
| Deopt | Deoptimization. Process of falling back from JIT code to interpreter |
| Side Exit | Exit from JIT code back to interpreter |
| Type Lattice | Hierarchy of types used for type inference and optimization |
| Constant Folding | Optimization that evaluates constant expressions at compile time |
| RSP | x86-64 stack pointer register used for native stack operations |
| Register Spilling | Process of moving register values to memory when running out of physical registers |
