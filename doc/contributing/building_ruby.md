# Building Ruby

## Quick start guide

1. Install the prerequisite dependencies for building the CRuby interpreter:

    * C compiler
    * autoconf - 2.67 or later
    * bison - 2.0 or later
    * gperf - 3.0.3 or later
    * ruby - 2.7 or later

2. Install optional, recommended dependencies:

    * OpenSSL/LibreSSL
    * readline/editline (libedit)
    * zlib
    * libffi
    * libyaml
    * libexecinfo (FreeBSD)

3. Checkout the CRuby source code:

    ```
    git clone https://github.com/ruby/ruby.git
    ```

4. Generate the configuration files and build. It's generally advisable to use a build directory:

    ```
    ./autogen.sh
    mkdir build && cd build # it's good practice to build outside of source dir
    mkdir ~/.rubies # we will install to .rubies/ruby-master in our home dir
    ../configure --prefix="${HOME}/.rubies/ruby-master"
    make install
    ```

5. Optional: If you are frequently building Ruby, disabling documentation will reduce the time it takes to `make install`:

    ``` shell
    ../configure --disable-install-doc
    ```

6. [Run tests](testing_ruby.md) to confirm your build succeeded

### Unexplainable Build Errors

If you are having unexplainable build errors, after saving all your work, try running `git clean -xfd` in the source root to remove all git ignored local files. If you are working from a source directory that's been updated several times, you may have temporary build artefacts from previous releases which can cause build failures.

## More details

If you're interested in continuing development on Ruby, here are more details
about Ruby's build to help out.

### Running make scripts in parallel

To run a specific make script in parallel, pass flag `-j<number of processes>`. For instance,
to run tests on 8 processes, use:

```
make test-all -j8
```

We can also set `MAKEFLAGS` to run _all_ `make` commands in parallel.

Ensuring `make` has the right `--jobs` flag will ensure all processors are utilized when building software projects To do this effectively, you can set `MAKEFLAGS` in your shell configuration/profile:

``` shell
# On macOS with Fish shell:
export MAKEFLAGS="--jobs "(sysctl -n hw.ncpu)

# On macOS with Bash/ZSH shell:
export MAKEFLAGS="--jobs $(sysctl -n hw.ncpu)"

# On Linux with Fish shell:
export MAKEFLAGS="--jobs "(nproc)

# On Linux with Bash/ZSH shell:
export MAKEFLAGS="--jobs $(nproc)"
```

### Miniruby vs Ruby

Miniruby is a version of Ruby which has no external dependencies and lacks certain features.
It can be useful in Ruby development because it allows for faster build times. Miniruby is
built before Ruby. A functional Miniruby is required to build Ruby. To build Miniruby:

```
make miniruby
```

## Debugging

You can use either lldb or gdb for debugging. Before debugging, you need to create a `test.rb`
with the Ruby script you'd like to run. You can use the following make targets:

* `make run`: Runs `test.rb` using Miniruby
* `make lldb`: Runs `test.rb` using Miniruby in lldb
* `make gdb`: Runs `test.rb` using Miniruby in gdb
* `make runruby`: Runs `test.rb` using Ruby
* `make lldb-ruby`: Runs `test.rb` using Ruby in lldb
* `make gdb-ruby`: Runs `test.rb` using Ruby in gdb

### Building with Address Sanitizer

Using the address sanitizer is a great way to detect memory issues.

``` shell
./autogen.sh
mkdir build && cd build
export ASAN_OPTIONS="halt_on_error=0:use_sigaltstack=0:detect_leaks=0"
../configure cppflags="-fsanitize=address -fno-omit-frame-pointer" optflags=-O0 LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"
make
```

On Linux it is important to specify -O0 when debugging and this is especially true for ASAN which sometimes works incorrectly at higher optimisation levels.

## How to measure coverage of C and Ruby code

You need to be able to use gcc (gcov) and lcov visualizer.

```
./autogen.sh
./configure --enable-gcov
make
make update-coverage
rm -f test-coverage.dat
make test-all COVERAGE=true
make lcov
open lcov-out/index.html
```

If you need only C code coverage, you can remove `COVERAGE=true` from the above process.
You can also use `gcov` command directly to get per-file coverage.

If you need only Ruby code coverage, you can remove `--enable-gcov`.
Note that `test-coverage.dat` accumulates all runs of `make test-all`.
Make sure that you remove the file if you want to measure one test run.

You can see the coverage result of CI: https://rubyci.org/coverage