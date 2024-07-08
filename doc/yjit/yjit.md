<p align="center">
  <a href="https://yjit.org/" target="_blank" rel="noopener noreferrer">
    <img src="https://user-images.githubusercontent.com/224488/131155756-aa8fb528-a813-4dfd-99ac-8785c3d5eed7.png" width="400">
  </a>
</p>

YJIT - Yet Another Ruby JIT
===========================

YJIT is a lightweight, minimalistic Ruby JIT built inside CRuby.
It lazily compiles code using a Basic Block Versioning (BBV) architecture.
YJIT is currently supported for macOS, Linux and BSD on x86-64 and arm64/aarch64 CPUs.
This project is open source and falls under the same license as CRuby.

<p align="center"><b>
    If you're using YJIT in production, please
    <a href="mailto:maxime.chevalierboisvert@shopify.com">share your success stories with us!</a>
</b></p>

If you wish to learn more about the approach taken, here are some conference talks and publications:

- RubyKaigi 2023 keynote: [Optimizing YJIT’s Performance, from Inception to Production](https://www.youtube.com/watch?v=X0JRhh8w_4I)
- RubyKaigi 2023 keynote: [Fitting Rust YJIT into CRuby](https://www.youtube.com/watch?v=GI7vvAgP_Qs)
- RubyKaigi 2022 keynote: [Stories from developing YJIT](https://www.youtube.com/watch?v=EMchdR9C8XM)
- RubyKaigi 2022 talk: [Building a Lightweight IR and Backend for YJIT](https://www.youtube.com/watch?v=BbLGqTxTRp0)
- RubyKaigi 2021 talk: [YJIT: Building a New JIT Compiler Inside CRuby](https://www.youtube.com/watch?v=PBVLf3yfMs8)
- Blog post: [YJIT: Building a New JIT Compiler Inside CRuby](https://pointersgonewild.com/2021/06/02/yjit-building-a-new-jit-compiler-inside-cruby/)
- MPLR 2023 paper: [Evaluating YJIT’s Performance in a Production Context: A Pragmatic Approach](https://dl.acm.org/doi/10.1145/3617651.3622982)
- VMIL 2021 paper: [YJIT: A Basic Block Versioning JIT Compiler for CRuby](https://dl.acm.org/doi/10.1145/3486606.3486781)
- MoreVMs 2021 talk: [YJIT: Building a New JIT Compiler Inside CRuby](https://www.youtube.com/watch?v=vucLAqv7qpc)
- ECOOP 2016 talk: [Interprocedural Type Specialization of JavaScript Programs Without Type Analysis](https://www.youtube.com/watch?v=sRNBY7Ss97A)
- ECOOP 2016 paper: [Interprocedural Type Specialization of JavaScript Programs Without Type Analysis](https://drops.dagstuhl.de/opus/volltexte/2016/6101/pdf/LIPIcs-ECOOP-2016-7.pdf)
- ECOOP 2015 talk: [Simple and Effective Type Check Removal through Lazy Basic Block Versioning](https://www.youtube.com/watch?v=S-aHBuoiYE0)
- ECOOP 2015 paper: [Simple and Effective Type Check Removal through Lazy Basic Block Versioning](https://arxiv.org/pdf/1411.0352.pdf)

To cite YJIT in your publications, please cite the MPLR 2023 paper:

```
@inproceedings{yjit_mplr_2023,
author = {Chevalier-Boisvert, Maxime and Kokubun, Takashi and Gibbs, Noah and Wu, Si Xing (Alan) and Patterson, Aaron and Issroff, Jemma},
title = {Evaluating YJIT’s Performance in a Production Context: A Pragmatic Approach},
year = {2023},
isbn = {9798400703805},
publisher = {Association for Computing Machinery},
address = {New York, NY, USA},
url = {https://doi.org/10.1145/3617651.3622982},
doi = {10.1145/3617651.3622982},
booktitle = {Proceedings of the 20th ACM SIGPLAN International Conference on Managed Programming Languages and Runtimes},
pages = {20–33},
numpages = {14},
keywords = {dynamically typed, optimization, just-in-time, virtual machine, ruby, compiler, bytecode},
location = {Cascais, Portugal},
series = {MPLR 2023}
}
```

## Current Limitations

YJIT may not be suitable for certain applications. It currently only supports macOS, Linux and BSD on x86-64 and arm64/aarch64 CPUs. YJIT will use more memory than the Ruby interpreter because the JIT compiler needs to generate machine code in memory and maintain additional state information.
You can change how much executable memory is allocated using [YJIT's command-line options](#command-line-options).

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
brew install openssl libyaml

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

<h3 id="command-line-options">Command-Line Options</h3>

YJIT supports all command-line options supported by upstream CRuby, but also adds a few YJIT-specific options:

- `--yjit`: enable YJIT (disabled by default)
- `--yjit-exec-mem-size=N`: size of the executable memory block to allocate, in MiB (default 48 MiB)
- `--yjit-call-threshold=N`: number of calls after which YJIT begins to compile a function.
  It defaults to 30, and it's then increased to 120 when the number of ISEQs in the process reaches 40,000.
- `--yjit-cold-threshold=N`: number of global calls after which an ISEQ is considered cold and not
  compiled, lower values mean less code is compiled (default 200K)
- `--yjit-stats`: print statistics after the execution of a program (incurs a run-time cost)
- `--yjit-stats=quiet`: gather statistics while running a program but don't print them. Stats are accessible through `RubyVM::YJIT.runtime_stats`. (incurs a run-time cost)
- `--yjit-disable`: disable YJIT despite other `--yjit*` flags for lazily enabling it with `RubyVM::YJIT.enable`
- `--yjit-code-gc`: enable code GC (disabled by default as of Ruby 3.3).
  It will cause all machine code to be discarded when the executable memory size limit is hit, meaning JIT compilation will then start over.
  This can allow you to use a lower executable memory size limit, but may cause a slight drop in performance when the limit is hit.
- `--yjit-perf`: enable frame pointers and profiling with the `perf` tool
- `--yjit-trace-exits`: produce a Marshal dump of backtraces from all exits. Automatically enables `--yjit-stats`
- `--yjit-trace-exits=COUNTER`: produce a Marshal dump of backtraces from specified exits. Automatically enables `--yjit-stats`
- `--yjit-trace-exits-sample-rate=N`: trace exit locations only every Nth occurrence. Automatically enables `--yjit-trace-exits`

Note that there is also an environment variable `RUBY_YJIT_ENABLE` which can be used to enable YJIT.
This can be useful for some deployment scripts where specifying an extra command-line option to Ruby is not practical.

You can also enable YJIT at run-time using `RubyVM::YJIT.enable`. This can allow you to enable YJIT after your application is done
booting, which makes it possible to avoid compiling any initialization code.

You can verify that YJIT is enabled using `RubyVM::YJIT.enabled?` or by checking that `ruby --yjit -v` includes the string `+YJIT`:

```sh
ruby --yjit -v
ruby 3.3.0dev (2023-01-31T15:11:10Z master 2a0bf269c9) +YJIT dev [x86_64-darwin22]

ruby --yjit -e "p RubyVM::YJIT.enabled?"
true

ruby -e "RubyVM::YJIT.enable; p RubyVM::YJIT.enabled?"
true
```

### Benchmarking

We have collected a set of benchmarks and implemented a simple benchmarking harness in the [yjit-bench](https://github.com/Shopify/yjit-bench) repository. This benchmarking harness is designed to disable CPU frequency scaling, set process affinity and disable address space randomization so that the variance between benchmarking runs will be as small as possible.

## Performance Tips for Production Deployments

While YJIT options default to what we think would work well for most workloads,
they might not necessarily be the best configuration for your application.
This section covers tips on improving YJIT performance in case YJIT does not
speed up your application in production.

### Increasing --yjit-exec-mem-size

When JIT code size (`RubyVM::YJIT.runtime_stats[:code_region_size]`) reaches this value,
YJIT stops compiling new code. Increasing the executable memory size means more code
can be optimized by YJIT, at the cost of more memory usage.

If you start Ruby with `--yjit-stats`, e.g. using an environment variable `RUBYOPT=--yjit-stats`,
`RubyVM::YJIT.runtime_stats[:ratio_in_yjit]` shows the ratio of YJIT-executed instructions in %.
Ideally, `ratio_in_yjit` should be as large as 99%, and increasing `--yjit-exec-mem-size` often
helps improving `ratio_in_yjit`.

### Running workers as long as possible

It's helpful to call the same code as many times as possible before a process restarts.
If a process is killed too frequently, the time taken for compiling methods may outweigh
the speedup obtained by compiling them.

You should monitor the number of requests each process has served.
If you're periodically killing worker processes, e.g. with `unicorn-worker-killer` or `puma_worker_killer`,
you may want to reduce the killing frequency or increase the limit.

## Reducing YJIT Memory Usage

YJIT allocates memory for JIT code and metadata. Enabling YJIT generally results in more memory usage.
This section goes over tips on minimizing YJIT memory usage in case it uses more than your capacity.

### Decreasing --yjit-exec-mem-size

The `--yjit-exec-mem-size` option specifies the JIT code size, but YJIT also uses memory for its metadata,
which often consumes more memory than JIT code. Generally, YJIT adds memory overhead by roughly
3-4x of `--yjit-exec-mem-size` in production as of Ruby 3.3. You should multiply that by the number
of worker processes to estimate the worst case memory overhead.

`--yjit-exec-mem-size=48` is the default since Ruby 3.3.1,
but smaller values like 32 MiB might make sense for your application.
While doing so, you may want to monitor `RubyVM::YJIT.runtime_stats[:ratio_in_yjit]` as explained above.

### Enabling YJIT lazily

If you enable YJIT by `--yjit` options or `RUBY_YJIT_ENABLE=1`, YJIT may compile code that is
used only during the application boot. `RubyVM::YJIT.enable` allows you to enable YJIT from Ruby code,
and you can call this after your application is initialized, e.g. on Unicorn's `after_fork` hook.
If you use any YJIT options (`--yjit-*`), YJIT will start at boot by default, but `--yjit-disable`
allows you to start Ruby with the YJIT-disabled mode while passing YJIT tuning options.

## Code Optimization Tips

This section contains tips on writing Ruby code that will run as fast as possible on YJIT. Some of this advice is based on current limitations of YJIT, while other advice is broadly applicable. It probably won't be practical to apply these tips everywhere in your codebase. You should ideally start by profiling your application using a tool such as [stackprof](https://github.com/tmm1/stackprof) so that you can determine which methods make up most of the execution time. You can then refactor the specific methods that make up the largest fractions of the execution time. We do not recommend modifying your entire codebase based on the current limitations of YJIT.

- Avoid using `OpenStruct`
- Avoid redefining basic integer operations (i.e. +, -, <, >, etc.)
- Avoid redefining the meaning of `nil`, equality, etc.
- Avoid allocating objects in the hot parts of your code
- Minimize layers of indirection
  - Avoid writing wrapper classes if you can (e.g. a class that only wraps a Ruby hash)
  - Avoid methods that just call another method
- Ruby method calls are costly. Avoid things such as methods that only return a value from a hash
- Try to write code so that the same variables and method arguments always have the same type
- Avoid using `TracePoint` as it can cause YJIT to deoptimize code
- Avoid using `Binding` as it can cause YJIT to deoptimize code

You can also use the `--yjit-stats` command-line option to see which bytecodes cause YJIT to exit, and refactor your code to avoid using these instructions in the hottest methods of your code.

### Other Statistics

If you run `ruby` with `--yjit-stats`, YJIT will track and return performance statistics in `RubyVM::YJIT.runtime_stats`.

```rb
$ RUBYOPT="--yjit-stats" irb
irb(main):001:0> RubyVM::YJIT.runtime_stats
=>
{:inline_code_size=>340745,
 :outlined_code_size=>297664,
 :all_stats=>true,
 :yjit_insns_count=>1547816,
 :send_callsite_not_simple=>7267,
 :send_kw_splat=>7,
 :send_ivar_set_method=>72,
...
```

Some of the counters include:

* `:yjit_insns_count` - how many Ruby bytecode instructions have been executed
* `:binding_allocations` - number of bindings allocated
* `:binding_set` - number of variables set via a binding
* `:code_gc_count` - number of garbage collections of compiled code since process start
* `:vm_insns_count` - number of instructions executed by the Ruby interpreter
* `:compiled_iseq_count` - number of bytecode sequences compiled
* `:inline_code_size` - size in bytes of compiled YJIT blocks
* `:outline_code_size` - size in bytes of YJIT error-handling compiled code
* `:side_exit_count` - number of side exits taken at runtime
* `:total_exit_count` - number of exits, including side exits, taken at runtime
* `:avg_len_in_yjit` - avg. number of instructions in compiled blocks before exiting to interpreter

Counters starting with "exit_" show reasons for YJIT code taking a side exit (return to the interpreter.)

Performance counter names are not guaranteed to remain the same between Ruby versions. If you're curious what each counter means,
it's usually best to search the source code for it &mdash; but it may change in a later Ruby version.

The printed text after a `--yjit-stats` run includes other information that may be named differently than the information in `RubyVM::YJIT.runtime_stats`.

## Contributing

We welcome open source contributions. You should feel free to open new issues to report bugs or just to ask questions.
Suggestions on how to make this readme file more helpful for new contributors are most welcome.

Bug fixes and bug reports are very valuable to us. If you find a bug in YJIT, it's very possible be that nobody has reported it before,
or that we don't have a good reproduction for it, so please open an issue and provide as much information as you can about your configuration and a description of how you encountered the problem. List the commands you used to run YJIT so that we can easily reproduce the issue on our end and investigate it. If you are able to produce a small program reproducing the error to help us track it down, that is very much appreciated as well.

If you would like to contribute a large patch to YJIT, we suggest opening an issue or a discussion on the [Shopify/ruby repository](https://github.com/Shopify/ruby/issues) so that
we can have an active discussion. A common problem is that sometimes people submit large pull requests to open source projects
without prior communication, and we have to reject them because the work they implemented does not fit within the design of the
project. We want to save you time and frustration, so please reach out so we can have a productive discussion as to how
you can contribute patches we will want to merge into YJIT.

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
- `yjit/src/cruby.rs`: C bindings manually exposed to the Rust codebase
- `yjit/bindgen/src/main.rs`: C bindings exposed to the Rust codebase through bindgen

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

There are multiple test suites:

- `make btest` (see `/bootstraptest`)
- `make test-all`
- `make test-spec`
- `make check` runs all of the above
- `make yjit-smoke-test` runs quick checks to see that YJIT is working correctly

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

## Profiling with Linux perf

`--yjit-perf` allows you to profile JIT-ed methods along with other native functions using Linux perf.
When you run Ruby with `perf record`, perf looks up `/tmp/perf-{pid}.map` to resolve symbols in JIT code,
and this option lets YJIT write method symbols into that file as well as enabling frame pointers.

### Call graph

Here's an example way to use this option with [Firefox Profiler](https://profiler.firefox.com)
(See also: [Profiling with Linux perf](https://profiler.firefox.com/docs/#/./guide-perf-profiling)):

```bash
# Compile the interpreter with frame pointers enabled
./configure --enable-yjit --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc cflags=-fno-omit-frame-pointer
make -j && make install

# [Optional] Allow running perf without sudo
echo 0 | sudo tee /proc/sys/kernel/kptr_restrict
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid

# Profile Ruby with --yjit-perf
cd ../yjit-bench
PERF="record --call-graph fp" ruby --yjit-perf -Iharness-perf benchmarks/liquid-render/benchmark.rb

# View results on Firefox Profiler https://profiler.firefox.com.
# Create /tmp/test.perf as below and upload it using "Load a profile from file".
perf script --fields +pid > /tmp/test.perf
```

### YJIT codegen

You can also profile the number of cycles consumed by code generated by each YJIT function.

```bash
# Install perf
apt-get install linux-tools-common linux-tools-generic linux-tools-`uname -r`

# [Optional] Allow running perf without sudo
echo 0 | sudo tee /proc/sys/kernel/kptr_restrict
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid

# Profile Ruby with --yjit-perf=codegen
cd ../yjit-bench
PERF=record ruby --yjit-perf=codegen -Iharness-perf benchmarks/lobsters/benchmark.rb

# Aggregate results
perf script > /tmp/perf.txt
../ruby/misc/yjit_perf.py /tmp/perf.txt
```

#### Building perf with Python support

The above instructions work fine for most people, but you could also use
a handy `perf script -s` interface if you build perf from source.

```bash
# Build perf from source for Python support
sudo apt-get install libpython3-dev python3-pip flex libtraceevent-dev \
  libelf-dev libunwind-dev libaudit-dev libslang2-dev libdw-dev
git clone --depth=1 https://github.com/torvalds/linux
cd linux/tools/perf
make
make install

# Aggregate results
perf script -s ../ruby/misc/yjit_perf.py
```
