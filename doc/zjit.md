# ZJIT: ADVANCED RUBY JIT PROTOTYPE

## Build Instructions

To build ZJIT on macOS:

```bash
./autogen.sh

./configure \
    --enable-zjit=dev \
    --prefix="$HOME"/.rubies/ruby-zjit \
    --disable-install-doc \
    --with-opt-dir="$(brew --prefix openssl):$(brew --prefix readline):$(brew --prefix libyaml)"

make -j miniruby
```

## Documentation

You can generate and open the source level documentation in your browser using:

```bash
cargo doc --document-private-items -p zjit --open
```

## Testing

Note that tests link against CRuby, so directly calling `cargo test`, or `cargo nextest` should not build. All tests are instead accessed through `make`.

### Setup

First, ensure you have `cargo` installed. If you do not already have it, you can use [rustup.rs](https://rustup.rs/).

Also install cargo-binstall with:

```bash
cargo install cargo-binstall
```

Make sure to add `--enable-zjit=dev` when you run `configure`, then install the following tools:

```bash
cargo binstall --secure cargo-nextest
cargo binstall --secure cargo-insta
```

`cargo-insta` is used for updating snapshots. `cargo-nextest` runs each test in its own process, which is valuable since CRuby only supports booting once per process, and most APIs are not thread safe.

### Running unit tests

For testing functionality within ZJIT, use:

```bash
make zjit-test
```

You can also run a single test case by specifying the function name:

```bash
make zjit-test ZJIT_TESTS=test_putobject
```

#### Snapshot Testing

ZJIT uses [insta](https://insta.rs/) for snapshot testing within unit tests. When tests fail due to snapshot mismatches, pending snapshots are created. The test command will notify you if there are pending snapshots:

```
Pending snapshots found. Accept with: make zjit-test-update
```

To update/accept all the snapshot changes:

```bash
make zjit-test-update
```

You can also review snapshot changes interactively one by one:

```bash
cd zjit && cargo insta review
```

Test changes will be reviewed alongside code changes.

### Running integration tests

This command runs Ruby execution tests.

```bash
make test-all TESTS="test/ruby/test_zjit.rb"
```

You can also run a single test case by matching the method name:

```bash
make test-all TESTS="test/ruby/test_zjit.rb -n TestZJIT#test_putobject"
```

### Running all tests

Runs both `make zjit-test` and `test/ruby/test_zjit.rb`:

```bash
make zjit-check
```

## Statistics Collection

ZJIT provides detailed statistics about JIT compilation and execution behavior.

### Basic Stats

Run with basic statistics printed on exit:

```bash
./miniruby --zjit-stats script.rb
```

Collect stats without printing (access via `RubyVM::ZJIT.stats` in Ruby):

```bash
./miniruby --zjit-stats=quiet script.rb
```

### Accessing Stats in Ruby

```ruby
# Check if stats are enabled
if RubyVM::ZJIT.stats_enabled?
  stats = RubyVM::ZJIT.stats
  puts "Compiled ISEQs: #{stats[:compiled_iseq_count]}"
  puts "Failed ISEQs: #{stats[:failed_iseq_count]}"

  # You can also reset stats during execution
  RubyVM::ZJIT.reset_stats!
end
```

### Performance Ratio

The `ratio_in_zjit` stat shows the percentage of Ruby instructions executed in JIT code vs interpreter. This metric only appears when ZJIT is built with `--enable-zjit=stats` (which enables `rb_vm_insn_count` tracking) and represents a key performance indicator for ZJIT effectiveness.

To build with stats support:

```bash
./configure --enable-zjit=stats
make -j
```

### Tracing side exits

Through [Stackprof](https://github.com/tmm1/stackprof), detailed information about the methods that the JIT side-exits from can be displayed after some execution of a program. Optionally, you can use `--zjit-trace-exits-sample-rate=N` to sample every N-th occurrence. Enabling `--zjit-trace-exits-sample-rate=N` will automatically enable `--zjit-trace-exits`.

```bash
./miniruby --zjit-trace-exits script.rb
```

A file called `zjit_exits_{pid}.dump` will be created in the same directory as `script.rb`. Viewing the side exited methods can be done with Stackprof:

```bash
stackprof path/to/zjit_exits_{pid}.dump
```

### Printing ZJIT Errors

`--zjit-debug` prints ZJIT compilation errors and other diagnostics:

```bash
./miniruby --zjit-debug script.rb
```

As you might guess from the name, this option is intended mostly for ZJIT developers.

## Useful dev commands

To view YARV output for code snippets:

```bash
./miniruby --dump=insns -e0
```

To run code snippets with ZJIT:

```bash
./miniruby --zjit -e0
```

You can also try https://www.rubyexplorer.xyz/ to view Ruby YARV disasm output with syntax highlighting
in a way that can be easily shared with other team members.

## Understanding Ruby Stacks

Ruby execution involves three distinct stacks and understanding them will help you understand ZJIT's implementation:

### 1. Native Stack

- **Purpose**: Return addresses and saved registers. ZJIT also uses it for some C functions' argument arrays
- **Management**: OS-managed, one per native thread
- **Growth**: Downward from high addresses
- **Constants**: `NATIVE_STACK_PTR`, `NATIVE_BASE_PTR`

### 2. Ruby VM Stack

The Ruby VM uses a single contiguous memory region (`ec->vm_stack`) containing two sub-stacks that grow toward each other. When they meet, stack overflow occurs.

See [doc/contributing/vm_stack_and_frames.md](contributing/vm_stack_and_frames.md) for detailed architecture and frame layout.

**Control Frame Stack:**

- **Stores**: Frame metadata (`rb_control_frame_t` structures)
- **Growth**: Downward from `vm_stack + size` (high addresses)
- **Constants**: `CFP`

**Value Stack:**

- **Stores**: YARV bytecode operands (self, arguments, locals, temporaries)
- **Growth**: Upward from `vm_stack` (low addresses)
- **Constants**: `SP`

## ZJIT Glossary

This glossary contains terms that are helpful for understanding ZJIT.

Please note that some terms may appear in CRuby internals too but with different meanings.

| Term              | Definition                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| HIR               | High-level Intermediate Representation. High-level (Ruby semantics) graph representation in static single-assignment (SSA) form |
| LIR               | Low-level Intermediate Representation. Low-level IR used in the backend for assembly generation                                 |
| SSA               | Static Single Assignment. A form where each variable is assigned exactly once                                                   |
| `opnd`            | Operand. An operand to an IR instruction (can be register, memory, immediate, etc.)                                             |
| `dst`             | Destination. The output operand of an instruction where the result is stored                                                    |
| VReg              | Virtual Register. A virtual register that gets lowered to physical register or memory                                           |
| `insn_id`         | Instruction ID. An index of an instruction in a function                                                                        |
| `block_id`        | The index of a basic block, which effectively acts like a pointer                                                               |
| `branch`          | Control flow edge between basic blocks in the compiled code                                                                     |
| `cb`              | Code Block. Memory region for generated machine code                                                                            |
| `entry`           | The starting address of compiled code for an ISEQ                                                                               |
| Patch Point       | Location in generated code that can be modified later in case assumptions get invalidated                                       |
| Frame State       | Captured state of the Ruby stack frame at a specific point for deoptimization                                                   |
| Guard             | A run-time check that ensures assumptions are still valid                                                                       |
| `invariant`       | An assumption that JIT code relies on, requiring invalidation if broken                                                         |
| Deopt             | Deoptimization. Process of falling back from JIT code to interpreter                                                            |
| Side Exit         | Exit from JIT code back to interpreter                                                                                          |
| Type Lattice      | Hierarchy of types used for type inference and optimization                                                                     |
| Constant Folding  | Optimization that evaluates constant expressions at compile time                                                                |
| RSP               | x86-64 stack pointer register used for native stack operations                                                                  |
| Register Spilling | Process of moving register values to memory when running out of physical registers                                              |
