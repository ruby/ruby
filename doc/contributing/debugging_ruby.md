# Debugging Ruby

You can use either lldb or gdb for debugging. Before debugging, you need to
create a `test.rb` with the Ruby script you'd like to run. You can use the
following make targets:

* `make run`: Runs `test.rb` using Miniruby
* `make lldb`: Runs `test.rb` using Miniruby in lldb
* `make gdb`: Runs `test.rb` using Miniruby in gdb
* `make runruby`: Runs `test.rb` using Ruby
* `make lldb-ruby`: Runs `test.rb` using Ruby in lldb
* `make gdb-ruby`: Runs `test.rb` using Ruby in gdb

For VS Code users, you can set up editor-based debugging experience by running:

```shell
cp -r misc/.vscode .vscode
```

This will add launch configurations for debugging Ruby itself by running `test.rb` with `lldb`.

**Note**: if you build Ruby under the `./build` folder, you'll need to update `.vscode/launch.json`'s program entry accordingly to: `"${workspaceFolder}/build/ruby"`

## Compiling for Debugging

You can compile Ruby with the `RUBY_DEBUG` macro to enable debugging on some
features. One example is debugging object shapes in Ruby with
`RubyVM::Shape.of(object)`.

Additionally Ruby can be compiled to support the `RUBY_DEBUG` environment
variable to enable debugging on some features. An example is using
`RUBY_DEBUG=gc_stress` to debug GC-related issues.

There is also support for the `RUBY_DEBUG_LOG` environment variable to log a
lot of information about what the VM is doing, via the `USE_RUBY_DEBUG_LOG`
macro.

You should also configure Ruby without optimization and other flags that may
interfere with debugging by changing the optimization flags.

Bringing it all together:

```sh
./configure cppflags="-DRUBY_DEBUG=1 -DUSE_RUBY_DEBUG_LOG=1" --enable-debug-env optflags="-O0 -fno-omit-frame-pointer"
```

## Building with Address Sanitizer

Using the address sanitizer (ASAN) is a great way to detect memory issues. It
can detect memory safety issues in Ruby itself, and also in any C extensions
compiled with and loaded into a Ruby compiled with ASAN.

```sh
./autogen.sh
mkdir build && cd build
../configure CC=clang-18 cflags="-fsanitize=address -fno-omit-frame-pointer -DUSE_MN_THREADS=0" # and any other options you might like
make
```

The compiled Ruby will now automatically crash with a report and a backtrace
if ASAN detects a memory safety issue. To run Ruby's test suite under ASAN,
issue the following command. Note that this will take quite a long time (over
two hours on my laptop); the `RUBY_TEST_TIMEOUT_SCALE` and
`SYNTAX_SUGGEST_TIMEOUT` variables are required to make sure tests don't
spuriously fail with timeouts when in fact they're just slow.

```sh
RUBY_TEST_TIMEOUT_SCALE=5 SYNTAX_SUGGEST_TIMEOUT=600 make check
```

Please note, however, the following caveats!

* Due to [Bug #20243], Clang generates code for threadlocal variables which
  doesn't work with M:N threading. Thus, it's necessary to disable M:N
  threading support at build time for now (with the `-DUSE_MN_THREADS=0`
  configure argument).
* ASAN will only work when using Clang version 18 or later - it requires
  [llvm/llvm-project#75290] related to multithreaded `fork`.
* ASAN has only been tested so far with Clang on Linux. It may or may not work
  with other compilers or on other platforms - please file an issue on
  [Ruby Issue Tracking System] if you run into problems with such configurations
  (or, to report that they actually work properly!)
* In particular, although I have not yet tried it, I have reason to believe
  ASAN will _not_ work properly on macOS yet - the fix for the multithreaded
  fork issue was actually reverted for macOS (see [llvm/llvm-project#75659]).
  Please open an issue on [Ruby Issue Tracking System] if this is a problem for
  you.

[Revision 9d0a5148]: https://bugs.ruby-lang.org/projects/ruby-master/repository/git/revisions/9d0a5148ae062a0481a4a18fbeb9cfd01dc10428
[Bug #20243]: https://bugs.ruby-lang.org/issues/20243
[llvm/llvm-project#75290]: https://github.com/llvm/llvm-project/pull/75290
[llvm/llvm-project#75659]: https://github.com/llvm/llvm-project/pull/75659#issuecomment-1861584777
[Ruby Issue Tracking System]: https://bugs.ruby-lang.org

## Crash dumps

A `[BUG]` report shows the backtrace of the crashing thread, but not the other threads or the memory, and some crashes leave no report at all, such as one in a thread other than the main one on Windows. A crash dump keeps that state for a debugger.

### Getting a dump

#### Locally

On Linux, the `abort()` after a `[BUG]` report writes a core file when `ulimit -c` allows. `/proc/sys/kernel/core_pattern` decides where it goes, and `coredumpctl` retrieves it if the pattern pipes to systemd-coredump. To write it into the current directory, as the CI does:

```sh
ulimit -c unlimited
echo "$PWD/core.%p" | sudo tee /proc/sys/kernel/core_pattern
```

On macOS, the kernel writes no core for the ad-hoc signed `ruby`. Instead, lldb can attach and save one through `RUBY_ON_BUG`, a command that Ruby runs with its pid appended when it reaches `[BUG]` (`make runruby` uses it for gdb):

```sh
RUBY_ON_BUG='lldb --batch -o "process save-core -s modified-memory /tmp/ruby.core" -p' ./ruby test.rb
```

On Windows, `RUBY_DEBUG=wer` leaves the crashes that bypass the `[BUG]` report to Windows Error Reporting, which writes a dump once `LocalDumps` is set in the registry as an administrator. `RUBY_DEBUG` needs `--enable-debug-env` at configure:

```
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps" /v DumpFolder /t REG_EXPAND_SZ /d C:\dumps /f
set RUBY_DEBUG=wer
```

#### From CI

When a Ruby process crashes in the tests on GitHub Actions, these workflows upload an artifact with the dumps and what is needed to read them:

* Windows (`windows.yml`), as `crashdumps-OS-TASK`, or `crashdumps-OS-x86-TASK` for the x86 job
* Ubuntu (`ubuntu.yml`, except the ppc64le and s390x jobs), YJIT Ubuntu (`yjit-ubuntu.yml`) and ZJIT Ubuntu (`zjit-ubuntu.yml`), as `crashdumps-JOB-INDEX`
* macOS (`macos.yml`), YJIT macOS (`yjit-macos.yml`) and ZJIT macOS (`zjit-macos.yml`), as `crashdumps-JOB-INDEX`

`JOB-INDEX` is the job name and its position in the matrix, such as `crashdumps-make-3`. The other workflows collect no dumps. The artifact is listed under "Artifacts" on the run's summary page for 7 days, and each dump is named after the pid in the `pid N killed by SIG...` line of the test output.

```sh
gh run download RUN_ID -R ruby/ruby -n ARTIFACT_NAME -D artifact
cd artifact
```

### Reading a dump

Below, `~/src/ruby` is a checkout of the commit that crashed.

#### Linux and macOS

A local dump opens with the binary that wrote it, as in `gdb ./ruby core.PID` or `lldb -c /tmp/ruby.core ./ruby`.

For a Linux dump from CI, `file core.PID` tells which executable crashed, and every file the process mapped is under `sysroot/` at its original path. gdb finds the libraries there by their sonames:

```sh
gdb -q -ex 'set sysroot sysroot' -ex "set solib-search-path $(find sysroot/usr -name libc.so.6 -printf '%h')" -ex 'set substitute-path /home/runner/work/ruby/ruby/src ~/src/ruby' -ex 'file sysroot/home/runner/work/ruby/ruby/build/ruby' -ex 'core-file core.PID'
```

lldb on macOS reads these cores too, with `target.exec-search-paths` set before `target create` (`aarch64-linux-gnu` for an arm64 job):

```sh
lldb -o 'settings set target.exec-search-paths sysroot/usr/lib/x86_64-linux-gnu' -o 'platform select remote-linux --sysroot sysroot' -o 'target create --core core.PID sysroot/home/runner/work/ruby/ruby/build/ruby'
```

A macOS dump from CI comes with `core.PID.lldb`, which loads the binaries and dSYMs under `sysroot/` first. If a dump is missing, see `lldb.PID.log`.

```sh
lldb -s core.PID.lldb -o 'settings set target.source-map /Users/runner/work/ruby/ruby/src ~/src/ruby' -o 'bt all'
```

The backtrace starts in the signal handler. The faulting instruction is found from the `sigsegv` frame, with `__rip` for `__pc` on x86_64:

```
image lookup -a `((ucontext_t *)ctx)->uc_mcontext->__ss.__pc`
```

#### Windows

In an artifact from CI, the dumps `ruby.exe.PID.dmp` are under `crashdumps/`, the binaries and PDBs under `build/` (those of extension libraries under `build/ext/NAME/`), and the vcpkg libraries under `src/vcpkg_installed/TRIPLET/bin/`. WinDbg reads a dump with these directories in the symbol path.

Elsewhere, lldb prints the frames as module offsets, which `llvm-symbolizer` resolves with the PDB:

```sh
lldb --batch -c crashdumps/ruby.exe.PID.dmp -o 'image list' -o 'bt all'
llvm-symbolizer --obj=build/arm64-vcruntime140-ruby410.dll --relative-address --inlining 0x15d7c
```

The offset is the frame address minus the module base in `image list`. `llvm-symbolizer` looks for a PDB only next to the binary, so link those of extension and vcpkg libraries there first.
