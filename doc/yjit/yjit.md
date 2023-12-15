<p align="center">
  <a href="https://yjit.org/" target="_blank" rel="noopener noreferrer">
    <img src="https://user-images.githubusercontent.com/224488/131155756-aa8fb528-a813-4dfd-99ac-8785c3d5eed7.png" width="400">
  </a>
</p>


YJIT - Yet Another Ruby JIT
===========================

YJIT is a lightweight, minimalistic Ruby JIT built inside CRuby.
It lazily compiles code using a Basic Block Versioning (BBV) architecture.
The target use case is that of servers running Ruby on Rails.
YJIT is currently supported for macOS, Linux and BSD on x86-64 and arm64/aarch64 CPUs.
This project is open source and falls under the same license as CRuby.

<p align="center"><b>
    If you're using YJIT in production, please
    <a href="mailto:maxime.chevalierboisvert@shopify.com">share your success stories with us!</a>
 </b></p>

If you wish to learn more about the approach taken, here are some conference talks and publications:
- RubyKaigi 2022 keynote: [Stories from developing YJIT](https://www.youtube.com/watch?v=EMchdR9C8XM)
- RubyKaigi 2022 talk: [Building a Lightweight IR and Backend for YJIT](https://www.youtube.com/watch?v=BbLGqTxTRp0)
- RubyKaigi 2021 talk: [YJIT: Building a New JIT Compiler Inside CRuby](https://www.youtube.com/watch?v=PBVLf3yfMs8)
- Blog post: [YJIT: Building a New JIT Compiler Inside CRuby](https://pointersgonewild.com/2021/06/02/yjit-building-a-new-jit-compiler-inside-cruby/)
- VMIL 2021 paper: [YJIT: A Basic Block Versioning JIT Compiler for CRuby](https://dl.acm.org/doi/10.1145/3486606.3486781)
- MoreVMs 2021 talk: [YJIT: Building a New JIT Compiler Inside CRuby](https://www.youtube.com/watch?v=vucLAqv7qpc)
- ECOOP 2016 talk: [Interprocedural Type Specialization of JavaScript Programs Without Type Analysis](https://www.youtube.com/watch?v=sRNBY7Ss97A)
- ECOOP 2016 paper: [Interprocedural Type Specialization of JavaScript Programs Without Type Analysis](https://drops.dagstuhl.de/opus/volltexte/2016/6101/pdf/LIPIcs-ECOOP-2016-7.pdf)
- ECOOP 2015 talk: [Simple and Effective Type Check Removal through Lazy Basic Block Versioning](https://www.youtube.com/watch?v=S-aHBuoiYE0)
- ECOOP 2015 paper: [Simple and Effective Type Check Removal through Lazy Basic Block Versioning](https://arxiv.org/pdf/1411.0352.pdf)

To cite YJIT in your publications, please cite the VMIL 2021 paper:

```
@inproceedings{yjit_vmil2021,
author = {Chevalier-Boisvert, Maxime and Gibbs, Noah and Boussier, Jean and Wu, Si Xing (Alan) and Patterson, Aaron and Newton, Kevin and Hawthorn, John},
title = {YJIT: A Basic Block Versioning JIT Compiler for CRuby},
year = {2021},
isbn = {9781450391092},
publisher = {Association for Computing Machinery},
address = {New York, NY, USA},
url = {https://doi.org/10.1145/3486606.3486781},
doi = {10.1145/3486606.3486781},
booktitle = {Proceedings of the 13th ACM SIGPLAN International Workshop on Virtual Machines and Intermediate Languages},
pages = {25–32},
numpages = {8},
keywords = {ruby, dynamically typed, compiler, optimization, just-in-time, bytecode},
location = {Chicago, IL, USA},
series = {VMIL 2021}
}
```

## Current Limitations

YJIT may not be suitable for certain applications. It currently only supports macOS and Linux on x86-64 and arm64/aarch64 CPUs. YJIT will use more memory than the Ruby interpreter because the JIT compiler needs to generate machine code in memory and maintain additional state information.
You can change how much executable memory is allocated using [YJIT's command-line options](#command-line-options). There is a slight performance tradeoff because allocating less executable memory could result in the generated machine code being collected more often.

## Installation

### Requirements

You will need to install:
- A C compiler such as GCC or Clang
- GNU Make and Autoconf
- The Rust compiler `rustc` and Cargo (if you want to build in dev/debug mode)
  - The Rust version must be [>= 1.58.0](../../yjit/Cargo.toml).

To install the Rust build toolchain, we suggest following the [recommended installation method][rust-install]. Rust also provides first class [support][editor-tools] for many source code editors.

[rust-install]: https://www.rust-lang.org/tools/install
[editor-tools]: https://www.rust-lang.org/tools

### Building YJIT

Start by cloning the `ruby/ruby` repository:

```sh
git clone https://github.com/ruby/ruby yjit
cd yjit
```

The YJIT `ruby` binary can be built with either GCC or Clang. It can be built either in dev (debug) mode or in release mode. For maximum performance, compile YJIT in release mode with GCC. More detailed build instructions are provided in the [Ruby README](https://github.com/ruby/ruby#how-to-build).

```sh
# Configure in release mode for maximum performance, build and install
./autogen.sh
./configure --enable-yjit --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc
make -j && make install
```

or

```sh
# Configure in lower-performance dev (debug) mode for development, build and install
./autogen.sh
./configure --enable-yjit=dev --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc
make -j && make install
```

Dev mode includes extended YJIT statistics, but can be slow. For only statistics you can configure in stats mode:

```sh
# Configure in extended-stats mode without slow runtime checks, build and install
./autogen.sh
./configure --enable-yjit=stats --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc
make -j && make install
```

On macOS, you may need to specify where to find some libraries:

```sh
# Install dependencies
brew install openssl readline libyaml

# Configure in dev (debug) mode for development, build and install
./autogen.sh
./configure --enable-yjit=dev --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc --with-opt-dir="$(brew --prefix openssl):$(brew --prefix readline):$(brew --prefix libyaml)"
make -j && make install
```

Typically configure will choose the default C compiler. To specify the C compiler, use

```sh
# Choosing a specific c compiler
export CC=/path/to/my/chosen/c/compiler
```

before running `./configure`.

You can test that YJIT works correctly by running:

```sh
# Quick tests found in /bootstraptest
make btest

# Complete set of tests
make -j test-all
```

## Usage

### Examples

Once YJIT is built, you can either use `./miniruby` from within your build directory, or switch to the YJIT version of `ruby`
by using the `chruby` tool:

```sh
chruby ruby-yjit
ruby myscript.rb
```

You can dump statistics about compilation and execution by running YJIT with the `--yjit-stats` command-line option:

```sh
./miniruby --yjit-stats myscript.rb
```

The machine code generated for a given method can be printed by adding `puts RubyVM::YJIT.disasm(method(:method_name))` to a Ruby script. Note that no code will be generated if the method is not compiled.

### Command-Line Options

YJIT supports all command-line options supported by upstream CRuby, but also adds a few YJIT-specific options:

- `--yjit`: enable YJIT (disabled by default)
- `--yjit-call-threshold=N`: number of calls after which YJIT begins to compile a function (default 30)
- `--yjit-exec-mem-size=N`: size of the executable memory block to allocate, in MiB (default 64 MiB)
- `--yjit-stats`: print statistics after the execution of a program (incurs a run-time cost)
- `--yjit-trace-exits`: produce a Marshal dump of backtraces from specific exits. Automatically enables `--yjit-stats`

Note that there is also an environment variable `RUBY_YJIT_ENABLE` which can be used to enable YJIT.
This can be useful for some deployment scripts where specifying an extra command-line option to Ruby is not practical.

### Benchmarking

We have collected a set of benchmarks and implemented a simple benchmarking harness in the [yjit-bench](https://github.com/Shopify/yjit-bench) repository. This benchmarking harness is designed to disable CPU frequency scaling, set process affinity and disable address space randomization so that the variance between benchmarking runs will be as small as possible. Please kindly note that we are at an early stage in this project.

## Performance Tips for Production Deployments

While YJIT options default to what we think would work well for most workloads,
they might not necessarily be the best configuration for your application.

This section covers tips on improving YJIT performance in case YJIT does not
speed up your application in production.

### Increasing --yjit-exec-mem-size

When JIT code size (`RubyVM::YJIT.runtime_stats[:code_region_size]`) reaches this value,
YJIT triggers "code GC" that frees all JIT code and starts recompiling everything.
Compiling code takes some time, so scheduling code GC too frequently slows down your application.
Increasing `--yjit-exec-mem-size` may speed up your application if `RubyVM::YJIT.runtime_stats[:code_gc_count]` is not 0 or 1.

### Running workers as long as possible

It's helpful to call the same code as many times as possible before a process restarts.
If a process is killed too frequently, the time taken for compiling methods may outweigh
the speedup obtained by compiling them.

You should monitor the number of requests each process has served.
If you're periodically killing worker processes, e.g. with `unicorn-worker-killer` or `puma_worker_killer`,
you may want to reduce the killing frequency or increase the limit.

## Saving YJIT Memory Usage

YJIT allocates memory for JIT code and metadata. Enabling YJIT generally results in more memory usage.

This section goes over tips on minimizing YJIT memory usage in case it uses more than your capacity.

### Increasing --yjit-call-threshold

As of Ruby 3.2, `--yjit-call-threshold` defaults to 30. With this default, some applications end up
compiling methods that are used only during the application boot. Increasing this option may help
you reduce the size of JIT code and metadata. It's worth trying different values like `--yjit-call-threshold=100`.

Note that increasing the value too much may result in compiling code too late.
You should monitor how many requests each worker processes before it's restarted. For example,
if each process only handles 1000 requests, `--yjit-call-threshold=1000` might be too large for your application.

### Decreasing --yjit-exec-mem-size

`--yjit-exec-mem-size` specifies the JIT code size, but YJIT also uses memory for its metadata,
which often consumes more memory than JIT code. Generally, YJIT adds memory overhead by roughly
3-4x of `--yjit-exec-mem-size` in production as of Ruby 3.2. You should multiply that by the number
of worker processes to estimate the worst case memory overhead.

Running code GC adds overhead, but it could be still faster than recovering from a whole process killed by OOM.

## Code Optimization Tips

This section contains tips on writing Ruby code that will run as fast as possible on YJIT. Some of this advice is based on current limitations of YJIT, while other advice is broadly applicable. It probably won't be practical to apply these tips everywhere in your codebase. You should ideally start by profiling your application using a tool such as [stackprof](https://github.com/tmm1/stackprof) so that you can determine which methods make up most of the execution time. You can then refactor the specific methods that make up the largest fractions of the execution time. We do not recommend modifying your entire codebase based on the current limitations of YJIT.

- Avoid using `OpenStruct`
- Avoid redefining basic integer operations (i.e. +, -, <, >, etc.)
- Avoid redefining the meaning of `nil`, equality, etc.
- Avoid allocating objects in the hot parts of your code
- Minimize layers of indirection
  - Avoid classes that wrap objects if you can
  - Avoid methods that just call another method, trivial one liner methods
- Try to write code so that the same variables always have the same type
- Use `while` loops if you can, instead of C methods like `Array#each`
  - This is not idiomatic Ruby, but could help in hot methods
- CRuby method calls are costly. Avoid things such as methods that only return a value from a hash or return a constant.

You can also use the `--yjit-stats` command-line option to see which bytecodes cause YJIT to exit, and refactor your code to avoid using these instructions in the hottest methods of your code.

### Other Statistics

If you run `ruby` with `--yjit --yjit-stats`, YJIT will track and return performance statistics in `RubyVM::YJIT.runtime_stats`.

```rb
$ RUBYOPT="--yjit --yjit-stats" irb
irb(main):001:0> RubyVM::YJIT.runtime_stats
=>
{:inline_code_size=>340745,
 :outlined_code_size=>297664,
 :all_stats=>true,
 :exec_instruction=>1547816,
 :send_callsite_not_simple=>7267,
 :send_kw_splat=>7,
 :send_ivar_set_method=>72,
...
```

Some of the counters include:

* :exec_instruction - how many Ruby bytecode instructions have been executed
* :binding_allocations - number of bindings allocated
* :binding_set - number of variables set via a binding
* :code_gc_count - number of garbage collections of compiled code since process start
* :vm_insns_count - number of instructions executed by the Ruby interpreter
* :compiled_iseq_count - number of bytecode sequences compiled
* :inline_code_size - size in bytes of compiled YJIT blocks
* :outline_code_size - size in bytes of YJIT error-handling compiled code
* :side_exit_count - number of side exits taken at runtime
* :total_exit_count - number of exits, including side exits, taken at runtime
* :avg_len_in_yjit - avg. number of instructions in compiled blocks before exiting to interpreter

Counters starting with "exit_" show reasons for YJIT code taking a side exit (return to the interpreter.) See yjit_hacking.md for more details.

Performance counter names are not guaranteed to remain the same between Ruby versions. If you're curious what one does, it's usually best to search the source code for it &mdash; but it may change in a later Ruby version.

The printed text after a --yjit-stats run includes other information that may be named differently than the information in runtime_stats.

## Contributing

We welcome open source contributors. You should feel free to open new issues to report bugs or just to ask questions.
Suggestions on how to make this readme file more helpful for new contributors are most welcome.

Bug fixes and bug reports are very valuable to us. If you find a bug in YJIT, it's very possible be that nobody has reported it before,
or that we don't have a good reproduction for it, so please open an issue and provide as much information as you can about your configuration and a description of how you encountered the problem. List the commands you used to run YJIT so that we can easily reproduce the issue on our end and investigate it. If you are able to produce a small program reproducing the error to help us track it down, that is very much appreciated as well.

If you would like to contribute a large patch to YJIT, we suggest opening an issue or a discussion on this repository so that
we can have an active discussion. A common problem is that sometimes people submit large pull requests to open source projects
without prior communication, and we have to reject them because the work they implemented does not fit within the design of the
project. We want to save you time and frustration, so please reach out and we can have a productive discussion as to how
you can contribute things we will want to merge into YJIT.

### Source Code Organization

The YJIT source code is divided between:
- `yjit.c`: code YJIT uses to interface with the rest of CRuby
- `yjit.h`: C definitions YJIT exposes to the rest of the CRuby
- `yjit.rb`: `YJIT` Ruby module that is exposed to Ruby
- `yjit/src/asm/*`: in-memory assembler we use to generate machine code
- `yjit/src/codegen.rs`: logic for translating Ruby bytecode to machine code
- `yjit/src/core.rb`: basic block versioning logic, core structure of YJIT
- `yjit/src/stats.rs`: gathering of run-time statistics
- `yjit/src/options.rs`: handling of command-line options
- `yjit/bindgen/src/main.rs`: C bindings exposed to the Rust codebase through bindgen
- `yjit/src/cruby.rs`: C bindings manually exposed to the Rust codebase

The core of CRuby's interpreter logic is found in:
- `insns.def`: defines Ruby's bytecode instructions (gets compiled into `vm.inc`)
- `vm_insnshelper.c`: logic used by Ruby's bytecode instructions
- `vm_exec.c`: Ruby interpreter loop

### Generating C bindings with bindgen

In order to expose C functions to the Rust codebase, you will need to generate C bindings:

```sh
CC=clang ./configure --enable-yjit=dev
make -j yjit-bindgen
```

This uses the bindgen tools to generate/update `yjit/src/cruby_bindings.inc.rs` based on the
bindings listed in `yjit/bindgen/src/main.rs`. Avoid manually editing this file
as it could be automatically regenerated at a later time. If you need to manually add C bindings,
add them to `yjit/cruby.rs` instead.

### Coding & Debugging Protips

There are 3 test suites:
- `make btest` (see `/bootstraptest`)
- `make test-all`
- `make test-spec`
- `make check` runs all of the above

The tests can be run in parallel like this:

```sh
make -j test-all RUN_OPTS="--yjit-call-threshold=1"
```

Or single-threaded like this, to more easily identify which specific test is failing:

```sh
make test-all TESTOPTS=--verbose RUN_OPTS="--yjit-call-threshold=1"
```

To debug a single test in `test-all`:

```sh
make test-all TESTS='test/-ext-/marshal/test_usrmarshal.rb' RUNRUBYOPT=--debugger=lldb RUN_OPTS="--yjit-call-threshold=1"
```

You can also run one specific test in `btest`:

```sh
make btest BTESTS=bootstraptest/test_ractor.rb RUN_OPTS="--yjit-call-threshold=1"
```

There are shortcuts to run/debug your own test/repro in `test.rb`:

```sh
make run  # runs ./miniruby test.rb
make lldb # launches ./miniruby test.rb in lldb
```

You can use the Intel syntax for disassembly in LLDB, keeping it consistent with YJIT's disassembly:

```sh
echo "settings set target.x86-disassembly-flavor intel" >> ~/.lldbinit
```

## Running x86 YJIT on Apple's Rosetta

For development purposes, it is possible to run x86 YJIT on an Apple M1 via Rosetta.  You can find basic
instructions below, but there are a few caveats listed further down.

First, install Rosetta:

```sh
$ softwareupdate --install-rosetta
```

Now any command can be run with Rosetta via the `arch` command line tool.

Then you can start your shell in an x86 environment:

```sh
$ arch -x86_64 zsh
```

You can double check your current architecture via the `arch` command:

```sh
$ arch -x86_64 zsh
$ arch
i386
```

You may need to set the default target for `rustc` to x86-64, e.g.

```sh
$ rustup default stable-x86_64-apple-darwin
```

While in your i386 shell, install Cargo and Homebrew, then hack away!

### Rosetta Caveats

1. You must install a version of Homebrew for each architecture
2. Cargo will install in $HOME/.cargo by default, and I don't know a good way to change architectures after install

If you use Fish shell you can [read this link](https://tenderlovemaking.com/2022/01/07/homebrew-rosetta-and-ruby.html) for information on making the dev environment easier.
